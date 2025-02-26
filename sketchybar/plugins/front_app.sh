#!/bin/sh

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

# Function to format time matching the Ableton timer script
format_time() {
  local time=$1
  local hours=$((time / 3600))
  local minutes=$(( (time % 3600) / 60 ))
  local seconds=$((time % 60))
  
  # Handle different formatting cases
  if [ $hours -eq 0 ]; then
    # Less than an hour
    if [ $minutes -eq 0 ]; then
      # Less than a minute
      if [ $seconds -lt 10 ]; then
        printf "0:0%d" $seconds
      else
        printf "0:%d" $seconds
      fi
    else
      # Minutes and seconds
      if [ $minutes -lt 10 ]; then
        printf "%d:%02d" $minutes $seconds
      else
        printf "%d:%02d" $minutes $seconds
      fi
    fi
  else
    # Hours, minutes, and seconds
    if [ $hours -lt 10 ]; then
      printf "%d:%02d:%02d" $hours $minutes $seconds
    else
      printf "%02d:%02d:%02d" $hours $minutes $seconds
    fi
  fi
}

# Check if Ableton is the current app and read its project timer
get_ableton_timer() {
  # Path to the timer state file
  TIMER_STATE_FILE="$HOME/.config/sketchybar/timer_data/timer_state.json"
  
  # Continuously update while Ableton is the front app
  while [ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')" = "Live" ]; do
    # Check if Ableton is running
    if ! pgrep -x "Live" > /dev/null; then
      break
    fi
    
    # Read timer state
    if [ -f "$TIMER_STATE_FILE" ]; then
      # Use jq to extract current project and time
      local project=$(jq -r '.current_project' "$TIMER_STATE_FILE")
      local time=$(jq -r ".projects[\"$project\"] // 0" "$TIMER_STATE_FILE")
      
      # Construct label with different font weights
      local label="$project - $(format_time "$time")"
      
      # Update Sketchybar with current timer
      sketchybar --set front_app label="$label"
      
      # Wait a second before next update
      sleep 1
    else
      break
    fi
  done
}

if [ "$SENDER" = "front_app_switched" ]; then
  # Get the app icon
  icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$INFO")"
  
  # Set the label to the current app name
  sketchybar --set "$NAME" label="$INFO" icon="$icon"
  
  # If it's Ableton Live, start timer update in background
  if [ "$INFO" = "Live" ]; then
    get_ableton_timer &
  fi
fi