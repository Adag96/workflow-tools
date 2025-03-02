#!/bin/bash
# Ensure workflow-tools repository path exists
WORKFLOW_TOOLS_PATH="$HOME/workflow-tools"
SKETCHYBAR_CONFIG_PATH="$HOME/.config/sketchybar"

# Define the local timer data directory - outside of the repo structure
LOCAL_TIMER_DATA_DIR="$HOME/.local/share/sketchybar_timer_data"
LOCAL_TIMER_STATE_FILE="$LOCAL_TIMER_DATA_DIR/timer_state.json"

# Create necessary directories
mkdir -p "$SKETCHYBAR_CONFIG_PATH"
mkdir -p "$LOCAL_TIMER_DATA_DIR"

# Yabai configuration
mkdir -p ~/.config/yabai
ln -sf "$WORKFLOW_TOOLS_PATH/yabairc" ~/.config/yabai/yabairc

# Sketchybar configuration
rm -rf "$SKETCHYBAR_CONFIG_PATH"
ln -sf "$WORKFLOW_TOOLS_PATH/sketchybar" "$SKETCHYBAR_CONFIG_PATH"

# === Install Ableton Project Timer ===
echo "Installing Ableton project timer..."

# Ensure the local timer state file exists with a default structure
if [ ! -f "$LOCAL_TIMER_STATE_FILE" ]; then
  echo '{
    "running": false,
    "current_project": "Untitled",
    "projects": {
      "Untitled": 0
    }
  }' > "$LOCAL_TIMER_STATE_FILE"
  echo "Created new timer state file at $LOCAL_TIMER_STATE_FILE"
else
  echo "Using existing timer state file at $LOCAL_TIMER_STATE_FILE"
fi

# Ensure other necessary timer data files exist
echo '{
  "running": false,
  "last_check_time": 0
}' > "$LOCAL_TIMER_DATA_DIR/last_ableton_state.json"

echo '{
  "enabled": false,
  "timestamp": 0
}' > "$LOCAL_TIMER_DATA_DIR/manual_override.json"

echo "Ableton project timer installed successfully"