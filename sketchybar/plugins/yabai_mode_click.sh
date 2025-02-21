#!/bin/bash
source "$HOME/.config/sketchybar/items/scheme.sh"
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
        background.color=$LEFT_ITEM_FEEDBACK_COLOR \
        background.drawing=on \
        icon.color=$LEFT_TEXT_FEEDBACK_COLOR

    # Wait for full animation
    sleep 0.2
    
    # Set icon color back to text color in final state
    sketchybar -m --animate sin 0 --set yabai_mode \
        icon="$STACK_ICON" \
        background.color=$LEFT_ITEM_COLOR \
        icon.color=$LEFT_TEXT_COLOR
    ;;
    stack)
    # Switch to bsp mode first
    yabai -m space --layout bsp
    
    # Show visual feedback with current icon
    sketchybar -m --set yabai_mode \
        background.color=$LEFT_ITEM_FEEDBACK_COLOR \
        background.drawing=on \
        icon.color=$LEFT_TEXT_FEEDBACK_COLOR

    # Wait for full animation
    sleep 0.2
    
    # Set icon color back to text color in final state
    sketchybar -m --animate sin 0 --set yabai_mode \
        icon="$BSP_ICON" \
        background.color=$LEFT_ITEM_COLOR \
        icon.color=$LEFT_TEXT_COLOR
    ;;
esac