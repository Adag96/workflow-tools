#!/bin/bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load the dynamic sizing variables directly
export SCALE_FACTOR=10
BASE_UNIT_RAW=4
export BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))
export RADIUS_L4=$((BASE_UNIT * 2))
export HEIGHT_L4=$((BASE_UNIT * 5))

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$HOME/.cache/sketchybar/current_scheme")
get_colors "$current_scheme"

if [ "$SENDER" = "space_windows_change" ]; then
 space="$(echo "$INFO" | jq -r '.space')"
 apps="$(echo "$INFO" | jq -r '.apps | keys[]')"

 # Debug logging
 echo "----------------------" >> /tmp/sketchybar_debug.log
 echo "Timestamp: $(date)" >> /tmp/sketchybar_debug.log
 echo "Space: $space" >> /tmp/sketchybar_debug.log
 echo "Raw apps: $apps" >> /tmp/sketchybar_debug.log

 icon_strip=""
 if [ "${apps}" != "" ]; then
   while read -r app
   do
     # Additional debug for each app
     icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$app")"
     echo "App: $app, Mapped Icon: $icon" >> /tmp/sketchybar_debug.log
     if [ -z "$icon_strip" ]; then
       icon_strip="$icon"
     else
       icon_strip+=" $icon"
     fi
   done <<< "${apps}"
 else
   icon_strip=" -"
 fi

 # Debug the final icon strip
 echo "Final Icon Strip: $icon_strip" >> /tmp/sketchybar_debug.log

 # Check if this space is currently active
 current_space=$(yabai -m query --spaces --space | jq '.index')
 
 # Update the space icons item
 if [ "$space" = "$current_space" ] && [ "${apps}" != "" ]; then
   # Active space with apps - show Pill Level 4 background
   sketchybar --set space_icons.$space label="$icon_strip" \
                                      background.drawing=on \
                                      background.color=$PILL_COLOR_4 \
                                      background.corner_radius=$RADIUS_L4 \
                                      background.height=$HEIGHT_L4
 else
   # Inactive space or no apps - no background
   sketchybar --set space_icons.$space label="$icon_strip" \
                                      background.drawing=off
 fi
fi