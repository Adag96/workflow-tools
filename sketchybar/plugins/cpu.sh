#!/bin/bash

# Get CPU usage using top and calculate total active percentage
CPU_USAGE=$(top -l 1 | grep "CPU usage" | awk '{print $3 + $5}' | cut -d'.' -f1)

sketchybar --set $NAME label="$CPU_USAGE%"