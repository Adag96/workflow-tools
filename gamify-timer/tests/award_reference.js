// FROZEN REFERENCE — the award code from background.js as it was before the engine
// migration (verbatim lines; only the host call and Date.now() are parameterised).
// Used by test_engine.py to prove gamify_store.focus_award is identical. Do not edit.
function localDateStr(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

// Calculate Focus Credits for a given session length
function calculateCredits(minutes) {
  return Math.floor(minutes * (minutes + 15) / 50);
}

// Get streak bonus multiplier based on cumulative focus minutes today
function getStreakMultiplier(minutesToday) {
  if (minutesToday >= 90) return 1.30;
  if (minutesToday >= 75) return 1.20;
  if (minutesToday >= 45) return 1.10;
  return 1;
}

function award(timerState, SHARED, today, NOW_MS) {
      const localDateStrToday = today;
      const shared = SHARED;
      const settings = shared.settings || {};
      const minutesToday = shared.lastSessionDate === today
        ? (shared.minutesFocusedToday || 0)
        : 0;

      const baseCredits = calculateCredits(timerState.sessionMinutes);
      const multiplier = getStreakMultiplier(minutesToday);

      // Look up tag data for multiplier and color
      let tagColor = null;
      let tagMultiplier = 1;
      if (timerState.tag) {
        const tagObj = (shared.tags || []).find(t => t.name === timerState.tag);
        tagColor = tagObj?.color || null;
        tagMultiplier = tagObj?.multiplier || 1;
      }

      // Pause penalty: free pause allowance = maxPausePercent of session, remainder reduces credits
      const maxPausePercent = (settings?.maxPausePercent ?? 10) / 100;
      const totalPausedSeconds = timerState.totalPausedSeconds || 0;
      const sessionSeconds = timerState.sessionMinutes * 60;
      const freePauseSeconds = Math.floor(sessionSeconds * maxPausePercent);
      const penaltySeconds = Math.max(0, totalPausedSeconds - freePauseSeconds);
      const effectiveSeconds = Math.max(0, sessionSeconds - penaltySeconds);
      const pauseMultiplier = effectiveSeconds / sessionSeconds;

      const totalCredits = Math.max(0, Math.floor(baseCredits * multiplier * tagMultiplier * pauseMultiplier));

      const entry = {
        type: 'earn',
        amount: totalCredits,
        baseAmount: baseCredits,
        streakBonus: multiplier > 1 ? `+${Math.round((multiplier - 1) * 100)}%` : null,
        tagMultiplier: tagMultiplier !== 1 ? tagMultiplier : null,
        pausePenalty: penaltySeconds > 0 ? Math.round(penaltySeconds / 60 * 10) / 10 : null,
        sessionMinutes: timerState.sessionMinutes,
        tag: timerState.tag || null,
        tagColor: tagColor,
        timestamp: NOW_MS
      };
      return entry;
}

const [today, now] = process.argv.slice(2);
let input = '';
process.stdin.on('data', c => input += c).on('end', () => {
  const cases = JSON.parse(input);
  process.stdout.write(JSON.stringify(cases.map(([s, d]) => award(s, d, today, Number(now)))));
});
