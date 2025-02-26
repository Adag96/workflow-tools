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

# Add initialization to sketchybarrc if not already there
if ! grep -q "ableton_project_timer.sh init" ~/.config/sketchybar/sketchybarrc; then
  echo "" >> ~/.config/sketchybar/sketchybarrc
  echo "# Initialize Ableton project timer" >> ~/.config/sketchybar/sketchybarrc
  echo "$HOME/.config/sketchybar/plugins/ableton_project_timer.sh init" >> ~/.config/sketchybar/sketchybarrc
  echo "Added Ableton timer initialization to sketchybarrc"
fi