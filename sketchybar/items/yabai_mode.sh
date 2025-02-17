#!/bin/bash

source "$CONFIG_DIR/colors.sh"

sketchybar --add item yabai_mode right \
           --set yabai_mode background.color=$ACCENT_COLOR \
                           label.color=$BAR_COLOR \
                           background.drawing=on \
                           script="$PLUGIN_DIR/yabai_mode.sh"