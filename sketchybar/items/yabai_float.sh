#!/bin/bash

source "$CONFIG_DIR/colors.sh"

sketchybar --add item yabai_float right \
           --set yabai_float background.color=$ACCENT_COLOR \
                            label.color=$BAR_COLOR \
                            background.drawing=on \
                            background.height=26 \
                            background.corner_radius=6 \
                            icon.color=$BAR_COLOR \
                            label.font="$FONT:Bold:15.0" \
                            script="$PLUGIN_DIR/yabai_float.sh" \
           --subscribe yabai_float float_change window_focus