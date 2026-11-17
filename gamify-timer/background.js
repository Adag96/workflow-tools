// Background service worker — handles timer logic and native messaging for shared data

importScripts('escalation.js');

const HOST_NAME = 'com.gamifytimer.host';


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

// ── Timer ────────────────────────────────────────────────────────────────────
// The session is owned by the local Gamify engine (gamify_engine.py, a LaunchAgent),
// shared by every browser profile and the sketchybar widget. This extension is a view +
// remote control: timer actions go host.py → engine, and getState returns the engine's
// session in the same `timerState` shape the popup has always rendered. Completion,
// credit award, notification and sound all happen in the engine — even with Brave closed.

const TIMER_ACTIONS = ['startSession', 'startRest', 'pause', 'resume', 'cancel'];

// Old per-profile timer state from before the engine — remove it once
chrome.storage.local.remove(['timerState', 'instanceId']);
chrome.alarms.clear('pomodoroTick');

// Badge: refresh every 30 s (sessions started elsewhere show up within that), plus
// immediately after any action from this profile
chrome.alarms.create('badgeSync', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'badgeSync') updateBadge();
});
chrome.runtime.onStartup.addListener(() => updateBadge());

// Message handler for popup communication
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  handleMessage(msg).then(sendResponse);
  return true;
});

async function handleMessage(msg) {
  if (TIMER_ACTIONS.includes(msg.action)) {
    const result = await nativeSend(msg);
    updateBadge();
    return result;
  }

  switch (msg.action) {
    case 'getState': {
      const shared = await nativeSend({ action: 'getState' });
      if (shared.error) return shared;
      return {
        timerState: shared.session,      // null when the engine is unreachable → popup shows "reconnecting"
        balance: shared.balance,
        history: shared.history,
        rewards: shared.rewards,
        activities: shared.activities || [],
        tags: shared.tags || [],
        minutesFocusedToday: shared.minutesFocusedToday || 0,
        lastSessionDate: shared.lastSessionDate || null,
        settings: shared.settings || {}
      };
    }

    case 'redeem': {
      const shared = await getSharedData();
      const settings = shared.settings || {};

      const reward = shared.rewards.find(r => r.id === msg.rewardId);
      if (!reward) return { error: 'Reward not found' };

      const { cost: effectiveCost } = escalatedCost(shared.history, reward);

      const entry = {
        type: 'spend',
        amount: effectiveCost,
        rewardId: reward.id,
        rewardName: reward.name,
        rewardEmoji: reward.emoji,
        timestamp: Date.now()
      };

      const result = await nativeSend({
        action: 'spendCredits',
        amount: effectiveCost,
        allowDebt: settings?.allowDebt || false,
        entry
      });

      if (result.error) return result;

      updateBadge();
      return { success: true, newBalance: result.newBalance };
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
      // Price escalating rewards against fresh history for the entry's own date
      const reward = shared.rewards.find(r => r.id === msg.entry.rewardId);
      if (reward?.consecutiveEscalation && reward.mode !== 'timed') {
        msg.amount = msg.entry.amount =
          escalatedCost(shared.history, reward, new Date(msg.entry.timestamp)).cost;
      }
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

    case 'logActivity': {
      const shared = await getSharedData();
      const activity = (shared.activities || []).find(a => a.id === msg.activityId);
      if (!activity) return { error: 'Activity not found' };

      // Whole credits only — leftover reps are discarded, not carried over
      const credits = activity.credits || 1;
      // Legacy activities predate the flag; they were counted iff perCredit > 1
      const counted = activity.counted ?? activity.perCredit > 1;
      const count = counted ? msg.count : 1;
      const amount = Math.floor(count / activity.perCredit) * credits;
      if (amount < 1) return { error: `Need at least ${activity.perCredit} for ${credits} FC.` };

      const result = await nativeSend({
        action: 'logEarn',
        amount,
        entry: {
          type: 'earn',
          amount,
          activityName: activity.name,
          activityEmoji: activity.emoji,
          activityCount: counted ? count : undefined,
          timestamp: msg.timestamp
        }
      });
      if (result.error) return result;
      updateBadge();
      return { success: true, amount, newBalance: result.newBalance };
    }

    case 'updateActivities': {
      await nativeSend({ action: 'setActivities', activities: msg.activities });
      return { success: true };
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
      await nativeSend({ action: 'cancel' });          // end any running session too
      await nativeSend({ action: 'resetAll' });
      await chrome.storage.local.clear();
      return { success: true };
    }

    default:
      return { error: 'Unknown action' };
  }
}

async function updateBadge() {
  try {
    const shared = await nativeSend({ action: 'getState' });
    if (shared.error) throw new Error(shared.error);
    const session = shared.session;
    if (session && (session.status === 'running' || session.status === 'paused')) {
      const mins = Math.ceil(session.remainingSeconds / 60);
      chrome.action.setBadgeText({ text: `${mins}m` });
      chrome.action.setBadgeBackgroundColor({
        color: session.mode === 'rest' ? '#00b894' : '#e17056'
      });
    } else {
      const balance = shared.balance ?? 0;
      const text = balance >= 1000 ? `${Math.floor(balance / 1000)}k`
        : balance <= -1000 ? `${Math.ceil(balance / 1000)}k`
        : `${balance}`;
      chrome.action.setBadgeText({ text });
      chrome.action.setBadgeBackgroundColor({ color: balance < 0 ? '#8B3040' : '#7C49B9' });
    }
  } catch {
    chrome.action.setBadgeText({ text: '?' });
    chrome.action.setBadgeBackgroundColor({ color: '#7C49B9' });
  }
}

// Set badge on startup
updateBadge();
