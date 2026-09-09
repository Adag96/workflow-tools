#!/bin/bash
# Draws the yabai on/off icon from the real launchd service state.
# No status file: launchd is the same source of truth --start/--stop-service use,
# and it only sees the daemon, never transient `yabai -m` client processes.

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/items/scheme.sh"
source "$CONFIG_DIR/icons.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme")"

if launchctl print "gui/$(id -u)/com.koekeishiya.yabai" >/dev/null 2>&1; then
  ICON="$YABAI_RUNNING_ICON"
else
  ICON="$YABAI_STOPPED_ICON"
fi

sketchybar --set "${NAME:-yabai.toggle}" icon="$ICON" icon.color=$RIGHT_TEXT_COLOR
