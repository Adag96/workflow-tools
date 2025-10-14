#!/bin/bash

# Script to reformat existing timer log to show daily totals instead of cumulative totals
# This will process the existing log and calculate daily totals per todo item per date
# Compatible with bash 3.2 (macOS default)

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
LOG_FILE="$CONFIG_DIR/todo_data/timer_log.txt"
BACKUP_FILE="$LOG_FILE.backup_$(date +%Y%m%d_%H%M%S)"
TEMP_FILE="$LOG_FILE.reformatted"
ENTRIES_FILE="$LOG_FILE.entries_temp"

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Timer log file not found at $LOG_FILE"
    exit 1
fi

# Create backup
echo "Creating backup at $BACKUP_FILE..."
cp "$LOG_FILE" "$BACKUP_FILE"

# Initialize temp file with header
head -2 "$BACKUP_FILE" > "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

# Extract all entries with their data to a temp file
# Format: date|time|todo_name|session_minutes|session_seconds
> "$ENTRIES_FILE"
while IFS= read -r line; do
    # Skip header lines and empty lines
    if [[ "$line" =~ ^#.* ]] || [ -z "$line" ]; then
        continue
    fi

    # Extract date, todo name, and session time
    if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}:[0-9]{2}:[0-9]{2})\]\ \"([^\"]+)\"\ -\ Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
        entry_date="${BASH_REMATCH[1]}"
        entry_time="${BASH_REMATCH[2]}"
        todo_name="${BASH_REMATCH[3]}"
        session_minutes="${BASH_REMATCH[4]}"
        session_seconds="${BASH_REMATCH[5]}"

        echo "${entry_date}|${entry_time}|${todo_name}|${session_minutes}|${session_seconds}" >> "$ENTRIES_FILE"
    fi
done < "$BACKUP_FILE"

# Process entries by date and todo
last_written_date=""
last_written_todo=""
daily_total=0

# Sort entries by date, then todo name
sort -t'|' -k1,1 -k3,3 -k2,2 "$ENTRIES_FILE" | while IFS='|' read -r entry_date entry_time todo_name session_minutes session_seconds; do
    # Check if we're on a new date
    if [ "$entry_date" != "$last_written_date" ]; then
        # Add date separator if not first date
        if [ -n "$last_written_date" ]; then
            echo "" >> "$TEMP_FILE"
        fi
        echo "================================" >> "$TEMP_FILE"
        echo "  $entry_date" >> "$TEMP_FILE"
        echo "================================" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
        last_written_date="$entry_date"
        last_written_todo=""
        daily_total=0
    fi

    # Check if we're on a new todo item
    if [ "$todo_name" != "$last_written_todo" ]; then
        # Add spacing between different todos
        if [ -n "$last_written_todo" ]; then
            echo "" >> "$TEMP_FILE"
        fi
        last_written_todo="$todo_name"
        daily_total=0
    fi

    # Calculate session in seconds
    session_total=$((session_minutes * 60 + session_seconds))

    # Add to daily total
    daily_total=$((daily_total + session_total))

    # Convert daily total to minutes and seconds
    daily_min=$((daily_total / 60))
    daily_sec=$((daily_total % 60))

    # Calculate decimal hours
    if command -v bc >/dev/null 2>&1; then
        daily_hours=$(echo "scale=2; $daily_total / 3600" | bc 2>/dev/null)
        if [[ "$daily_hours" =~ ^\..*$ ]]; then
            daily_hours="0$daily_hours"
        fi
    else
        daily_hours=$(awk "BEGIN {printf \"%.2f\", $daily_total / 3600}")
    fi

    # Ensure valid format
    if [ -z "$daily_hours" ] || [[ ! "$daily_hours" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        daily_hours="0.00"
    fi

    # Write the entry
    echo "[$entry_date $entry_time] \"${todo_name}\" - Session: ${session_minutes}m ${session_seconds}s | Daily Total: ${daily_min}m ${daily_sec}s (${daily_hours} hours)" >> "$TEMP_FILE"
done

# Clean up temp files
rm -f "$ENTRIES_FILE"

# Replace original file with reformatted version
mv "$TEMP_FILE" "$LOG_FILE"

echo "✅ Log file reformatted successfully!"
echo "   - Backup saved to: $BACKUP_FILE"
echo "   - Updated log file: $LOG_FILE"
echo ""
echo "Changes made:"
echo "  - 'Total' changed to 'Daily Total' (showing per-day totals per todo item)"
echo "  - Added date separators between different days"
echo "  - Entries grouped by date and todo item"
