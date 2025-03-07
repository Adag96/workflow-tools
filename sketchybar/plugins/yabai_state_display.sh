#!/bin/bash

source "$HOME/.config/sketchybar/items/scheme.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme")"

STATUS_FILE="/tmp/yabai_status"

# Define icons directly in this script
RUNNING_ICON="􀷄"   
STOPPED_ICON="􀷃" 

# If status file doesn't exist, create it
if [ ! -f "$STATUS_FILE" ]; then
  # Check if yabai is actually running
  if pgrep -q yabai; then
    echo "running" > "$STATUS_FILE"
  else
    echo "stopped" > "$STATUS_FILE"
  fi
fi

# Read the status
CURRENT_STATUS=$(cat "$STATUS_FILE")

# Set icon based on status
if [ "$CURRENT_STATUS" = "running" ]; then
  sketchybar --set $NAME icon="$RUNNING_ICON" icon.color=$RIGHT_TEXT_COLOR
else
  sketchybar --set $NAME icon="$STOPPED_ICON" icon.color=$RIGHT_TEXT_COLOR
fi