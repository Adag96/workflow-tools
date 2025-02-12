#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/yabai_icons.sh"

space_number=$(yabai -m query --spaces --space | jq -r .index)
yabai_mode=$(yabai -m query --spaces --space | jq -r .type)

case "$yabai_mode" in
    bsp)
    sketchybar -m --set yabai_mode label="$BSP_ICON" \
                                  background.color=$ACCENT_COLOR \
                                  background.drawing=on \
                                  label.color=$BAR_COLOR
    ;;
    stack)
    sketchybar -m --set yabai_mode label="$STACK_ICON" \
                                  background.color=$ACCENT_COLOR \
                                  background.drawing=on \
                                  label.color=$BAR_COLOR
    ;;
esac