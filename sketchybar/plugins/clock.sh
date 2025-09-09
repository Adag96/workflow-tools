#!/bin/bash

# Load sizing variables
SCALE_FACTOR=10
BASE_UNIT_RAW=4
BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))
FONT_SIZE_MEDIUM=$((BASE_UNIT * 15 / 4))
FONT_SIZE_LARGE=$((BASE_UNIT * 4))

NAME="clock"

# Get time without leading zero and without seconds
TIME=$(date '+%l:%M')
# Get AM/PM for label (to appear on the right)
AMPM=$(date '+%p')

# Use time as icon (bold), AM/PM as label (regular) with proper spacing
sketchybar --set $NAME icon="$TIME" \
             label="$AMPM" \
             icon.font="SF Pro:Heavy:$FONT_SIZE_LARGE.0" \
             label.font="SF Pro:Regular:$FONT_SIZE_MEDIUM.0" \
             icon.padding_right=8 \
             label.padding_left=0 \
             2>/dev/null

pkill -f "sleep 20"