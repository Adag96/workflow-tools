#!/bin/bash

source "$HOME/.config/sketchybar/items/scheme.sh"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

space_number=$(yabai -m query --spaces --space | jq -r .index)
yabai_mode=$(yabai -m query --spaces --space | jq -r .type)

case "$yabai_mode" in
    bsp)
    sketchybar -m --set yabai_mode icon="$BSP_ICON" \
                                  background.color=$LEFT_ITEM_COLOR \
                                  background.drawing=on \
                                  icon.color=$LEFT_TEXT_COLOR
    ;;
    stack)
    sketchybar -m --set yabai_mode icon="$STACK_ICON" \
                                  background.color=$LEFT_ITEM_COLOR \
                                  background.drawing=on \
                                  icon.color=$LEFT_TEXT_COLOR
    ;;
esac