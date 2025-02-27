#!/bin/bash

sketchybar --add item cpu right \
           --set cpu update_freq=2 \
                     icon=􀫥 \
                     icon.color=$RIGHT_TEXT_COLOR \
                     label.color=$RIGHT_TEXT_COLOR \
                     padding_left=5 \
                     padding_right=0 \
                     script="$PLUGIN_DIR/cpu.sh" \
                     NAME=cpu