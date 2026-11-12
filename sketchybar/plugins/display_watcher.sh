#!/bin/bash

# Display Watcher — automatically manages macOS space counts
# when external monitors are connected/disconnected.
#
# Triggered by yabai signals: display_added, display_removed, system_woke
#
# Target space counts (MacBook Pro):
#   Standalone:          5 spaces on laptop
#   External connected:  3 on laptop, 4 on external (7 total)
# Targets are minimums: extra spaces are trimmed only if they're empty.
# Mac Studio: no-op (display config never changes)
#
# Timing-proof by design: instead of acting once on a snapshot, it re-reads the
# real state every round and fixes what's off, until everything matches (or
# MAX_ROUNDS pass). So it doesn't matter how long macOS takes to attach a new
# monitor's first space, or whether displays change while it runs.

LOG_FILE="/tmp/display_watcher.log"
LOCK_DIR="/tmp/display_watcher.lock"
LAST_RUN_FILE="/tmp/display_watcher.last_run"   # read by space_count_changed.sh
MAX_ROUNDS=20

log() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"; }

# Cap the log at ~256KB (keep the recent half) so it can't grow unbounded
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -c 131072 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# --- Concurrency: one run at a time. A trigger that arrives mid-run waits its
# turn instead of being dropped (runs are idempotent — a later one that finds
# everything correct does nothing). mkdir-based: macOS has no flock. ---
GOT_LOCK=""
for i in $(seq 1 120); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then GOT_LOCK=1; break; fi
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || date +%s) ))
    if [ "$lock_age" -gt 120 ]; then
        rm -rf "$LOCK_DIR"   # owner was hard-killed; a real run never takes this long
        continue
    fi
    [ "$i" -eq 1 ] && log "Another run in progress — waiting for it"
    sleep 1
done
[ -z "$GOT_LOCK" ] && { log "ERROR: lock never freed — giving up"; exit 1; }
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

# --- Targets for the current display layout (sets LAPTOP_INDEX,
# EXTERNAL_INDEX, TARGET_LAPTOP, TARGET_EXTERNAL) ---
plan_targets() {
    if [ "$(echo "$DISPLAYS_JSON" | jq 'length')" -eq 1 ]; then
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
        TARGET_EXTERNAL=4 # External monitor
    fi
}

# Spaces on a display with no windows at all (incl. minimized/hidden), highest
# index first — the only ones the trim pass may destroy
empty_spaces() {
    echo "$SPACES_JSON" | jq -r --argjson d "$1" --argjson w "$WINDOWS_JSON" \
        '[.[] | select(.display == $d) | .index as $i
              | select([$w[] | select(.space == $i)] | length == 0) | $i]
         | sort | reverse | .[]'
}

space_count() { echo "$SPACES_JSON" | jq --argjson d "$1" '[.[] | select(.display == $d)] | length'; }

# Does a display match its target? Enough spaces, and no *empty* extras.
in_target() {
    local current; current=$(space_count "$1")
    [ "$current" -lt "$2" ] && return 1
    [ "$current" -gt "$2" ] && [ -n "$(empty_spaces "$1")" ] && return 1
    return 0
}

# Bring one display to its target: create missing spaces on it, or destroy
# empty extras (a space with windows is in use — never destroyed)
adjust_display() {
    local display_id=$1 target=$2 current sid
    current=$(space_count "$display_id")
    if [ "$current" -lt "$target" ]; then
        log "Display $display_id: creating $((target - current)) spaces ($current -> $target)"
        for ((i=current; i<target; i++)); do
            # Target the display explicitly — never rely on focus
            yabai -m space --create "$display_id" 2>/dev/null \
                || log "ERROR: space --create on display $display_id failed"
            sleep 0.2
        done
    elif [ "$current" -gt "$target" ]; then
        # Highest index first, so destroying one never shifts a pending index
        for sid in $(empty_spaces "$display_id"); do
            [ "$current" -le "$target" ] && break
            yabai -m space --destroy "$sid" 2>/dev/null || continue
            current=$((current - 1))
            log "Destroyed empty space $sid on display $display_id"
            sleep 0.2
        done
    fi
}

# --- Converge ---
DONE=""
CHANGED=""
WAITING_LOGGED=""
for round in $(seq 1 $MAX_ROUNDS); do
    DISPLAYS_JSON=$(yabai -m query --displays 2>/dev/null)
    SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
    WINDOWS_JSON=$(yabai -m query --windows 2>/dev/null)
    # Not settled yet: yabai down, or a display without its first space (right
    # after a hotplug macOS lists the monitor before attaching one)
    if [ -z "$DISPLAYS_JSON" ] || [ "$DISPLAYS_JSON" = "null" ] \
       || [ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ] \
       || [ -z "$WINDOWS_JSON" ] || [ "$WINDOWS_JSON" = "null" ] \
       || [ "$(echo "$DISPLAYS_JSON" | jq 'all(.[]; (.spaces | length) > 0)')" != "true" ]; then
        [ -z "$WAITING_LOGGED" ] && log "Round $round: displays not settled yet — retrying"
        WAITING_LOGGED=1
        sleep 1
        continue
    fi

    plan_targets
    if in_target "$LAPTOP_INDEX" "$TARGET_LAPTOP" \
       && { [ -z "$EXTERNAL_INDEX" ] || in_target "$EXTERNAL_INDEX" "$TARGET_EXTERNAL"; }; then
        log "Round $round: $(echo "$DISPLAYS_JSON" | jq 'length') display(s), laptop=$LAPTOP_INDEX external=${EXTERNAL_INDEX:-none} — spaces match targets"
        DONE=1
        break
    fi

    adjust_display "$LAPTOP_INDEX" "$TARGET_LAPTOP"
    if [ -n "$EXTERNAL_INDEX" ]; then
        SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
        WINDOWS_JSON=$(yabai -m query --windows 2>/dev/null)
        adjust_display "$EXTERNAL_INDEX" "$TARGET_EXTERNAL"
    fi
    CHANGED=1
    sleep 1   # let macOS settle, then the next round verifies the real result
done
[ -z "$DONE" ] && log "WARNING: spaces still off target after $MAX_ROUNDS rounds"

[ -n "$CHANGED" ] && yabai -m space --balance 2>/dev/null

# Bring the bar in line: no-op if it already matches, live-syncs space items,
# or fully reloads if the set of displays changed
"$(dirname "$0")/space_sync.sh"

date +%s > "$LAST_RUN_FILE"
log "Display watcher complete"
