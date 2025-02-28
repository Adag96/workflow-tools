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
  
  # Log for debugging
  echo "$(date): Starting Ableton timer in front_app.sh" >> /tmp/ableton_timer_debug.log
  
  # Initial read of timer state
  if [ -f "$TIMER_STATE_FILE" ]; then
    # Use jq to extract current project and time
    local project=$(jq -r '.current_project' "$TIMER_STATE_FILE")
    local time=$(jq -r ".projects[\"$project\"] // 0" "$TIMER_STATE_FILE")
    
    echo "$(date): Initial project=$project, time=$time" >> /tmp/ableton_timer_debug.log
    
    # Set initial label
    if [[ -n "$project" && "$project" != "null" && "$project" != "Live" ]]; then
      local label="$project - $(format_time "$time")"
      echo "$(date): Setting initial label to '$label'" >> /tmp/ableton_timer_debug.log
      sketchybar --set front_app label="$label"
    else
      echo "$(date): No valid initial project, using default" >> /tmp/ableton_timer_debug.log
    fi
  else
    echo "$(date): Timer state file not found" >> /tmp/ableton_timer_debug.log
  fi
  
  # Continuously update while Ableton is the front app
  while true; do
    # Check if Ableton is still the frontmost app
    local frontmost=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")
    echo "$(date): Frontmost app: $frontmost" >> /tmp/ableton_timer_debug.log
    
    if [[ "$frontmost" != "Live" ]]; then
      echo "$(date): Ableton is no longer frontmost, exiting timer loop" >> /tmp/ableton_timer_debug.log
      break
    fi
    
    # Check if Ableton is running
    if ! pgrep -x "Live" > /dev/null; then
      echo "$(date): Ableton is no longer running, exiting timer loop" >> /tmp/ableton_timer_debug.log
      break
    fi
    
    # Read timer state
    if [ -f "$TIMER_STATE_FILE" ]; then
      # Use jq to extract current project and time
      local project=$(jq -r '.current_project' "$TIMER_STATE_FILE")
      local time=$(jq -r ".projects[\"$project\"] // 0" "$TIMER_STATE_FILE")
      
      echo "$(date): Updated project=$project, time=$time" >> /tmp/ableton_timer_debug.log
      
      # Construct label with different font weights
      if [[ -n "$project" && "$project" != "null" && "$project" != "Live" ]]; then
        local label="$project - $(format_time "$time")"
        echo "$(date): Setting label to '$label'" >> /tmp/ableton_timer_debug.log
        sketchybar --set front_app label="$label"
      else
        echo "$(date): No valid project found, using default label" >> /tmp/ableton_timer_debug.log
        sketchybar --set front_app label="Live"
      fi
    else
      echo "$(date): Timer state file not found during update" >> /tmp/ableton_timer_debug.log
      break
    fi
    
    # Wait a second before next update
    sleep 1
  done
  
  echo "$(date): Exited Ableton timer loop" >> /tmp/ableton_timer_debug.log
}

if [ "$SENDER" = "front_app_switched" ]; then
  echo "$(date): Front app switched to: $INFO" >> /tmp/ableton_timer_debug.log
  
  # Get the app icon
  icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$INFO")"
  
  # Set the label to the current app name
  sketchybar --set "$NAME" label="$INFO" icon="$icon"
  
  # If it's Ableton Live, start timer update in background
  if [ "$INFO" = "Live" ]; then
    echo "$(date): Detected Live as frontmost app, starting timer" >> /tmp/ableton_timer_debug.log
    
    # Kill any existing timer processes to avoid duplicates
    pkill -f "get_ableton_timer" 2>/dev/null
    
    # Start timer in background
    get_ableton_timer &
  fi
fi