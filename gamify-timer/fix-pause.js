// One-shot fix: rewrite the current paused session so it reflects
// having unpaused 38 min ago at the -1 penalty mark (7 min total pause).
//
// HOW TO RUN:
//   1. Open chrome://extensions
//   2. Find "Gamify Timer" and click the "service worker" link
//   3. Paste this whole file into the DevTools console and press Enter
//
// It only modifies the in-memory paused session — does NOT touch
// history, balance, or credits. Credits will be calculated normally
// when the session completes (with a 1-min pause penalty).

(async () => {
  const { timerState: ts } = await chrome.storage.local.get('timerState');
  if (!ts) { console.error('No timerState found'); return; }
  if (ts.status !== 'paused') {
    console.error(`Expected status=paused, got ${ts.status}. Aborting.`);
    return;
  }
  if (ts.mode === 'rest') {
    console.error('Session is a rest session, not a focus session. Aborting.');
    return;
  }

  const now = Date.now();
  const sessionSec = ts.sessionMinutes * 60;

  // Current pause-time accounting
  const storedPaused = ts.totalPausedSeconds || 0;
  const currentPauseSec = ts.pausedAt ? Math.floor((now - ts.pausedAt) / 1000) : 0;
  const observedTotalPaused = storedPaused + currentPauseSec;

  // We want the timer to behave as if the user resumed when total paused
  // time was exactly 7 minutes (6 free + 1 penalty = the "-1 min" mark).
  const TARGET_PAUSED_SEC = 7 * 60;
  const extraPauseToReclaim = observedTotalPaused - TARGET_PAUSED_SEC;

  if (extraPauseToReclaim <= 0) {
    console.error(
      `Already at or below 7 min total pause (${observedTotalPaused}s). ` +
      `Nothing to reclaim. Use a normal resume.`
    );
    return;
  }

  // Shift startedAt backward by `extraPauseToReclaim` seconds so the
  // wall-clock elapsed time grows by exactly that amount. Combined with
  // setting totalPausedSeconds = TARGET_PAUSED_SEC, this is mathematically
  // identical to having resumed `extraPauseToReclaim` seconds ago.
  const newStartedAt = ts.startedAt - extraPauseToReclaim * 1000;

  const newState = {
    ...ts,
    status: 'running',
    pausedAt: null,
    totalPausedSeconds: TARGET_PAUSED_SEC,
    startedAt: newStartedAt
  };

  // Sanity-check the resulting remaining time
  const newElapsed = (now - newStartedAt) / 1000;
  const newRemaining = Math.round(sessionSec - newElapsed + TARGET_PAUSED_SEC);

  console.log('Before:', {
    status: ts.status,
    sessionMinutes: ts.sessionMinutes,
    tag: ts.tag,
    storedPaused_sec: storedPaused,
    currentPauseSec,
    observedTotalPaused_min: (observedTotalPaused / 60).toFixed(1)
  });
  console.log('After:', {
    status: newState.status,
    totalPaused_min: (TARGET_PAUSED_SEC / 60).toFixed(1),
    elapsed_min: (newElapsed / 60).toFixed(1),
    remaining_min: (newRemaining / 60).toFixed(1),
    expectedPenalty_min: Math.max(0, (TARGET_PAUSED_SEC - sessionSec * 0.1) / 60).toFixed(1)
  });

  await chrome.storage.local.set({ timerState: newState });
  await chrome.alarms.create('pomodoroTick', { periodInMinutes: 1 / 60 });

  console.log('Done. Session is running again. Open the popup to verify.');
})();
