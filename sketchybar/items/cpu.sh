#!/bin/bash

sketchybar --add item cpu right \
           --set cpu update_freq=2 \
                     icon=􀫥 \
                     icon.color=$RIGHT_TEXT_COLOR \
                     label.color=$RIGHT_TEXT_COLOR \
                     script="$PLUGIN_DIR/cpu.sh" \
                     NAME=cpu