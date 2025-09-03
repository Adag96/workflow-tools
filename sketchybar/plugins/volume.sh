#!/bin/bash

WIDTH=100
ICONS_VOLUME=(􀊣 􀊡 􀊥 􀊧 􀊩)

volume_change() {
  # Set icon + color depending on volume percentage
  case $INFO in
  [6-9][0-9] | 100)
    ICON=${ICONS_VOLUME[4]}
    ;;
  [3-5][0-9])
    ICON=${ICONS_VOLUME[3]}
    ;;
  [1-2][0-9])
    ICON=${ICONS_VOLUME[2]}
    ;;
  [1-9])
    ICON=${ICONS_VOLUME[1]}
    ;;
  0)
    ICON=${ICONS_VOLUME[0]}
    ;;
  *) ICON=${ICONS_VOLUME[4]} ;;
  esac

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
