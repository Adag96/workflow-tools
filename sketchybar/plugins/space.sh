#!/bin/sh

# The $SELECTED variable is available for space components and indicates if
# the space invoking this script (with name: $NAME) is currently selected:
# https://felixkratz.github.io/SketchyBar/config/components#space----associate-mission-control-spaces-with-an-item

source "$HOME/.config/sketchybar/items/scheme.sh"
source "$CONFIG_DIR/colors.sh" # Loads all defined colors

if [ $SELECTED = true ]; then
  sketchybar --set $NAME background.drawing=on \
                         background.color=$LEFT_ITEM_COLOR \
                         label.color=$LEFT_TEXT_COLOR \
                         icon.color=$LEFT_TEXT_COLOR
else
  sketchybar --set $NAME background.color=off \
                         label.color=$LEFT_ITEM_COLOR \
                         icon.color=$LEFT_ITEM_COLOR 
fi
