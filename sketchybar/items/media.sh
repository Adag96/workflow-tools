#!/bin/bash

# Get the machine name
MACHINE_NAME=$(scutil --get ComputerName)

# Set device-specific configurations
if [[ "$MACHINE_NAME" == *"Studio"* ]]; then
    MAX_CHARS=40  # Larger value for Mac Studio
else
    MAX_CHARS=24  # Default to MacBook Pro value
fi

sketchybar --add item media right \
          --set media label.color=$MEDIA_COLOR \
                      label.max_chars=$MAX_CHARS \
                      icon.padding_left=0 \
                      scroll_texts=on \
                      icon=􀑪 \
                      icon.color=$MEDIA_COLOR \
                      background.drawing=off \
                      script="$PLUGIN_DIR/media.sh" \
          --subscribe media media_change