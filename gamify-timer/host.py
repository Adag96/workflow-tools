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
import tempfile
from datetime import datetime, timedelta

DATA_FILE = os.path.expanduser('~/Dropbox/Workflow Tools/Gamify Timer/data.json')

DEFAULT_DATA = {
    'balance': 0,
    'history': [],
    'rewards': [
        {'id': 1, 'name': 'Ghost Energy Drink', 'cost': 20, 'tier': 1, 'emoji': '\u26a1'},
        {'id': 2, 'name': 'Masturbate', 'cost': 60, 'tier': 2, 'emoji': '\U0001f525'}
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


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        sys.exit(0)
    length = struct.unpack('@I', raw_length)[0]
    message = sys.stdin.buffer.read(length).decode('utf-8')
    return json.loads(message)


def send_message(obj):
    encoded = json.dumps(obj, ensure_ascii=False).encode('utf-8')
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
        entry = msg['entry']
        # Insert at correct chronological position (history is newest-first)
        inserted = False
        for i, h in enumerate(data['history']):
            if entry['timestamp'] >= h.get('timestamp', 0):
                data['history'].insert(i, entry)
                inserted = True
                break
        if not inserted:
            data['history'].append(entry)
        write_data(data)
        return {'success': True, 'newBalance': data['balance']}

    elif action == 'setRewards':
        data = read_data()
        data['rewards'] = msg['rewards']
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
        data['tags'] = DEFAULT_DATA['tags']
        data['settings'] = DEFAULT_DATA['settings'].copy()
        write_data(data)
        return {'success': True}

    elif action == 'resetAll':
        write_data(DEFAULT_DATA.copy())
        return {'success': True}

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
