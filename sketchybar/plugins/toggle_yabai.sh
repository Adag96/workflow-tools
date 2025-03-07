#!/bin/bash

# Source the icons file to ensure we have access to the icon variables
source "$HOME/.config/sketchybar/icons.sh"

# File to track Yabai status
STATUS_FILE="/tmp/yabai_status"

# Log the toggle event
echo "$(date): Toggling Yabai..." >> /tmp/yabai_toggle.log

# Check if status file exists, create it if not (default to running)
if [ ! -f "$STATUS_FILE" ]; then
  echo "running" > "$STATUS_FILE"
fi

# Read current status
CURRENT_STATUS=$(cat "$STATUS_FILE")

# Toggle based on current status
# Instead of using variables, we'll use direct sketchybar property commands
if [ "$CURRENT_STATUS" = "running" ]; then
  # Stop Yabai
  echo "$(date): Stopping Yabai..." >> /tmp/yabai_toggle.log
  yabai --stop-service
  
  # Update status
  echo "stopped" > "$STATUS_FILE"
  
  # Just set the icon properties directly
  sketchybar --set yabai.toggle icon.color=0xFFE06C75 label="Stopped" icon.drawing=off
  # Then set the icon separately
  sketchybar --set yabai.toggle icon.drawing=on
  
  # Clear label after 2 seconds
  (sleep 2 && sketchybar --set yabai.toggle label.drawing=off) &
else
  # Start Yabai
  echo "$(date): Starting Yabai..." >> /tmp/yabai_toggle.log
  yabai --start-service
  
  # Update status
  echo "running" > "$STATUS_FILE"
  
  # Just set the icon properties directly
  sketchybar --set yabai.toggle icon.color=0xFF98C379 label="Running" icon.drawing=off
  # Then set the icon separately
  sketchybar --set yabai.toggle icon.drawing=on
  
  # Clear label after 2 seconds
  (sleep 2 && sketchybar --set yabai.toggle label.drawing=off) &
fi