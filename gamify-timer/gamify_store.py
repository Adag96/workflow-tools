"""
Shared data store + credit rules for Gamify Timer (used by host.py and gamify_engine.py).

data.json (balance, history, rewards, tags, activities, settings) lives in Dropbox and is
shared by every browser profile and Mac. Every read-modify-write goes through
`locked_data()`, which holds an exclusive lock for the whole transaction, so concurrent
writers (several host processes + the engine) can't lose each other's updates.

The credit rules below are a line-by-line port of the original background.js award code
(calculateCredits / getStreakMultiplier / pause penalty) — keep them identical; the
parity tests in tests/test_engine.py check them against the JavaScript.

Paths are configurable (GAMIFY_DATA_FILE, GAMIFY_STATE_DIR) so tests never touch real data.
"""

import copy
import fcntl
import json
import math
import os
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime

DATA_FILE = os.environ.get(
    'GAMIFY_DATA_FILE',
    os.path.expanduser('~/Dropbox/Workflow Tools/Gamify Timer/data.json'))
STATE_DIR = os.environ.get(
    'GAMIFY_STATE_DIR',
    os.path.expanduser('~/Library/Application Support/GamifyTimer'))
# The lock is machine-local on purpose: flock doesn't work across Dropbox anyway, and a
# lock file inside the Dropbox folder would just sync around as noise.
LOCK_FILE = os.path.join(STATE_DIR, 'data.lock')

DEFAULT_DATA = {
    'balance': 0,
    'history': [],
    'rewards': [
        {'id': 1, 'name': 'Ghost Energy Drink', 'cost': 20, 'tier': 1, 'emoji': '⚡'},
        {'id': 2, 'name': 'Masturbate', 'cost': 60, 'tier': 2, 'emoji': '\U0001f525'}
    ],
    'activities': [
        {'id': 1, 'name': 'Sit-ups', 'emoji': '\U0001f4aa', 'perCredit': 4, 'credits': 1, 'counted': True}
    ],
    'tags': [],
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


def defaults():
    """A fresh, independent copy of the defaults (never mutate DEFAULT_DATA itself)."""
    return copy.deepcopy(DEFAULT_DATA)


# ── data.json I/O ──────────────────────────────────────────────────────────────

def read_data(attempts=5):
    # data.json lives in Dropbox (File Provider), so it can be briefly missing, empty or
    # half-written while a sync lands. NEVER treat that as "fresh install" and write
    # defaults over it — that wipes balance + history. Retry, then raise; every caller
    # already retries later (award) or keeps its last good state (widget, popup).
    for attempt in range(attempts):
        try:
            with open(DATA_FILE, 'r') as f:
                fcntl.flock(f, fcntl.LOCK_SH)
                try:
                    content = f.read()
                finally:
                    fcntl.flock(f, fcntl.LOCK_UN)
            data = json.loads(content)
            if not isinstance(data, dict):
                raise ValueError('data.json is not an object')
            break
        except (OSError, ValueError) as e:      # JSONDecodeError is a ValueError
            if attempt == attempts - 1:
                raise RuntimeError(f'data.json unreadable ({e!r}); not touching it') from e
            time.sleep(0.2)
    # Backfill missing top-level keys
    for key, default in DEFAULT_DATA.items():
        if key not in data:
            data[key] = copy.deepcopy(default)
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


@contextmanager
def locked_data():
    """Exclusive read-modify-write transaction: `with locked_data() as data: ...`.
    The (possibly modified) data is written back when the block exits normally."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LOCK_FILE, 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = read_data()
            yield data
            write_data(data)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def insert_chronological(history, entry):
    # History is newest-first; place a backdated entry at its correct position
    for i, h in enumerate(history):
        if entry['timestamp'] >= h.get('timestamp', 0):
            history.insert(i, entry)
            return
    history.append(entry)


# ── Credit rules (port of background.js) ───────────────────────────────────────

def js_round(x):
    """JavaScript Math.round (halves round up), unlike Python's banker's rounding."""
    return math.floor(x + 0.5)


def js_number(x):
    """Store whole floats as ints, like JSON.stringify does (3.0 → 3)."""
    return int(x) if isinstance(x, float) and x.is_integer() else x


def local_date_str(dt=None):
    """Local date YYYY-MM-DD (background.js localDateStr)."""
    return (dt or datetime.now()).strftime('%Y-%m-%d')


def calculate_credits(minutes):
    return math.floor(minutes * (minutes + 15) / 50)


def streak_multiplier(minutes_today):
    if minutes_today >= 90:
        return 1.30
    if minutes_today >= 75:
        return 1.20
    if minutes_today >= 45:
        return 1.10
    return 1


def minutes_focused_today(data, today):
    """Minutes focused earlier today (resets on a new day)."""
    return (data.get('minutesFocusedToday') or 0) if data.get('lastSessionDate') == today else 0


def focus_award(session, data, today, now_ms):
    """The history entry for a completed focus session — same fields and maths as the
    original background.js completion handler (plus sessionId, for idempotency)."""
    settings = data.get('settings') or {}
    minutes_today = minutes_focused_today(data, today)

    base_credits = calculate_credits(session['sessionMinutes'])
    multiplier = streak_multiplier(minutes_today)

    tag_color = None
    tag_multiplier = 1
    if session.get('tag'):
        tag_obj = next((t for t in (data.get('tags') or []) if t.get('name') == session['tag']), None)
        tag_color = (tag_obj or {}).get('color') or None
        tag_multiplier = (tag_obj or {}).get('multiplier') or 1

    max_pause = settings.get('maxPausePercent')
    max_pause_percent = (10 if max_pause is None else max_pause) / 100
    total_paused_seconds = session.get('totalPausedSeconds') or 0
    session_seconds = session['sessionMinutes'] * 60
    free_pause_seconds = math.floor(session_seconds * max_pause_percent)
    penalty_seconds = max(0, total_paused_seconds - free_pause_seconds)
    effective_seconds = max(0, session_seconds - penalty_seconds)
    pause_multiplier = effective_seconds / session_seconds

    total_credits = max(0, math.floor(base_credits * multiplier * tag_multiplier * pause_multiplier))

    return {
        'type': 'earn',
        'amount': total_credits,
        'baseAmount': base_credits,
        'streakBonus': f'+{js_round((multiplier - 1) * 100)}%' if multiplier > 1 else None,
        'tagMultiplier': tag_multiplier if tag_multiplier != 1 else None,
        'pausePenalty': js_number(js_round(penalty_seconds / 60 * 10) / 10) if penalty_seconds > 0 else None,
        'sessionMinutes': session['sessionMinutes'],
        'tag': session.get('tag') or None,
        'tagColor': tag_color,
        'timestamp': now_ms,
        'sessionId': session.get('sessionId'),
    }
