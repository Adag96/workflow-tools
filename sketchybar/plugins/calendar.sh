#!/bin/bash

NAME="calendar"

sketchybar --set $NAME label="$(date +'%a, %b %d')" 2>/dev/null

pkill -f "sleep 20"