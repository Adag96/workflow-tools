#!/bin/bash

# Yabai configuration
mkdir -p ~/.config/yabai
ln -sf ~/workflow-tools/yabairc ~/.config/yabai/yabairc

# Sketchybar configuration
rm -rf ~/.config/sketchybar
ln -sf ~/workflow-tools/sketchybar ~/.config/sketchybar