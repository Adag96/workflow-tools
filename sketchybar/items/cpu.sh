#!/bin/bash

# CPU: the number sits in a fixed, right-aligned box (CPU_WIDTH), so it never
# pushes its neighbours around as the value changes.
sketchybar --add item cpu right \
           --set cpu update_freq=2 \
                     icon=􀧓 \
                     icon.color=$ICON_COLOR \
                     label.width=$CPU_WIDTH \
                     label.align=right \
                     label.color=$RIGHT_TEXT_COLOR \
                     script="$PLUGIN_DIR/cpu.sh"
