#!/bin/bash
# Yabai configuration
mkdir -p ~/.config/yabai
ln -sf ~/workflow-tools/yabairc ~/.config/yabai/yabairc

# Sketchybar configuration
rm -rf ~/.config/sketchybar
ln -sf ~/workflow-tools/sketchybar ~/.config/sketchybar

# === Install Ableton Project Timer ===
echo "Installing Ableton project timer..."

# Create timer data directory (this won't be symlinked)
mkdir -p ~/.config/sketchybar/timer_data

# Only create the timer state file if it DOES NOT already exist
if [ ! -f ~/.config/sketchybar/timer_data/timer_state.json ]; then
  echo '{
    "running": false,
    "current_project": "",
    "projects": {}
  }' > ~/.config/sketchybar/timer_data/timer_state.json
  echo "Created new timer state file"
else
  echo "Existing timer state file preserved"
fi