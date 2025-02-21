#!/bin/bash

NAME="clock"

# Get time without leading zero
TIME=$(date '+%l:%M:%S')
# Get AM/PM for icon
AMPM=$(date '+%p')

# Use time as label, AM/PM as icon
sketchybar --set $NAME label="$TIME" \
             icon="$AMPM" \
             icon.font="SF Pro:Regular:15" \
             2>/dev/null

pkill -f "sleep 20"