#!/bin/bash

source "$CONFIG_DIR/colors.sh"

sketchybar --add item yabai_mode right \
           --set yabai_mode background.color=$ACCENT_COLOR \
                           label.color=$BAR_COLOR \
                           background.drawing=on \
                           background.height=26 \
                           background.corner_radius=6 \
                           label.font="$FONT:Bold:15.0" \
                           icon.padding_left=15 \
                           label.padding_right=15 \
                           script="$PLUGIN_DIR/yabai_mode.sh"