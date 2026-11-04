#!/usr/bin/env python3
"""
Native messaging host for Gamify Timer.
Reads/writes shared data (balance, history, rewards) to a local JSON file
so all browser profiles share the same state.
"""

import json
import struct
import sys
import os
import fcntl
import pwd
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timedelta

DATA_FILE = os.path.expanduser('~/Dropbox/Workflow Tools/Gamify Timer/data.json')

DEFAULT_DATA = {
    'balance': 0,
    'history': [],
    'rewards': [
        {'id': 1, 'name': 'Ghost Energy Drink', 'cost': 20, 'tier': 1, 'emoji': '\u26a1'},
        {'id': 2, 'name': 'Masturbate', 'cost': 60, 'tier': 2, 'emoji': '\U0001f525'}
    ],
    'activities': [
        {'id': 1, 'name': 'Sit-ups', 'emoji': '\U0001f4aa', 'perCredit': 4, 'credits': 1, 'counted': True}
    ],
    'tags': [],
    'consecutiveRedemptions': {},
    'minutesFocusedToday': 0,
    'lastSessionDate': None,
    'settings': {
        'defaultSessionMinutes': 25,
        'defaultRestMinutes': 5,
        'longRestMinutes': 15,
        'sessionsBeforeLongRest': 4,
        'maxPausePercent': 10,
        'allowDebt': False,
        'soundVolume': 0.7,
        'focusSound': 'focus-complete.wav',
        'restSound': 'rest-complete.wav'
    }
}


def read_data():
    if not os.path.exists(DATA_FILE):
        write_data(DEFAULT_DATA)
        return DEFAULT_DATA.copy()
    try:
        with open(DATA_FILE, 'r') as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            try:
                content = f.read()
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)
        if not content.strip():
            raise ValueError('Empty data file')
        data = json.loads(content)
    except (json.JSONDecodeError, ValueError):
        # Corrupt or empty file — preserve a backup and fall back to defaults
        backup = DATA_FILE + '.corrupt'
        try:
            os.replace(DATA_FILE, backup)
        except OSError:
            pass
        write_data(DEFAULT_DATA)
        return DEFAULT_DATA.copy()
    # Backfill missing top-level keys
    for key, default in DEFAULT_DATA.items():
        if key not in data:
            data[key] = default.copy() if isinstance(default, (dict, list)) else default
    # Backfill missing individual settings keys
    for key, default in DEFAULT_DATA['settings'].items():
        if key not in data['settings']:
            data['settings'][key] = default
    return data


def write_data(data):
    # Atomic write: write to temp file then rename, so data.json is never truncated mid-write
    dir_path = os.path.dirname(DATA_FILE)
    fd, tmp_path = tempfile.mkstemp(dir=dir_path, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, DATA_FILE)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def insert_chronological(history, entry):
    # History is newest-first; place a backdated entry at its correct position
    for i, h in enumerate(history):
        if entry['timestamp'] >= h.get('timestamp', 0):
            history.insert(i, entry)
            return
    history.append(entry)


# Timer mirror for the sketchybar widget: one file per browser profile (each profile
# has its own extension storage, identified by a random instanceId). Machine-local
# on purpose — a running timer belongs to this Mac, unlike data.json (Dropbox).
TIMER_DIR = os.path.expanduser('~/.cache/sketchybar/gamify')


def report_timer(msg):
    instance_id = re.sub(r'[^A-Za-z0-9-]', '', str(msg.get('instanceId', '')))[:64]
    if not instance_id:
        return {'error': 'Missing instanceId'}
    timer = msg.get('timer') or {}
    path = os.path.join(TIMER_DIR, instance_id + '.json')
    os.makedirs(TIMER_DIR, exist_ok=True)

    if timer.get('status') in ('running', 'paused'):
        tag = timer.get('tag')
        tag_color = None
        max_pause_percent = DEFAULT_DATA['settings']['maxPausePercent']
        try:
            data = read_data()
            max_pause_percent = data.get('settings', {}).get('maxPausePercent', max_pause_percent)
            if tag:
                tag_color = next((t.get('color') for t in data.get('tags', []) if t.get('name') == tag), None)
        except Exception:
            pass
        # maxPausePercent: the widget shows the free pause time left, same as the popup
        record = dict(timer, tagColor=tag_color, maxPausePercent=max_pause_percent)
        fd, tmp_path = tempfile.mkstemp(dir=TIMER_DIR, suffix='.tmp')
        with os.fdopen(fd, 'w') as f:
            json.dump(record, f, ensure_ascii=False)
        os.replace(tmp_path, path)
    else:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Nudge sketchybar to redraw now. Brave launches hosts with a minimal PATH, and
    # the sketchybar client aborts without $USER, so make sure both are available.
    sketchybar = shutil.which('sketchybar') or '/opt/homebrew/bin/sketchybar'
    env = dict(os.environ)
    env.setdefault('USER', pwd.getpwuid(os.getuid()).pw_name)
    try:
        subprocess.run([sketchybar, '--trigger', 'gamify_update'], timeout=2, env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass
    return {'success': True}


# Command channel (sketchybar → extension). The sketchybar widget's pause/resume
# button writes "toggle" to TIMER_DIR/cmd/<instanceId>; the profile holding a
# long-lived port (only while its timer is running/paused) forwards it. The thread
# dies with the process when the extension closes the port (stdin EOF).
def listen_commands(instance_id):
    cmd_dir = os.path.join(TIMER_DIR, 'cmd')
    os.makedirs(cmd_dir, exist_ok=True)
    cmd_path = os.path.join(cmd_dir, instance_id)
    try:
        os.remove(cmd_path)        # a click from before this profile was listening
    except FileNotFoundError:
        pass
    while True:
        time.sleep(0.25)
        try:
            with open(cmd_path) as f:
                command = f.read().strip()
            os.remove(cmd_path)
        except FileNotFoundError:
            continue
        except OSError:
            continue
        if command == 'toggle':
            send_message({'type': 'command', 'command': command})


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        sys.exit(0)
    length = struct.unpack('@I', raw_length)[0]
    message = sys.stdin.buffer.read(length).decode('utf-8')
    return json.loads(message)


_stdout_lock = threading.Lock()   # the command thread and main loop both write


def send_message(obj):
    encoded = json.dumps(obj, ensure_ascii=False).encode('utf-8')
    with _stdout_lock:
        sys.stdout.buffer.write(struct.pack('@I', len(encoded)))
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()


def handle(msg):
    action = msg.get('action')

    if action == 'getData':
        data = read_data()
        return data

    elif action == 'setBalance':
        data = read_data()
        data['balance'] = msg['balance']
        write_data(data)
        return {'success': True}

    elif action == 'addHistory':
        data = read_data()
        data['history'].insert(0, msg['entry'])
        write_data(data)
        return {'success': True}

    elif action == 'earnCredits':
        data = read_data()
        data['balance'] = data.get('balance', 0) + msg['amount']
        data['history'].insert(0, msg['entry'])
        write_data(data)
        return {'success': True, 'newBalance': data['balance']}

    elif action == 'spendCredits':
        data = read_data()
        balance = data.get('balance', 0)
        cost = msg['amount']
        allow_debt = msg.get('allowDebt', False)
        if balance < cost and not allow_debt:
            return {'error': 'Insufficient credits'}
        data['balance'] = balance - cost
        data['history'].insert(0, msg['entry'])
        # Track consecutive redemptions for escalating cost
        reward_id = msg.get('rewardId')
        if reward_id is not None:
            consec = data.get('consecutiveRedemptions', {})
            today = datetime.now().strftime('%Y-%m-%d')
            consec[str(reward_id)] = {'lastDate': today, 'streak': msg.get('streak', 0)}
            data['consecutiveRedemptions'] = consec
        write_data(data)
        return {'success': True, 'newBalance': data['balance']}

    elif action == 'logSpend':
        data = read_data()
        balance = data.get('balance', 0)
        cost = msg['amount']
        allow_debt = msg.get('allowDebt', False)
        if balance < cost and not allow_debt:
            return {'error': 'Insufficient credits'}
        data['balance'] = balance - cost
        insert_chronological(data['history'], msg['entry'])
        write_data(data)
        return {'success': True, 'newBalance': data['balance']}

    elif action == 'logEarn':
        data = read_data()
        data['balance'] = data.get('balance', 0) + msg['amount']
        insert_chronological(data['history'], msg['entry'])
        write_data(data)
        return {'success': True, 'newBalance': data['balance']}

    elif action == 'setRewards':
        data = read_data()
        data['rewards'] = msg['rewards']
        write_data(data)
        return {'success': True}

    elif action == 'setActivities':
        data = read_data()
        data['activities'] = msg['activities']
        write_data(data)
        return {'success': True}

    elif action == 'updateStreak':
        data = read_data()
        data['minutesFocusedToday'] = msg.get('minutesFocusedToday', 0)
        data['lastSessionDate'] = msg.get('lastSessionDate')
        write_data(data)
        return {'success': True}

    elif action == 'updateHistoryEntry':
        data = read_data()
        timestamp = msg['timestamp']
        updates = msg['updates']
        for entry in data['history']:
            if entry.get('timestamp') == timestamp:
                entry.update(updates)
                break
        # Re-sort history if timestamp was changed (keep newest-first order)
        if 'timestamp' in updates:
            data['history'].sort(key=lambda e: e.get('timestamp', 0), reverse=True)
        write_data(data)
        return {'success': True}

    elif action == 'deleteHistoryEntry':
        data = read_data()
        timestamp = msg['timestamp']
        data['history'] = [e for e in data['history'] if e.get('timestamp') != timestamp]
        write_data(data)
        return {'success': True}

    elif action == 'setTags':
        data = read_data()
        data['tags'] = msg['tags']
        write_data(data)
        return {'success': True}

    elif action == 'updateSettings':
        data = read_data()
        data['settings'] = msg['settings']
        write_data(data)
        return {'success': True}

    elif action == 'resetConfig':
        data = read_data()
        data['rewards'] = DEFAULT_DATA['rewards']
        data['activities'] = DEFAULT_DATA['activities']
        data['tags'] = DEFAULT_DATA['tags']
        data['settings'] = DEFAULT_DATA['settings'].copy()
        write_data(data)
        return {'success': True}

    elif action == 'resetAll':
        write_data(DEFAULT_DATA.copy())
        return {'success': True}

    elif action == 'reportTimer':
        return report_timer(msg)

    elif action == 'listenCommands':
        instance_id = re.sub(r'[^A-Za-z0-9-]', '', str(msg.get('instanceId', '')))[:64]
        if not instance_id:
            return {'error': 'Missing instanceId'}
        threading.Thread(target=listen_commands, args=(instance_id,), daemon=True).start()
        return {'listening': True}

    else:
        return {'error': f'Unknown action: {action}'}


def main():
    while True:
        try:
            msg = read_message()
            response = handle(msg)
            send_message(response)
        except Exception as e:
            send_message({'error': str(e)})


if __name__ == '__main__':
    main()
