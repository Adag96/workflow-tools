# Claude Lessons — Gamify Timer

Project-specific gotchas and fixes discovered while working on this extension.

---

## 2026-07-14 — Session completion could silently drop the credit award

**Category:** Reliability / MV3 service worker + native messaging

**What happened:** A completed 60-min focus session was never awarded. The popup
showed a frozen clock ("stuck at 12 min"), a stale/zero balance ("no credits"),
and no running timer. Data was not corrupt — the award simply never happened, and
the timer state got wedged.

**Root cause:** In `background.js`, the focus-completion branch of the
`chrome.alarms.onAlarm` handler had **no error handling** around its
`getSharedData()` / `nativeSend()` calls. If the native host (`host.py`) was
briefly unreachable at the exact moment of completion, the exception propagated
out of the handler: credits were not awarded, the alarm was not cleared, and the
module-level `completionInProgress` flag was left `true` — blocking all future
completion attempts while the worker lived. The popup, meanwhile, had no handling
for a failed `getState`, so it rendered the last-known (frozen) state and a
default `balance: 0`, which read as "no credits."

**Rules:**
1. The **award (`earnCredits`) is the commit point.** Do all "mark the session
   done" work (set state idle, clear alarm) only *after* it succeeds, so a retry
   can never double-award. Follow-ups like `updateStreak` and notifications are
   best-effort — wrap them so their failure can't undo a successful award.
2. On completion failure, **leave the timer `running` and the alarm active** so
   the next tick retries once the host recovers. Reset `completionInProgress` in
   a `finally`.
3. In the popup, **never let a failed `getState` clobber `state`.** Keep the last
   good state, set a `connected=false` flag, and surface it in the UI
   (`body.reconnecting` → dim balance/clock + "reconnecting…" label) so stale
   numbers don't read as current truth.

**Recovery for a dropped award:** `data.json` is the source of truth and is safe
to edit directly (back it up first). Award formula for a session:
`floor(calculateCredits(min) * streakMult * tagMult * pauseMult)` where
`calculateCredits(min) = floor(min*(min+15)/50)`, streak tiers are
1.0/1.1/1.2/1.3 at 0/45/75/90 cumulative min *before* the session, and pause
penalty only bites beyond the free `maxPausePercent` (default 10%) allowance.
The stored balance should equal the signed sum of history amounts — reconcile if
it drifts (small drifts come from history-entry edits / timed spends).

---

## 2026-09-23 — `__pycache__/` in the extension dir breaks "Reload"

**Category:** Tooling / Chrome extension loading

**What happened:** After adding the activity-credits feature, Chrome's reload
failed with "Failed to reload extension".

**Root cause:** A test did `import host` from inside the extension directory,
so Python wrote `__pycache__/` there. Chrome refuses to load an unpacked
extension that contains any file or directory whose name starts with `_`.

**Rules:**
1. Never import `host.py` from inside the extension dir. Test it with
   `PYTHONDONTWRITEBYTECODE=1` or from a scratch copy, and delete any
   `__pycache__/` before reloading.
2. Reloading the extension doesn't lose a running timer. `timerState` lives in
   `chrome.storage.local` with a wall-clock `startedAt`, and `recoverTimer()`
   re-arms the alarm when the worker loads.

---

## 2026-11-04 — Sketchybar timer widget: report state changes only, and give the host $USER

**Category:** Native messaging / integration

**What happened:** Added a `reportTimer` action so `host.py` mirrors each profile's
timer to `~/.cache/sketchybar/gamify/<instanceId>.json` for a sketchybar widget.
Two traps: the tick handler rewrites `timerState.remainingSeconds` every second, so
a naive `storage.onChanged` hook would spawn the host once a second per profile;
and the host's `sketchybar --trigger` silently failed in a stripped environment
because the sketchybar client aborts when `$USER` is unset.

**Rules:**
1. Report only when a meaningful key changes (`REPORTED_KEYS` in background.js:
   status/mode/startedAt/sessionMinutes/totalPausedSeconds/pausedAt/tag) — never on
   the per-second `remainingSeconds` writes. The widget computes time left itself.
2. Reporting is best-effort: it must never throw into timer logic.
3. Any subprocess the host launches gets `PATH` fallbacks and `USER` set
   (`pwd.getpwuid`), since browsers launch hosts with a minimal environment.
4. Test the host by running it as a script with framed stdin messages and
   `PYTHONDONTWRITEBYTECODE=1` (never `import host` from this dir — see above).

## 2026-11-04 — One engine owns the session (replaces per-profile timers + reportTimer)

**Category:** Architecture / data safety

**What happened:** Each Brave profile ran its own Pomodoro in its service worker, so
sessions fragmented across profiles, couldn't start from sketchybar and died with Brave.
Moved the session into `gamify_engine.py` (LaunchAgent `com.gamifytimer.engine`,
`install-engine.sh`); host.py forwards timer actions to its Unix socket, gamifyctl is the
CLI (sketchybar uses it). The per-profile `reportTimer` mirror above is gone.

**Rules:**
1. Every data.json read-modify-write goes through `gamify_store.locked_data()` (flock on
   `STATE_DIR/data.lock`). Never write data.json outside it — host processes run in parallel.
2. Focus awards are idempotent by `sessionId`: never award without checking history for it.
3. Credit maths is a port of the JS (`js_round` = JS Math.round). Changing it means
   updating `tests/award_reference.js` and keeping `tests/run.sh` green.
4. Tests use `GAMIFY_DATA_FILE` / `GAMIFY_STATE_DIR` / `GAMIFY_ENGINE_SOCK` temp paths and
   `GAMIFY_QUIET=1` — never the real Dropbox data.json.
5. Every Python entry point sets `sys.dont_write_bytecode = True` before importing
   gamify_store (an `__pycache__` in this folder breaks the unpacked extension).

## 2026-11-05 — read_data() wiped balance + history by "resetting" a mid-sync file

**Category:** Data safety / Dropbox File Provider

**What happened:** Completing a 60-min focus session replaced data.json with factory
defaults. Balance and history were gone, and the award itself got no streak bonus
because it was computed against the defaults.

**Root cause:** `gamify_store.read_data()` treated "file missing" (`os.path.exists`
False) and "empty/invalid JSON" as a fresh install and wrote `defaults()` over the file.
data.json lives in Dropbox's File Provider folder, where it can be briefly missing or
half-written while a sync lands. The engine's unlocked readers (`watch_balance` polls
every second, `publish`) and the locked award all go through read_data, so any read
during that window permanently replaced the real data.

**Rules:**
1. Reading never writes. An unreadable data.json is retried, then raises. Never fall
   back to defaults and save them.
2. Recovery: Dropbox version history on data.json (dropbox.com → file → Version history)
   holds the pre-wipe version. The `data.json.bak-*` files are older manual snapshots.
