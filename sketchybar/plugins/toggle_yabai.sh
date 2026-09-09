#!/bin/bash
# Enable/disable yabai. Decides from the live launchd state, not a cached file,
# so one click always does the opposite of what yabai is actually doing.

if launchctl print "gui/$(id -u)/com.koekeishiya.yabai" >/dev/null 2>&1; then
  yabai --stop-service
else
  yabai --start-service
fi

# Redraw the icon from the new state
NAME="${NAME:-yabai.toggle}" "$HOME/.config/sketchybar/plugins/yabai_state_display.sh"
