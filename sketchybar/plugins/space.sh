#!/bin/sh

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Check if the space has any windows
WINDOWS_COUNT=$(yabai -m query --spaces --space $SID | jq '.windows | length')

if [ "$SELECTED" = "true" ]; then
  # State: Active/Focused Space
  # Show background pill with bold space number and app icons, with proper left padding
  sketchybar --set $NAME background.drawing=on \
                         background.color=$ACTIVE_SPACE_ITEM_COLOR \
                         background.height=20 \
                         background.corner_radius=$CORNER_RADIUS \
                         icon.color=$ACTIVE_SPACE_TEXT_COLOR \
                         icon.font="SF Pro:Bold:16.0" \
                         icon.padding_left=6 \
                         icon.padding_right=0 \
                         label.drawing=on \
                         label.color=$ACTIVE_SPACE_TEXT_COLOR
elif [ "$WINDOWS_COUNT" -gt 0 ]; then
  # State: Occupied but Inactive Space
  # No background, both space number and app icons in white color
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         icon.font="SF Pro:Regular:16.0" \
                         icon.padding_left=0 \
                         icon.padding_right=0 \
                         label.drawing=on \
                         label.color=$LEFT_TEXT_COLOR
else
  # State: Empty and Inactive Space
  # No background, space number in white, no app icons
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         icon.font="SF Pro:Regular:16.0" \
                         icon.padding_left=0 \
                         icon.padding_right=0 \
                         label.drawing=off
fi