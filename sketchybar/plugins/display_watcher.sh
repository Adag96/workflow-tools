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
COOLDOWN_FILE="/tmp/display_watcher.last_run"
COOLDOWN_SECONDS=10

log() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"; }

# Cap the log at ~256KB (keep the recent half) so it can't grow unbounded
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -c 131072 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# --- Cooldown: skip if we completed a run recently ---
if [ -f "$COOLDOWN_FILE" ]; then
    last_run=$(cat "$COOLDOWN_FILE" 2>/dev/null)
    now=$(date +%s)
    elapsed=$((now - last_run))
    if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
        log "Skipping — cooldown active (${elapsed}s since last run)"
        exit 0
    fi
fi

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

# --- Machine detection (fail safe: only proceed on a positively identified
# non-Studio machine — an empty scutil result must never fall through to
# space creation/destruction) ---
MACHINE_NAME=$(scutil --get ComputerName 2>/dev/null)
if [ -z "$MACHINE_NAME" ]; then
    log "ERROR: could not determine machine name — refusing to manage spaces"
    exit 0
fi
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

# --- Resolve which yabai display is the built-in panel ---
# yabai (7.x) has no is-builtin field, and its display indices follow the
# macOS arrangement (not guaranteed 1=laptop). system_profiler knows the
# internal panel and reports the same CoreGraphics display ID yabai uses.
resolve_builtin_index() {
    local cg_id
    cg_id=$(system_profiler SPDisplaysDataType -json 2>/dev/null | jq -r \
        '[.SPDisplaysDataType[].spdisplays_ndrvs[]?
          | select(.spdisplays_connection_type == "spdisplays_internal")
          | ._spdisplays_displayID][0] // empty')
    case "$cg_id" in
        ''|*[!0-9]*) return ;;  # empty or non-numeric — caller falls back
    esac
    echo "$DISPLAYS_JSON" | jq -r "[.[] | select(.id == $cg_id)][0].index // empty"
}

# --- Define target space counts per display ---
if [ "$DISPLAY_COUNT" -eq 1 ]; then
    LAPTOP_INDEX=$(echo "$DISPLAYS_JSON" | jq '.[0].index')
    EXTERNAL_INDEX=""
    TARGET_LAPTOP=5
    TARGET_EXTERNAL=0
else
    LAPTOP_INDEX=$(resolve_builtin_index)
    if [ -z "$LAPTOP_INDEX" ]; then
        log "WARNING: could not identify built-in display — assuming index 1"
        LAPTOP_INDEX=1
    fi
    EXTERNAL_INDEX=$(echo "$DISPLAYS_JSON" | jq -r "[.[] | select(.index != $LAPTOP_INDEX)][0].index")
    TARGET_LAPTOP=3   # Built-in (laptop)
    TARGET_EXTERNAL=6 # External monitor
fi
log "Built-in display index: $LAPTOP_INDEX, external: ${EXTERNAL_INDEX:-none}"

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
adjust_display "$LAPTOP_INDEX" "$TARGET_LAPTOP" "create"
[ -n "$EXTERNAL_INDEX" ] && adjust_display "$EXTERNAL_INDEX" "$TARGET_EXTERNAL" "create"

# Pass 2: Destroy excess spaces
adjust_display "$LAPTOP_INDEX" "$TARGET_LAPTOP" "destroy"
[ -n "$EXTERNAL_INDEX" ] && adjust_display "$EXTERNAL_INDEX" "$TARGET_EXTERNAL" "destroy"

# Balance windows after adjustments
yabai -m space --balance 2>/dev/null

# Reload sketchybar so space items update
sketchybar --reload &

# Stamp cooldown so rapid re-triggers are suppressed
date +%s > "$COOLDOWN_FILE"

log "Display watcher complete"
