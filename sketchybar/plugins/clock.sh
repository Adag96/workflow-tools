#!/bin/bash

NAME="clock"

sketchybar --set $NAME label="$(date +'%l:%M:%S %p')" 2>/dev/null

pkill -f "sleep 20"