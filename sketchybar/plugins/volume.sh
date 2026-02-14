#!/bin/bash

WIDTH=100
ICONS_VOLUME=(􀊣 􀊡 􀊥 􀊧 􀊩)

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

# Routine update: poll actual system volume to catch changes from SoundSource etc.
routine_update() {
  VOLUME=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
  MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)

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
  sketchybar --set volume slider.knob.drawing=on
}

mouse_exited() {
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
