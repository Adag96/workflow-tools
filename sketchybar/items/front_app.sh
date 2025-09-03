#!/bin/bash

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

sketchybar --add item front_app left \
           --set front_app      background.color=$ACTIVE_SPACE_ITEM_COLOR \
                                background.height=20 \
                                background.corner_radius=9 \
                                icon.color=$ACTIVE_SPACE_TEXT_COLOR \
                                icon.font="sketchybar-app-font:Regular:15.0" \
                                label.font="$TEXT_FONT:Bold:15.0"\
                                label.color=$ACTIVE_SPACE_TEXT_COLOR \
                                padding_right=2 \
                                update_freq=1 \
                                script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched