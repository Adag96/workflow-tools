#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

space_number=$(yabai -m query --spaces --space | jq -r .index)
yabai_mode=$(yabai -m query --spaces --space | jq -r .type)

case "$yabai_mode" in
    bsp)
    # Switch to stack mode first
    yabai -m space --layout stack
    
    # Show visual feedback with current icon
    sketchybar -m --set yabai_mode \
        background.color=$ITEM_BG_COLOR \
        background.drawing=on \
        icon.color=$BAR_COLOR

    # Wait for full animation
    sleep 0.2
    
    # Set icon color back to BAR_COLOR in final state
    sketchybar -m --animate sin 0 --set yabai_mode \
        icon="$STACK_ICON" \
        background.color=$ACCENT_COLOR \
        icon.color=$BAR_COLOR
    ;;
    stack)
    # Switch to bsp mode first
    yabai -m space --layout bsp
    
    # Show visual feedback with current icon
    sketchybar -m --set yabai_mode \
        background.color=$ITEM_BG_COLOR \
        background.drawing=on \
        icon.color=$BAR_COLOR

    # Wait for full animation
    sleep 0.2
    
    # Set icon color back to BAR_COLOR in final state
    sketchybar -m --animate sin 0 --set yabai_mode \
        icon="$BSP_ICON" \
        background.color=$ACCENT_COLOR \
        icon.color=$BAR_COLOR
    ;;
esac