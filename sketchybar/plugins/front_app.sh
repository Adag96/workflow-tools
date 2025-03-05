#!/bin/sh

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

if [ "$SENDER" = "front_app_switched" ]; then
  echo "$(date): Front app switched to: $INFO" >> /tmp/front_app_debug.log
  
  # Get the app icon
  icon="$($CONFIG_DIR/plugins/icon_map_fn.sh "$INFO")"
  
  # Always set the icon for all apps
  sketchybar --set "$NAME" icon="$icon"
  
  # Always set the label for all apps
  # The Ableton timer will overwrite this label for Live when it's ready
  sketchybar --set "$NAME" label="$INFO"
fi