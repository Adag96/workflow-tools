// Background service worker — handles timer logic and native messaging for shared data

const HOST_NAME = 'com.gamifytimer.host';

// Guard against concurrent completion processing (alarm can fire while async completion is in-flight)
let completionInProgress = false;

// Native messaging helper — sends a message and gets one response
function nativeSend(msg) {
  return new Promise((resolve, reject) => {
    const port = chrome.runtime.connectNative(HOST_NAME);
    let responded = false;

    port.onMessage.addListener((response) => {
      responded = true;
      port.disconnect();
      resolve(response);
    });

    port.onDisconnect.addListener(() => {
      if (!responded) {
        const err = chrome.runtime.lastError?.message || 'Native host disconnected';
        reject(new Error(err));
      }
    });

    port.postMessage(msg);
  });
}

// Get shared data (balance, history, rewards) from native host
async function getSharedData() {
  try {
    const data = await nativeSend({ action: 'getData' });
    return data;
  } catch (e) {
    console.error('Native host error:', e.message);
    throw e;
  }
}

// Initialize per-profile local data (timer state)
chrome.runtime.onInstalled.addListener(async () => {
  const { timerState } = await chrome.storage.local.get('timerState');
  if (!timerState) {
    await chrome.storage.local.set({
      timerState: {
        status: 'idle',
        sessionMinutes: 25,
        remainingSeconds: 0,
        startedAt: null,
        pausedAt: null
      }
    });
  }
});

// Recover the timer whenever the service worker spins up (MV3 evicts it when
// idle; if it was killed mid-session the pomodoroTick alarm may be gone, leaving
// a 'running' session with nothing to complete it). Re-arm the alarm so the
// session either keeps ticking or immediately completes on the next tick.
async function recoverTimer() {
  const { timerState } = await chrome.storage.local.get('timerState');
  if (timerState && timerState.status === 'running') {
    const existing = await chrome.alarms.get('pomodoroTick');
    if (!existing) {
      await chrome.alarms.create('pomodoroTick', { periodInMinutes: 1 / 60 });
    }
  }
  updateBadge();
}
chrome.runtime.onStartup.addListener(recoverTimer);
recoverTimer();

// Local date string (YYYY-MM-DD) — avoids UTC timezone drift
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

// Timer tick via alarms
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== 'pomodoroTick') return;

  const { timerState } = await chrome.storage.local.get('timerState');
  if (!timerState || timerState.status !== 'running') return;

  // Compute remaining time from wall clock (resilient to throttled/delayed alarms)
  const elapsed = (Date.now() - timerState.startedAt) / 1000;
  timerState.remainingSeconds = Math.round(
    timerState.sessionMinutes * 60 - elapsed + (timerState.totalPausedSeconds || 0)
  );

  if (timerState.remainingSeconds <= 0) {
    // Prevent duplicate completion if alarm fires while async completion is still running
    if (completionInProgress) return;
    completionInProgress = true;

    if (timerState.mode === 'rest') {
      timerState.status = 'idle';
      timerState.remainingSeconds = 0;
      await chrome.alarms.clear('pomodoroTick');
      await chrome.storage.local.set({ timerState });

      chrome.notifications.create('restComplete', {
        type: 'basic',
        iconUrl: 'icons/icon128.png',
        title: 'Rest Complete',
        message: 'Ready for another focus session?'
      });
      playSound('rest');
      updateBadge();
      completionInProgress = false;
      return;
    }

    // Focus session complete — award credits via native host.
    // Wrapped so a native-host failure can't drop the award or wedge the timer:
    // on error we leave the alarm running and the state 'running' so the next
    // tick retries. The award (earnCredits) is the commit point — everything
    // that could double-count on retry happens only after it succeeds.
    try {
      const today = localDateStr();
      const shared = await getSharedData();
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
        timestamp: Date.now()
      };

      // COMMIT POINT: award the credits. If this throws, nothing below runs and
      // the session stays 'running' so the next tick retries the whole block.
      const result = await nativeSend({
        action: 'earnCredits',
        amount: totalCredits,
        entry
      });

      // Award succeeded — from here on, mark the session done FIRST so that even
      // if a later step (streak/notification) fails, a retry can't re-award.
      await chrome.storage.local.set({
        timerState: {
          ...timerState,
          status: 'idle',
          remainingSeconds: 0
        }
      });
      await chrome.alarms.clear('pomodoroTick');

      // Best-effort follow-ups — a failure here must not undo the award.
      try {
        await nativeSend({
          action: 'updateStreak',
          minutesFocusedToday: minutesToday + timerState.sessionMinutes,
          lastSessionDate: today
        });
      } catch (e) {
        console.error('updateStreak failed after award (credits are safe):', e.message);
      }

      chrome.notifications.create('sessionComplete', {
        type: 'basic',
        iconUrl: 'icons/icon128.png',
        title: 'Session Complete!',
        message: `Earned ${totalCredits} FC${multiplier > 1 ? ' (streak bonus!)' : ''}. Balance: ${result.newBalance} FC`
      });

      playSound('focus');
      updateBadge();
    } catch (e) {
      // Native host unreachable at completion time. Do NOT clear the alarm or
      // mark the session idle — the timer stays 'running' (remaining stays <= 0)
      // so the next alarm tick retries the award once the host recovers.
      console.error('Session completion failed, will retry on next tick:', e.message);
    } finally {
      completionInProgress = false;
    }
    return;
  }

  await chrome.storage.local.set({ timerState });
  updateBadge();
});

// Message handler for popup communication
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  handleMessage(msg).then(sendResponse);
  return true;
});

async function handleMessage(msg) {
  const { timerState } = await chrome.storage.local.get('timerState');

  switch (msg.action) {
    case 'startSession': {
      const minutes = msg.minutes || 25;
      const newState = {
        ...timerState,
        status: 'running',
        mode: 'focus',
        sessionMinutes: minutes,
        remainingSeconds: minutes * 60,
        startedAt: Date.now(),
        pausedAt: null,
        totalPausedSeconds: 0,
        tag: msg.tag || null
      };
      await chrome.storage.local.set({ timerState: newState });
      await chrome.alarms.create('pomodoroTick', { periodInMinutes: 1 / 60 });
      updateBadge();
      return { success: true };
    }

    case 'startRest': {
      const minutes = msg.minutes || 5;
      const newState = {
        ...timerState,
        status: 'running',
        mode: 'rest',
        sessionMinutes: minutes,
        remainingSeconds: minutes * 60,
        startedAt: Date.now(),
        pausedAt: null
      };
      await chrome.storage.local.set({ timerState: newState });
      await chrome.alarms.create('pomodoroTick', { periodInMinutes: 1 / 60 });
      updateBadge();
      return { success: true };
    }

    case 'pause': {
      const newState = {
        ...timerState,
        status: 'paused',
        pausedAt: Date.now()
      };
      await chrome.storage.local.set({ timerState: newState });
      await chrome.alarms.clear('pomodoroTick');
      return { success: true };
    }

    case 'resume': {
      const pauseDuration = timerState.pausedAt ? Math.floor((Date.now() - timerState.pausedAt) / 1000) : 0;
      const newState = {
        ...timerState,
        status: 'running',
        pausedAt: null,
        totalPausedSeconds: (timerState.totalPausedSeconds || 0) + pauseDuration
      };
      await chrome.storage.local.set({ timerState: newState });
      await chrome.alarms.create('pomodoroTick', { periodInMinutes: 1 / 60 });
      return { success: true };
    }

    case 'cancel': {
      const newState = {
        ...timerState,
        status: 'idle',
        remainingSeconds: 0,
        startedAt: null,
        pausedAt: null
      };
      await chrome.storage.local.set({ timerState: newState });
      await chrome.alarms.clear('pomodoroTick');
      updateBadge();
      return { success: true };
    }

    case 'redeem': {
      const shared = await getSharedData();
      const settings = shared.settings || {};

      const reward = shared.rewards.find(r => r.id === msg.rewardId);
      if (!reward) return { error: 'Reward not found' };

      // Calculate consecutive streak and escalated cost (only for rewards with escalation enabled)
      let streak = 0;
      let effectiveCost = reward.cost;
      if (reward.consecutiveEscalation) {
        const consec = shared.consecutiveRedemptions || {};
        const tracking = consec[String(reward.id)];
        const today = new Date().toISOString().slice(0, 10);
        const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
        if (tracking) {
          if (tracking.lastDate === today) {
            streak = tracking.streak;
          } else if (tracking.lastDate === yesterday) {
            streak = tracking.streak + 1;
          }
        }
        effectiveCost = Math.round(reward.cost * Math.pow(1.1, streak));
      }

      const entry = {
        type: 'spend',
        amount: effectiveCost,
        rewardName: reward.name,
        rewardEmoji: reward.emoji,
        timestamp: Date.now()
      };

      const result = await nativeSend({
        action: 'spendCredits',
        amount: effectiveCost,
        allowDebt: settings?.allowDebt || false,
        rewardId: reward.id,
        streak,
        entry
      });

      if (result.error) return result;

      updateBadge();
      return { success: true, newBalance: result.newBalance };
    }

    case 'getState': {
      const shared = await getSharedData();
      return {
        timerState,
        balance: shared.balance,
        history: shared.history,
        rewards: shared.rewards,
        tags: shared.tags || [],
        consecutiveRedemptions: shared.consecutiveRedemptions || {},
        minutesFocusedToday: shared.minutesFocusedToday || 0,
        lastSessionDate: shared.lastSessionDate || null,
        settings: shared.settings || {}
      };
    }

    case 'updateHistoryEntry': {
      const shared = await getSharedData();
      const entry = shared.history.find(e => e.timestamp === msg.timestamp);

      if (entry && entry.type === 'earn' && 'tag' in msg.updates) {
        // Recalculate credits with new tag multiplier
        const newTag = msg.updates.tag;
        const newTagObj = newTag ? (shared.tags || []).find(t => t.name === newTag) : null;
        const newTagMult = newTagObj?.multiplier || 1;

        // Reverse-engineer the base amount without any tag multiplier
        // Use stored baseAmount if available, otherwise the full amount
        const baseAmount = entry.baseAmount || entry.amount;

        // Recalculate: base × streak × new tag multiplier
        const streakMult = entry.streakBonus
          ? 1 + parseInt(entry.streakBonus) / 100
          : 1;
        const newAmount = Math.floor(baseAmount * streakMult * newTagMult);
        const diff = newAmount - entry.amount;

        msg.updates.amount = newAmount;
        msg.updates.tagMultiplier = newTagMult !== 1 ? newTagMult : null;

        await nativeSend({
          action: 'updateHistoryEntry',
          timestamp: msg.timestamp,
          updates: msg.updates
        });

        // Adjust balance by the difference
        if (diff !== 0) {
          const data = await getSharedData();
          await nativeSend({
            action: 'setBalance',
            balance: data.balance + diff
          });
        }

        updateBadge();
        return { success: true, diff };
      }

      // For spend entries: adjust balance if amount changed
      const spendEntry = shared.history.find(e => e.timestamp === msg.timestamp);
      const amountDiff = (spendEntry && spendEntry.type === 'spend' && 'amount' in msg.updates)
        ? spendEntry.amount - msg.updates.amount  // positive = refund, negative = extra charge
        : 0;

      await nativeSend({
        action: 'updateHistoryEntry',
        timestamp: msg.timestamp,
        updates: msg.updates
      });

      if (amountDiff !== 0) {
        const data = await getSharedData();
        await nativeSend({ action: 'setBalance', balance: data.balance + amountDiff });
      }

      updateBadge();
      return { success: true };
    }

    case 'deleteHistoryEntry': {
      const shared = await getSharedData();
      const entry = shared.history.find(e => e.timestamp === msg.timestamp);
      if (!entry) return { success: false, error: 'Entry not found' };

      // Refund spend or deduct earn from balance
      const balanceAdj = entry.type === 'spend' ? entry.amount : -entry.amount;

      await nativeSend({ action: 'deleteHistoryEntry', timestamp: msg.timestamp });

      if (balanceAdj !== 0) {
        const data = await getSharedData();
        await nativeSend({ action: 'setBalance', balance: data.balance + balanceAdj });
      }

      updateBadge();
      return { success: true };
    }

    case 'timedSpend': {
      const shared = await getSharedData();
      const settings = shared.settings || {};
      const result = await nativeSend({
        action: 'spendCredits',
        amount: msg.amount,
        allowDebt: settings.allowDebt || false,
        entry: msg.entry
      });
      if (result.error) return result;
      updateBadge();
      return { success: true, newBalance: result.newBalance };
    }

    case 'logReward': {
      const shared = await getSharedData();
      const settings = shared.settings || {};
      const result = await nativeSend({
        action: 'logSpend',
        amount: msg.amount,
        allowDebt: settings.allowDebt || false,
        entry: msg.entry
      });
      if (result.error) return result;
      updateBadge();
      return { success: true, newBalance: result.newBalance };
    }

    case 'updateRewards': {
      await nativeSend({ action: 'setRewards', rewards: msg.rewards });
      return { success: true };
    }

    case 'updateTags': {
      await nativeSend({ action: 'setTags', tags: msg.tags });
      return { success: true };
    }

    case 'updateSettings': {
      await nativeSend({ action: 'updateSettings', settings: msg.settings });
      return { success: true };
    }

    case 'resetConfig': {
      await nativeSend({ action: 'resetConfig' });
      return { success: true };
    }

    case 'resetAll': {
      await nativeSend({ action: 'resetAll' });
      await chrome.storage.local.clear();
      return { success: true };
    }

    default:
      return { error: 'Unknown action' };
  }
}

async function updateBadge() {
  const { timerState } = await chrome.storage.local.get('timerState');

  if (timerState && (timerState.status === 'running' || timerState.status === 'paused')) {
    const mins = Math.ceil(timerState.remainingSeconds / 60);
    chrome.action.setBadgeText({ text: `${mins}m` });
    chrome.action.setBadgeBackgroundColor({
      color: timerState.mode === 'rest' ? '#00b894' : '#e17056'
    });
  } else {
    try {
      const shared = await getSharedData();
      const balance = shared.balance ?? 0;
      const text = balance >= 1000 ? `${Math.floor(balance / 1000)}k`
        : balance <= -1000 ? `${Math.ceil(balance / 1000)}k`
        : `${balance}`;
      chrome.action.setBadgeText({ text });
      chrome.action.setBadgeBackgroundColor({ color: balance < 0 ? '#8B3040' : '#7C49B9' });
    } catch {
      chrome.action.setBadgeText({ text: '?' });
      chrome.action.setBadgeBackgroundColor({ color: '#7C49B9' });
    }
  }
}

// Offscreen document for playing sounds
async function ensureOffscreen() {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT']
  });
  if (contexts.length > 0) return;
  try {
    await chrome.offscreen.createDocument({
      url: 'offscreen.html',
      reasons: ['AUDIO_PLAYBACK'],
      justification: 'Play completion chime when timer ends'
    });
  } catch (e) {
    // Already exists
  }
}

async function playSound(type) {
  const shared = await getSharedData();
  const settings = shared.settings || {};
  const volume = settings.soundVolume ?? 0.7;
  if (volume === 0) return;

  const soundMap = {
    focus: settings?.focusSound || 'focus-complete.wav',
    rest: settings?.restSound || 'rest-complete.wav'
  };
  const file = soundMap[type] || 'focus-complete.wav';

  await ensureOffscreen();
  chrome.runtime.sendMessage({ action: 'playSound', file, volume });
}

// Set badge on startup
updateBadge();
