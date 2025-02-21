#!/bin/bash

# First, ensure we get the current color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Log for debugging
echo "Reloading sketchybar with scheme: $current_scheme" >> /tmp/scheme_debug.log
echo "BAR_COLOR value: $BAR_COLOR" >> /tmp/scheme_debug.log

# Original reload functionality
sketchybar -m --set reload.bar \
              background.color=$LEFT_ITEM_COLOR \
              background.drawing=on \
              icon.color=$RIGHT_TEXT_FEEDBACK_COLOR

sleep 0.3

sketchybar -m --set reload.bar \
              background.drawing=off \
              icon.color=$ICON_COLOR

sketchybar --reload