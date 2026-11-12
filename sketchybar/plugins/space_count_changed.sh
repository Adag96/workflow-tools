#!/bin/bash

# Rebuild the bar when spaces are created/destroyed (Mission Control "+",
# yabai space --create/--destroy). Space items are built once at config load
# by items/spaces.sh, so without this the bar keeps the old space count.
#
# Triggered by yabai signals: space_created, space_destroyed
# Debounced, and defers to display_watcher.sh (which reloads the bar itself
# after its own create/destroy batch) so two reloads never overlap.

PID_FILE="/tmp/sketchybar_space_count.pid"
WATCHER_LOCK="/tmp/display_watcher.lock"
WATCHER_LAST_RUN="/tmp/display_watcher.last_run"

watcher_busy() {
    [ -d "$WATCHER_LOCK" ] && return 0
    # Watcher finished within the last 5s — its reload covers this change
    if [ -f "$WATCHER_LAST_RUN" ]; then
        [ $(( $(date +%s) - $(cat "$WATCHER_LAST_RUN" 2>/dev/null || echo 0) )) -lt 5 ] && return 0
    fi
    return 1
}

watcher_busy && exit 0

# Debounce: only the last event in a burst acts
echo $$ > "$PID_FILE"
sleep 0.3
[ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ] || exit 0
watcher_busy && exit 0

YABAI_COUNT=$(yabai -m query --spaces 2>/dev/null | jq 'length' 2>/dev/null)
BAR_COUNT=$(sketchybar --query bar 2>/dev/null | jq '[.items[] | select(test("^space\\.[0-9]+$"))] | length' 2>/dev/null)

[ -n "$YABAI_COUNT" ] && [ "$YABAI_COUNT" != "$BAR_COUNT" ] && "$(dirname "$0")/space_sync.sh"
