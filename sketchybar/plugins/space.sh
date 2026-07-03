#!/bin/bash

# Batch handler for all space items, subscribed once (via spaces_watcher) to
# space_change/display_change. One yabai query + one sketchybar call updates
# every space.N / space_icons.N / space_N_bracket — replaces the old per-item
# scripts (9 spawns × 9 queries per space switch).

# Load the dynamic sizing variables directly
export SCALE_FACTOR=10
BASE_UNIT_RAW=4
export BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))
export RADIUS_L4=$((BASE_UNIT * 2))
export HEIGHT_L4=$((BASE_UNIT * 5))
export FONT_SIZE_LARGE=$((BASE_UNIT * 4))

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Latest-wins guard: if another instance is mid-update, flag it to run one more
# pass with fresh state and exit. Prevents pileup AND out-of-order updates.
LOCK_DIR="/tmp/sketchybar_space_refresh.lock"
RERUN_FLAG="$LOCK_DIR/rerun"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  touch "$RERUN_FLAG" 2>/dev/null
  exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

while :; do
  rm -f "$RERUN_FLAG"

  # yabai down (e.g. mid-restart): nothing to update, exit quietly
  SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
  [ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ] && exit 0

  # Items are created at config load; skip spaces added since (no item to style)
  BAR_ITEMS=" $(sketchybar --query bar 2>/dev/null | jq -r '.items | join(" ")') "

  ARGS=()
  while IFS=$'\t' read -r sid display windows visible; do
    [ -z "$sid" ] && continue
    case "$BAR_ITEMS" in *" space.$sid "*) ;; *) continue ;; esac

    if [ "$visible" = "true" ]; then
      # Active/visible space: accent number, bracket on, icon pill if occupied
      ARGS+=(--set "space.$sid" background.drawing=off \
                               icon.color=$ACCENT_COLOR \
                               icon.font="SF Pro:Bold:$FONT_SIZE_LARGE.0" \
                               icon.padding_left=6 \
                               icon.padding_right=0 \
                               associated_display=$display)
      ARGS+=(--set "space_${sid}_bracket" background.drawing=on)
      if [ "${windows:-0}" -gt 0 ]; then
        ARGS+=(--set "space_icons.$sid" background.drawing=on \
                                        background.color=$PILL_COLOR_4 \
                                        background.corner_radius=$RADIUS_L4 \
                                        background.height=$HEIGHT_L4 \
                                        label.color=$LEFT_TEXT_COLOR \
                                        associated_display=$display)
      else
        ARGS+=(--set "space_icons.$sid" background.drawing=off \
                                        associated_display=$display)
      fi
    else
      # Inactive space: plain number, no bracket, no icon pill
      ARGS+=(--set "space.$sid" background.drawing=off \
                               icon.color=$LEFT_TEXT_COLOR \
                               icon.font="SF Pro:Regular:$FONT_SIZE_LARGE.0" \
                               icon.padding_left=0 \
                               icon.padding_right=0 \
                               associated_display=$display)
      ARGS+=(--set "space_${sid}_bracket" background.drawing=off)
      ARGS+=(--set "space_icons.$sid" background.drawing=off \
                                      label.color=$LEFT_TEXT_COLOR \
                                      associated_display=$display)
    fi
  done < <(echo "$SPACES_JSON" | jq -r \
    '.[] | [.index, .display, (.windows | length), ."is-visible"] | @tsv')

  [ ${#ARGS[@]} -gt 0 ] && sketchybar "${ARGS[@]}"

  # An event arrived while we were updating — loop once more with fresh state
  [ -f "$RERUN_FLAG" ] || break
done
