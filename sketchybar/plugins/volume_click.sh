#!/bin/bash

WIDTH=100

detail_on() {
  sketchybar --animate tanh 30 --set volume slider.width=$WIDTH
}

detail_off() {
  sketchybar --animate tanh 30 --set volume slider.width=0
}

# Devices without a macOS volume (e.g. the Apollo, whose level SoundSource owns) can't
# be set from here, so the slider stays closed for them. osascript is alarm-wrapped.
controllable() {
  [ "$(perl -e 'alarm 5; exec @ARGV' osascript -e 'output volume of (get volume settings)' 2>/dev/null)" != "missing value" ]
}

toggle_detail() {
  if [ "$BUTTON" = "left" ]; then
    controllable || return 0
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
