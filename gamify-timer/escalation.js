// Shared by popup.js (<script>) and background.js (importScripts).

function localDateStr(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

// Consecutive-day escalation: +12.5% of base per consecutive day, capped at 3 steps
// (400 → 450 → 500 → 550 → 550…). It punishes impulsive day-off streaks without making
// long planned breaks absurd. streak = consecutive local days immediately before `date`
// on which the reward was redeemed.
const ESCALATION_STEP = 0.125;
const ESCALATION_MAX_STEPS = 3;
// Derived from history (not a separate tracker) so live redemptions and backdated
// "Log Past Reward" entries count identically, whatever order they were logged in.
function escalatedCost(history, reward, date = new Date()) {
  if (!reward.consecutiveEscalation || reward.mode === 'timed') {
    return { streak: 0, cost: reward.cost };
  }
  const days = new Set(history
    .filter(e => e.type === 'spend' &&
      (e.rewardId != null ? e.rewardId === reward.id : e.rewardName === reward.name))
    .map(e => localDateStr(new Date(e.timestamp))));
  let streak = 0;
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1);
  while (days.has(localDateStr(d))) {
    streak++;
    d.setDate(d.getDate() - 1);
  }
  const steps = Math.min(streak, ESCALATION_MAX_STEPS);
  return { streak, cost: Math.round(reward.cost * (1 + ESCALATION_STEP * steps)) };
}
