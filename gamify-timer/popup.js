// State
let state = {
  timerState: { status: 'idle', remainingSeconds: 0, sessionMinutes: 25 },
  balance: 0,
  history: [],
  rewards: [],
  tags: [],
  settings: {}
};

let selectedMinutes = 25;
let selectedTag = null;
let editingRewardId = null;
let rewardMode = 'fixed';
let spendTimer = null; // { rewardId, rewardName, costPerMin, startedAt, maxMinutes }
let spendInterval = null;
let tickInterval = null;
let initialRenderDone = false;
let lastRingMode = null; // 'focus' | 'pause' | 'idle' — track to snap on mode change
let historyView = 'list';
let chartWeekOffset = 0;
const CHART_DAYS = 7;

// Init
document.addEventListener('DOMContentLoaded', async () => {
  await loadState();
  await loadSelectedTag();
  loadTheme();
  setupThemeToggle();
  setupTabs();
  setupTimerControls();
  setupRewardModal();
  setupHistoryChart();
  setupSettings();
  render();
  startTicking();
});

// Theme
async function loadTheme() {
  const { theme } = await chrome.storage.local.get('theme');
  document.body.classList.toggle('light', theme === 'light');
  updateThemeIcon();
}

function setupThemeToggle() {
  document.getElementById('theme-toggle').addEventListener('click', async () => {
    const isLight = document.body.classList.toggle('light');
    await chrome.storage.local.set({ theme: isLight ? 'light' : 'dark' });
    updateThemeIcon();
  });
}

function updateThemeIcon() {
  const btn = document.getElementById('theme-toggle');
  btn.textContent = document.body.classList.contains('light') ? '\u263E' : '\u2600';
}

// True when the last getState round-trip returned usable data.
// When false, the popup shows a "reconnecting" hint instead of a frozen
// clock and a fake zero balance (which happens when the MV3 service worker
// is asleep or the native host is briefly unreachable).
let connected = true;

async function loadState() {
  try {
    const fresh = await chrome.runtime.sendMessage({ action: 'getState' });
    // A live worker with a reachable native host returns an object with a
    // numeric balance. Anything else (undefined / {error} from a failed
    // getSharedData) means we should keep the last good state, not clobber it.
    if (fresh && typeof fresh.balance === 'number' && fresh.timerState) {
      state = fresh;
      connected = true;
    } else {
      connected = false;
    }
  } catch (e) {
    // sendMessage rejects when the worker is being (re)spawned. Keep the last
    // known state; the next tick will retry.
    connected = false;
  }
}

async function loadSelectedTag() {
  const { selectedTag: saved } = await chrome.storage.local.get('selectedTag');
  if (saved && (state.tags || []).some(t => t.name === saved)) {
    selectedTag = saved;
  }
}

async function saveSelectedTag() {
  await chrome.storage.local.set({ selectedTag: selectedTag || '' });
}

function startTicking() {
  if (tickInterval) clearInterval(tickInterval);
  tickInterval = setInterval(async () => {
    await loadState();
    render();
  }, 1000);
}

// Tabs
function setupTabs() {
  document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      tab.classList.add('active');
      document.getElementById(`tab-${tab.dataset.tab}`).classList.add('active');
      if (tab.dataset.tab === 'history') renderHistory();
      if (tab.dataset.tab === 'rewards') renderRewards();
      if (tab.dataset.tab === 'settings') { loadSettings(); renderTags(); }
    });
  });
}

// Timer controls
function setupTimerControls() {
  // Session length selection
  document.querySelectorAll('.length-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (state.timerState.status !== 'idle') return;
      selectedMinutes = parseInt(btn.dataset.minutes);
      document.querySelectorAll('.length-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      renderTimer();
    });
  });

  document.getElementById('btn-start').addEventListener('click', async () => {
    if (!selectedTag) {
      alert('Please select a tag before starting a session.');
      return;
    }
    await chrome.runtime.sendMessage({ action: 'startSession', minutes: selectedMinutes, tag: selectedTag });
    await loadState();
    render();
  });

  document.getElementById('btn-pause').addEventListener('click', async () => {
    await chrome.runtime.sendMessage({ action: 'pause' });
    await loadState();
    render();
  });

  document.getElementById('btn-resume').addEventListener('click', async () => {
    await chrome.runtime.sendMessage({ action: 'resume' });
    await loadState();
    render();
  });

  document.getElementById('btn-cancel').addEventListener('click', async () => {
    if (confirm('Cancel this session? No credits will be earned.')) {
      await chrome.runtime.sendMessage({ action: 'cancel' });
      await loadState();
      render();
    }
  });

}

// Render
function render() {
  // Flag stale data so the balance/clock aren't silently shown as truth when
  // the worker or native host is unreachable.
  document.body.classList.toggle('reconnecting', !connected);
  renderBalance();
  renderTimer();
  renderStreak();
  renderTagSelector();
}

function renderBalance() {
  const isNegative = state.balance < 0;
  const balanceEl = document.getElementById('balance-display');
  document.getElementById('balance-amount').textContent = state.balance;
  balanceEl.classList.toggle('negative', isNegative);
  document.querySelectorAll('.rewards-balance-amount').forEach(el => {
    el.textContent = state.balance;
    el.classList.toggle('negative', isNegative);
  });
}

function renderTimer() {
  const ts = state.timerState;
  const timerMinutes = document.getElementById('timer-minutes');
  const timerSeconds = document.getElementById('timer-seconds');
  const timerLabel = document.getElementById('timer-label');
  const creditPreview = document.getElementById('credit-preview');
  const ringProgress = document.getElementById('ring-progress');

  const btnStart = document.getElementById('btn-start');
  const btnPause = document.getElementById('btn-pause');
  const btnResume = document.getElementById('btn-resume');
  const btnCancel = document.getElementById('btn-cancel');
  const sessionLengths = document.getElementById('session-lengths');

  const circumference = 2 * Math.PI * 90; // matches r=90 in SVG

  if (ts.status === 'idle') {
    const mins = selectedMinutes;
    timerMinutes.textContent = String(mins).padStart(2, '0');
    timerSeconds.textContent = '00';
    timerLabel.textContent = 'Ready to focus';

    const baseCredits = calculateCredits(mins);
    const tagObj = selectedTag ? (state.tags || []).find(t => t.name === selectedTag) : null;
    const tagMult = tagObj?.multiplier || 1;
    const today = localDateStr();
    const minutesToday = state.lastSessionDate === today ? (state.minutesFocusedToday || 0) : 0;
    const streakMult = getStreakMultiplier(minutesToday);
    const credits = Math.floor(baseCredits * tagMult * streakMult);
    creditPreview.textContent = `Worth ${credits} FC`;

    setRingOffset(ringProgress, '0', 'idle');
    ringProgress.classList.remove('rest', 'pause-budget', 'pause-penalty');
    const ringColor = tagObj?.color || null;
    ringProgress.style.stroke = ringColor || '';
    ringProgress.style.filter = ringColor ? `drop-shadow(0 0 6px ${ringColor}40)` : '';

    btnStart.classList.remove('hidden');
    btnPause.classList.add('hidden');
    btnResume.classList.add('hidden');
    btnCancel.classList.add('hidden');
    sessionLengths.style.opacity = '1';
    sessionLengths.style.pointerEvents = 'auto';
    document.getElementById('app').classList.remove('running');
  } else {
    // Compute remaining time from wall clock for accurate display
    let remaining;
    if (ts.status === 'running' && ts.startedAt) {
      const elapsed = (Date.now() - ts.startedAt) / 1000;
      remaining = Math.max(0, Math.round(
        ts.sessionMinutes * 60 - elapsed + (ts.totalPausedSeconds || 0)
      ));
    } else {
      remaining = ts.remainingSeconds;
    }
    const mins = Math.floor(remaining / 60);
    const secs = remaining % 60;
    timerMinutes.textContent = String(mins).padStart(2, '0');
    timerSeconds.textContent = String(secs).padStart(2, '0');

    const totalSeconds = ts.sessionMinutes * 60;
    const elapsedDisplay = totalSeconds - remaining;
    const progress = elapsedDisplay / totalSeconds;

    if (ts.mode === 'rest') {
      setRingOffset(ringProgress, String(circumference * (1 - progress)), 'rest');
      timerLabel.textContent = 'Resting...';
      ringProgress.classList.remove('pause-budget', 'pause-penalty');
      ringProgress.classList.add('rest');
      ringProgress.style.stroke = '';
      ringProgress.style.filter = '';
      creditPreview.textContent = '';
    } else if (ts.status === 'paused') {
      // Show pause budget countdown
      ringProgress.classList.remove('rest');
      ringProgress.style.stroke = '';
      ringProgress.style.filter = '';
      const maxPausePercent = (state.settings?.maxPausePercent ?? 10) / 100;
      const sessionSec = ts.sessionMinutes * 60;
      const freePauseSec = Math.floor(sessionSec * maxPausePercent);
      const alreadyPaused = ts.totalPausedSeconds || 0;
      const currentPauseSec = ts.pausedAt ? Math.floor((Date.now() - ts.pausedAt) / 1000) : 0;
      const totalPaused = alreadyPaused + currentPauseSec;
      const freeRemaining = Math.max(0, freePauseSec - totalPaused);
      const inPenalty = freeRemaining === 0;

      if (inPenalty) {
        const penaltySec = totalPaused - freePauseSec;
        const penaltyMin = Math.floor(penaltySec / 60);
        const penaltySecs = penaltySec % 60;
        timerMinutes.textContent = String(penaltyMin).padStart(2, '0');
        timerSeconds.textContent = String(penaltySecs).padStart(2, '0');
        timerLabel.textContent = 'Penalty accruing';
        creditPreview.textContent = `−${Math.ceil(penaltySec / 60)} min penalty`;
        ringProgress.classList.remove('pause-budget');
        ringProgress.classList.add('pause-penalty');
        setRingOffset(ringProgress, String(circumference), 'penalty');
      } else {
        const freeMin = Math.floor(freeRemaining / 60);
        const freeSec = freeRemaining % 60;
        timerMinutes.textContent = String(freeMin).padStart(2, '0');
        timerSeconds.textContent = String(freeSec).padStart(2, '0');
        timerLabel.textContent = 'Paused — free time left';
        creditPreview.textContent = '';
        ringProgress.classList.remove('pause-penalty');
        ringProgress.classList.add('pause-budget');
        const pauseProgress = 1 - (freeRemaining / freePauseSec);
        setRingOffset(ringProgress, String(circumference * pauseProgress), 'pause');
      }
    } else {
      timerLabel.textContent = 'Focusing...';
      ringProgress.classList.remove('rest', 'pause-budget', 'pause-penalty');
      setRingOffset(ringProgress, String(circumference * (1 - progress)), 'focus');
      const baseCredits = calculateCredits(ts.sessionMinutes);
      const runningTagObj = ts.tag ? (state.tags || []).find(t => t.name === ts.tag) : null;
      const focusRingColor = runningTagObj?.color || null;
      ringProgress.style.stroke = focusRingColor || '';
      ringProgress.style.filter = focusRingColor ? `drop-shadow(0 0 6px ${focusRingColor}40)` : '';
      const runningTagMult = runningTagObj?.multiplier || 1;
      const credits = Math.floor(baseCredits * runningTagMult);
      creditPreview.textContent = `Earning ${credits} FC`;
    }

    btnStart.classList.add('hidden');
    sessionLengths.style.opacity = '0.3';
    sessionLengths.style.pointerEvents = 'none';

    if (ts.status === 'running') {
      btnPause.classList.remove('hidden');
      btnResume.classList.add('hidden');
    } else {
      btnPause.classList.add('hidden');
      btnResume.classList.remove('hidden');
    }
    btnCancel.classList.remove('hidden');
    document.getElementById('app').classList.add('running');
  }
}

function renderStreak() {
  const today = localDateStr();
  const minutesToday = state.lastSessionDate === today ? (state.minutesFocusedToday || 0) : 0;
  const multiplier = getStreakMultiplier(minutesToday);

  const el = document.getElementById('streak-display');
  if (multiplier > 1) {
    el.innerHTML = `<span id="streak-bonus">+${Math.round((multiplier - 1) * 100)}% streak bonus</span>`;
  } else {
    el.textContent = '';
  }
}

// Tag Selector
function renderTagSelector() {
  const container = document.getElementById('tag-selector');
  const ts = state.timerState;
  const tags = state.tags || [];

  if (tags.length === 0) {
    container.innerHTML = '';
    return;
  }

  // While running, lock to the active tag
  const isLocked = ts.status !== 'idle';
  const activeTag = isLocked ? ts.tag : selectedTag;

  let html = '';
  for (const tag of tags) {
    const color = tag.color || '#6C5CE7';
    const isActive = activeTag === tag.name;
    html += `<button class="tag-pill${isActive ? ' active' : ''}" data-tag="${escapeHtml(tag.name)}">
      <span class="tag-dot" style="background:${color}"></span>${escapeHtml(tag.name)}
    </button>`;
  }

  container.innerHTML = html;
  container.classList.toggle('disabled', isLocked);

  if (!isLocked) {
    container.querySelectorAll('.tag-pill').forEach(btn => {
      btn.addEventListener('click', () => {
        const tagName = btn.dataset.tag;
        // Toggle: clicking active tag deselects it
        selectedTag = selectedTag === tagName ? null : tagName;
        saveSelectedTag();
        renderTagSelector();
        renderTimer();
      });
    });
  }
}

// Rewards
function renderRewards() {
  const list = document.getElementById('rewards-list');
  const tiers = [
    { num: 1, label: 'Small Indulgences' },
    { num: 2, label: 'Medium Indulgences' },
    { num: 3, label: 'Big Indulgences' },
    { num: 4, label: 'Nuclear' }
  ];

  let html = '';
  for (const tier of tiers) {
    const tierRewards = state.rewards.filter(r => r.tier === tier.num)
      .sort((a, b) => a.cost - b.cost);
    if (tierRewards.length === 0) continue;

    html += `<div style="font-size:11px;color:#666;padding:6px 0 2px;text-transform:uppercase;letter-spacing:0.5px;">
      ${tier.label}
    </div>`;

    for (const r of tierRewards) {
      const isTimed = r.mode === 'timed';
      const debtAllowed = state.settings?.allowDebt || false;

      // Consecutive day escalation (only for rewards with escalation enabled)
      let streak = 0;
      let effectiveCost = r.cost;
      if (r.consecutiveEscalation && !isTimed) {
        const consec = state.consecutiveRedemptions || {};
        const tracking = consec[String(r.id)];
        const today = new Date().toISOString().slice(0, 10);
        const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
        if (tracking) {
          if (tracking.lastDate === today) {
            streak = tracking.streak;
          } else if (tracking.lastDate === yesterday) {
            streak = tracking.streak + 1;
          }
        }
        effectiveCost = Math.round(r.cost * Math.pow(1.1, streak));
      }

      const canAfford = state.balance >= effectiveCost || (debtAllowed && !isTimed);
      const canStartTimed = isTimed && (state.balance >= r.cost || debtAllowed);
      const enabled = isTimed ? canStartTimed : canAfford;
      const costLabel = isTimed ? `${r.cost} FC/min` : (streak > 0 ? `${effectiveCost} FC (+${streak}x)` : `${r.cost} FC`);
      const neededMore = effectiveCost - state.balance;
      const btnLabel = (isTimed ? canStartTimed : canAfford)
        ? 'Redeem'
        : (isTimed ? 'Need credits' : `Need ${neededMore} more`);
      const deficit = state.balance < effectiveCost;
      const btnClass = isTimed ? 'redeem-timed-btn' : 'redeem-btn';
      html += `
        <div class="reward-item">
          <span class="reward-emoji">${r.emoji}</span>
          <div class="reward-info">
            <div class="reward-name">${escapeHtml(r.name)}</div>
            <div class="reward-cost">${costLabel}</div>
          </div>
          <div class="reward-actions">
            <button class="edit-reward-btn" data-id="${r.id}" title="Edit">&#9998;</button>
            <button class="delete-reward-btn" data-id="${r.id}" title="Delete">&times;</button>
            <button class="${btnClass}${deficit ? ' redeem-deficit' : ''}" data-id="${r.id}" ${enabled ? '' : 'disabled'}>
              ${btnLabel}
            </button>
          </div>
        </div>`;
    }
  }

  list.innerHTML = html;

  // Bind redeem buttons
  list.querySelectorAll('.redeem-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const reward = state.rewards.find(r => r.id === parseInt(btn.dataset.id));
      // Compute escalated cost for confirm dialog
      let displayCost = reward.cost;
      if (reward.consecutiveEscalation) {
        const consec = state.consecutiveRedemptions || {};
        const tracking = consec[String(reward.id)];
        const today = new Date().toISOString().slice(0, 10);
        const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
        let streak = 0;
        if (tracking) {
          if (tracking.lastDate === today) streak = tracking.streak;
          else if (tracking.lastDate === yesterday) streak = tracking.streak + 1;
        }
        displayCost = Math.round(reward.cost * Math.pow(1.1, streak));
      }
      if (confirm(`Redeem "${reward.name}" for ${displayCost} FC?`)) {
        const result = await chrome.runtime.sendMessage({ action: 'redeem', rewardId: reward.id });
        if (result?.error) {
          alert(result.error);
        }
        await loadState();
        render();
        renderRewards();
      }
    });
  });

  // Bind timed redeem buttons
  list.querySelectorAll('.redeem-timed-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const reward = state.rewards.find(r => r.id === parseInt(btn.dataset.id));
      const debtAllowed = state.settings?.allowDebt || false;
      const maxMinutes = debtAllowed ? Infinity : Math.floor(state.balance / reward.cost);
      if (maxMinutes < 1) {
        alert(`You need at least ${reward.cost} FC for 1 minute.`);
        return;
      }
      showTimedChoice(reward, maxMinutes);
    });
  });

  // Bind edit buttons
  list.querySelectorAll('.edit-reward-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const reward = state.rewards.find(r => r.id === parseInt(btn.dataset.id));
      editingRewardId = reward.id;
      rewardMode = reward.mode || 'fixed';
      document.getElementById('modal-title').textContent = 'Edit Reward';
      document.getElementById('reward-name').value = reward.name;
      document.getElementById('reward-emoji').value = reward.emoji;
      document.getElementById('reward-cost').value = reward.cost;
      document.getElementById('reward-tier').value = reward.tier;
      document.getElementById('reward-escalation').checked = reward.consecutiveEscalation || false;
      document.querySelectorAll('.mode-btn').forEach(b => b.classList.toggle('active', b.dataset.mode === rewardMode));
      document.getElementById('reward-cost-label').textContent = rewardMode === 'timed' ? 'FC/min' : 'FC';
      document.getElementById('reward-cost').placeholder = rewardMode === 'timed' ? 'FC per minute' : 'Cost (FC)';
      document.getElementById('reward-modal').classList.remove('hidden');
    });
  });

  // Bind delete buttons
  list.querySelectorAll('.delete-reward-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const reward = state.rewards.find(r => r.id === parseInt(btn.dataset.id));
      if (confirm(`Delete "${reward.name}"?`)) {
        const updated = state.rewards.filter(r => r.id !== reward.id);
        await chrome.runtime.sendMessage({ action: 'updateRewards', rewards: updated });
        await loadState();
        renderRewards();
      }
    });
  });
}

// Timed reward choice (timer vs manual minutes)
function showTimedChoice(reward, maxMinutes) {
  const choice = document.getElementById('timed-choice');
  const rewardsList = document.getElementById('rewards-list');
  const actionsRow = document.getElementById('btn-add-reward').parentElement;

  choice.querySelector('.timed-choice-name').textContent = `${reward.emoji} ${reward.name}`;
  choice.querySelector('.timed-choice-info').textContent = maxMinutes === Infinity
    ? `${reward.cost} FC/min · No limit`
    : `${reward.cost} FC/min · Max ${maxMinutes} min`;

  choice.classList.remove('hidden');
  rewardsList.classList.add('hidden');
  actionsRow.classList.add('hidden');

  const startBtn = document.getElementById('btn-timed-start');
  const manualBtn = document.getElementById('btn-timed-manual');
  const cancelBtn = document.getElementById('btn-timed-cancel');

  const cleanup = () => {
    choice.classList.add('hidden');
    rewardsList.classList.remove('hidden');
    actionsRow.classList.remove('hidden');
    startBtn.replaceWith(startBtn.cloneNode(true));
    manualBtn.replaceWith(manualBtn.cloneNode(true));
    cancelBtn.replaceWith(cancelBtn.cloneNode(true));
  };

  startBtn.addEventListener('click', () => {
    cleanup();
    startSpendTimer(reward, maxMinutes);
  });

  manualBtn.addEventListener('click', async () => {
    const input = prompt(maxMinutes === Infinity ? 'How many minutes?' : `How many minutes? (max ${maxMinutes})`);
    if (input === null) return;
    const minutes = parseInt(input);
    if (isNaN(minutes) || minutes < 1) {
      alert('Enter a valid number of minutes.');
      return;
    }
    if (maxMinutes !== Infinity && minutes > maxMinutes) {
      alert(`You can only afford ${maxMinutes} minutes.`);
      return;
    }
    const totalCost = minutes * reward.cost;
    const entry = {
      type: 'spend',
      amount: totalCost,
      rewardName: reward.name,
      rewardEmoji: reward.emoji,
      timedMinutes: minutes,
      timestamp: Date.now()
    };
    await chrome.runtime.sendMessage({ action: 'timedSpend', amount: totalCost, entry });
    cleanup();
    await loadState();
    render();
    renderRewards();
  });

  cancelBtn.addEventListener('click', cleanup);
}

// Spend Timer (timed rewards)
function startSpendTimer(reward, maxMinutes) {
  spendTimer = {
    rewardId: reward.id,
    rewardName: reward.name,
    rewardEmoji: reward.emoji,
    costPerMin: reward.cost,
    startedAt: Date.now(),
    maxMinutes
  };

  const overlay = document.getElementById('spend-timer');
  const rewardsList = document.getElementById('rewards-list');
  const actionsRow = document.getElementById('btn-add-reward').parentElement;

  overlay.classList.remove('hidden');
  rewardsList.classList.add('hidden');
  actionsRow.classList.add('hidden');

  overlay.querySelector('.spend-timer-name').textContent = `${reward.emoji} ${reward.name}`;
  overlay.querySelector('.spend-timer-limit').textContent = maxMinutes === Infinity
    ? `${reward.cost} FC/min · No max`
    : `Max: ${maxMinutes} min (${maxMinutes * reward.cost} FC)`;

  updateSpendTimerDisplay();

  if (spendInterval) clearInterval(spendInterval);
  spendInterval = setInterval(() => {
    const elapsed = Math.floor((Date.now() - spendTimer.startedAt) / 1000);
    const elapsedMin = Math.floor(elapsed / 60);

    // Auto-stop if max reached
    if (elapsedMin >= spendTimer.maxMinutes) {
      stopSpendTimer();
      return;
    }

    updateSpendTimerDisplay();
  }, 1000);
}

function updateSpendTimerDisplay() {
  if (!spendTimer) return;
  const elapsed = Math.floor((Date.now() - spendTimer.startedAt) / 1000);
  const mins = Math.floor(elapsed / 60);
  const secs = elapsed % 60;
  const cost = Math.max(1, Math.ceil(elapsed / 60)) * spendTimer.costPerMin;

  const overlay = document.getElementById('spend-timer');
  overlay.querySelector('.spend-timer-clock').textContent = `${mins}:${String(secs).padStart(2, '0')}`;
  overlay.querySelector('.spend-timer-cost').textContent = `${cost} FC spent`;
}

async function stopSpendTimer() {
  if (!spendTimer) return;
  if (spendInterval) {
    clearInterval(spendInterval);
    spendInterval = null;
  }

  const elapsed = Math.floor((Date.now() - spendTimer.startedAt) / 1000);
  const minutesUsed = Math.max(1, Math.ceil(elapsed / 60));
  const totalCost = minutesUsed * spendTimer.costPerMin;

  const entry = {
    type: 'spend',
    amount: totalCost,
    rewardName: spendTimer.rewardName,
    rewardEmoji: spendTimer.rewardEmoji,
    timedMinutes: minutesUsed,
    timestamp: Date.now()
  };

  await chrome.runtime.sendMessage({
    action: 'timedSpend',
    amount: totalCost,
    entry
  });

  spendTimer = null;

  const overlay = document.getElementById('spend-timer');
  overlay.classList.add('hidden');
  document.getElementById('rewards-list').classList.remove('hidden');
  document.getElementById('btn-add-reward').parentElement.classList.remove('hidden');

  await loadState();
  render();
  renderRewards();

  alert(`Spent ${totalCost} FC (${minutesUsed} min)`);
}

// Reward Modal
function setupRewardModal() {
  // Mode toggle
  document.querySelectorAll('.mode-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.mode-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      rewardMode = btn.dataset.mode;
      document.getElementById('reward-cost-label').textContent = rewardMode === 'timed' ? 'FC/min' : 'FC';
      document.getElementById('reward-cost').placeholder = rewardMode === 'timed' ? 'FC per minute' : 'Cost (FC)';
    });
  });

  // Stop spend timer
  document.getElementById('btn-spend-stop').addEventListener('click', () => {
    stopSpendTimer();
  });

  document.getElementById('btn-add-reward').addEventListener('click', () => {
    editingRewardId = null;
    rewardMode = 'fixed';
    document.getElementById('modal-title').textContent = 'Add Reward';
    document.getElementById('reward-name').value = '';
    document.getElementById('reward-emoji').value = '';
    document.getElementById('reward-cost').value = '';
    document.getElementById('reward-tier').value = '1';
    document.getElementById('reward-escalation').checked = false;
    document.querySelectorAll('.mode-btn').forEach(b => b.classList.toggle('active', b.dataset.mode === 'fixed'));
    document.getElementById('reward-cost-label').textContent = 'FC';
    document.getElementById('reward-cost').placeholder = 'Cost (FC)';
    document.getElementById('reward-modal').classList.remove('hidden');
  });

  document.getElementById('btn-cancel-reward').addEventListener('click', () => {
    document.getElementById('reward-modal').classList.add('hidden');
  });

  document.getElementById('btn-save-reward').addEventListener('click', async () => {
    const name = document.getElementById('reward-name').value.trim();
    const emoji = document.getElementById('reward-emoji').value.trim() || '🎁';
    const cost = parseInt(document.getElementById('reward-cost').value);
    const tier = parseInt(document.getElementById('reward-tier').value);
    const consecutiveEscalation = document.getElementById('reward-escalation').checked;

    if (!name || !cost || cost < 1) {
      alert('Please fill in name and cost.');
      return;
    }

    let rewards = [...state.rewards];

    if (editingRewardId) {
      rewards = rewards.map(r =>
        r.id === editingRewardId ? { ...r, name, emoji, cost, tier, mode: rewardMode, consecutiveEscalation } : r
      );
    } else {
      const maxId = rewards.reduce((max, r) => Math.max(max, r.id), 0);
      rewards.push({ id: maxId + 1, name, emoji, cost, tier, mode: rewardMode, consecutiveEscalation });
    }

    await chrome.runtime.sendMessage({ action: 'updateRewards', rewards });
    await loadState();
    renderRewards();
    document.getElementById('reward-modal').classList.add('hidden');
  });

  // Log Reward
  const logOverlay = document.getElementById('log-reward-overlay');
  const logSelect = document.getElementById('log-reward-select');
  const logMinutesRow = document.getElementById('log-reward-minutes-row');
  const logMinutesInput = document.getElementById('log-reward-minutes');
  const logDateInput = document.getElementById('log-reward-date');
  const logTimeInput = document.getElementById('log-reward-time');
  const logCostDisplay = document.getElementById('log-reward-cost-display');

  function updateLogCost() {
    const reward = state.rewards.find(r => r.id === parseInt(logSelect.value));
    if (!reward) { logCostDisplay.textContent = '0'; return; }
    if (reward.mode === 'timed') {
      const mins = parseInt(logMinutesInput.value) || 0;
      logCostDisplay.textContent = mins * reward.cost;
    } else {
      logCostDisplay.textContent = reward.cost;
    }
  }

  logSelect.addEventListener('change', () => {
    const reward = state.rewards.find(r => r.id === parseInt(logSelect.value));
    if (reward && reward.mode === 'timed') {
      logMinutesRow.classList.remove('hidden');
    } else {
      logMinutesRow.classList.add('hidden');
      logMinutesInput.value = '';
    }
    updateLogCost();
  });

  logMinutesInput.addEventListener('input', updateLogCost);

  document.getElementById('btn-log-reward').addEventListener('click', () => {
    // Populate select sorted by tier then cost
    const sorted = [...state.rewards].sort((a, b) => a.tier - b.tier || a.cost - b.cost);
    logSelect.innerHTML = sorted.map(r =>
      `<option value="${r.id}">${r.emoji} ${r.name} — ${r.mode === 'timed' ? r.cost + ' FC/min' : r.cost + ' FC'}</option>`
    ).join('');
    // Default date/time to now
    const now = new Date();
    logDateInput.value = localDateStr(now);
    logTimeInput.value = now.toTimeString().slice(0, 5);
    // Reset minutes
    logMinutesRow.classList.add('hidden');
    logMinutesInput.value = '';
    // Check first reward in sorted list
    const firstReward = sorted[0];
    if (firstReward && firstReward.mode === 'timed') {
      logMinutesRow.classList.remove('hidden');
    }
    updateLogCost();
    logOverlay.classList.remove('hidden');
  });

  document.getElementById('btn-log-cancel').addEventListener('click', () => {
    logOverlay.classList.add('hidden');
  });

  document.getElementById('btn-log-submit').addEventListener('click', async () => {
    const reward = state.rewards.find(r => r.id === parseInt(logSelect.value));
    if (!reward) return;

    let amount;
    let timedMinutes = null;
    if (reward.mode === 'timed') {
      const mins = parseInt(logMinutesInput.value);
      if (!mins || mins < 1) {
        alert('Enter a valid number of minutes.');
        return;
      }
      timedMinutes = mins;
      amount = mins * reward.cost;
    } else {
      amount = reward.cost;
    }

    const dateVal = logDateInput.value;
    const timeVal = logTimeInput.value;
    if (!dateVal || !timeVal) {
      alert('Please select a date and time.');
      return;
    }

    const timestamp = new Date(`${dateVal}T${timeVal}:00`).getTime();
    if (isNaN(timestamp)) {
      alert('Invalid date or time.');
      return;
    }

    const entry = {
      type: 'spend',
      amount,
      rewardName: reward.name,
      rewardEmoji: reward.emoji,
      timestamp
    };
    if (timedMinutes) entry.timedMinutes = timedMinutes;

    const result = await chrome.runtime.sendMessage({ action: 'logReward', amount, entry });
    if (result.error) {
      alert(result.error);
      return;
    }

    logOverlay.classList.add('hidden');
    await loadState();
    render();
    renderRewards();
  });
}

// History
function setupHistoryChart() {
  document.querySelectorAll('.history-view-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      historyView = btn.dataset.view;
      document.querySelectorAll('.history-view-btn').forEach(b => b.classList.toggle('active', b === btn));
      chartWeekOffset = 0;
      renderHistory();
    });
  });

  document.getElementById('chart-prev').addEventListener('click', () => {
    chartWeekOffset++;
    renderChart();
  });

  document.getElementById('chart-next').addEventListener('click', () => {
    if (chartWeekOffset > 0) chartWeekOffset--;
    renderChart();
  });
}

function aggregateHistoryByDay(history) {
  const byDay = {};
  for (const entry of history) {
    const dateStr = localDateStr(new Date(entry.timestamp));
    if (!byDay[dateStr]) byDay[dateStr] = { earned: 0, spent: 0 };
    if (entry.type === 'earn') {
      byDay[dateStr].earned += entry.amount;
    } else {
      byDay[dateStr].spent += entry.amount;
    }
  }
  return byDay;
}

function renderChart() {
  const byDay = aggregateHistoryByDay(state.history);
  const allDates = Object.keys(byDay).sort().reverse();

  if (allDates.length === 0) {
    document.getElementById('chart-bars').innerHTML =
      '<div style="text-align:center;color:var(--text-faint);padding:20px;font-size:13px;">No data yet.</div>';
    document.getElementById('chart-date-range').textContent = '';
    document.getElementById('chart-prev').disabled = true;
    document.getElementById('chart-next').disabled = true;
    return;
  }

  const startIdx = chartWeekOffset * CHART_DAYS;
  const pageDates = allDates.slice(startIdx, startIdx + CHART_DAYS);

  document.getElementById('chart-prev').disabled = (startIdx + CHART_DAYS >= allDates.length);
  document.getElementById('chart-next').disabled = (chartWeekOffset === 0);

  const fmtDate = (s) => {
    const d = new Date(s + 'T12:00:00');
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
  };
  const newest = pageDates[0];
  const oldest = pageDates[pageDates.length - 1];
  document.getElementById('chart-date-range').textContent =
    oldest === newest ? fmtDate(newest) : `${fmtDate(oldest)} \u2013 ${fmtDate(newest)}`;

  // Max is the largest total (earned + spent) for any day on this page
  const maxVal = Math.max(1, ...pageDates.map(d => byDay[d].earned + byDay[d].spent));

  const chronological = [...pageDates].reverse();
  document.getElementById('chart-bars').innerHTML = chronological.map(dateStr => {
    const data = byDay[dateStr];
    const total = data.earned + data.spent;
    const totalPct = (total / maxVal) * 100;
    const earnFrac = total > 0 ? (data.earned / total) * 100 : 100;
    const spendFrac = total > 0 ? (data.spent / total) * 100 : 0;
    const d = new Date(dateStr + 'T12:00:00');
    const label = d.toLocaleDateString([], { weekday: 'short' });
    const dayNum = d.getDate();

    return `<div class="chart-col">
      <div class="chart-bar-stack">
        <div class="chart-tooltip">
          <span class="cv-earn">${data.earned}</span><br>
          <span class="cv-spend">${data.spent}</span>
        </div>
        <div class="chart-bar-inner" style="height:${totalPct}%">
          <div class="chart-segment spent" style="height:${spendFrac}%"></div>
          <div class="chart-segment earned" style="height:${earnFrac}%"></div>
        </div>
      </div>
      <div class="chart-label">${label}<br>${dayNum}</div>
    </div>`;
  }).join('');
}

function renderHistory() {
  const today = localDateStr();
  const todayStart = new Date(today + 'T00:00:00').getTime();

  let todayEarned = 0;
  let todaySpent = 0;
  let totalEarned = 0;

  for (const entry of state.history) {
    if (entry.type === 'earn') {
      totalEarned += entry.amount;
      if (entry.timestamp >= todayStart) todayEarned += entry.amount;
    } else {
      if (entry.timestamp >= todayStart) todaySpent += entry.amount;
    }
  }

  document.getElementById('stat-today-earned').textContent = todayEarned;
  document.getElementById('stat-today-spent').textContent = todaySpent;
  document.getElementById('stat-total-earned').textContent = totalEarned;

  document.getElementById('history-list').style.display = historyView === 'list' ? '' : 'none';
  document.getElementById('history-chart').style.display = historyView === 'chart' ? '' : 'none';

  if (historyView === 'chart') {
    renderChart();
    return;
  }

  const list = document.getElementById('history-list');
  const recent = state.history.slice(0, 50);

  if (recent.length === 0) {
    list.innerHTML = '<div style="text-align:center;color:#555;padding:20px;font-size:13px;">No history yet. Complete a session to get started.</div>';
    return;
  }

  let lastDateLabel = '';
  list.innerHTML = recent.map(entry => {
    const d = new Date(entry.timestamp);
    const now = new Date();
    const dateStr = localDateStr(d);
    const todayStr = localDateStr(now);
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = localDateStr(yesterday);

    let dateLabel;
    if (dateStr === todayStr) dateLabel = 'Today';
    else if (dateStr === yesterdayStr) dateLabel = 'Yesterday';
    else dateLabel = d.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' });

    let header = '';
    if (dateLabel !== lastDateLabel) {
      lastDateLabel = dateLabel;
      header = `<div class="history-day-header">${dateLabel}</div>`;
    }

    const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if (entry.type === 'earn') {
      const bonus = entry.streakBonus ? ` (${entry.streakBonus})` : '';
      const pauseNote = entry.pausePenalty ? ` <span class="history-pause-penalty">-${entry.pausePenalty}m paused</span>` : '';
      const tagObj = entry.tag ? (state.tags || []).find(t => t.name === entry.tag) : null;
      const tagColor = entry.tagColor || tagObj?.color || '#6C5CE7';
      const tag = entry.tag ? `<span class="history-tag" style="background:${tagColor}">${escapeHtml(entry.tag)}</span>` : '';
      return `${header}<div class="history-item earn">
        <div>
          <div class="history-detail">${entry.sessionMinutes}min session${bonus}${pauseNote} ${tag}</div>
          <div class="history-time">${time}</div>
        </div>
        <span class="history-amount positive">+${entry.amount} FC</span>
      </div>`;
    } else {
      return `${header}<div class="history-item spend">
        <div>
          <div class="history-detail">${entry.rewardEmoji} ${escapeHtml(entry.rewardName)} <button class="history-edit-spend" data-ts="${entry.timestamp}" title="Edit">&#9998;</button>${entry.timedMinutes ? ` (${entry.timedMinutes} min)` : ''}</div>
          <div class="history-time">${time}</div>
        </div>
        <span class="history-amount negative">-${entry.amount} FC</span>
      </div>`;
    }
  }).join('');

  // Bind history spend edit buttons
  list.querySelectorAll('.history-edit-spend').forEach(btn => {
    btn.addEventListener('click', () => {
      const ts = parseInt(btn.dataset.ts);
      const entry = state.history.find(e => e.timestamp === ts);
      if (!entry) return;
      openEditSpendModal(entry);
    });
  });
}

// Edit Spend Modal
function openEditSpendModal(entry) {
  const modal = document.getElementById('edit-spend-modal');
  const titleEl = document.getElementById('edit-spend-title');
  const dateInput = document.getElementById('edit-spend-date');
  const timeInput = document.getElementById('edit-spend-time');
  const durationRow = document.getElementById('edit-spend-duration-row');
  const durationInput = document.getElementById('edit-spend-duration');
  const costPreview = modal.querySelector('.edit-spend-cost-preview');

  const isTimed = entry.timedMinutes != null;
  const costPerMin = isTimed ? entry.amount / entry.timedMinutes : 0;

  titleEl.textContent = `Edit ${entry.rewardEmoji} ${entry.rewardName}`;

  // Populate date/time from entry timestamp
  const d = new Date(entry.timestamp);
  const pad = n => String(n).padStart(2, '0');
  dateInput.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  timeInput.value = `${pad(d.getHours())}:${pad(d.getMinutes())}`;

  // Show duration row only for timed rewards
  if (isTimed) {
    durationRow.classList.remove('hidden');
    durationInput.value = entry.timedMinutes;
    costPreview.textContent = `= ${entry.amount} FC`;
    durationInput.oninput = () => {
      const mins = parseInt(durationInput.value) || 0;
      costPreview.textContent = mins > 0 ? `= ${Math.round(costPerMin * mins)} FC` : '';
    };
  } else {
    durationRow.classList.add('hidden');
  }

  modal.classList.remove('hidden');

  const originalTs = entry.timestamp;

  const save = async () => {
    const updates = {};
    const newDate = new Date(`${dateInput.value}T${timeInput.value}`);
    if (!isNaN(newDate.getTime()) && newDate.getTime() !== originalTs) {
      updates.timestamp = newDate.getTime();
    }
    if (isTimed) {
      const newMin = parseInt(durationInput.value);
      if (newMin > 0 && newMin !== entry.timedMinutes) {
        updates.timedMinutes = newMin;
        updates.amount = Math.round(costPerMin * newMin);
      }
    }
    if (Object.keys(updates).length > 0) {
      await chrome.runtime.sendMessage({ action: 'updateHistoryEntry', timestamp: originalTs, updates });
      await loadState();
      render();
      renderHistory();
    }
    close();
  };

  const del = async () => {
    if (!confirm(`Delete this ${entry.rewardEmoji} ${entry.rewardName} entry? ${entry.amount} FC will be refunded.`)) return;
    await chrome.runtime.sendMessage({ action: 'deleteHistoryEntry', timestamp: originalTs });
    await loadState();
    render();
    renderHistory();
    close();
  };

  const close = () => {
    modal.classList.add('hidden');
    document.getElementById('btn-edit-spend-save').removeEventListener('click', save);
    document.getElementById('btn-edit-spend-cancel').removeEventListener('click', close);
    document.getElementById('btn-edit-spend-delete').removeEventListener('click', del);
  };

  document.getElementById('btn-edit-spend-save').addEventListener('click', save);
  document.getElementById('btn-edit-spend-cancel').addEventListener('click', close);
  document.getElementById('btn-edit-spend-delete').addEventListener('click', del);
}

// Settings
function loadSettings() {
  const s = state.settings;
  document.getElementById('setting-focus').value = s.defaultSessionMinutes || 25;
  document.getElementById('setting-rest').value = s.defaultRestMinutes || 5;
  document.getElementById('setting-long-rest').value = s.longRestMinutes || 15;
  document.getElementById('setting-sessions-long').value = s.sessionsBeforeLongRest || 4;
  document.getElementById('setting-debt').checked = s.allowDebt || false;

  document.getElementById('setting-max-pause').value = s.maxPausePercent ?? 10;

  const vol = Math.round((s.soundVolume ?? 0.7) * 100);
  document.getElementById('setting-volume').value = vol;
  document.getElementById('volume-value').textContent = `${vol}%`;
  document.getElementById('setting-focus-sound').value = s.focusSound || 'focus-complete.wav';
  document.getElementById('setting-rest-sound').value = s.restSound || 'rest-complete.wav';
}

function renderTags() {
  const list = document.getElementById('tags-list');
  const tags = state.tags || [];

  if (tags.length === 0) {
    list.innerHTML = '<div style="text-align:center;color:var(--text-faintest);padding:8px;font-size:12px;">No tags yet</div>';
    return;
  }

  // Count usage per tag from history
  const counts = {};
  for (const entry of state.history) {
    if (entry.tag) {
      counts[entry.tag] = (counts[entry.tag] || 0) + 1;
    }
  }

  list.innerHTML = tags.map(tag => {
    const color = tag.color || '#6C5CE7';
    const mult = tag.multiplier || 1;
    return `
    <div class="tag-item">
      <span class="tag-swatch" style="background:${color}" title="Change color">
        <input type="color" value="${color}" data-id="${tag.id}">
      </span>
      <span class="tag-item-name">${escapeHtml(tag.name)}</span>
      <input type="number" class="tag-multiplier" data-id="${tag.id}" value="${mult}" min="0.1" max="10" step="0.1" title="Credit multiplier">
      <span class="tag-mult-label">x</span>
      <span class="tag-item-count">${counts[tag.name] || 0} sessions</span>
      <button class="edit-tag-btn" data-id="${tag.id}" title="Rename">&#9998;</button>
      <button class="delete-tag-btn" data-id="${tag.id}" title="Delete">&times;</button>
    </div>`;
  }).join('');

  list.querySelectorAll('.edit-tag-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const tag = tags.find(t => t.id === parseInt(btn.dataset.id));
      const newName = prompt('Rename tag:', tag.name);
      if (newName && newName.trim() && newName.trim() !== tag.name) {
        const updated = tags.map(t =>
          t.id === tag.id ? { ...t, name: newName.trim() } : t
        );
        await chrome.runtime.sendMessage({ action: 'updateTags', tags: updated });
        await loadState();
        renderTags();
      }
    });
  });

  list.querySelectorAll('.delete-tag-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const tag = tags.find(t => t.id === parseInt(btn.dataset.id));
      if (confirm(`Delete tag "${tag.name}"? Existing history entries will keep the tag name.`)) {
        const updated = tags.filter(t => t.id !== tag.id);
        await chrome.runtime.sendMessage({ action: 'updateTags', tags: updated });
        await loadState();
        renderTags();
      }
    });
  });

  // Color swatch change
  list.querySelectorAll('.tag-swatch input[type="color"]').forEach(input => {
    input.addEventListener('change', async () => {
      const updated = tags.map(t =>
        t.id === parseInt(input.dataset.id) ? { ...t, color: input.value } : t
      );
      await chrome.runtime.sendMessage({ action: 'updateTags', tags: updated });
      await loadState();
      renderTags();
    });
  });

  // Multiplier change
  list.querySelectorAll('.tag-multiplier').forEach(input => {
    input.addEventListener('change', async () => {
      const val = parseFloat(input.value);
      if (isNaN(val) || val <= 0) return;
      const updated = tags.map(t =>
        t.id === parseInt(input.dataset.id) ? { ...t, multiplier: val } : t
      );
      await chrome.runtime.sendMessage({ action: 'updateTags', tags: updated });
      await loadState();
      renderTags();
    });
  });
}

function gatherSettings() {
  return {
    defaultSessionMinutes: parseInt(document.getElementById('setting-focus').value),
    defaultRestMinutes: parseInt(document.getElementById('setting-rest').value),
    longRestMinutes: parseInt(document.getElementById('setting-long-rest').value),
    sessionsBeforeLongRest: parseInt(document.getElementById('setting-sessions-long').value),
    maxPausePercent: parseInt(document.getElementById('setting-max-pause').value) || 10,
    allowDebt: document.getElementById('setting-debt').checked,
    soundVolume: parseInt(document.getElementById('setting-volume').value) / 100,
    focusSound: document.getElementById('setting-focus-sound').value,
    restSound: document.getElementById('setting-rest-sound').value
  };
}

function setupSettings() {
  const inputs = ['setting-focus', 'setting-rest', 'setting-long-rest', 'setting-sessions-long', 'setting-max-pause',
                   'setting-debt', 'setting-focus-sound', 'setting-rest-sound'];
  inputs.forEach(id => {
    document.getElementById(id).addEventListener('change', async () => {
      await chrome.runtime.sendMessage({ action: 'updateSettings', settings: gatherSettings() });
      await loadState();
    });
  });

  // Volume slider (live update label)
  document.getElementById('setting-volume').addEventListener('input', (e) => {
    document.getElementById('volume-value').textContent = `${e.target.value}%`;
  });
  document.getElementById('setting-volume').addEventListener('change', async () => {
    await chrome.runtime.sendMessage({ action: 'updateSettings', settings: gatherSettings() });
    await loadState();
  });

  // Test sound buttons
  document.getElementById('btn-test-focus').addEventListener('click', () => {
    const file = document.getElementById('setting-focus-sound').value;
    const volume = parseInt(document.getElementById('setting-volume').value) / 100;
    const audio = new Audio(chrome.runtime.getURL(`sounds/${file}`));
    audio.volume = volume;
    audio.play();
  });

  document.getElementById('btn-test-rest').addEventListener('click', () => {
    const file = document.getElementById('setting-rest-sound').value;
    const volume = parseInt(document.getElementById('setting-volume').value) / 100;
    const audio = new Audio(chrome.runtime.getURL(`sounds/${file}`));
    audio.volume = volume;
    audio.play();
  });

  // Tag add button
  document.getElementById('btn-add-tag').addEventListener('click', async () => {
    const input = document.getElementById('new-tag-name');
    const colorInput = document.getElementById('new-tag-color');
    const name = input.value.trim();
    if (!name) return;

    const tags = [...(state.tags || [])];
    if (tags.some(t => t.name.toLowerCase() === name.toLowerCase())) {
      alert('A tag with that name already exists.');
      return;
    }

    const maxId = tags.reduce((max, t) => Math.max(max, t.id), 0);
    tags.push({ id: maxId + 1, name, color: colorInput.value, multiplier: 1 });

    await chrome.runtime.sendMessage({ action: 'updateTags', tags });
    await loadState();
    input.value = '';
    renderTags();
  });

  // Allow Enter key to add tag
  document.getElementById('new-tag-name').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') document.getElementById('btn-add-tag').click();
  });

  document.getElementById('btn-export').addEventListener('click', async () => {
    const shared = await chrome.runtime.sendMessage({ action: 'getState' });
    const blob = new Blob([JSON.stringify(shared, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `gamify-timer-export-${localDateStr()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  });

  document.getElementById('btn-reset-config').addEventListener('click', async () => {
    if (confirm('Reset rewards and settings to defaults? Credits and history will be kept.')) {
      await chrome.runtime.sendMessage({ action: 'resetConfig' });
      chrome.runtime.reload();
      window.close();
    }
  });

  document.getElementById('btn-reset-all').addEventListener('click', async () => {
    if (confirm('This will delete ALL data — balance, history, rewards, settings. Are you sure?')) {
      if (confirm('Really? This cannot be undone.')) {
        await chrome.runtime.sendMessage({ action: 'resetAll' });
        chrome.runtime.reload();
        window.close();
      }
    }
  });
}

// Helpers
function localDateStr(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function setRingOffset(el, value, mode) {
  const modeChanged = mode && mode !== lastRingMode;
  if (mode) lastRingMode = mode;

  if (!initialRenderDone || modeChanged) {
    // Snap to position with no animation on first render or mode change
    el.style.transition = 'none';
    el.style.strokeDashoffset = value;
    el.getBoundingClientRect();
    el.style.transition = 'stroke-dashoffset 1s linear';
    initialRenderDone = true;
  } else {
    el.style.strokeDashoffset = value;
  }
}

function calculateCredits(minutes) {
  return Math.floor(minutes * (minutes + 15) / 50);
}

function getStreakMultiplier(minutesToday) {
  if (minutesToday >= 90) return 1.30;
  if (minutesToday >= 75) return 1.20;
  if (minutesToday >= 45) return 1.10;
  return 1;
}

function formatTime(timestamp) {
  const d = new Date(timestamp);
  const now = new Date();
  const today = localDateStr(now);
  const dateStr = localDateStr(d);

  const time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  if (dateStr === today) return `Today ${time}`;

  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (dateStr === localDateStr(yesterday)) return `Yesterday ${time}`;

  return `${d.toLocaleDateString([], { month: 'short', day: 'numeric' })} ${time}`;
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}
