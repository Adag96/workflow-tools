#!/bin/bash
# Hover capsule for anything clickable (bar buttons + gear-menu rows).
# The gear and the Gamify balance keep their capsule while their menu is open (pressed state).
case "$SENDER" in
  mouse.entered)
    # The Gamify clock is only a button while idle; expanded, it's a status readout
    if [ "$NAME" = "gamify.1" ] && [ "$(sketchybar --query gamify.1.btn | jq -r '.icon.width')" -gt 0 ]; then
      exit 0
    fi
    sketchybar --set "$NAME" background.drawing=on ;;
  mouse.exited)
    if [ "$NAME" = "controls" ] && [ "$(sketchybar --query controls | jq -r '.popup.drawing')" = "on" ]; then
      exit 0
    fi
    case "$NAME" in
      gamify.1|gamify.step.*)   # Gamify start menu open: the balance stays pressed, and
                                # the menu closes once the cursor has really left it
        if [ "$(sketchybar --query gamify.step.value | jq -r '.label.width')" -gt 0 ]; then
          "$CONFIG_DIR/plugins/gamify_menu.sh" check &
          [ "$NAME" = "gamify.1" ] && exit 0
        fi ;;
    esac
    sketchybar --set "$NAME" background.drawing=off ;;
esac
