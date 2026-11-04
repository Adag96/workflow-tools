#!/bin/bash
# Gear menu. The popup lives on the right pill's end spacer (right_end) so its right
# edge lines up with the pill; the gear shows a pressed capsule while it's open.
#   controls.sh toggle | close      (or run by sketchybar on mouse.exited.global)
open_menu()  { sketchybar --set right_end popup.drawing=on  --set controls background.drawing=on; }
close_menu() { sketchybar --set right_end popup.drawing=off --set controls background.drawing=off; }

case "${1:-$SENDER}" in
  mouse.entered|mouse.exited)
    exec "$(dirname "$0")/hover.sh" ;;
  toggle)
    if [ "$(sketchybar --query right_end | jq -r '.popup.drawing')" = "on" ]; then close_menu; else open_menu; fi ;;
  close|mouse.exited.global)
    close_menu ;;
esac
