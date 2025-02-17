#!/bin/bash

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$SENDER" = "space_windows_change" ]; then
 space="$(echo "$INFO" | jq -r '.space')"
 apps="$(echo "$INFO" | jq -r '.apps | keys[]')"

 # Debug logging
 echo "----------------------" >> /tmp/sketchybar_debug.log
 echo "Timestamp: $(date)" >> /tmp/sketchybar_debug.log
 echo "Space: $space" >> /tmp/sketchybar_debug.log
 echo "Raw apps: $apps" >> /tmp/sketchybar_debug.log

 icon_strip=" "
 if [ "${apps}" != "" ]; then
   while read -r app
   do
     # Additional debug for each app
     icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$app")"
     echo "App: $app, Mapped Icon: $icon" >> /tmp/sketchybar_debug.log
     icon_strip+=" $icon"
   done <<< "${apps}"
 else
   icon_strip=" -"
 fi

 # Debug the final icon strip
 echo "Final Icon Strip: $icon_strip" >> /tmp/sketchybar_debug.log

 sketchybar --set space.$space label="$icon_strip"
fi