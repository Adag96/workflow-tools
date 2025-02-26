#!/bin/bash

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

sketchybar --add item front_app left \
           --set front_app      background.color=$ACTIVE_SPACE_ITEM_COLOR \
                                icon.color=$ACTIVE_SPACE_TEXT_COLOR \
                                icon.font="sketchybar-app-font:Regular:15.0" \
                                label.font="$TEXT_FONT:Bold:15.0"\
                                label.color=$ACTIVE_SPACE_TEXT_COLOR \
                                update_freq=1 \
                                script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched