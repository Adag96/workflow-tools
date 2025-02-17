#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

sketchybar -m --set reload.bar \
    background.color=$ACCENT_COLOR \
    background.drawing=on \
    icon.color=$BAR_COLOR

sleep 0.3

sketchybar -m --set reload.bar \
    background.drawing=off \
    icon.color=$ICON_COLOR

sketchybar --reload