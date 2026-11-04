#!/bin/bash

WIDTH=100
ICONS_VOLUME=(􀊣 􀊡 􀊥 􀊧 􀊩)
ICON_FIXED=${ICONS_VOLUME[4]}   # hardware-volume devices: the normal speaker icon, never "muted"

# Audio interfaces like the UA Apollo have no software volume: macOS reports
# "missing value" and sketchybar's volume_change sends 0, which used to show "muted".
# osascript can hang on stalled Apple Events, so it's alarm-killed after 5s.
software_volume() {
  perl -e 'alarm 5; exec @ARGV' osascript -e 'output volume of (get volume settings)' 2>/dev/null
}

get_icon_for_volume() {
  local vol=$1
  case $vol in
  [6-9][0-9] | 100)
    echo ${ICONS_VOLUME[4]}
    ;;
  [3-5][0-9])
    echo ${ICONS_VOLUME[3]}
    ;;
  [1-2][0-9])
    echo ${ICONS_VOLUME[2]}
    ;;
  [1-9])
    echo ${ICONS_VOLUME[1]}
    ;;
  0)
    echo ${ICONS_VOLUME[0]}
    ;;
  *)
    echo ${ICONS_VOLUME[4]}
    ;;
  esac
}

volume_change() {
  if [ "$(software_volume)" = "missing value" ]; then
    sketchybar --set volume_icon icon=$ICON_FIXED
    return
  fi
  ICON=$(get_icon_for_volume "$INFO")
  sketchybar --set volume_icon icon=$ICON

  sketchybar --set volume slider.percentage=$INFO \
    --animate tanh 30 --set volume slider.width=$WIDTH

  sleep 2

  # Check whether the volume was changed another time while sleeping
  FINAL_PERCENTAGE=$(sketchybar --query volume | jq -r ".slider.percentage")
  if [ "$FINAL_PERCENTAGE" -eq "$INFO" ]; then
    sketchybar --animate tanh 30 --set volume slider.width=0
  fi
}

# Routine update: one-time sync at load plus a 5-minute safety net. Live changes
# arrive via the volume_change event (sketchybar holds a persistent CoreAudio
# listener). Each osascript spawns a new CoreAudio client, and polling every
# 10s helped degrade coreaudiod over multi-day uptimes (Sept 2026).
routine_update() {
  # osascript can hang indefinitely if Apple Events stall; alarm-kill after 5s
  # so instances can't pile up across ticks (same failure class as the cpu.sh incident)
  VOLUME=$(perl -e 'alarm 5; exec @ARGV' osascript -e 'output volume of (get volume settings)' 2>/dev/null)
  MUTED=$(perl -e 'alarm 5; exec @ARGV' osascript -e 'output muted of (get volume settings)' 2>/dev/null)

  if [ "$VOLUME" = "missing value" ]; then
    sketchybar --set volume_icon icon=$ICON_FIXED
    return
  fi

  # Handle muted state
  if [ "$MUTED" = "true" ]; then
    VOLUME=0
  fi

  # Only update icon (don't show slider on routine updates)
  ICON=$(get_icon_for_volume "$VOLUME")
  sketchybar --set volume_icon icon=$ICON
}

mouse_clicked() {
  osascript -e "set volume output volume $PERCENTAGE"
}

mouse_entered() {
  [ "$NAME" = "volume_icon" ] && exec "$(dirname "$0")/hover.sh"
  sketchybar --set volume slider.knob.drawing=on
}

mouse_exited() {
  [ "$NAME" = "volume_icon" ] && exec "$(dirname "$0")/hover.sh"
  sketchybar --set volume slider.knob.drawing=off
}

case "$SENDER" in
"volume_change")
  volume_change
  ;;
"routine")
  routine_update
  ;;
"mouse.clicked")
  mouse_clicked
  ;;
"mouse.entered")
  mouse_entered
  ;;
"mouse.exited")
  mouse_exited
  ;;
esac
