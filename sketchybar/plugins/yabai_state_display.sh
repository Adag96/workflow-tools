#!/bin/bash
# Draws the yabai on/off icon from the real launchd service state.
# No status file: launchd is the same source of truth --start/--stop-service use,
# and it only sees the daemon, never transient `yabai -m` client processes.

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
# This item is also a gear-menu row: hover events just toggle its highlight
case "$SENDER" in
  mouse.entered|mouse.exited) exec "$CONFIG_DIR/plugins/hover.sh" ;;
esac
source "$CONFIG_DIR/items/scheme.sh"
source "$CONFIG_DIR/icons.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme")"

# yabai's launchd label moved from com.koekeishiya.yabai to com.asmvik.yabai
# (project moved orgs) — accept either
if launchctl print "gui/$(id -u)/com.asmvik.yabai" >/dev/null 2>&1 \
   || launchctl print "gui/$(id -u)/com.koekeishiya.yabai" >/dev/null 2>&1; then
  ICON="$YABAI_RUNNING_ICON"; LABEL="Yabai: on"
else
  ICON="$YABAI_STOPPED_ICON"; LABEL="Yabai: off"
fi

sketchybar --set "${NAME:-yabai.toggle}" icon="$ICON" label="$LABEL" icon.color=$RIGHT_TEXT_COLOR
