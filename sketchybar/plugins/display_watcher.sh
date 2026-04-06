#!/bin/bash

# Display Watcher — automatically manages macOS space counts
# when external monitors are connected/disconnected.
#
# Triggered by yabai signals: display_added, display_removed, system_woke
#
# Target space counts (MacBook Pro):
#   Standalone:          5 spaces on laptop
#   External connected:  3 on laptop, 6 on external (9 total)
# Mac Studio: no-op (display config never changes)

LOG_FILE="/tmp/display_watcher.log"
LOCK_DIR="/tmp/display_watcher.lock"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"; }

# --- Concurrency lock (mkdir-based, macOS has no flock) ---
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    if [ -d "$LOCK_DIR" ]; then
        lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR") ))
        if [ "$lock_age" -gt 30 ]; then
            rm -rf "$LOCK_DIR"
            mkdir "$LOCK_DIR" 2>/dev/null || exit 0
        else
            log "Skipping — another instance is running"
            exit 0
        fi
    fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# --- Machine detection ---
MACHINE_NAME=$(scutil --get ComputerName 2>/dev/null)
if [[ "$MACHINE_NAME" == *"Studio"* ]]; then
    log "Mac Studio detected — skipping space management"
    exit 0
fi

# --- Wait for yabai readiness ---
for attempt in 1 2 3 4 5; do
    DISPLAYS_JSON=$(yabai -m query --displays 2>/dev/null)
    SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
    if [ -n "$DISPLAYS_JSON" ] && [ "$DISPLAYS_JSON" != "null" ] \
       && [ -n "$SPACES_JSON" ] && [ "$SPACES_JSON" != "null" ]; then
        break
    fi
    sleep 1
done

if [ -z "$DISPLAYS_JSON" ] || [ -z "$SPACES_JSON" ]; then
    log "ERROR: yabai not responding after 5 attempts"
    exit 1
fi

DISPLAY_COUNT=$(echo "$DISPLAYS_JSON" | jq 'length')
log "Detected $DISPLAY_COUNT display(s)"

# --- Define target space counts per display ---
if [ "$DISPLAY_COUNT" -eq 1 ]; then
    TARGET_1=5
    TARGET_2=0
else
    TARGET_1=3  # Built-in (laptop)
    TARGET_2=6  # External monitor
fi

# --- Adjust spaces for a display ---
adjust_display() {
    local display_id=$1
    local target=$2
    local mode=$3  # "create" or "destroy"

    SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
    local current=$(echo "$SPACES_JSON" | jq "[.[] | select(.display == $display_id)] | length")

    if [ "$mode" = "create" ] && [ "$current" -lt "$target" ]; then
        local spaces_to_add=$((target - current))
        log "Display $display_id: creating $spaces_to_add spaces ($current -> $target)"
        yabai -m display --focus "$display_id" 2>/dev/null
        sleep 0.3
        for ((i=0; i<spaces_to_add; i++)); do
            yabai -m space --create 2>/dev/null
            sleep 0.2
        done

    elif [ "$mode" = "destroy" ] && [ "$current" -gt "$target" ]; then
        local spaces_to_remove=$((current - target))
        log "Display $display_id: removing $spaces_to_remove spaces ($current -> $target)"
        local space_indices=$(echo "$SPACES_JSON" | jq -r \
            "[.[] | select(.display == $display_id)] | sort_by(.index) | reverse | .[0:$spaces_to_remove] | .[].index")

        for sid in $space_indices; do
            local windows=$(yabai -m query --windows --space "$sid" 2>/dev/null | jq -r '.[].id' 2>/dev/null)
            if [ -n "$windows" ]; then
                SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
                local target_space=$(echo "$SPACES_JSON" | jq -r \
                    "[.[] | select(.display == $display_id and .index != $sid)] | sort_by(.index) | .[0].index")
                for wid in $windows; do
                    yabai -m window "$wid" --space "$target_space" 2>/dev/null
                    log "Moved window $wid from space $sid to space $target_space"
                done
            fi

            yabai -m space --destroy "$sid" 2>/dev/null
            log "Destroyed space $sid on display $display_id"
            sleep 0.2
        done
    fi
}

# Pass 1: Create spaces where needed (do this first)
adjust_display 1 "$TARGET_1" "create"
[ "$TARGET_2" -gt 0 ] && adjust_display 2 "$TARGET_2" "create"

# Pass 2: Destroy excess spaces
adjust_display 1 "$TARGET_1" "destroy"
[ "$TARGET_2" -gt 0 ] && adjust_display 2 "$TARGET_2" "destroy"

# Balance windows after adjustments
yabai -m space --balance 2>/dev/null

# Reload sketchybar so space items update
sketchybar --reload &

log "Display watcher complete"
