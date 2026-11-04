#!/bin/bash
# Bail if a previous sample is still running — prevents pileup under load
pgrep -fq "top -l 1 -n 0" && exit 0

# Get CPU usage using top (-n 0 skips the per-process list, which is the slow part)
CPU_USAGE=$(top -l 1 -n 0 | awk '/CPU usage/ {print int($3 + $5)}')
[ -z "$CPU_USAGE" ] && exit 0

# The label box fits two digits (see CPU_WIDTH); cap so 100% can't overflow it
[ "$CPU_USAGE" -gt 99 ] && CPU_USAGE=99
sketchybar --set "$NAME" label="${CPU_USAGE}%"
