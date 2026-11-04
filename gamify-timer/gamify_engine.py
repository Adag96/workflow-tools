#!/usr/bin/env python3
"""
Gamify Timer engine — the single owner of the (one) focus/rest session on this Mac.

Runs as a LaunchAgent (com.gamifytimer.engine). Every browser profile (via host.py) and
the sketchybar widget (via gamifyctl) are views + remote controls of this session, so a
session started anywhere shows everywhere, and completes and awards credits even when no
browser is open.

Protocol: Unix socket ENGINE_SOCK, one newline-terminated JSON request per connection,
one JSON line back.
  {"action": "get"}                               → {"session": {...}}
  {"action": "start", "minutes": 25, "tag": "X"}  → refused if a session exists
  {"action": "startRest", "minutes": 5}
  {"action": "pause" | "resume" | "toggle" | "cancel"}
Every reply carries the resulting session (`timerState` shape the popup already renders,
with remainingSeconds computed) or {"error": "..."}.

Completion is idempotent: the award is written in one locked data.json transaction only if
no history entry already has this sessionId — so a crash/restart can never double-award
(the old extension could), and the streak minutes update in the same transaction.

Stock bash/python only (macOS python3 3.9): no external packages.
"""

import sys
sys.dont_write_bytecode = True     # never drop __pycache__ into the extension folder

import json
import math
import os
import pwd
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import uuid

import gamify_store as store

HERE = os.path.dirname(os.path.abspath(__file__))
SESSION_FILE = os.path.join(store.STATE_DIR, 'session.json')
ENGINE_SOCK = os.environ.get('GAMIFY_ENGINE_SOCK', os.path.join(store.STATE_DIR, 'engine.sock'))
# Session mirror for the sketchybar widget (absent when idle)
WIDGET_FILE = os.environ.get('GAMIFY_WIDGET_FILE',
                             os.path.expanduser('~/.cache/sketchybar/gamify/session.json'))
# Balance mirror for the widget's idle state (plain number; rewritten whenever it changes)
BALANCE_FILE = os.path.join(os.path.dirname(WIDGET_FILE), 'balance')
SOUNDS_DIR = os.path.join(HERE, 'sounds')
RETRY_SECONDS = 5                  # completion retry when data.json is briefly unavailable

IDLE = {'status': 'idle', 'mode': 'focus', 'sessionMinutes': 25, 'startedAt': None,
        'pausedAt': None, 'totalPausedSeconds': 0, 'tag': None, 'sessionId': None}


def now_ms():
    return int(time.time() * 1000)


def log(*args):
    print(time.strftime('%Y-%m-%d %H:%M:%S'), *args, file=sys.stderr, flush=True)


# ── Session state ──────────────────────────────────────────────────────────────

class Engine:
    def __init__(self):
        self.lock = threading.RLock()
        self.wake = threading.Condition(self.lock)
        self.session = self._load()

    # persistence
    def _load(self):
        try:
            with open(SESSION_FILE) as f:
                s = json.load(f)
            return dict(IDLE, **s)
        except (OSError, ValueError):
            return dict(IDLE)

    def _save(self):
        os.makedirs(store.STATE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=store.STATE_DIR, suffix='.tmp')
        with os.fdopen(fd, 'w') as f:
            json.dump(self.session, f)
        os.replace(tmp, SESSION_FILE)

    # same wall-clock maths as the original background.js tick
    def remaining_seconds(self, s=None):
        s = s or self.session
        if s['status'] == 'idle' or not s['startedAt']:
            return 0
        until = s['pausedAt'] if s['status'] == 'paused' else now_ms()
        return store.js_round(s['sessionMinutes'] * 60 - (until - s['startedAt']) / 1000
                              + (s.get('totalPausedSeconds') or 0))

    def view(self):
        """The session in the popup's timerState shape (+ remainingSeconds)."""
        s = dict(self.session)
        s['remainingSeconds'] = max(0, self.remaining_seconds())
        return s

    def _changed(self):
        self._save()
        self.publish()
        self.wake.notify_all()

    # actions
    def start(self, minutes, tag, mode='focus'):
        with self.lock:
            if self.session['status'] != 'idle':
                return {'error': 'A session is already running', 'session': self.view()}
            minutes = int(minutes or (25 if mode == 'focus' else 5))
            self.session = dict(IDLE, status='running', mode=mode, sessionMinutes=minutes,
                                startedAt=now_ms(), tag=(tag or None) if mode == 'focus' else None,
                                sessionId=str(uuid.uuid4()))
            self._changed()
            return {'success': True, 'session': self.view()}

    def pause(self):
        with self.lock:
            if self.session['status'] != 'running':
                return {'error': 'No running session', 'session': self.view()}
            self.session.update(status='paused', pausedAt=now_ms())
            self._changed()
            return {'success': True, 'session': self.view()}

    def resume(self):
        with self.lock:
            if self.session['status'] != 'paused':
                return {'error': 'No paused session', 'session': self.view()}
            pause_duration = math.floor((now_ms() - self.session['pausedAt']) / 1000)
            self.session.update(status='running', pausedAt=None,
                                totalPausedSeconds=(self.session.get('totalPausedSeconds') or 0) + pause_duration)
            self._changed()
            return {'success': True, 'session': self.view()}

    def toggle(self):
        with self.lock:
            return self.pause() if self.session['status'] == 'running' else self.resume()

    def cancel(self):
        with self.lock:
            self.session = dict(IDLE)
            self._changed()
            return {'success': True, 'session': self.view()}

    # completion
    def complete(self):
        """Finish a running session whose time is up. Returns True when done."""
        with self.lock:
            # Re-check under the lock: it may have been paused/cancelled a moment ago
            if self.session['status'] != 'running' or self.remaining_seconds() > 0:
                return True
            s = dict(self.session)
        if s['mode'] == 'rest':
            with self.lock:
                if self.session.get('sessionId') == s['sessionId']:
                    self.session = dict(IDLE)
                    self._changed()
            notify('Rest Complete', 'Ready for another focus session?')
            play_sound('rest')
            return True

        today = store.local_date_str()
        try:
            with store.locked_data() as data:
                existing = next((e for e in data['history'] if e.get('sessionId') == s['sessionId']), None)
                if existing is None:
                    minutes_today = store.minutes_focused_today(data, today)
                    entry = store.focus_award(s, data, today, now_ms())
                    data['history'].insert(0, entry)
                    data['balance'] = data.get('balance', 0) + entry['amount']
                    data['minutesFocusedToday'] = minutes_today + s['sessionMinutes']
                    data['lastSessionDate'] = today
                    awarded, balance = entry, data['balance']
                else:
                    awarded, balance = None, data.get('balance', 0)   # already awarded (restart)
        except Exception as e:      # e.g. Dropbox briefly unavailable — keep running, retry
            log('award failed, will retry:', repr(e))
            return False

        with self.lock:
            if self.session.get('sessionId') == s['sessionId']:
                self.session = dict(IDLE)
                self._changed()
        if awarded:
            log('awarded', awarded['amount'], 'FC for', s['sessionMinutes'], 'min', s.get('tag'))
            bonus = ' (streak bonus!)' if awarded['streakBonus'] else ''
            notify('Session Complete!', f"Earned {awarded['amount']} FC{bonus}. Balance: {balance} FC")
            play_sound('focus')
        return True

    def run_timer(self):
        """Background loop: sleep until the session is due, then complete it."""
        while True:
            with self.lock:
                if self.session['status'] == 'running':
                    left = self.remaining_seconds()
                    if left > 0:
                        self.wake.wait(timeout=min(left, 30))
                        continue
                else:
                    self.wake.wait(timeout=60)
                    continue
            if not self.complete():
                time.sleep(RETRY_SECONDS)

    # widget mirror
    def publish(self):
        s = self.session
        try:
            os.makedirs(os.path.dirname(WIDGET_FILE), exist_ok=True)
            if s['status'] in ('running', 'paused'):
                tag_color, max_pause = None, 10
                try:
                    data = store.read_data()
                    max_pause = data['settings'].get('maxPausePercent', 10)
                    if s.get('tag'):
                        tag_color = next((t.get('color') for t in data.get('tags', [])
                                          if t.get('name') == s['tag']), None)
                except Exception:
                    pass
                fd, tmp = tempfile.mkstemp(dir=os.path.dirname(WIDGET_FILE), suffix='.tmp')
                with os.fdopen(fd, 'w') as f:
                    json.dump(dict(s, tagColor=tag_color, maxPausePercent=max_pause), f)
                os.replace(tmp, WIDGET_FILE)
            else:
                try:
                    os.remove(WIDGET_FILE)
                except FileNotFoundError:
                    pass
        except OSError as e:
            log('widget mirror failed:', repr(e))
        sketchybar_trigger()


def watch_balance():
    """Mirror the credit balance for the widget. Polls data.json's mtime (a stat a second)
    so every writer counts: host.py (redeem, log, edits), awards, and Dropbox syncing
    changes from another Mac."""
    seen_mtime, shown, last_err = None, None, None
    while True:
        try:
            mtime = os.stat(store.DATA_FILE).st_mtime_ns
            if mtime != seen_mtime:
                balance = store.js_number(store.read_data().get('balance', 0))
                seen_mtime = mtime
                if balance != shown:
                    os.makedirs(os.path.dirname(BALANCE_FILE), exist_ok=True)
                    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(BALANCE_FILE), suffix='.tmp')
                    with os.fdopen(fd, 'w') as f:
                        f.write(f'{balance}\n')
                    os.replace(tmp, BALANCE_FILE)
                    shown = balance
                    sketchybar_trigger()
            last_err = None
        except Exception as e:      # missing/mid-sync file: try again next second
            if repr(e) != last_err:
                log('balance mirror:', repr(e))
                last_err = repr(e)
        time.sleep(1)


# ── Side effects ───────────────────────────────────────────────────────────────

def _env():
    env = dict(os.environ)
    env.setdefault('USER', pwd.getpwuid(os.getuid()).pw_name)   # sketchybar client needs it
    env['PATH'] = env.get('PATH', '') + ':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'
    return env


def _run(cmd, timeout=5):
    try:
        subprocess.run(cmd, timeout=timeout, env=_env(),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


def sketchybar_trigger():
    exe = shutil.which('sketchybar', path=_env()['PATH'])
    if exe:
        _run([exe, '--trigger', 'gamify_update'], timeout=2)


def notify(title, message):
    if os.environ.get('GAMIFY_QUIET'):
        return
    script = f'display notification {json.dumps(message)} with title {json.dumps(title)}'
    threading.Thread(target=_run, args=(['/usr/bin/osascript', '-e', script],), daemon=True).start()


def play_sound(kind):
    if os.environ.get('GAMIFY_QUIET'):
        return
    try:
        settings = store.read_data().get('settings', {})
    except Exception:
        settings = {}
    volume = settings.get('soundVolume', 0.7)
    if not volume:
        return
    name = settings.get('focusSound' if kind == 'focus' else 'restSound') or \
        ('focus-complete.wav' if kind == 'focus' else 'rest-complete.wav')
    path = os.path.join(SOUNDS_DIR, os.path.basename(name))
    if os.path.exists(path):
        threading.Thread(target=_run, args=(['/usr/bin/afplay', '-v', str(max(0, min(1, volume))), path], 30),
                         daemon=True).start()


# ── Socket server ──────────────────────────────────────────────────────────────

ENGINE = None


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            msg = json.loads(self.rfile.readline() or b'{}')
            action = msg.get('action')
            if action == 'get':
                with ENGINE.lock:
                    reply = {'session': ENGINE.view()}
            elif action == 'start':
                reply = ENGINE.start(msg.get('minutes'), msg.get('tag'))
            elif action == 'startRest':
                reply = ENGINE.start(msg.get('minutes'), None, mode='rest')
            elif action in ('pause', 'resume', 'toggle', 'cancel'):
                reply = getattr(ENGINE, action)()
            else:
                reply = {'error': f'Unknown action: {action}'}
        except Exception as e:
            reply = {'error': str(e)}
        self.wfile.write((json.dumps(reply) + '\n').encode())


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main():
    global ENGINE
    os.makedirs(os.path.dirname(ENGINE_SOCK), exist_ok=True)
    try:
        os.remove(ENGINE_SOCK)
    except FileNotFoundError:
        pass
    ENGINE = Engine()
    with ENGINE.lock:
        ENGINE.publish()                 # restore the widget after a restart
    threading.Thread(target=ENGINE.run_timer, daemon=True).start()
    threading.Thread(target=watch_balance, daemon=True).start()
    log('engine up; session:', ENGINE.session['status'])
    with Server(ENGINE_SOCK, Handler) as server:
        os.chmod(ENGINE_SOCK, 0o600)
        server.serve_forever()


if __name__ == '__main__':
    main()
