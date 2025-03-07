#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

case "$(yabai -m query --windows --window | jq .floating)" in
    0)
    sketchybar -m --set yabai_float label="$FLOAT_WINDOW_OFF" \
                                   background.color=$LEFT_ITEM_COLOR \
                                   background.drawing=on \
                                   label.color=$BAR_COLOR
    ;;
    1)
    sketchybar -m --set yabai_float label="$FLOAT_WINDOW_ON" \
                                   background.color=$LEFT_ITEM_COLOR \
                                   background.drawing=on \
                                   label.color=$BAR_COLOR
    ;;
esac