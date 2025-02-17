#!/bin/bash

sketchybar --add item wifi right \
           --set wifi script="$PLUGIN_DIR/wifi.sh" \
                     update_freq=2 \
                     icon.font="SF Pro:Bold:16.0" \
                     icon.padding_right=4 \
                     label.font="SF Pro:Regular:12.0" \
                     label.padding_right=8 \
                     background.padding_left=2 \
                     background.padding_right=2 \
                     background.corner_radius=5 \
                     icon.color=$WHITE \
                     label.color=$WHITE