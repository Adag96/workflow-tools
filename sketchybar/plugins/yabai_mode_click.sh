#!/bin/bash
# Toggle the current space between BSP and Stack. The hover capsule is the click
# feedback; yabai_mode.sh (chained in click_script) redraws the icon.
case "$(yabai -m query --spaces --space | jq -r .type)" in
  bsp)   yabai -m space --layout stack ;;
  stack) yabai -m space --layout bsp ;;
esac
