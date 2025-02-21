#!/bin/bash

sketchybar --add item volume right \
           --set volume script="$PLUGIN_DIR/volume.sh" \
             icon.color=$RIGHT_TEXT_COLOR \
             label.color=$RIGHT_TEXT_COLOR \
           --subscribe volume volume_change \