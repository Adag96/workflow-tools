#!/bin/bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load the dynamic sizing variables directly
export SCALE_FACTOR=10
BASE_UNIT_RAW=4
export BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))

# Load the color scheme
source "$HOME/.config/sketchybar/items/scheme.sh"
current_scheme=$(cat "$HOME/.cache/sketchybar/current_scheme")
get_colors "$current_scheme"

# render_space <space> <apps, one per line> — paint one space's icon strip
render_space() {
 local space="$1" apps="$2"

 # Apps that appear on all spaces but shouldn't show in the icon strip
 EXCLUDED_APPS="Vowen"

 icon_strip=""
 if [ "${apps}" != "" ]; then
   while read -r app
   do
     # Skip excluded apps
     if echo "$EXCLUDED_APPS" | grep -qw "$app"; then
       continue
     fi
     icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$app")"
     if [ -z "$icon_strip" ]; then
       icon_strip="$icon"
     else
       icon_strip+=" $icon"
     fi
   done <<< "${apps}"
 else
   icon_strip=" -"
 fi

 # Check if this space is currently active
 current_space=$(yabai -m query --spaces --space | jq '.index')
 
 # Treat empty icon_strip (after filtering) as no apps
 if [ -z "$icon_strip" ]; then
   icon_strip=" -"
 fi

 # Update the space icons item
 if [ "$space" = "$current_space" ] && [ "$icon_strip" != " -" ]; then
   # Active space with apps - show Pill Level 4 background
   sketchybar --set space_icons.$space label="$icon_strip" \
                                      background.drawing=on \
                                      background.color=$PILL_COLOR_4
   # (pill geometry is set once in items/spaces.sh — don't restyle it here)
 else
   # Inactive space or no apps - no background
   sketchybar --set space_icons.$space label="$icon_strip" \
                                      background.drawing=off
 fi
}

if [ "$SENDER" = "space_windows_change" ]; then
 render_space "$(echo "$INFO" | jq -r '.space')" "$(echo "$INFO" | jq -r '.apps | keys[]')"
elif [ "$SENDER" = "refresh_all" ]; then
 # Called by space_sync.sh after spaces are added/removed: space numbers may
 # have shifted, so repaint every strip from yabai's window list
 WINDOWS_JSON=$(yabai -m query --windows 2>/dev/null)
 for space in $(yabai -m query --spaces 2>/dev/null | jq -r '.[].index'); do
   render_space "$space" "$(echo "$WINDOWS_JSON" | jq -r --argjson s "$space" \
     '[.[] | select(.space == $s and (."is-minimized" | not)) | .app] | unique | .[]')"
 done
fi
