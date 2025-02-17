#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

yabai -m window --toggle float
sketchybar -m --trigger float_change