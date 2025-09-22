#!/bin/bash

# Script to cluster timer log entries by todo item
# Usage: ./cluster_logs.sh

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
LOG_FILE="$CONFIG_DIR/todo_data/timer_log.txt"

if [ ! -f "$LOG_FILE" ]; then
    echo "No timer log file found at $LOG_FILE"
    exit 1
fi

echo "Clustering timer log entries by todo item..."

# Create temp files
TEMP_LOG="${LOG_FILE}.clustered"
TEMP_ENTRIES="${LOG_FILE}.entries"

# Extract header
head -2 "$LOG_FILE" > "$TEMP_LOG"

# Extract all log entries (lines starting with [)
grep '^\[' "$LOG_FILE" > "$TEMP_ENTRIES" 2>/dev/null || true

if [ ! -s "$TEMP_ENTRIES" ]; then
    echo "No timer entries found to cluster."
    rm -f "$TEMP_ENTRIES"
    exit 0
fi

# Get unique todo names in order of first appearance
TODO_NAMES=$(awk -F'"' '{if(NF>=3) print $2}' "$TEMP_ENTRIES" | awk '!seen[$0]++')

# Write entries grouped by todo name
echo "$TODO_NAMES" | while IFS= read -r todo_name; do
    if [ -n "$todo_name" ]; then
        echo "Clustering entries for: $todo_name"
        # Find all entries for this todo and write them
        grep "\"$todo_name\"" "$TEMP_ENTRIES" >> "$TEMP_LOG"
        echo "" >> "$TEMP_LOG"
    fi
done

# Replace original file with clustered version
mv "$TEMP_LOG" "$LOG_FILE"
rm -f "$TEMP_ENTRIES"

echo "✅ Timer log successfully clustered by todo item!"
echo "📁 Clustered log saved to: $LOG_FILE"