#!/bin/bash
# Gear menu. The popup hangs from the gear itself (right-aligned) and the gear's pressed
# capsule becomes a folder tab running down into it (MENU_TAB_* in sketchybarrc).
#   controls.sh toggle | close      (or run by sketchybar on mouse.exited.global)
TAB_OPEN="background.height=${MENU_TAB_HEIGHT:-50} background.y_offset=${MENU_TAB_OFFSET:--12} background.drawing=on"
TAB_CLOSED="background.height=${CAPSULE_HEIGHT:-26} background.y_offset=0 background.drawing=off"
# shellcheck disable=SC2086
open_menu()  { sketchybar --set controls popup.drawing=on  $TAB_OPEN; }
# shellcheck disable=SC2086
close_menu() { sketchybar --set controls popup.drawing=off $TAB_CLOSED; }

case "${1:-$SENDER}" in
  mouse.entered|mouse.exited)
    exec "$(dirname "$0")/hover.sh" ;;
  toggle)
    if [ "$(sketchybar --query controls | jq -r '.popup.drawing')" = "on" ]; then close_menu; else open_menu; fi ;;
  close|mouse.exited.global)
    close_menu ;;
esac
