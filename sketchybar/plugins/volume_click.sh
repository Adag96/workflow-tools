#!/bin/bash

WIDTH=100

detail_on() {
  sketchybar --animate tanh 30 --set volume slider.width=$WIDTH
}

detail_off() {
  sketchybar --animate tanh 30 --set volume slider.width=0
}

toggle_detail() {
  if [ "$BUTTON" = "left" ]; then
    INITIAL_WIDTH=$(sketchybar --query volume | jq -r '.slider.width')
    if [ "$INITIAL_WIDTH" -eq "0" ]; then
      detail_on
    else
      detail_off
    fi
  else
    # Right click - open system sound preferences
    open /System/Library/PreferencePanes/Sound.prefPane
  fi
}

toggle_detail
