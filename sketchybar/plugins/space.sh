#!/bin/sh

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Check if the space has any windows
WINDOWS_COUNT=$(yabai -m query --spaces --space $SID | jq '.windows | length')

if [ "$SELECTED" = "true" ]; then
  # State: Focused
  # Restore the background "pill" and set contrasting text/icon color
  sketchybar --set $NAME background.drawing=on \
                         background.color=$ACTIVE_SPACE_ITEM_COLOR \
                         background.height=20 \
                         background.corner_radius=9 \
                         icon.color=$ACTIVE_SPACE_TEXT_COLOR \
                         label.color=$ACTIVE_SPACE_TEXT_COLOR
elif [ "$WINDOWS_COUNT" -gt 0 ]; then
  # State: Occupied (has windows but not focused)
  # Turn off background, use accent color for label but keep icon normal
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         label.color=$ACCENT_COLOR
else
  # State: Empty
  # Turn off background, use default color for text/icon
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         label.color=$LEFT_TEXT_COLOR
fi