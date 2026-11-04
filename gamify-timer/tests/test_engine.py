#!/usr/bin/env python3
"""Gamify Timer engine tests. Run with:  tests/run.sh   (never touches real data).

1. Award parity: the Python port in gamify_store.focus_award must produce exactly what the
   ORIGINAL background.js award code produced. The JS is extracted verbatim from
   tests/award_reference.js (a frozen copy of the pre-engine code) and run with node over
   a large table of inputs.
2. Engine behaviour against a temp data file (see EngineTests).
"""
import itertools, json, os, subprocess, sys, tempfile, unittest

sys.dont_write_bytecode = True   # no __pycache__ in the extension folder (Chrome refuses it)
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TMP = tempfile.mkdtemp(prefix='gamify-test-')
os.environ['GAMIFY_DATA_FILE'] = os.path.join(TMP, 'data.json')
os.environ['GAMIFY_STATE_DIR'] = os.path.join(TMP, 'state')
sys.path.insert(0, ROOT)
import gamify_store as store  # noqa: E402

TODAY = '2026-11-04'
NOW_MS = 1793800000000
TAGS = [{'id': 1, 'name': 'UJAM', 'color': '#3cecb1', 'multiplier': 1},
        {'id': 2, 'name': 'SEASON', 'color': '#ffd561', 'multiplier': 1.3},
        {'id': 3, 'name': 'STUDIES', 'color': '#42adff', 'multiplier': 1.2},
        {'id': 4, 'name': 'MUSIC', 'color': '#9a5be6', 'multiplier': 1.1},
        {'id': 5, 'name': 'ZERO', 'color': '', 'multiplier': 0}]


def cases():
    for minutes, today_min, last, tag, pause_mode, max_pause in itertools.product(
            [1, 10, 15, 20, 25, 30, 45, 60, 90, 120],
            [0, 44, 45, 74, 75, 89, 90, 200],
            [TODAY, '2026-11-03', None],
            [None, 'UJAM', 'SEASON', 'STUDIES', 'MUSIC', 'MISSING', 'ZERO'],
            ['none', 'free-1', 'free', 'free+1', '600', 'double'],
            [10, 0, 25, None]):
        session_s = minutes * 60
        free = int(session_s * ((10 if max_pause is None else max_pause) / 100))
        paused = {'none': 0, 'free-1': max(0, free - 1), 'free': free, 'free+1': free + 1,
                  '600': 600, 'double': session_s * 2}[pause_mode]
        settings = {} if max_pause is None else {'maxPausePercent': max_pause}
        yield ({'sessionMinutes': minutes, 'tag': tag, 'totalPausedSeconds': paused},
               {'settings': settings, 'tags': TAGS, 'minutesFocusedToday': today_min, 'lastSessionDate': last})


class AwardParity(unittest.TestCase):
    def test_matches_original_javascript(self):
        ref = os.path.join(HERE, 'award_reference.js')
        all_cases = list(cases())
        payload = json.dumps([[s, d] for s, d in all_cases])
        js = subprocess.run(['node', ref, TODAY, str(NOW_MS)], input=payload, capture_output=True,
                            text=True, check=True)
        expected = json.loads(js.stdout)
        self.assertEqual(len(expected), len(all_cases))
        for (session, data), exp in zip(all_cases, expected):
            got = store.focus_award(dict(session, sessionId='x'), data, TODAY, NOW_MS)
            got.pop('sessionId')
            self.assertEqual(got, exp, f'case {session} {data}')
        print(f'\n  award parity: {len(all_cases)} cases identical to the original JS')


import shutil, socket, time  # noqa: E402

ENGINE = os.path.join(ROOT, 'gamify_engine.py')
STATE = os.environ['GAMIFY_STATE_DIR']
SOCK = os.path.join(TMP, 'e.sock')
WIDGET = os.path.join(TMP, 'widget.json')
ENV = dict(os.environ, GAMIFY_ENGINE_SOCK=SOCK, GAMIFY_WIDGET_FILE=WIDGET, GAMIFY_QUIET='1',
           PYTHONDONTWRITEBYTECODE='1')


def call(msg):
    s = socket.socket(socket.AF_UNIX); s.settimeout(3); s.connect(SOCK)
    s.sendall((json.dumps(msg) + '\n').encode()); buf = b''
    while not buf.endswith(b'\n'):
        c = s.recv(65536)
        if not c: break
        buf += c
    s.close(); return json.loads(buf)


class EngineTests(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(STATE, ignore_errors=True)
        data = store.defaults(); data['tags'] = TAGS; data['balance'] = 100
        os.makedirs(STATE, exist_ok=True); store.write_data(data)
        self.proc = None

    def tearDown(self):
        self.stop()

    def start_engine(self):
        self.proc = subprocess.Popen(['/usr/bin/python3', '-B', ENGINE], env=ENV,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(50):
            if os.path.exists(SOCK):
                try: call({'action': 'get'}); return
                except OSError: pass
            time.sleep(0.1)
        self.fail('engine did not start: ' + self.proc.stderr.read().decode())

    def stop(self):
        if self.proc:
            self.proc.terminate(); self.proc.wait(5); self.proc = None

    def write_session(self, **kw):
        sess = dict(status='running', mode='focus', sessionMinutes=25, pausedAt=None,
                    totalPausedSeconds=0, tag='STUDIES', sessionId='sess-1', **kw)
        with open(os.path.join(STATE, 'session.json'), 'w') as f: json.dump(sess, f)

    def test_one_session_at_a_time_and_pause_accounting(self):
        self.start_engine()
        r = call({'action': 'start', 'minutes': 25, 'tag': 'UJAM'})
        self.assertEqual(r['session']['status'], 'running')
        self.assertTrue(os.path.exists(WIDGET), 'widget mirror written')
        self.assertIn('error', call({'action': 'start', 'minutes': 10, 'tag': 'MUSIC'}))
        call({'action': 'pause'}); time.sleep(2.1)
        r = call({'action': 'toggle'})                       # resume
        self.assertEqual(r['session']['status'], 'running')
        self.assertGreaterEqual(r['session']['totalPausedSeconds'], 2)
        call({'action': 'cancel'})
        self.assertFalse(os.path.exists(WIDGET), 'widget mirror removed when idle')
        self.assertEqual(store.read_data()['balance'], 100, 'cancel awards nothing')

    def test_completes_after_restart_and_never_double_awards(self):
        started = int(time.time() * 1000) - 26 * 60 * 1000   # 25-min session, already overdue
        self.write_session(startedAt=started)
        self.start_engine(); time.sleep(1.5)
        data = store.read_data()
        awards = [e for e in data['history'] if e.get('sessionId') == 'sess-1']
        self.assertEqual(len(awards), 1)
        expected = store.calculate_credits(25)                # STUDIES ×1.2, no streak/pause
        self.assertEqual(awards[0]['amount'], int(expected * 1.2))
        self.assertEqual(data['balance'], 100 + awards[0]['amount'])
        self.assertEqual(data['minutesFocusedToday'], 25)
        self.assertEqual(call({'action': 'get'})['session']['status'], 'idle')
        # Replay the same overdue session (as if the engine died before marking it idle)
        self.stop(); self.write_session(startedAt=started); self.start_engine(); time.sleep(1.5)
        data = store.read_data()
        self.assertEqual(len([e for e in data['history'] if e.get('sessionId') == 'sess-1']), 1)
        self.assertEqual(data['balance'], 100 + awards[0]['amount'], 'no double award')

    def test_concurrent_writers_lose_nothing(self):
        script = ('import sys; sys.dont_write_bytecode=True; sys.path.insert(0, %r); import gamify_store as s\n'
                  'with s.locked_data() as d:\n'
                  '    d["history"].insert(0, {"type":"earn","amount":1,"timestamp":0}); d["balance"] += 1\n') % ROOT
        procs = [subprocess.Popen([sys.executable, '-B', '-c', script], env=ENV) for _ in range(20)]
        for p in procs: p.wait()
        data = store.read_data()
        self.assertEqual(len(data['history']), 20)
        self.assertEqual(data['balance'], 120)


if __name__ == '__main__':
    unittest.main(verbosity=2)
