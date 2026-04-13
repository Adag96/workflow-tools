#!/usr/bin/env bash

# Moves a window to the display it was dragged to.
# Called by yabai window_moved signal with $1 = window ID.
# Uses debounce: only acts after window stops moving (drag ended).

WINDOW_ID="$1"
[ -z "$WINDOW_ID" ] && exit 0

# Prevent re-entry from yabai re-tiling
LOCK_FILE="/tmp/yabai_move_lock_$WINDOW_ID"
if [ -f "$LOCK_FILE" ]; then
  if [ "$(find "$LOCK_FILE" -mtime -1s 2>/dev/null)" ]; then
    exit 0
  fi
fi

# Debounce: kill any previous pending move for this window, then wait
DEBOUNCE_PID_FILE="/tmp/yabai_move_debounce_$WINDOW_ID"
if [ -f "$DEBOUNCE_PID_FILE" ]; then
  old_pid=$(cat "$DEBOUNCE_PID_FILE" 2>/dev/null)
  kill "$old_pid" 2>/dev/null
fi

# Run the actual move check in background after a short delay
(
  echo $$ > "$DEBOUNCE_PID_FILE"
  sleep 0.15

  # Get window info
  win_info=$(yabai -m query --windows --window "$WINDOW_ID" 2>/dev/null) || exit 0
  win_display=$(echo "$win_info" | jq -r '.display')

  # Use mouse display as the target (most reliable for all layout modes)
  mouse_display=$(yabai -m query --displays --display mouse 2>/dev/null | jq -r '.index' 2>/dev/null)

  # Fallback to window center position
  if [ -z "$mouse_display" ]; then
    win_x=$(echo "$win_info" | jq -r '.frame.x')
    win_w=$(echo "$win_info" | jq -r '.frame.w')
    win_center_x=$(echo "$win_x + $win_w / 2" | bc -l)
    displays=$(yabai -m query --displays 2>/dev/null) || exit 0
    mouse_display=$(echo "$displays" | jq -r --argjson cx "$win_center_x" '
      .[] | select(.frame.x <= $cx and ($cx < .frame.x + .frame.w)) | .index
    ' | head -1)
  fi

  [ -z "$mouse_display" ] && exit 0

  if [ "$mouse_display" != "$win_display" ]; then
    touch "$LOCK_FILE"
    yabai -m window "$WINDOW_ID" --display "$mouse_display"
    # Re-insert into BSP layout if the window became floating from the drag
    is_floating=$(yabai -m query --windows --window "$WINDOW_ID" 2>/dev/null | jq -r '."is-floating"')
    if [ "$is_floating" = "true" ]; then
      yabai -m window "$WINDOW_ID" --toggle float
    fi
    yabai -m window "$WINDOW_ID" --focus
    (sleep 1 && rm -f "$LOCK_FILE") &
  fi

  rm -f "$DEBOUNCE_PID_FILE"
) &
