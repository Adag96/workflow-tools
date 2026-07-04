#!/bin/bash

# First, ensure we get the current color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Original reload functionality
sketchybar -m --set reload.bar \
              background.color=$LEFT_ITEM_COLOR \
              background.drawing=on \
              icon.color=$RIGHT_TEXT_FEEDBACK_COLOR

sleep 0.3

sketchybar -m --set reload.bar \
              background.drawing=off \
              icon.color=$ICON_COLOR

# Reload the bar only. Restarting yabai here caused a reload storm: the yabai
# restart fired the display watcher, whose own `sketchybar --reload` ran
# concurrently with this one — two config loads interleaving left the bar
# transparent, mis-ordered, and missing pills. Restart yabai via its toggle
# widget or `yabai --restart-service` when actually needed.
sketchybar --reload