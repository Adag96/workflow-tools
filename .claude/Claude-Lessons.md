# Claude Lessons — workflow-tools

Patterns learned from mistakes, corrections, and hard-won debugging.
Read this at session start. Follow these rules to avoid repeating past issues.

## Entry Format
Each lesson follows this structure:
- **Date**: When it was learned
- **Category**: `Shell` | `Sketchybar` | `Yabai` | `Performance` | `Workflow`
- **What happened**: Brief description of the problem
- **Root cause**: Why it happened
- **Rule**: A concrete, followable instruction to prevent recurrence

---

## Lessons

### Scripts invoked by yabai/sketchybar run under stock bash 3.2
- **Date**: 2026-07-03
- **Category**: Shell
- **What happened**: A `$BASHPID` fix for the move_window_to_display.sh debounce silently expanded to empty — the debounce PID file was blank, so the fix didn't work despite correct-looking code.
- **Root cause**: yabai signals and sketchybar scripts execute with a minimal PATH, so `#!/usr/bin/env bash` resolves to macOS stock `/bin/bash` (3.2, from 2007) even if Homebrew bash is installed. Bash 3.2 lacks `$BASHPID`, associative arrays (`declare -A` — this is also why items/space_brackets.sh:18 errors), `${var,,}`, and other bash 4+ features.
- **Rule**: In any script this repo's daemons invoke, write for bash 3.2. For a subshell's own PID use `( ... ) & echo $! > pidfile` from the parent (or `$(sh -c 'echo $PPID')` inside), never `$BASHPID`. No `declare -A`. Test features in `/bin/bash` before assuming they work.

### Polling plugins must never outlive their update interval
- **Date**: 2026-07-03
- **Category**: Performance
- **What happened**: cpu.sh used `top -l 1` (full process-table scan). One slow sample overran the widget's update_freq, sketchybar spawned the next instance anyway, and each stuck instance made the process table bigger and every scan slower. ~1400 processes accumulated, load average hit 327, the whole machine crawled.
- **Root cause**: sketchybar re-runs a plugin every update_freq with no awareness of whether the previous run finished. Any plugin whose worst-case runtime can exceed its interval (top/ps scans, osascript, yabai queries, network, reads from a sleepable external drive) will pile up under load — a positive feedback loop.
- **Rule**: Every polling plugin needs (a) a reentrancy guard (`pgrep -fq <unique cmdline> && exit 0` or an mkdir lock) and (b) a bounded worst case — timeout hang-prone calls (`perl -e 'alarm 5; exec @ARGV' <cmd>`, since macOS has no `timeout`). osascript specifically can hang forever on stalled Apple Events; never call it from a poller without the alarm wrapper.
