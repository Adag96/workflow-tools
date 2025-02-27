#!/bin/bash

# Yabai mode icons
export BSP_ICON="􀇷"
export STACK_ICON="􀏜"
# Float icons
export FLOAT_WINDOW_ON="􀈈" # icon for floating window
export FLOAT_WINDOW_OFF="􀈆" # icon for tiled window

# Battery level icons
export BATTERY_FULL="􀛨"
export BATTERY_HIGH="􀺸"
export BATTERY_MED="􀺶"
export BATTERY_LOW="􀛩"
export BATTERY_CRIT="􀛪"
export BATTERY_CHARGING="􀢋"

# Sketchybar reload icon
export RELOAD_ICON="􂣾"

# Color scheme selector icon
export SCHEME_ICON="􀏅"

# Ableton timer icons
export RESUME_TIMER_ICON="􀊖"
export PAUSE_TIMER_ICON="􀊘"

# WiFi widget icons
WIFI_ICONS=(
  wifi.high=􀽗
  wifi.med=􀽗
  wifi.low=􀽗
  wifi.disconnected=􀽗
)

for icon in "${WIFI_ICONS[@]}"; do
  sketchybar --set $icon
done