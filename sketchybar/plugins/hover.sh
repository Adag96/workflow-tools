#!/bin/bash
# Hover capsule for anything clickable (bar buttons + gear-menu rows).
# The gear keeps its capsule while its menu is open (pressed state).
case "$SENDER" in
  mouse.entered) sketchybar --set "$NAME" background.drawing=on ;;
  mouse.exited)
    if [ "$NAME" = "controls" ] && [ "$(sketchybar --query right_end | jq -r '.popup.drawing')" = "on" ]; then
      exit 0
    fi
    sketchybar --set "$NAME" background.drawing=off ;;
esac
