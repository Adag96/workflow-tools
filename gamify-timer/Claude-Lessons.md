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
