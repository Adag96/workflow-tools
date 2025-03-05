#!/bin/bash

# Define primary location on external T7 drive
T7_TIMER_DIR="/Volumes/T7/Ableton Timer Data"
T7_TIMER_STATE_FILE="$T7_TIMER_DIR/timer_state.json"

# Define fallback local location (keep as backup)
LOCAL_TIMER_DATA_DIR="$HOME/.local/share/sketchybar_timer_data"  
LOCAL_TIMER_STATE_FILE="$LOCAL_TIMER_DATA_DIR/timer_state.json"
LAST_ABLETON_STATE_FILE="$LOCAL_TIMER_DATA_DIR/last_ableton_state.json"  
MANUAL_OVERRIDE_FILE="$LOCAL_TIMER_DATA_DIR/manual_override.json"

# Add debugging with timestamp and line numbers  
debug_log() {  
  echo "$(date '+%Y-%m-%d %H:%M:%S') [${BASH_LINENO[0]}]: $1" >> /tmp/ableton_timer_debug.log  
}

debug_log "Script started with PID $$"

# Define fallback icons first  
RESUME_ICON="▶︎"  
PAUSE_ICON="❚❚"

# Check if T7 drive is connected
is_t7_connected() {
  if [ -d "$T7_TIMER_DIR" ]; then
    debug_log "T7 drive is connected at $T7_TIMER_DIR"
    return 0
  else
    debug_log "T7 drive is NOT connected"
    return 1
  fi
}

# Get the appropriate timer state file path
get_timer_file_path() {
  if is_t7_connected; then
    echo "$T7_TIMER_STATE_FILE"
  else
    echo "$LOCAL_TIMER_STATE_FILE"
  fi
}

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

# Create the necessary directories
mkdir -p "$LOCAL_TIMER_DATA_DIR"
debug_log "Local timer data directory: $LOCAL_TIMER_DATA_DIR"

# Create T7 directory if drive is connected
if is_t7_connected; then
  mkdir -p "$T7_TIMER_DIR"
  debug_log "Created T7 timer directory: $T7_TIMER_DIR"
fi

# Initialize the timer state file if it doesn't exist or is invalid  
initialize_timer_state() {  
  local timer_file=$(get_timer_file_path)
  debug_log "Checking timer state file: $timer_file"  
  local needs_init=true  
  
  # Check if file exists and has content  
  if [ -f "$timer_file" ]; then  
    local file_size=$(wc -c < "$timer_file")  
    debug_log "Existing file size: $file_size bytes"  
    
    if [ "$file_size" -gt 10 ]; then  # At least some reasonable JSON size  
      # Check if content is valid JSON  
      if cat "$timer_file" | jq . >/dev/null 2>&1; then  
        debug_log "Existing timer state file contains valid JSON"  
        needs_init=false  
      else  
        debug_log "Existing timer state file contains invalid JSON"  
      fi  
    else  
      debug_log "Existing timer state file too small or empty"  
    fi  
  else  
    debug_log "Timer state file does not exist"  
  fi  
  
  # Initialize if needed  
  if [ "$needs_init" = true ]; then  
    debug_log "Initializing timer state file"  
    # First, check if we have data in the other location
    local other_file=""
    if is_t7_connected; then
      other_file="$LOCAL_TIMER_STATE_FILE"
    else
      other_file="$T7_TIMER_STATE_FILE"
    fi
    
    # If other location has valid data, copy it
    if [ -f "$other_file" ] && [ "$(wc -c < "$other_file")" -gt 10 ]; then
      if cat "$other_file" | jq . >/dev/null 2>&1; then
        debug_log "Copying timer state from $other_file to $timer_file"
        cp "$other_file" "$timer_file"
        needs_init=false
      fi
    fi
    
    # If we still need to initialize, create new file
    if [ "$needs_init" = true ]; then
      echo '{  
        "running": false,  
        "current_project": "Untitled",  
        "last_update_time": 0,  
        "projects": {  
          "Untitled": 0  
        }  
      }' > "$timer_file"  
      
      # Verify file creation  
      if [ -f "$timer_file" ]; then  
        local new_size=$(wc -c < "$timer_file")  
        debug_log "Timer state file created, size: $new_size bytes"  
        debug_log "Timer state file content: $(cat "$timer_file")"  
      else  
        debug_log "ERROR: Failed to create timer state file"  
      fi
    fi
  fi  
}

# Call initialization during script startup  
initialize_timer_state

# Write timer state to file
write_timer_state() {  
  local new_state="$1"  
  local timer_file=$(get_timer_file_path)
  debug_log "Writing timer state to file: $timer_file"  
  echo "$new_state" > "$timer_file"  
  sync  # Force filesystem sync to ensure write completes  
  
  # If T7 is connected and we wrote to the T7, also update the local copy as backup
  if is_t7_connected; then
    debug_log "Updating local backup copy of timer state"
    echo "$new_state" > "$LOCAL_TIMER_STATE_FILE"
    sync
  fi
  
  # If we're writing to local and T7 exists, try to update T7 as well
  if [ "$timer_file" = "$LOCAL_TIMER_STATE_FILE" ] && [ -d "$T7_TIMER_DIR" ]; then
    debug_log "T7 just became available, updating T7 copy"
    echo "$new_state" > "$T7_TIMER_STATE_FILE"
    sync
  fi
}

# Initialize or get the Ableton state  
get_ableton_state() {  
  debug_log "Getting Ableton state data"  
  if [ ! -f "$LAST_ABLETON_STATE_FILE" ] || [ ! -s "$LAST_ABLETON_STATE_FILE" ]; then  
    debug_log "Initializing Ableton state file"  
    echo '{"running": false, "last_check_time": 0}' > "$LAST_ABLETON_STATE_FILE"  
  fi  
  # Read and return the file content, ensuring it's valid JSON  
  local content=$(cat "$LAST_ABLETON_STATE_FILE")  
  if echo "$content" | jq . >/dev/null 2>&1; then  
    echo "$content"  
  else  
    debug_log "Invalid Ableton state JSON, reinitializing"  
    echo '{"running": false, "last_check_time": 0}'  
  fi  
}

# Write Ableton state to file  
write_ableton_state() {  
  local new_state="$1"  
  debug_log "Writing new Ableton state: $new_state"  
  if echo "$new_state" | jq . >/dev/null 2>&1; then  
    echo "$new_state" > "$LAST_ABLETON_STATE_FILE"  
    sync  # Force filesystem sync  
  else  
    debug_log "ERROR: Attempted to write invalid JSON to Ableton state file"  
  fi  
}

# Initialize or get the manual override state  
get_manual_override() {  
  debug_log "Getting manual override state"  
  if [ ! -f "$MANUAL_OVERRIDE_FILE" ] || [ ! -s "$MANUAL_OVERRIDE_FILE" ]; then  
    debug_log "Initializing manual override file"  
    echo '{"enabled": false, "timestamp": 0}' > "$MANUAL_OVERRIDE_FILE"  
  fi  
  # Read and return the file content, ensuring it's valid JSON  
  local content=$(cat "$MANUAL_OVERRIDE_FILE")  
  if echo "$content" | jq . >/dev/null 2>&1; then  
    echo "$content"  
  else  
    debug_log "Invalid manual override JSON, reinitializing"  
    echo '{"enabled": false, "timestamp": 0}'  
  fi  
}

# Write manual override state to file  
write_manual_override() {  
  local new_state="$1"  
  debug_log "Writing new manual override state: $new_state"  
  if echo "$new_state" | jq . >/dev/null 2>&1; then  
    echo "$new_state" > "$MANUAL_OVERRIDE_FILE"  
    sync  # Force filesystem sync  
  else  
    debug_log "ERROR: Attempted to write invalid JSON to manual override file"  
  fi  
}

# Helper function to get the current Ableton project name from window title  
get_ableton_project_name() {  
  debug_log "=== get_ableton_project_name START ==="  
  # Get ALL windows first, then filter for Live  
  debug_log "Getting all window info from yabai..."  
  all_windows=$(yabai -m query --windows)  
  debug_log "Searching for Live windows..."  
  # Extract Live windows  
  live_windows=$(echo "$all_windows" | jq -r '.[] | select(.app=="Live")')  
  debug_log "Found Live windows: $(echo "$live_windows" | wc -l | tr -d ' ')"  
  # If we found Live windows  
  if [[ -n "$live_windows" ]]; then  
    # Filter for primary project window
    # First, get all titles
    all_titles=$(echo "$live_windows" | jq -r '.title')
    debug_log "All Live window titles: $(echo "$all_titles" | tr '\n' ', ')"
    
    # Filter out plugin windows (those containing '/') and dialog windows
    main_titles=$(echo "$all_titles" | grep -v "/" | grep -v "Save" | grep -v "Open" | grep -v "Export" | head -n 1)
    debug_log "Main project titles after filtering: $(echo "$main_titles" | tr '\n' ', ')"
    
    # Get the first valid title as window_title
    window_title=$(echo "$main_titles" | head -n 1)
    debug_log "Selected window title: '$window_title'"
    
    # Check if this is a Save dialog  
    if [[ "$window_title" == "Save" || "$window_title" == "Save As" || "$window_title" == "Save Live Set" ]]; then  
      debug_log "Detected Save dialog - ignoring window title change"  
      debug_log "=== get_ableton_project_name END ==="  
      return  
    fi  
    
    # Return the title  
    debug_log "Returning window title: '$window_title'"  
    echo "$window_title"  
  else  
    debug_log "No Live windows found"  
    echo ""  
  fi  
  debug_log "=== get_ableton_project_name END ==="  
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

# Get timer state from file, ensuring it's valid  
get_timer_state() {  
  debug_log "Getting timer state from file"  
  # Ensure the file exists and is valid  
  initialize_timer_state  
  # Read and return the file content
  local timer_file=$(get_timer_file_path)
  cat "$timer_file"  
}

# Function to update the timer for the current project  
update_project_timer() {  
  debug_log "=== update_project_timer START ==="  
  # Get current time for timing measurements  
  local current_time=$(date +%s)  
  debug_log "Current time: $current_time"  
  
  # Check if T7 is connected
  local t7_connected=false
  if is_t7_connected; then
    t7_connected=true
  fi
  debug_log "T7 drive connected: $t7_connected"
  
  # Get the current timer state  
  local timer_state=$(get_timer_state)  
  debug_log "Current timer state: $timer_state"  
  local running=$(echo "$timer_state" | jq -r '.running')  
  local current_project=$(echo "$timer_state" | jq -r '.current_project')  
  local last_update_time=$(echo "$timer_state" | jq -r '.last_update_time // 0')  
  debug_log "Current state: running=$running, current_project=$current_project, last_update_time=$last_update_time"  
  
  # Get the manual override state  
  local manual_override=$(get_manual_override)  
  local override_enabled=$(echo "$manual_override" | jq -r '.enabled')  
  local override_timestamp=$(echo "$manual_override" | jq -r '.timestamp')  
  debug_log "Manual override: enabled=$override_enabled, timestamp=$override_timestamp"  
  
  # Check if Ableton is running  
  local ableton_running=$(pgrep -x "Live" > /dev/null && echo "true" || echo "false")  
  debug_log "Ableton running: $ableton_running"  
  
  # Check if Ableton is in focus (front app)  
  local front_app=$(yabai -m query --windows --window | jq -r '.app')  
  local ableton_focused=$([ "$front_app" = "Live" ] && echo "true" || echo "false")  
  debug_log "Front app: $front_app, Ableton focused: $ableton_focused"  
  
  # Get the last Ableton state  
  local ableton_state=$(get_ableton_state)  
  local last_running=$(echo "$ableton_state" | jq -r '.running')  
  
  # Check for Ableton restart (was not running before, is running now)  
  if [[ "$last_running" == "false" && "$ableton_running" == "true" ]]; then  
    debug_log "Ableton was just started, resetting 'Untitled' project data and setting current project to 'Live'"  
    
    # Reset the Untitled project data  
    local new_state=$(echo "$timer_state" | jq '.projects["Untitled"] = 0')  
    
    # Set current project to "Live" initially  
    new_state=$(echo "$new_state" | jq '.current_project = "Live"')  
    
    # Initialize "Live" project if it doesn't exist  
    local live_exists=$(echo "$new_state" | jq '.projects | has("Live")')  
    if [[ "$live_exists" == "false" ]]; then  
      new_state=$(echo "$new_state" | jq '.projects["Live"] = 0')  
    fi  
    
    # Update last_update_time  
    new_state=$(echo "$new_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
    
    write_timer_state "$new_state"  
    timer_state="$new_state"  
    current_project="Live"  
    last_update_time=$current_time  
  fi  
  
  # Update and store the current Ableton state  
  local new_ableton_state=$(echo "$ableton_state" | jq --arg running "$ableton_running" --arg time "$current_time" \
    '.running = ($running == "true") | .last_check_time = ($time | tonumber)')  
  write_ableton_state "$new_ableton_state"  
  
  # If Ableton isn't running, hide the widgets and exit  
  if [[ "$ableton_running" == "false" ]]; then  
    debug_log "Ableton not running, hiding widgets"  
    sketchybar --set ableton_timer drawing=off  
    sketchybar --set ableton_timer_toggle drawing=off  
    debug_log "=== update_project_timer END ==="  
    return  
  fi  
  
  # Ableton is running, show the widgets  
  debug_log "Ableton is running, showing widgets"  
  sketchybar --set ableton_timer drawing=off  
  sketchybar --set ableton_timer_toggle drawing=on  
  
  # Auto-pause timer if Ableton loses focus  
  if [[ "$ableton_focused" == "false" && "$running" == "true" && "$override_enabled" == "false" ]]; then  
    debug_log "Ableton lost focus, auto-pausing timer"  
    running="false"  
    local updated_state=$(echo "$timer_state" | jq '.running = false')  
    updated_state=$(echo "$updated_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
    write_timer_state "$updated_state"  
    timer_state="$updated_state"  
    last_update_time=$current_time  
  fi  
  
  # Auto-resume timer if Ableton gains focus (only if not manually paused)  
  if [[ "$ableton_focused" == "true" && "$running" == "false" && "$override_enabled" == "false" ]]; then  
    debug_log "Ableton gained focus, auto-resuming timer"  
    running="true"  
    local updated_state=$(echo "$timer_state" | jq '.running = true')  
    updated_state=$(echo "$updated_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
    write_timer_state "$updated_state"  
    timer_state="$updated_state"  
    last_update_time=$current_time  
  fi  
  
  # No hard drive message if T7 is not connected
if [ "$t7_connected" = "false" ] && [ "$ableton_focused" = "true" ]; then
  debug_log "T7 drive not connected, showing warning message with project name"
  # Get current project name
  local project_name=$(get_ableton_project_name)
  
  # If no project is open, use appropriate default
  if [[ -z "$project_name" ]]; then
    if [[ "$current_project" == "Live" ]]; then
      project_name="Live"
    else
      project_name="Untitled"
    fi
  fi
  
  sketchybar --set front_app label="$project_name - No Drive!"
  sketchybar --set ableton_timer label="$project_name - No Drive!"
  debug_log "=== update_project_timer END ==="
  return
fi
  
  # Get current project name  
  debug_log "Getting current project name..."  
  local project_name=$(get_ableton_project_name)  
  debug_log "Project name: '$project_name'"  
  
  # If no project is open, use appropriate default  
  if [[ -z "$project_name" ]]; then  
    # If we're in initial startup (current project is already "Live"), keep it as "Live"  
    if [[ "$current_project" == "Live" ]]; then  
      debug_log "No project name detected during startup, keeping as 'Live'"  
      project_name="Live"  
    else  
      debug_log "No project name detected, using 'Untitled'"  
      project_name="Untitled"  
    fi  
  fi  
  
  # Check if project has changed  
  if [[ "$current_project" != "$project_name" ]]; then  
    debug_log "Project changed from '$current_project' to '$project_name'"  
    
    # Special case: Only migrate time from "Untitled" if the new project doesn't already exist  
    if [[ "$current_project" == "Untitled" && "$project_name" != "Untitled" ]]; then  
      # Check if the target project already exists in our tracking  
      local project_exists=$(echo "$timer_state" | jq --arg name "$project_name" '.projects[$name] != null')  
      
      if [[ "$project_exists" == "false" ]]; then  
        # This is likely a save of a new project - migrate the time  
        local untitled_time=$(echo "$timer_state" | jq -r '.projects["Untitled"] // 0')  
        debug_log "Migrating time from Untitled to $project_name: $untitled_time seconds"  
        
        local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" --arg time "$untitled_time" '.projects[$name] = ($time|tonumber)')  
        updated_state=$(echo "$updated_state" | jq --arg name "$project_name" '.current_project = $name')  
        updated_state=$(echo "$updated_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
        write_timer_state "$updated_state"  
        
        # Keep running state  
        local running_state=$(echo "$timer_state" | jq -r '.running')  
        updated_state=$(echo "$updated_state" | jq --arg state "$running_state" '.running = ($state=="true")')  
        write_timer_state "$updated_state"  
        
        # Remove the Untitled project entirely  
        updated_state=$(echo "$updated_state" | jq 'del(.projects["Untitled"])')  
        write_timer_state "$updated_state"  
        
        debug_log "Successfully migrated time from Untitled to $project_name"  
        timer_state="$updated_state"  
        current_project="$project_name"  
        last_update_time=$current_time  
      else  
        # This is switching to an existing project - just update current project  
        debug_log "Switching to existing project: $project_name"  
        local updated_state=$(echo "$timer_state" | jq --arg name "$project_name" '.current_project = $name')  
        updated_state=$(echo "$updated_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
        write_timer_state "$updated_state"  
        timer_state="$updated_state"  
        current_project="$project_name"  
        last_update_time=$current_time  
      fi  
    else  
      # Regular project change  
      debug_log "Regular project change"  
      
      # Get all projects data  
      local projects_data=$(echo "$timer_state" | jq '.projects')  
      
      # Create a new state with the updated project  
      local new_state=$(echo '{  
        "running": '"$running"',  
        "current_project": "'"$project_name"'",  
        "last_update_time": '"$current_time"',  
        "projects": '"$projects_data"'  
      }')  
      
      # Initialize this project if it doesn't exist yet  
      local project_exists=$(echo "$new_state" | jq --arg name "$project_name" '.projects[$name] != null')  
      if [[ "$project_exists" == "false" ]]; then  
        debug_log "Initializing new project: $project_name"  
        new_state=$(echo "$new_state" | jq --arg name "$project_name" '.projects[$name] = 0')  
        # Auto-start timer for new projects  
        new_state=$(echo "$new_state" | jq '.running = true')  
        running="true"  
      fi  
      
      write_timer_state "$new_state"  
      timer_state="$new_state"  
      current_project="$project_name"  
      last_update_time=$current_time  
    fi  
  fi  
  
  # Get current elapsed time for this project  
  local elapsed_time=$(echo "$timer_state" | jq -r --arg name "$project_name" '.projects[$name] // 0')  
  debug_log "Current elapsed time for '$project_name': $elapsed_time seconds"  
  
  # Calculate time difference since last update  
  local time_diff=$((current_time - last_update_time))  
  debug_log "Time difference since last update: $time_diff seconds"  
  
  # If timer is running and at least 1 second has passed, increment the timer  
  if [[ "$running" == "true" && $time_diff -ge 1 ]]; then  
    debug_log "Timer is running, adding 1 second"  
    
    # Only increment by 1 second each time to maintain accurate timing  
    elapsed_time=$((elapsed_time + 1))  
    debug_log "Incremented time to $elapsed_time seconds"  
    
    # Update the time for this project  
    local new_state=$(echo "$timer_state" | jq --arg name "$project_name" --argjson time "$elapsed_time" '.projects[$name] = $time')  
    # Update the last update time  
    new_state=$(echo "$new_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
    
    # Write the updated state back to the file  
    write_timer_state "$new_state"  
    
    # Update our in-memory copy  
    timer_state="$new_state"  
    
    debug_log "Updated timer state file with new time"  
  else  
    debug_log "Timer is not running or less than 1 second passed, time stays at $elapsed_time seconds"  
  fi  
  
  # Format the time for display  
  local formatted_time=$(format_time $elapsed_time)  
  
  # Icon shows the action that will happen when clicked  
  local status_indicator=$([ "$running" == "true" ] && echo "$PAUSE_ICON" || echo "$RESUME_ICON")  
  
  # Update the timer toggle button  
  debug_log "Updating timer toggle button: $status_indicator"  
  sketchybar --set ableton_timer_toggle label="$status_indicator"  
  
  # Update the right-side timer display  
  debug_log "Updating right-side timer display: $project_name - $formatted_time"  
  sketchybar --set ableton_timer label="$project_name - $formatted_time"  
  
  # Update the front app label when Ableton is focused  
  if [[ "$ableton_focused" == "true" ]]; then  
    debug_log "Updating front_app label to show project and time"  
    sketchybar --set front_app label="$project_name - $formatted_time"  
  fi  
  
  debug_log "=== update_project_timer END ==="  
}

# Function to toggle the timer state  
toggle_timer() {  
  debug_log "=== toggle_timer START ==="  
  # Get current time  
  local current_time=$(date +%s)  
  # Get the current timer state  
  local timer_state=$(get_timer_state)  
  debug_log "Current timer state: $timer_state"  
  # Get the current running state  
  local running=$(echo "$timer_state" | jq -r '.running')  
  debug_log "Current running state: $running"  
  # Toggle the running state  
  if [[ "$running" == "true" ]]; then  
    debug_log "Changing running state to false"  
    running="false"  
  else  
    debug_log "Changing running state to true"  
    running="true"  
  fi  
  # Create the updated state  
  local updated_state=$(echo "$timer_state" | jq ".running = $running")  
  # Update the last update time  
  updated_state=$(echo "$updated_state" | jq --argjson time "$current_time" '.last_update_time = $time')  
  debug_log "Updated state: $updated_state"  
  # Write the new state to file  
  write_timer_state "$updated_state"  
  # Set the manual override flag  
  # When manually toggled to off, enable override to prevent auto-resume  
  # When manually toggled to on, disable override to allow normal auto behavior  
  local override_enabled=$([[ "$running" == "false" ]] && echo "true" || echo "false")  
  local new_override=$(echo '{"enabled": '"$override_enabled"', "timestamp": '"$current_time"'}')  
  write_manual_override "$new_override"  
  debug_log "Set manual override to: $new_override"  
  # Update the display immediately  
  local status_indicator=$([ "$running" == "true" ] && echo "$PAUSE_ICON" || echo "$RESUME_ICON")  
  sketchybar --set ableton_timer_toggle label="$status_indicator"  
  debug_log "Updated timer state, now calling update_project_timer"  
  update_project_timer  
  debug_log "=== toggle_timer END ==="  
}

# Initialize the timer widget (called when Sketchybar starts)  
initialize_timer_widget() {  
  debug_log "Initializing timer widget"  
  # Add the timer item to Sketchybar (visible on right side)  
  sketchybar --add item ableton_timer right \
             --set ableton_timer drawing=off \
             --set ableton_timer update_freq=1 \
             --set ableton_timer script="$HOME/.config/sketchybar/plugins/ableton_project_timer.sh update" \
             --set ableton_timer label="" \
             --set ableton_timer width=dynamic \
             --set ableton_timer icon.drawing=off

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