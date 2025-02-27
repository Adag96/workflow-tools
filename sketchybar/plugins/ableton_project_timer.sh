#!/bin/bash

# Create necessary files for storing project data if they don't exist
TIMER_DATA_DIR="$HOME/.config/sketchybar/timer_data"
TIMER_STATE_FILE="$TIMER_DATA_DIR/timer_state.json"

# Add debugging
debug_log() {
  echo "$(date): $1" >> /tmp/ableton_timer_debug.log
}

debug_log "Script started"

# Define fallback icons first
RESUME_ICON="▶︎"
PAUSE_ICON="❚❚"

# Try to source the icons file
if [ -f "$HOME/.config/sketchybar/icons.sh" ]; then
  debug_log "Attempting to source icons.sh"
  source "$HOME/.config/sketchybar/icons.sh"
  debug_log "After sourcing: RESUME_TIMER_ICON=${RESUME_TIMER_ICON:-not set}, PAUSE_TIMER_ICON=${PAUSE_TIMER_ICON:-not set}"
  
  # Use the icons if they're defined, otherwise stick with fallbacks
  if [ -n "$RESUME_TIMER_ICON" ]; then
    RESUME_ICON="$RESUME_TIMER_ICON"
    debug_log "Using custom resume icon"
  fi
  
  if [ -n "$PAUSE_TIMER_ICON" ]; then
    PAUSE_ICON="$PAUSE_TIMER_ICON"
    debug_log "Using custom pause icon"
  fi
else
  debug_log "Icons file not found at $HOME/.config/sketchybar/icons.sh"
fi

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
  local window_app=$(yabai -m query --windows --window | jq -r '.app')
  
  # Check if this is Ableton (app name "Live")
  if [[ "$window_app" == "Live" ]]; then
    # Skip Save dialogs to prevent them from being tracked as projects
    if [[ "$window_title" == "Save" || "$window_title" == "Save As" || "$window_title" == "Save Live Set" ]]; then
      debug_log "Detected Save dialog - ignoring window title change"
      return
    fi
    
    # For Ableton, the project name is simply the window title
    echo "$window_title"
  else
    echo ""
  fi
}

# Helper function to format seconds into variable-length time format
format_time() {
  local total_seconds=$1
  local hours=$((total_seconds / 3600))
  local minutes=$(( (total_seconds % 3600) / 60 ))
  local seconds=$((total_seconds % 60))
  
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

# Function to update the timer for the current project
update_project_timer() {
  local timer_state=$(cat "$TIMER_STATE_FILE")
  local running=$(echo "$timer_state" | jq -r '.running')
  local current_project=$(echo "$timer_state" | jq -r '.current_project')
  
  # Check if Ableton is running
  local ableton_running=$(pgrep -x "Live" > /dev/null && echo "true" || echo "false")
  debug_log "Ableton running: $ableton_running"
  
  # If Ableton isn't running, hide the widget and exit
  if [[ "$ableton_running" == "false" ]]; then
    # Remove the Untitled project entry when Live closes
    local has_untitled=$(echo "$timer_state" | jq '.projects | has("Untitled")')
    if [[ "$has_untitled" == "true" ]]; then
      debug_log "Live is closed - removing Untitled project data"
      local updated_state=$(echo "$timer_state" | jq 'del(.projects["Untitled"])')
      update_timer_state "$updated_state"
    fi
    
    # Also remove any "Save" entries that might have been created
    for save_variant in "Save" "Save As" "Save Live Set"; do
      local has_variant=$(echo "$timer_state" | jq --arg variant "$save_variant" '.projects | has($variant)')
      if [[ "$has_variant" == "true" ]]; then
        debug_log "Live is closed - removing $save_variant dialog project data"
        local updated_state=$(echo "$timer_state" | jq --arg variant "$save_variant" 'del(.projects[$variant])')
        update_timer_state "$updated_state"
      fi
    done
    
    # Reset current_project to "Live" when Live closes
    local updated_state=$(echo "$timer_state" | jq '.current_project = "Live"')
    update_timer_state "$updated_state"
    debug_log "Live is closed - reset current_project to 'Live'"
    
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
  debug_log "Project name: $project_name"
  
  # If no project is open, show idle message
  if [[ -z "$project_name" ]]; then
    sketchybar --set ableton_timer label=""
    return
  fi
  
  # Check if project has changed
  if [[ "$current_project" != "$project_name" ]]; then
    debug_log "Project changed from '$current_project' to '$project_name'"
    
    # Special case: Only migrate time from "Untitled" if the new project doesn't already exist
    if [[ "$current_project" == "Untitled" && "$project_name" != "Untitled" ]]; then
      # Check if the target project already exists in our tracking
      local project_exists=$(echo "$timer_state" | jq ".projects[\"$project_name\"] != null")
      
      if [[ "$project_exists" == "false" ]]; then
        # This is likely a save of a new project - migrate the time
        local untitled_time=$(echo "$timer_state" | jq -r '.projects["Untitled"] // 0')
        local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" --arg time "$untitled_time" '.projects[$name] = ($time|tonumber)')
        updated_state=$(echo "$updated_state" | jq --arg name "$project_name" '.current_project = $name')
        update_timer_state "$updated_state"
        
        # Keep running state
        local running_state=$(echo "$timer_state" | jq -r '.running')
        updated_state=$(echo "$updated_state" | jq --arg state "$running_state" '.running = ($state=="true")')
        update_timer_state "$updated_state"
        
        # Remove the Untitled project entirely
        updated_state=$(echo "$updated_state" | jq 'del(.projects["Untitled"])')
        update_timer_state "$updated_state"
        
        debug_log "Migrated time from Untitled to $project_name: $untitled_time seconds"
      else
        # This is likely opening an existing project - keep its existing time
        local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" '.current_project = $name')
        update_timer_state "$updated_state"
        
        # Remove the Untitled project entirely
        updated_state=$(echo "$updated_state" | jq 'del(.projects["Untitled"])')
        update_timer_state "$updated_state"
      fi
    elif [[ "$current_project" != "Untitled" && "$project_name" == "Untitled" ]]; then
      # We're switching to Untitled from a named project
      # First save the previous project's time
      if [[ "$current_project" != "Live" ]]; then
        local prev_project_time=$(echo "$timer_state" | jq -r ".projects[\"$current_project\"] // 0")
        local updated_state=$(echo "$timer_state" | jq ".projects[\"$current_project\"] = $prev_project_time")
      else
        local updated_state=$(echo "$timer_state")
      fi
      
      # Start fresh with Untitled project
      updated_state=$(echo "$updated_state" | jq '.projects["Untitled"] = 0')
      updated_state=$(echo "$updated_state" | jq '.current_project = "Untitled"')
      updated_state=$(echo "$updated_state" | jq '.running = true')
      update_timer_state "$updated_state"
    else
      # Standard project change handling
      # Save the previous project's time
      if [[ ! -z "$current_project" && "$current_project" != "Live" ]]; then
        local prev_project_time=$(echo "$timer_state" | jq -r ".projects[\"$current_project\"] // 0")
        local updated_state=$(echo "$timer_state" | jq ".projects[\"$current_project\"] = $prev_project_time")
        
        # If we're leaving Untitled, remove it entirely
        if [[ "$current_project" == "Untitled" ]]; then
          updated_state=$(echo "$updated_state" | jq 'del(.projects["Untitled"])')
        fi
        
        update_timer_state "$updated_state"
      else
        # Coming from "Live" placeholder, just update current project
        local updated_state=$(echo "$timer_state")
      fi
      
      # Update current project
      local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" '.current_project = $name')
      update_timer_state "$updated_state"
      
      # Initialize this project if it doesn't exist yet
      local project_exists=$(echo "$updated_state" | jq ".projects[\"$project_name\"] != null")
      if [[ "$project_exists" == "false" ]]; then
        updated_state=$(echo "$updated_state" | jq --arg name "$project_name" '.projects[$name] = 0')
        # Auto-start timer for new projects
        updated_state=$(echo "$updated_state" | jq '.running = true')
        update_timer_state "$updated_state"
      fi
    fi
    
    # Reload the timer state after changes
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
  # Icon shows the action that will happen when clicked
  local status_indicator=$([ "$running" == "true" ] && echo "$PAUSE_ICON" || echo "$RESUME_ICON")
  
  # Update the display
  debug_log "Updating display: project=$project_name, time=$formatted_time, icon=$status_indicator"
  sketchybar --set ableton_timer label=""
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
  debug_log "Initializing timer widget"
  # Add the timer item to Sketchybar
  sketchybar --add item ableton_timer right \
             --set ableton_timer drawing=off \
             --set ableton_timer update_freq=1 \
             --set ableton_timer script="$HOME/.config/sketchybar/plugins/ableton_project_timer.sh update" \
             --set ableton_timer label="" \
             --set ableton_timer width=0 \
             --set ableton_timer icon.drawing=off
  
  # Add the start/stop toggle button next to front app
  sketchybar --add item ableton_timer_toggle left \
             --set ableton_timer_toggle drawing=off \
             --set ableton_timer_toggle \
                   label.padding=0 \
                   icon.padding_left=0 \
                   icon.padding_right=0 \
                   icon.font="$ICON_FONT:Semibold:18.0" \
                   background.corner_radius=50 \
                   padding.left=5 \
                   padding.right=0 \
                   align=center \
             --set ableton_timer_toggle click_script="$HOME/.config/sketchybar/plugins/ableton_project_timer.sh toggle" \
             --set ableton_timer_toggle label="$RESUME_ICON" \
             --set ableton_timer_toggle associated_display=active

  debug_log "Timer widget initialization completed"
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