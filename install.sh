#!/bin/bash
# Ensure workflow-tools repository path exists
WORKFLOW_TOOLS_PATH="$HOME/workflow-tools"
SKETCHYBAR_CONFIG_PATH="$HOME/.config/sketchybar"

# Define the local timer data directory - outside of the repo structure
LOCAL_TIMER_DATA_DIR="$HOME/.local/share/sketchybar_timer_data"
LOCAL_TIMER_STATE_FILE="$LOCAL_TIMER_DATA_DIR/timer_state.json"

# Define T7 timer data directory
T7_TIMER_DIR="/Volumes/T7/Ableton Timer Data"
T7_TIMER_STATE_FILE="$T7_TIMER_DIR/timer_state.json"

# Create necessary directories
mkdir -p "$HOME/.config"
mkdir -p "$LOCAL_TIMER_DATA_DIR"

# If T7 is connected, create the directory there too
if [ -d "/Volumes/T7" ]; then
  mkdir -p "$T7_TIMER_DIR"
  echo "Created T7 timer directory at $T7_TIMER_DIR"
fi

# Yabai configuration — back up a pre-existing real config before symlinking
mkdir -p "$HOME/.config/yabai"
if [ -e "$HOME/.config/yabai/yabairc" ] && [ ! -L "$HOME/.config/yabai/yabairc" ]; then
  mv "$HOME/.config/yabai/yabairc" "$HOME/.config/yabai/yabairc.bak.$(date +%s)"
  echo "Backed up existing yabairc"
fi
ln -sf "$WORKFLOW_TOOLS_PATH/yabairc" "$HOME/.config/yabai/yabairc"

# Sketchybar configuration — skip if already linked; back up anything else (never delete)
if [ "$(readlink "$SKETCHYBAR_CONFIG_PATH")" = "$WORKFLOW_TOOLS_PATH/sketchybar" ]; then
  echo "Sketchybar config already linked"
else
  if [ -e "$SKETCHYBAR_CONFIG_PATH" ] || [ -L "$SKETCHYBAR_CONFIG_PATH" ]; then
    mv "$SKETCHYBAR_CONFIG_PATH" "$SKETCHYBAR_CONFIG_PATH.bak.$(date +%s)"
    echo "Backed up existing sketchybar config"
  fi
  ln -s "$WORKFLOW_TOOLS_PATH/sketchybar" "$SKETCHYBAR_CONFIG_PATH"
fi

# Initialize Yabai status file
if pgrep -q yabai; then
  echo "running" > /tmp/yabai_status
  echo "Initialized Yabai status as running"
else
  echo "stopped" > /tmp/yabai_status
  echo "Initialized Yabai status as stopped"
fi

# === Install Ableton Project Timer ===
echo "Installing Ableton project timer..."

# Function to determine which timer file to use
get_timer_file() {
  if [ -d "/Volumes/T7" ]; then
    # T7 is connected
    if [ -f "$T7_TIMER_STATE_FILE" ] && [ -s "$T7_TIMER_STATE_FILE" ]; then
      # T7 timer file exists and has content
      echo "$T7_TIMER_STATE_FILE"
    elif [ -f "$LOCAL_TIMER_STATE_FILE" ] && [ -s "$LOCAL_TIMER_STATE_FILE" ]; then
      # Local file exists and has content, copy to T7
      mkdir -p "$T7_TIMER_DIR"
      cp "$LOCAL_TIMER_STATE_FILE" "$T7_TIMER_STATE_FILE"
      echo "$T7_TIMER_STATE_FILE"
    else
      # Create new file on T7
      mkdir -p "$T7_TIMER_DIR"
      echo "$T7_TIMER_STATE_FILE"
    fi
  else
    # T7 is not connected, use local file
    echo "$LOCAL_TIMER_STATE_FILE"
  fi
}

# Get the appropriate timer file to use
TIMER_FILE=$(get_timer_file)
echo "Using timer state file: $TIMER_FILE"

# Ensure the timer state file exists with a default structure
if [ ! -f "$TIMER_FILE" ]; then
  echo '{
    "running": false,
    "current_project": "Untitled",
    "projects": {
      "Untitled": 0
    }
  }' > "$TIMER_FILE"
  echo "Created new timer state file at $TIMER_FILE"
else
  echo "Using existing timer state file at $TIMER_FILE"
fi

# Also maintain a local copy for when T7 is disconnected
if [ "$TIMER_FILE" = "$T7_TIMER_STATE_FILE" ] && [ ! -f "$LOCAL_TIMER_STATE_FILE" ]; then
  cp "$T7_TIMER_STATE_FILE" "$LOCAL_TIMER_STATE_FILE"
  echo "Created local backup copy of timer state"
fi

# Ensure other necessary timer data files exist (never reset existing ones —
# manual_override holds a live pause state)
if [ ! -f "$LOCAL_TIMER_DATA_DIR/last_ableton_state.json" ]; then
  echo '{
  "running": false,
  "last_check_time": 0
}' > "$LOCAL_TIMER_DATA_DIR/last_ableton_state.json"
fi

if [ ! -f "$LOCAL_TIMER_DATA_DIR/manual_override.json" ]; then
  echo '{
  "enabled": false,
  "timestamp": 0
}' > "$LOCAL_TIMER_DATA_DIR/manual_override.json"
fi

echo "Ableton project timer installed successfully"