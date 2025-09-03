#!/bin/sh

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Check if the space has any windows
HAS_WINDOWS=$(yabai -m query --spaces --space $SID | jq '."has-windows"')

if [ "$SELECTED" = "true" ]; then
  # State: Focused
  # Restore the background "pill" and set contrasting text/icon color
  sketchybar --set $NAME background.drawing=on \
                         background.color=$ACTIVE_SPACE_ITEM_COLOR \
                         icon.color=$ACTIVE_SPACE_TEXT_COLOR \
                         label.color=$ACTIVE_SPACE_TEXT_COLOR
elif [ "$HAS_WINDOWS" = "true" ]; then
  # State: Occupied (has windows but not focused)
  # Turn off background, use accent color for text/icon
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$ACCENT_COLOR \
                         label.color=$ACCENT_COLOR
else
  # State: Empty
  # Turn off background, use default color for text/icon
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         label.color=$LEFT_TEXT_COLOR
fi