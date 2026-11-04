#!/bin/bash
CONFIG_DIR="${CONFIG_DIR:-$HOME/workflow-tools/sketchybar}"
case "$SENDER" in
  mouse.entered|mouse.exited) exec "$CONFIG_DIR/plugins/hover.sh" ;;
esac
source "$CONFIG_DIR/icons.sh"

case "$(yabai -m query --spaces --space | jq -r .type)" in
  bsp)   sketchybar --set yabai_mode icon="$BSP_ICON"   label="Layout: BSP" ;;
  stack) sketchybar --set yabai_mode icon="$STACK_ICON" label="Layout: Stack" ;;
esac
