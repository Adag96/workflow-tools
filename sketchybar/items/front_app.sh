#!/bin/bash

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

sketchybar --add item front_app left \
           --set front_app      background.color=$LEFT_ITEM_COLOR \
                                icon.color=$LEFT_TEXT_COLOR \
                                icon.font="sketchybar-app-font:Regular:15.0" \
                                label.font="$TEXT_FONT:Bold:15.0"\
                                label.color=$LEFT_TEXT_COLOR \
                                script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched