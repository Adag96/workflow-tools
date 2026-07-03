#!/bin/bash
# Ensure workflow-tools repository path exists
WORKFLOW_TOOLS_PATH="$HOME/workflow-tools"
SKETCHYBAR_CONFIG_PATH="$HOME/.config/sketchybar"

# Create necessary directories
mkdir -p "$HOME/.config"

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
