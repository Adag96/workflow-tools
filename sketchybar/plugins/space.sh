#!/bin/sh

# Load the dynamic sizing variables directly
export SCALE_FACTOR=10
BASE_UNIT_RAW=4
export BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))
export RADIUS_L4=$((BASE_UNIT * 2))
export HEIGHT_L4=$((BASE_UNIT * 5))
export FONT_SIZE_LARGE=$((BASE_UNIT * 4))

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Check if the space has any windows
WINDOWS_COUNT=$(yabai -m query --spaces --space $SID | jq '.windows | length')

if [ "$SELECTED" = "true" ]; then
  # State: Active/Focused Space 
  # Show the space number without its own background (contained in bracket)
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$ACCENT_COLOR \
                         icon.font="SF Pro:Bold:$FONT_SIZE_LARGE.0" \
                         icon.padding_left=6 \
                         icon.padding_right=0
  
  # Show the concentric Pill Level 3 bracket (space number + icons)
  sketchybar --set space_${SID}_bracket background.drawing=on
  
  # If this space has windows, show Pill Level 4 for icons (innermost)
  if [ "$WINDOWS_COUNT" -gt 0 ]; then
    sketchybar --set space_icons.$SID background.drawing=on \
                                     background.color=$PILL_COLOR_4 \
                                     background.corner_radius=$RADIUS_L4 \
                                     background.height=$HEIGHT_L4 \
                                     label.color=$LEFT_TEXT_COLOR
  else
    sketchybar --set space_icons.$SID background.drawing=off
  fi
  
elif [ "$WINDOWS_COUNT" -gt 0 ]; then
  # State: Occupied but Inactive Space
  # No backgrounds, space number in white color
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         icon.font="SF Pro:Regular:$FONT_SIZE_LARGE.0" \
                         icon.padding_left=0 \
                         icon.padding_right=0
  
  # Hide the concentric bracket
  sketchybar --set space_${SID}_bracket background.drawing=off
  
  # Show icons without background
  sketchybar --set space_icons.$SID background.drawing=off \
                                   label.color=$LEFT_TEXT_COLOR
else
  # State: Empty and Inactive Space
  # No backgrounds, space number in white
  sketchybar --set $NAME background.drawing=off \
                         icon.color=$LEFT_TEXT_COLOR \
                         icon.font="SF Pro:Regular:$FONT_SIZE_LARGE.0" \
                         icon.padding_left=0 \
                         icon.padding_right=0
  
  # Hide the concentric bracket
  sketchybar --set space_${SID}_bracket background.drawing=off
  
  # Hide icons
  sketchybar --set space_icons.$SID background.drawing=off
fi