#!/bin/bash

NAME="clock"

# Get time without leading zero and without seconds
TIME=$(date '+%l:%M')
# Get AM/PM for label (to appear on the right)
AMPM=$(date '+%p')

# Use time as icon (bold), AM/PM as label (regular) with proper spacing
sketchybar --set $NAME icon="$TIME" \
             label="$AMPM" \
             icon.font="SF Pro:Heavy:16.0" \
             label.font="SF Pro:Regular:15.0" \
             icon.padding_right=8 \
             label.padding_left=0 \
             2>/dev/null

pkill -f "sleep 20"