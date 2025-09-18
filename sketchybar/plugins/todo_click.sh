#!/bin/bash

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
TODO_DATA_FILE="$CONFIG_DIR/todo_data/todos.json"

# Function to show todos directly with action buttons
show_main_menu() {
    local active_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")

    # First, show todos if any exist
    if [ "$total_count" -gt 0 ]; then
        show_todos_with_actions
    else
        # No todos, show add option
        add_todo
    fi
}

# Function to show todos with action buttons
show_todos_with_actions() {
    local active_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")

    # Get todo list with status including active timers - incomplete items first
    local todo_list=$(cat "$TODO_DATA_FILE" | jq -r '.todos | sort_by(.completed, .id) | .[] | "[\(if .completed then "✓" elif .timer_start != null then "⏱" else " " end)] \(.text)\(if .timer_start != null and .completed == false then " (TIMER ACTIVE)" else "" end)"' 2>/dev/null)

    # Check if there's an active timer to determine button text
    local active_timer_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false and .timer_start != null)] | length' 2>/dev/null || echo "0")
    local timer_button_text
    if [ "$active_timer_count" -gt 0 ]; then
        timer_button_text="Stop Item"
    else
        timer_button_text="Start Item"
    fi

    # Show todos with action buttons
    local choice=$(osascript -e "display dialog \"${todo_list}\" with title \"Todo List (${active_count} active)\" buttons {\"${timer_button_text}\", \"Actions\", \"OK\"} default button \"OK\"")

    # Extract which button was clicked
    local selected_button=$(echo "$choice" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    case "$selected_button" in
        "Start Item")
            start_timer
            ;;
        "Stop Item")
            stop_timer
            ;;
        "Actions")
            show_action_menu
            ;;
        "OK"|*)
            # Just close the dialog
            ;;
    esac
}

# Function to show action menu
show_action_menu() {
    local active_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")

    # Build action options based on current state
    local actions=("Add New Item(s)")
    if [ "$active_count" -gt 0 ]; then
        actions+=("Complete Todo")
    fi

    if [ "$total_count" -gt 0 ]; then
        actions+=("Delete Todo" "Clear All")
    fi

    # Always show clear timer logs option
    actions+=("Clear Timer Logs")

    # Create AppleScript list for choose from list
    local script_options=""
    for action in "${actions[@]}"; do
        if [ -n "$script_options" ]; then
            script_options="${script_options}, \"${action}\""
        else
            script_options="\"${action}\""
        fi
    done

    local choice=$(osascript -e "choose from list {${script_options}} with title \"What would you like to do?\" with prompt \"Choose an action:\"")

    # Handle the choice
    if [ "$choice" != "false" ]; then
        case "$choice" in
            "Add New Item(s)")
                add_todo
                ;;
            "Complete Todo")
                complete_todo
                ;;
            "Delete Todo")
                delete_todo
                ;;
            "Clear All")
                clear_all_todos
                ;;
            "Clear Timer Logs")
                clear_timer_logs
                ;;
        esac
    fi
}

view_todos() {
    local todo_list=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | "[\(if .completed then "✓" else " " end)] \(.text)"' 2>/dev/null)
    if [ -z "$todo_list" ]; then
        todo_list="No todos yet"
    fi

    osascript -e "display dialog \"$todo_list\" with title \"All Todos\" buttons {\"OK\"} default button \"OK\""
}

add_todo() {
    local dialog_result=$(osascript -e 'display dialog "Enter new todo item(s):\n\nSeparate multiple items with commas\nExample: Go through inbox, Test styles" default answer "" buttons {"Cancel", "Add"} default button "Add"' 2>/dev/null)
    local new_todos=$(echo "$dialog_result" | sed -n 's/.*text returned:\(.*\)/\1/p')

    if [ -n "$new_todos" ]; then
        local next_id=$(cat "$TODO_DATA_FILE" | jq '.next_id' 2>/dev/null || echo "1")
        local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local items_added=0

        # Split by comma and process each item
        IFS=',' read -ra TODO_ARRAY <<< "$new_todos"
        for todo_item in "${TODO_ARRAY[@]}"; do
            # Trim leading/trailing whitespace
            todo_item=$(echo "$todo_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Skip empty items
            if [ -n "$todo_item" ]; then
                # Add this todo to JSON
                cat "$TODO_DATA_FILE" | jq --arg text "$todo_item" --arg time "$current_time" --arg id "$next_id" \
                    '.todos += [{"id": ($id | tonumber), "text": $text, "completed": false, "created": $time, "timer_start": null, "timer_duration": 0}] | .next_id += 1' \
                    > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

                next_id=$((next_id + 1))
                items_added=$((items_added + 1))
            fi
        done

        sketchybar --trigger todo_update

        # Show confirmation with count
        if [ "$items_added" -eq 1 ]; then
            osascript -e "display dialog \"✅ Added 1 todo item\" with title \"Item Added\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        else
            osascript -e "display dialog \"✅ Added $items_added todo items\" with title \"Items Added\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        fi
    fi
}

complete_todo() {
    # Use different approach to handle todos with spaces
    local todo_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No active todos to complete!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Get todos using newline delimiter instead of spaces
    local todos_text=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false) | .text' 2>/dev/null)

    # Convert newline-separated text to AppleScript list
    local script_options=""
    while IFS= read -r todo; do
        if [ -n "$todo" ]; then
            if [ -n "$script_options" ]; then
                script_options="${script_options}, \"${todo}\""
            else
                script_options="\"${todo}\""
            fi
        fi
    done <<< "$todos_text"

    local selected=$(osascript -e "choose from list {${script_options}} with title \"Mark Todo as Complete\" with prompt \"Select todo to mark as completed:\"")

    if [ "$selected" != "false" ]; then
        # Find the todo ID by text
        local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg text "$selected" '.todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)

        if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
            # Mark todo as completed
            cat "$TODO_DATA_FILE" | jq --argjson id "$todo_id" \
                '(.todos[] | select(.id == $id)).completed = true' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

            sketchybar --trigger todo_update

            # Show confirmation
            osascript -e "display dialog \"✓ Completed: ${selected}\" with title \"Todo Completed\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        fi
    fi
}

delete_todo() {
    local todo_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No todos" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Get todos using newline delimiter
    local todos_text=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | .text' 2>/dev/null)

    # Convert newline-separated text to AppleScript list
    local script_options=""
    while IFS= read -r todo; do
        if [ -n "$todo" ]; then
            if [ -n "$script_options" ]; then
                script_options="${script_options}, \"${todo}\""
            else
                script_options="\"${todo}\""
            fi
        fi
    done <<< "$todos_text"

    local selected=$(osascript -e "choose from list {${script_options}} with title \"Delete Todo\" with prompt \"Select todo to delete:\"")

    if [ "$selected" != "false" ]; then
        local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg text "$selected" '.todos[] | select(.text == $text) | .id' 2>/dev/null)

        if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
            # Remove todo from JSON
            cat "$TODO_DATA_FILE" | jq --argjson id "$todo_id" \
                '.todos = [.todos[] | select(.id != $id)]' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

            sketchybar --trigger todo_update
        fi
    fi
}

start_timer() {
    local todo_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No active todos" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Check if there's already an active timer
    local active_timer=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false and .timer_start != null) | .text' 2>/dev/null)
    if [ -n "$active_timer" ]; then
        osascript -e "display dialog \"Timer already running for: ${active_timer}\n\nStop the current timer before starting a new one.\" with title \"Timer Already Active\" buttons {\"OK\"} default button \"OK\""
        return
    fi

    # Get todos using newline delimiter
    local todos_text=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false) | .text' 2>/dev/null)

    # Convert newline-separated text to AppleScript list
    local script_options=""
    while IFS= read -r todo; do
        if [ -n "$todo" ]; then
            if [ -n "$script_options" ]; then
                script_options="${script_options}, \"${todo}\""
            else
                script_options="\"${todo}\""
            fi
        fi
    done <<< "$todos_text"

    local selected=$(osascript -e "choose from list {${script_options}} with title \"Start Timer\" with prompt \"Select todo to start timer:\"")

    if [ "$selected" != "false" ]; then
        local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg text "$selected" '.todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)

        # Store timestamp as Unix epoch seconds (much simpler and more reliable)
        local current_time=$(date +%s)

        # Set timer start time
        cat "$TODO_DATA_FILE" | jq --argjson id "$todo_id" --argjson time "$current_time" \
            '(.todos[] | select(.id == $id)).timer_start = $time' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Force immediate update with multiple triggers to ensure it works
        sketchybar --trigger todo_update
        sleep 0.1
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"⏱ Timer started for: ${selected}\" with title \"Timer Started\" buttons {\"OK\"} default button \"OK\" giving up after 2"
    fi
}

stop_timer() {
    # Find the active timer automatically (since we only allow one)
    local active_timer_text=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false and .timer_start != null) | .text' 2>/dev/null)
    local active_timer_id=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false and .timer_start != null) | .id' 2>/dev/null)

    if [ -z "$active_timer_text" ] || [ "$active_timer_text" = "null" ]; then
        osascript -e 'display dialog "No active timer to stop!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    local current_time=$(date +%s)

    # Calculate duration and stop timer
    local start_time=$(cat "$TODO_DATA_FILE" | jq -r --argjson id "$active_timer_id" '.todos[] | select(.id == $id) | .timer_start' 2>/dev/null)
    if [ "$start_time" != "null" ] && [ -n "$start_time" ]; then
        echo "Debug: start_time=$start_time, current_time=$current_time" >> /tmp/timer_debug.log

        local start_seconds="$start_time"

        # Check if start_time is a string (old format) or number (new format)
        if [[ "$start_time" =~ ^[0-9]+$ ]]; then
            # It's already a Unix timestamp
            start_seconds="$start_time"
        else
            # It's an ISO string, try to parse it
            if command -v gdate >/dev/null 2>&1; then
                start_seconds=$(gdate -d "$start_time" +%s 2>/dev/null)
            else
                start_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null)
                if [ -z "$start_seconds" ]; then
                    start_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${start_time%Z}" +%s 2>/dev/null)
                fi
            fi

            # If parsing failed, use current time (0 duration)
            if [ -z "$start_seconds" ] || [ "$start_seconds" -eq 0 ]; then
                echo "Warning: Failed to parse start time: $start_time" >> /tmp/timer_debug.log
                start_seconds=$current_time
            fi
        fi

        local duration=$((current_time - start_seconds))
        echo "Debug: start_seconds=$start_seconds, duration=$duration seconds" >> /tmp/timer_debug.log

        # Ensure duration is positive and reasonable (less than 24 hours)
        if [ "$duration" -lt 0 ] || [ "$duration" -gt 86400 ]; then
            echo "Warning: Invalid duration ($duration), using 0" >> /tmp/timer_debug.log
            duration=0
        fi

        # Get previous total time and add this session
        local previous_duration=$(cat "$TODO_DATA_FILE" | jq -r --argjson id "$active_timer_id" '.todos[] | select(.id == $id) | .timer_duration' 2>/dev/null || echo "0")
        local total_duration=$((previous_duration + duration))

        # Update the todo with total time and clear timer_start
        cat "$TODO_DATA_FILE" | jq --argjson id "$active_timer_id" --argjson total "$total_duration" \
            '(.todos[] | select(.id == $id)) |= (.timer_duration = $total | .timer_start = null)' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Log to timer log file
        local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
        local session_minutes=$((duration / 60))
        local session_seconds=$((duration % 60))
        local total_minutes=$((total_duration / 60))
        local total_seconds=$((total_duration % 60))

        # Calculate decimal hours for time logging software
        # Formula: hours = total_seconds / 3600, rounded to 2 decimal places
        local total_hours
        if command -v bc >/dev/null 2>&1; then
            total_hours=$(echo "scale=2; $total_duration / 3600" | bc 2>/dev/null)
            # Add leading zero if needed (bc sometimes returns .05 instead of 0.05)
            if [[ "$total_hours" =~ ^\..*$ ]]; then
                total_hours="0$total_hours"
            fi
        else
            # Fallback using awk if bc is not available
            total_hours=$(awk "BEGIN {printf \"%.2f\", $total_duration / 3600}")
        fi

        # Ensure we have a valid number with proper format
        # Accept formats like: 0.05, .05, 1.25, 0, etc.
        if [ -z "$total_hours" ] || [[ ! "$total_hours" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            total_hours="0.00"
            echo "Debug: Invalid hours calculation, using 0.00" >> /tmp/timer_debug.log
        fi

        # Debug the calculation
        echo "Debug: total_duration=$total_duration, calculated_hours=$total_hours" >> /tmp/timer_debug.log

        local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

        # Check if this is a new todo item (different from the last logged item)
        local last_logged_item=""
        if [ -f "$log_file" ]; then
            last_logged_item=$(tail -1 "$log_file" 2>/dev/null | grep -o '"[^"]*"' | head -1)
        fi

        # Add spacing if this is a different todo item
        if [ -n "$last_logged_item" ] && [ "$last_logged_item" != "\"$active_timer_text\"" ]; then
            echo "" >> "$log_file"
        fi

        echo "[$timestamp] \"$active_timer_text\" - Session: ${session_minutes}m ${session_seconds}s | Total: ${total_minutes}m ${total_seconds}s (${total_hours} hours)" >> "$log_file"

        # Show confirmation with time spent including decimal hours
        osascript -e "display dialog \"⏹ Timer stopped for: ${active_timer_text}\n\nThis session: ${session_minutes}m ${session_seconds}s\nTotal time: ${total_minutes}m ${total_seconds}s\nDecimal hours: ${total_hours}\" with title \"Timer Stopped\" buttons {\"OK\"} default button \"OK\" giving up after 5"
    fi

    sketchybar --trigger todo_update
}

clear_all_todos() {
    local total_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")
    if [ "$total_count" -eq 0 ]; then
        osascript -e 'display dialog "No todos to clear!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Confirmation dialog
    local confirm=$(osascript -e "display dialog \"Are you sure you want to delete ALL ${total_count} todos?\n\nThis action cannot be undone.\" with title \"Clear All Todos\" buttons {\"Cancel\", \"Delete All\"} default button \"Cancel\"")

    local confirmed=$(echo "$confirm" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    if [ "$confirmed" = "Delete All" ]; then
        # Clear all todos
        echo '{"todos": [], "next_id": 1}' > "$TODO_DATA_FILE"
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"🗑 All todos cleared!\" with title \"Todos Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 2"
    fi
}

clear_timer_logs() {
    local log_file="$CONFIG_DIR/todo_data/timer_log.txt"

    # Check if timer log exists and has content
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        osascript -e 'display dialog "No timer logs to clear!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Count existing log entries
    local log_count=$(grep -c "^\[" "$log_file" 2>/dev/null || echo "0")

    # Confirmation dialog
    local confirm=$(osascript -e "display dialog \"Are you sure you want to clear all timer logs?\n\nThis will delete ${log_count} log entries permanently.\n\nThis action cannot be undone.\" with title \"Clear Timer Logs\" buttons {\"Cancel\", \"Clear Logs\"} default button \"Cancel\"")

    local confirmed=$(echo "$confirm" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    if [ "$confirmed" = "Clear Logs" ]; then
        # Clear the timer log file
        > "$log_file"

        # Add a header with the current date for the new session
        local start_date=$(date "+%Y-%m-%d")
        echo "# Timer Log - Started $start_date" >> "$log_file"
        echo "" >> "$log_file"

        # Reset all timer durations to 0 in the JSON file
        cat "$TODO_DATA_FILE" | jq '.todos[].timer_duration = 0' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Update the display to reflect reset totals
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"🗑 Timer logs cleared!\n\nStarted fresh log session for today.\nAll timer totals have been reset to 0.\" with title \"Logs Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 4"
    fi
}

show_main_menu