#!/bin/bash

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

sketchybar --add item front_app left \
           --set front_app      background.color=$PILL_COLOR_2 \
                                background.height=$HEIGHT_L4 \
                                background.corner_radius=$RADIUS_L3 \
                                icon.color=$LEFT_TEXT_COLOR \
                                icon.font="sketchybar-app-font:Regular:$FONT_SIZE_MEDIUM.0" \
                                label.font="$TEXT_FONT:Bold:$FONT_SIZE_MEDIUM.0"\
                                label.color=$LEFT_TEXT_COLOR \
                                padding_right=$PADDING_M \
                                update_freq=1 \
                                script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched