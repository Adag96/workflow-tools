#!/bin/bash
# Ensure workflow-tools repository path exists
WORKFLOW_TOOLS_PATH="$HOME/workflow-tools"
SKETCHYBAR_CONFIG_PATH="$HOME/.config/sketchybar"
TIMER_DATA_DIR="$SKETCHYBAR_CONFIG_PATH/timer_data"

# Create necessary directories
mkdir -p "$SKETCHYBAR_CONFIG_PATH"
mkdir -p "$TIMER_DATA_DIR"

# Yabai configuration
mkdir -p ~/.config/yabai
ln -sf "$WORKFLOW_TOOLS_PATH/yabairc" ~/.config/yabai/yabairc

# Sketchybar configuration
rm -rf "$SKETCHYBAR_CONFIG_PATH"
ln -sf "$WORKFLOW_TOOLS_PATH/sketchybar" "$SKETCHYBAR_CONFIG_PATH"

# === Install Ableton Project Timer ===
echo "Installing Ableton project timer..."

# Centralized timer state file path
CENTRAL_TIMER_STATE_FILE="$WORKFLOW_TOOLS_PATH/sketchybar/timer_data/timer_state.json"
LOCAL_TIMER_STATE_FILE="$TIMER_DATA_DIR/timer_state.json"

# Ensure the central timer state file exists with a default structure
if [ ! -f "$CENTRAL_TIMER_STATE_FILE" ]; then
  mkdir -p "$(dirname "$CENTRAL_TIMER_STATE_FILE")"
  echo '{
    "running": false,
    "current_project": "Untitled",
    "projects": {
      "Untitled": 0
    }
  }' > "$CENTRAL_TIMER_STATE_FILE"
fi

# Copy (not symlink) the timer state file
# This allows local modifications while keeping a central reference
cp "$CENTRAL_TIMER_STATE_FILE" "$LOCAL_TIMER_STATE_FILE"

echo "Ableton project timer installed successfully"