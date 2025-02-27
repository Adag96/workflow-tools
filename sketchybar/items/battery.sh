#!/bin/bash

# Check if the machine has a battery
if [[ $(system_profiler SPPowerDataType | grep "Battery Information") ]]; then
  sketchybar --add item battery right \
             --set battery update_freq=120 \
                           script="$PLUGIN_DIR/battery.sh" \
                           NAME=battery \
             --subscribe battery system_woke power_source_change
else
  # No battery, do nothing
  echo "No battery detected. Skipping battery item."
fi