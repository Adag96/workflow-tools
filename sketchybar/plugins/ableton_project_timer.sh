#!/bin/bash

# Create necessary files for storing project data if they don't exist
TIMER_DATA_DIR="/Volumes/T7/Ableton Timer Data"
TIMER_STATE_FILE="$TIMER_DATA_DIR/timer_state.json"

mkdir -p "$TIMER_DATA_DIR"

if [ ! -f "$TIMER_STATE_FILE" ]; then
  echo '{
    "running": false,
    "current_project": "",
    "projects": {}
  }' > "$TIMER_STATE_FILE"
fi

# Helper function to update the timer state file
update_timer_state() {
  echo "$1" > "$TIMER_STATE_FILE"
}

# Helper function to get the current Ableton project name from window title
get_ableton_project_name() {
  local window_title=$(yabai -m query --windows --window | jq -r '.title')
  
  # Extract project name from window title
  # Ableton shows titles like "Project Name - Ableton Live 11"
  # or "Project Name* - Ableton Live 11" when unsaved changes exist
  local project_name=$(echo "$window_title" | sed -E 's/^(.*) - Ableton Live.*/\1/' | sed 's/\*$//')
  
  # If we couldn't extract a name or it's not an Ableton window, return empty
  if [[ "$window_title" != *"Ableton Live"* ]]; then
    echo ""
  else
    echo "$project_name"
  fi
}

# Helper function to format seconds into HH:MM:SS
format_time() {
  local total_seconds=$1
  local hours=$((total_seconds / 3600))
  local minutes=$(( (total_seconds % 3600) / 60 ))
  local seconds=$((total_seconds % 60))
  
  printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# Function to update the timer for the current project
update_project_timer() {
  local timer_state=$(cat "$TIMER_STATE_FILE")
  local running=$(echo "$timer_state" | jq -r '.running')
  local current_project=$(echo "$timer_state" | jq -r '.current_project')
  
  # Check if Ableton is running
  local ableton_running=$(pgrep -x "Ableton Live" > /dev/null && echo "true" || echo "false")
  
  # If Ableton isn't running, hide the widget and exit
  if [[ "$ableton_running" == "false" ]]; then
    sketchybar --set ableton_timer drawing=off
    sketchybar --set ableton_timer_toggle drawing=off
    
    # If timer was running, save the state as not running
    if [[ "$running" == "true" ]]; then
      local updated_state=$(echo "$timer_state" | jq '.running = false')
      update_timer_state "$updated_state"
    fi
    return
  fi
  
  # Ableton is running, show the widget
  sketchybar --set ableton_timer drawing=on
  sketchybar --set ableton_timer_toggle drawing=on
  
  # Get current project name
  local project_name=$(get_ableton_project_name)
  
  # If no project is open, show idle message
  if [[ -z "$project_name" ]]; then
    sketchybar --set ableton_timer label="No project"
    return
  fi
  
  # Check if project has changed
  if [[ "$current_project" != "$project_name" ]]; then
    # Save the previous project's time if there was one
    if [[ ! -z "$current_project" && "$current_project" != "$project_name" ]]; then
      # Only update if we had a valid previous project
      local prev_project_time=$(echo "$timer_state" | jq -r ".projects[\"$current_project\"] // 0")
      local updated_state=$(echo "$timer_state" | jq ".projects[\"$current_project\"] = $prev_project_time")
      update_timer_state "$updated_state"
    fi
    
    # Update current project
    local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" '.current_project = $name')
    update_timer_state "$updated_state"
    
    # Initialize this project if it doesn't exist yet
    local project_exists=$(echo "$updated_state" | jq ".projects[\"$project_name\"] != null")
    if [[ "$project_exists" == "false" ]]; then
      updated_state=$(echo "$updated_state" | jq --arg name "$project_name" '.projects[$name] = 0')
      update_timer_state "$updated_state"
    fi
    
    timer_state=$(cat "$TIMER_STATE_FILE")
  fi
  
  # Get current elapsed time for this project
  local elapsed_time=$(echo "$timer_state" | jq -r ".projects[\"$project_name\"] // 0")
  
  # If timer is running, update the elapsed time
  if [[ "$running" == "true" ]]; then
    ((elapsed_time++))
    local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" ".projects[\$name] = $elapsed_time")
    update_timer_state "$updated_state"
  fi
  
  # Format the time for display
  local formatted_time=$(format_time $elapsed_time)
  local status_indicator=$([ "$running" == "true" ] && echo "▶︎" || echo "❚❚")
  
  # Update the display
  sketchybar --set ableton_timer label="$project_name: $formatted_time"
  sketchybar --set ableton_timer_toggle label="$status_indicator"
}

# Function to toggle the timer state
toggle_timer() {
  local timer_state=$(cat "$TIMER_STATE_FILE")
  local running=$(echo "$timer_state" | jq -r '.running')
  
  # Toggle the running state
  if [[ "$running" == "true" ]]; then
    local updated_state=$(echo "$timer_state" | jq '.running = false')
  else
    local updated_state=$(echo "$timer_state" | jq '.running = true')
  fi
  
  update_timer_state "$updated_state"
  update_project_timer
}

# Initialize the timer widget (called when Sketchybar starts)
initialize_timer_widget() {
  # Add the timer item to Sketchybar
  sketchybar --add item ableton_timer right \
             --set ableton_timer drawing=off \
             --set ableton_timer update_freq=1 \
             --set ableton_timer script="$HOME/.config/sketchybar/plugins/ableton_project_timer.sh update" \
             --set ableton_timer label="No project" \
             --set ableton_timer icon=🎵 \
             --set ableton_timer icon.padding_right=5
  
  # Add the start/stop toggle button
  sketchybar --add item ableton_timer_toggle right \
             --set ableton_timer_toggle drawing=off \
             --set ableton_timer_toggle click_script="$HOME/.config/sketchybar/plugins/ableton_project_timer.sh toggle" \
             --set ableton_timer_toggle label="❚❚" \
             --set ableton_timer_toggle icon.padding_left=5
}

# Main script logic
case "$1" in
  "init")
    initialize_timer_widget
    ;;
  "update")
    update_project_timer
    ;;
  "toggle")
    toggle_timer
    ;;
  *)
    update_project_timer
    ;;
esac