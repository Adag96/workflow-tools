#!/usr/bin/env python3
"""
Native messaging host for Gamify Timer — the browser's bridge to local state.

- Data actions (balance, history, rewards, tags, activities, settings) read/write the
  shared data.json through gamify_store, each in one exclusive locked transaction.
- Timer actions are forwarded to the gamify engine (gamify_engine.py, a LaunchAgent),
  which owns the single session for every browser profile and the sketchybar widget.
"""

import sys
sys.dont_write_bytecode = True     # never drop __pycache__ into the extension folder

import json
import os
import socket
import struct

import gamify_store as store

ENGINE_SOCK = os.environ.get('GAMIFY_ENGINE_SOCK', os.path.join(store.STATE_DIR, 'engine.sock'))

# Extension action → engine action
TIMER_ACTIONS = {'startSession': 'start', 'startRest': 'startRest', 'pause': 'pause',
                 'resume': 'resume', 'cancel': 'cancel', 'toggle': 'toggle', 'getSession': 'get'}


def engine_call(msg, timeout=3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(ENGINE_SOCK)
        s.sendall((json.dumps(msg) + '\n').encode())
        buf = b''
        while not buf.endswith(b'\n'):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        return json.loads(buf)
    except (OSError, ValueError) as e:
        return {'error': f'Timer engine not reachable: {e}'}
    finally:
        s.close()


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

    if action in TIMER_ACTIONS:
        req = {'action': TIMER_ACTIONS[action]}
        if action == 'startSession':
            req.update(minutes=msg.get('minutes'), tag=msg.get('tag'))
        elif action == 'startRest':
            req.update(minutes=msg.get('minutes'))
        return engine_call(req)

    if action == 'getData':
        return store.read_data()

    if action == 'getState':
        # Everything the popup renders, in one host round-trip
        data = store.read_data()
        reply = engine_call({'action': 'get'})
        data['session'] = reply.get('session')
        if 'error' in reply:
            data['sessionError'] = reply['error']
        return data

    # Everything below mutates data.json — one exclusive transaction each
    with store.locked_data() as data:

        if action == 'setBalance':
            data['balance'] = msg['balance']
            return {'success': True}

        if action == 'addHistory':
            data['history'].insert(0, msg['entry'])
            return {'success': True}

        if action == 'earnCredits':
            data['balance'] = data.get('balance', 0) + msg['amount']
            data['history'].insert(0, msg['entry'])
            return {'success': True, 'newBalance': data['balance']}

        if action == 'spendCredits':
            balance = data.get('balance', 0)
            cost = msg['amount']
            if balance < cost and not msg.get('allowDebt', False):
                raise InsufficientCredits()
            data['balance'] = balance - cost
            data['history'].insert(0, msg['entry'])
            return {'success': True, 'newBalance': data['balance']}

        if action == 'logSpend':
            balance = data.get('balance', 0)
            cost = msg['amount']
            if balance < cost and not msg.get('allowDebt', False):
                raise InsufficientCredits()
            data['balance'] = balance - cost
            store.insert_chronological(data['history'], msg['entry'])
            return {'success': True, 'newBalance': data['balance']}

        if action == 'logEarn':
            data['balance'] = data.get('balance', 0) + msg['amount']
            store.insert_chronological(data['history'], msg['entry'])
            return {'success': True, 'newBalance': data['balance']}

        if action == 'setRewards':
            data['rewards'] = msg['rewards']
            return {'success': True}

        if action == 'setActivities':
            data['activities'] = msg['activities']
            return {'success': True}

        if action == 'updateStreak':
            data['minutesFocusedToday'] = msg.get('minutesFocusedToday', 0)
            data['lastSessionDate'] = msg.get('lastSessionDate')
            return {'success': True}

        if action == 'updateHistoryEntry':
            timestamp = msg['timestamp']
            updates = msg['updates']
            for entry in data['history']:
                if entry.get('timestamp') == timestamp:
                    entry.update(updates)
                    break
            # Re-sort history if timestamp was changed (keep newest-first order)
            if 'timestamp' in updates:
                data['history'].sort(key=lambda e: e.get('timestamp', 0), reverse=True)
            return {'success': True}

        if action == 'deleteHistoryEntry':
            timestamp = msg['timestamp']
            data['history'] = [e for e in data['history'] if e.get('timestamp') != timestamp]
            return {'success': True}

        if action == 'setTags':
            data['tags'] = msg['tags']
            return {'success': True}

        if action == 'updateSettings':
            data['settings'] = msg['settings']
            return {'success': True}

        if action == 'resetConfig':
            d = store.defaults()
            data['rewards'] = d['rewards']
            data['activities'] = d['activities']
            data['tags'] = d['tags']
            data['settings'] = d['settings']
            return {'success': True}

        if action == 'resetAll':
            data.clear()
            data.update(store.defaults())
            return {'success': True}

        raise UnknownAction(action)


class InsufficientCredits(Exception):
    """Abort the transaction without writing (data.json untouched)."""


class UnknownAction(Exception):
    pass


def main():
    while True:
        try:
            msg = read_message()
            try:
                response = handle(msg)
            except InsufficientCredits:
                response = {'error': 'Insufficient credits'}
            except UnknownAction as e:
                response = {'error': f'Unknown action: {e}'}
            send_message(response)
        except SystemExit:
            raise
        except Exception as e:
            send_message({'error': str(e)})


if __name__ == '__main__':
    main()
