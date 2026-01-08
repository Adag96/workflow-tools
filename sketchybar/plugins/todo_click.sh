#!/bin/bash

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
TODO_DATA_FILE="$CONFIG_DIR/todo_data/todos.json"

# Source icons for SF Symbols
source "$CONFIG_DIR/icons.sh"

# Helper function to get all todos from current space view
get_current_todos() {
    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

    if [ "$current_space" = "ALL" ]; then
        # Get all todos from all spaces
        cat "$TODO_DATA_FILE" | jq -r '.spaces | to_entries[] | .value.todos[]' 2>/dev/null
    else
        # Get todos from specific space
        cat "$TODO_DATA_FILE" | jq -r --arg space "$current_space" '.spaces[$space].todos[]' 2>/dev/null
    fi
}

# Helper function to get SF Symbol icon for a space name (used in dialogs)
get_space_sf_icon() {
    local space_name="$1"
    case "$space_name" in
        "ALL")
            echo "$TODO_SPACE_ALL"
            ;;
        "Ujam")
            echo "$TODO_SPACE_UJAM"
            ;;
        "Lonebody")
            echo "$TODO_SPACE_LONEBODY"
            ;;
        "Personal")
            echo "$TODO_SPACE_PERSONAL"
            ;;
        "60 Pleasant")
            echo "$TODO_SPACE_60_PLEASANT"
            ;;
        "Workflow Tools")
            echo "$TODO_SPACE_WORKFLOW"
            ;;
        *)
            echo "$TODO_SPACE_ALL"
            ;;
    esac
}

# Helper function to get current space info
get_current_space_info() {
    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")
    local sf_icon=$(get_space_sf_icon "$current_space")
    echo "$sf_icon $current_space"
}

# Helper function to write organized timer logs
# Format: Date -> Space -> Task (grouped)
# Args: $1=space_name, $2=task_name, $3=session_seconds, $4=task_daily_total_seconds, $5=task_daily_hours
write_organized_log() {
    local space_name="$1"
    local task_name="$2"
    local session_seconds="$3"
    local task_daily_total="$4"
    local task_daily_hours="$5"

    local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
    local current_date=$(date "+%Y-%m-%d")
    local current_time=$(date "+%H:%M:%S")

    local session_minutes=$((session_seconds / 60))
    local session_secs=$((session_seconds % 60))
    local task_daily_minutes=$((task_daily_total / 60))
    local task_daily_secs=$((task_daily_total % 60))

    # Create log file if it doesn't exist
    if [ ! -f "$log_file" ]; then
        echo "# Timer Log" > "$log_file"
        echo "" >> "$log_file"
    fi

    # Read the entire file
    local file_content=$(cat "$log_file")

    # Check if today's date section exists
    local date_header="================================"
    local date_line="  $current_date"

    if ! echo "$file_content" | grep -q "^  $current_date$"; then
        # Date section doesn't exist - append it at the end
        # Calculate space daily total (just this session since it's the first)
        local space_daily_total=$session_seconds
        local space_daily_minutes=$((space_daily_total / 60))
        local space_daily_secs=$((space_daily_total % 60))
        local space_daily_hours
        if command -v bc >/dev/null 2>&1; then
            space_daily_hours=$(echo "scale=2; $space_daily_total / 3600" | bc 2>/dev/null)
            if [[ "$space_daily_hours" =~ ^\..*$ ]]; then
                space_daily_hours="0$space_daily_hours"
            fi
        else
            space_daily_hours=$(awk "BEGIN {printf \"%.2f\", $space_daily_total / 3600}")
        fi
        {
            echo ""
            echo "$date_header"
            echo "$date_line"
            echo "$date_header"
            echo ""
            echo "--- $space_name ---------------"
            echo "  \"$task_name\""
            echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s"
            echo ""
            echo "  Daily Total: ${space_daily_minutes}m ${space_daily_secs}s (${space_daily_hours} hours)"
        } >> "$log_file"
    else
        # Date section exists - need to find the right place to insert
        # Strategy:
        # 1. First pass: insert the new entry in the right place
        # 2. Second pass: update/add the space Daily Total footer

        local temp_file=$(mktemp)
        local in_date=0
        local in_space=0
        local in_task=0
        local wrote_entry=0

        # First pass: insert the task entry
        while IFS= read -r line || [ -n "$line" ]; do
            # Check for date header
            if [[ "$line" == "  $current_date" ]]; then
                in_date=1
                in_space=0
                in_task=0
            elif [[ "$line" =~ ^\ \ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ $in_date -eq 1 ]; then
                # Different date - write pending entry before leaving
                if [ $wrote_entry -eq 0 ]; then
                    if [ $in_space -eq 0 ]; then
                        echo "" >> "$temp_file"
                        echo "--- $space_name ---------------" >> "$temp_file"
                        echo "  \"$task_name\"" >> "$temp_file"
                        echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
                    elif [ $in_task -eq 0 ]; then
                        echo "  \"$task_name\"" >> "$temp_file"
                        echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
                    else
                        echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
                    fi
                    wrote_entry=1
                fi
                in_date=0
                in_space=0
                in_task=0
            fi

            # Check for space header within date (match both old and new formats)
            if [ $in_date -eq 1 ] && [[ "$line" == "--- $space_name ---------------" || "$line" == "--- $space_name ---" ]]; then
                in_space=1
                in_task=0
            elif [ $in_date -eq 1 ] && [[ "$line" =~ ^---\ .* ]]; then
                # Different space - write task before if we were in our space without finding task
                if [ $in_space -eq 1 ] && [ $in_task -eq 0 ] && [ $wrote_entry -eq 0 ]; then
                    echo "  \"$task_name\"" >> "$temp_file"
                    echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
                    wrote_entry=1
                fi
                in_space=0
                in_task=0
            fi

            # Check for task header within space
            if [ $in_date -eq 1 ] && [ $in_space -eq 1 ] && [[ "$line" == "  \"$task_name\"" ]]; then
                in_task=1
            elif [ $in_date -eq 1 ] && [ $in_space -eq 1 ] && [[ "$line" =~ ^\ \ \" ]]; then
                # Different task - write entry before if we were in our task
                if [ $in_task -eq 1 ] && [ $wrote_entry -eq 0 ]; then
                    echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
                    wrote_entry=1
                fi
                in_task=0
            fi

            # Skip existing Daily Total footer lines for our space (we'll recalculate)
            # Also skip blank lines immediately before Daily Total (they get re-added in third pass)
            if [ $in_date -eq 1 ] && [ $in_space -eq 1 ] && [[ "$line" =~ ^\ \ Daily\ Total: ]]; then
                continue
            fi
            if [ $in_date -eq 1 ] && [ $in_space -eq 1 ] && [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
                # Skip blank lines within our space section (the footer pass will add the right one)
                continue
            fi

            echo "$line" >> "$temp_file"
        done < "$log_file"

        # Handle end of file
        if [ $wrote_entry -eq 0 ]; then
            if [ $in_date -eq 0 ]; then
                # Should not happen since we checked date exists
                :
            elif [ $in_space -eq 0 ]; then
                echo "" >> "$temp_file"
                echo "--- $space_name ---------------" >> "$temp_file"
                echo "  \"$task_name\"" >> "$temp_file"
                echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
            elif [ $in_task -eq 0 ]; then
                echo "  \"$task_name\"" >> "$temp_file"
                echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
            else
                echo "    [$current_time] Session: ${session_minutes}m ${session_secs}s | Day: ${task_daily_minutes}m ${task_daily_secs}s" >> "$temp_file"
            fi
        fi

        mv "$temp_file" "$log_file"

        # Second pass: calculate and add/update space Daily Total footers
        # Sum all sessions for this space on this date and add footer
        local space_daily_total=0
        local in_date=0
        local in_space=0

        while IFS= read -r line; do
            if [[ "$line" == "  $current_date" ]]; then
                in_date=1
                in_space=0
            elif [[ "$line" =~ ^\ \ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ $in_date -eq 1 ]; then
                in_date=0
                in_space=0
            fi

            if [ $in_date -eq 1 ]; then
                if [[ "$line" == "--- $space_name ---------------" || "$line" == "--- $space_name ---" ]]; then
                    in_space=1
                elif [[ "$line" =~ ^---\ .* ]]; then
                    in_space=0
                fi
            fi

            # Sum session times within target space
            if [ $in_date -eq 1 ] && [ $in_space -eq 1 ]; then
                if [[ "$line" =~ Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
                    local sess_min="${BASH_REMATCH[1]}"
                    local sess_sec="${BASH_REMATCH[2]}"
                    space_daily_total=$((space_daily_total + sess_min * 60 + sess_sec))
                fi
            fi
        done < "$log_file"

        # Calculate space daily total display values
        local space_daily_minutes=$((space_daily_total / 60))
        local space_daily_secs=$((space_daily_total % 60))
        local space_daily_hours
        if command -v bc >/dev/null 2>&1; then
            space_daily_hours=$(echo "scale=2; $space_daily_total / 3600" | bc 2>/dev/null)
            if [[ "$space_daily_hours" =~ ^\..*$ ]]; then
                space_daily_hours="0$space_daily_hours"
            fi
        else
            space_daily_hours=$(awk "BEGIN {printf \"%.2f\", $space_daily_total / 3600}")
        fi

        # Third pass: insert the Daily Total footer at the end of the space section
        local temp_file2=$(mktemp)
        local in_date=0
        local in_space=0
        local footer_written=0

        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" == "  $current_date" ]]; then
                in_date=1
                in_space=0
                footer_written=0
            elif [[ "$line" =~ ^\ \ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ $in_date -eq 1 ]; then
                # New date starting - write footer if we were in our space
                if [ $in_space -eq 1 ] && [ $footer_written -eq 0 ]; then
                    echo "" >> "$temp_file2"
                    echo "  Daily Total: ${space_daily_minutes}m ${space_daily_secs}s (${space_daily_hours} hours)" >> "$temp_file2"
                    footer_written=1
                fi
                in_date=0
                in_space=0
            fi

            if [ $in_date -eq 1 ]; then
                if [[ "$line" == "--- $space_name ---------------" || "$line" == "--- $space_name ---" ]]; then
                    in_space=1
                elif [[ "$line" =~ ^---\ .* ]]; then
                    # Different space starting - write footer before if we were in our space
                    if [ $in_space -eq 1 ] && [ $footer_written -eq 0 ]; then
                        echo "" >> "$temp_file2"
                        echo "  Daily Total: ${space_daily_minutes}m ${space_daily_secs}s (${space_daily_hours} hours)" >> "$temp_file2"
                        footer_written=1
                    fi
                    in_space=0
                fi
            fi

            echo "$line" >> "$temp_file2"
        done < "$log_file"

        # Handle end of file - write footer if we're still in our space
        if [ $in_space -eq 1 ] && [ $footer_written -eq 0 ]; then
            echo "" >> "$temp_file2"
            echo "  Daily Total: ${space_daily_minutes}m ${space_daily_secs}s (${space_daily_hours} hours)" >> "$temp_file2"
        fi

        mv "$temp_file2" "$log_file"
    fi

    sync  # Force filesystem sync for Dropbox
}

# Function to show todos directly with action buttons
show_main_menu() {
    local active_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")

    # Always show the main interface, even if no todos
    show_todos_with_actions
}

# Function to show todos with action buttons
show_todos_with_actions() {
    local active_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")

    # Get current space info for title
    local space_info=$(get_current_space_info)

    # Get todo list with status including active timers - incomplete items first
    local todo_list=""
    local todos_data="$(get_current_todos | jq -s 'sort_by(.completed, .id) | .[]' -c 2>/dev/null)"

    if [ -n "$todos_data" ]; then
        while IFS= read -r todo; do
            if [ -n "$todo" ]; then
                local completed=$(echo "$todo" | jq -r '.completed')
                local text=$(echo "$todo" | jq -r '.text')
                local timer_start=$(echo "$todo" | jq -r '.timer_start')

                local status=" "
                if [ "$completed" = "true" ]; then
                    status="✓"
                elif [ "$timer_start" != "null" ]; then
                    status="⏱"
                    text="$text (TIMER ACTIVE)"
                fi

                if [ -n "$todo_list" ]; then
                    todo_list="$todo_list\n[$status] $text"
                else
                    todo_list="[$status] $text"
                fi
            fi
        done <<< "$todos_data"
    fi

    # If no todos, show a helpful message
    if [ -z "$todo_list" ]; then
        todo_list="No todos in this space yet.\n\nUse 'Actions' > 'Add New Item(s)' to get started!"
    fi

    # Check if there's an active timer to determine button text (check both music and todo timers)
    local active_timer_count=$(get_current_todos | jq -s '[.[] | select(.completed == false and .timer_start != null)] | length' 2>/dev/null || echo "0")
    local music_timer_active=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_start // null' 2>/dev/null)
    local timer_button_text
    if [ "$active_timer_count" -gt 0 ] || ([ -n "$music_timer_active" ] && [ "$music_timer_active" != "null" ]); then
        timer_button_text="Stop Item"
    else
        timer_button_text="Start Item"
    fi

    # AppleScript display dialog is limited to 3 buttons maximum
    # Add cancel button support for Escape key / Cmd+. to work
    local choice=$(osascript -e "try
        display dialog \"${todo_list}\" with title \"${space_info} (${active_count} active)\" buttons {\"Switch Space\", \"${timer_button_text}\", \"Actions\"} default button \"Actions\"
    on error number -128
        return \"user_canceled\"
    end try" 2>/dev/null)

    # Check if user canceled (pressed Escape or Cmd+.)
    if [ "$choice" = "user_canceled" ] || [ -z "$choice" ]; then
        return
    fi

    # Extract which button was clicked
    local selected_button=$(echo "$choice" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    case "$selected_button" in
        "Switch Space")
            switch_space
            ;;
        "Start Item")
            start_timer
            ;;
        "Stop Item")
            stop_timer
            ;;
        "Actions")
            show_action_menu
            ;;
        *)
            # Dialog was closed via window controls or timeout
            ;;
    esac
}

# Function to show action menu
show_action_menu() {
    local active_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")

    # Build action options based on current state
    local actions=("Add New Item(s)")
    if [ "$active_count" -gt 0 ]; then
        actions+=("Complete Todo(s)")
    fi

    if [ "$total_count" -gt 0 ]; then
        actions+=("Delete Todo")

        # Check if there are completed items to clear
        local completed_count=$(get_current_todos | jq -s '[.[] | select(.completed == true)] | length' 2>/dev/null || echo "0")
        if [ "$completed_count" -gt 0 ]; then
            actions+=("Clear Completed Items")
        fi

        actions+=("Clear All")
    fi

    # Always show timer-related options
    actions+=("Start Music Timer" "Dump Video Game Bank" "Show Time Logs" "Clear Timer Logs")

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
            "Complete Todo(s)")
                complete_todos
                ;;
            "Delete Todo")
                delete_todo
                ;;
            "Clear Completed Items")
                clear_completed_todos
                ;;
            "Clear All")
                clear_all_todos
                ;;
            "Start Music Timer")
                start_music_timer
                ;;
            "Dump Video Game Bank")
                dump_video_game_bank
                ;;
            "Show Time Logs")
                show_time_logs
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
    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")
    local target_space="Personal"

    # If we're in a specific space, use that space. If "ALL", default to Personal
    if [ "$current_space" != "ALL" ]; then
        target_space="$current_space"
    fi

    # Verify target space exists, if not default to Personal
    local space_exists=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$target_space" '.spaces[$space] // empty' 2>/dev/null)
    if [ -z "$space_exists" ]; then
        target_space="Personal"
    fi

    local dialog_result=$(osascript -e "display dialog \"Enter new todo item(s) for $target_space:\n\nSeparate multiple items with commas\nExample: Go through inbox, Test styles\" default answer \"\" buttons {\"Cancel\", \"Add\"} default button \"Add\"" 2>/dev/null)
    local new_todos=$(echo "$dialog_result" | sed -n 's/.*text returned:\(.*\)/\1/p')

    if [ -n "$new_todos" ]; then
        # Read initial state once
        local initial_data=$(cat "$TODO_DATA_FILE")
        local next_id=$(echo "$initial_data" | jq '.next_id' 2>/dev/null || echo "1")
        local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local items_added=0

        # Build array of new todos to add all at once
        local new_todos_json="[]"

        # Split by comma and process each item
        IFS=',' read -ra TODO_ARRAY <<< "$new_todos"
        for todo_item in "${TODO_ARRAY[@]}"; do
            # Trim leading/trailing whitespace
            todo_item=$(echo "$todo_item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Skip empty items
            if [ -n "$todo_item" ]; then
                # Add to our array of new todos
                new_todos_json=$(echo "$new_todos_json" | jq --arg text "$todo_item" --arg time "$current_time" --argjson id "$next_id" \
                    '. += [{"id": $id, "text": $text, "completed": false, "created": $time, "timer_start": null, "timer_duration": 0}]')
                next_id=$((next_id + 1))
                items_added=$((items_added + 1))
            fi
        done

        # Add all items at once to prevent race conditions
        if [ "$items_added" -gt 0 ]; then
            echo "$initial_data" | jq --arg space "$target_space" --argjson new_todos "$new_todos_json" --argjson next_id "$next_id" \
                '.spaces[$space].todos += $new_todos | .next_id = $next_id' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

            sketchybar --trigger todo_update

            # Show confirmation with count
            if [ "$items_added" -eq 1 ]; then
                osascript -e "display dialog \"✅ Added 1 todo item to $target_space\" with title \"Item Added\" buttons {\"OK\"} default button \"OK\" giving up after 2"
            else
                osascript -e "display dialog \"✅ Added $items_added todo items to $target_space\" with title \"Items Added\" buttons {\"OK\"} default button \"OK\" giving up after 2"
            fi
        fi
    fi
}

complete_todos() {
    # Multi-select version - complete one or more todos at once
    local todo_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No active todos to complete!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Get todos using newline delimiter instead of spaces
    local todos_text=$(get_current_todos | jq -s -r '.[] | select(.completed == false) | .text' 2>/dev/null)

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

    # Use multi-select AppleScript dialog - return items separated by newlines to avoid comma issues
    local selected=$(osascript -e "
        set selectedItems to choose from list {${script_options}} with title \"Mark Todo(s) as Complete\" with prompt \"Select todo(s) to mark as completed:\" with multiple selections allowed
        if selectedItems is false then
            return \"false\"
        else
            set output to \"\"
            repeat with anItem in selectedItems
                if output is \"\" then
                    set output to anItem as text
                else
                    set output to output & \"\n\" & (anItem as text)
                end if
            end repeat
            return output
        end if
    ")

    if [ "$selected" != "false" ] && [ -n "$selected" ]; then
        local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")
        local completed_count=0

        # Process each selected item (now separated by newlines)
        while IFS= read -r selected_item; do
            # Skip empty items
            [ -z "$selected_item" ] && continue

            if [ "$current_space" = "ALL" ]; then
                # For ALL view, find which space contains this todo and complete it there
                local space_list=$(cat "$TODO_DATA_FILE" | jq -r '.spaces | keys[]' 2>/dev/null)
                while IFS= read -r space; do
                    if [ -n "$space" ]; then
                        local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" --arg text "$selected_item" '.spaces[$space].todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)
                        if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
                            # Mark todo as completed
                            cat "$TODO_DATA_FILE" | jq --arg space "$space" --argjson id "$todo_id" \
                                '(.spaces[$space].todos[] | select(.id == $id)).completed = true' \
                                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
                            completed_count=$((completed_count + 1))
                            break
                        fi
                    fi
                done <<< "$space_list"
            else
                # For specific space view, complete in current space
                local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$current_space" --arg text "$selected_item" '.spaces[$space].todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)
                if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
                    # Mark todo as completed
                    cat "$TODO_DATA_FILE" | jq --arg space "$current_space" --argjson id "$todo_id" \
                        '(.spaces[$space].todos[] | select(.id == $id)).completed = true' \
                        > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
                    completed_count=$((completed_count + 1))
                fi
            fi
        done <<< "$selected"

        sketchybar --trigger todo_update

        # Show confirmation with count
        if [ "$completed_count" -eq 1 ]; then
            osascript -e "display dialog \"✓ Completed 1 todo!\" with title \"Todo Completed\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        elif [ "$completed_count" -gt 1 ]; then
            osascript -e "display dialog \"✓ Completed ${completed_count} todos!\" with title \"Todos Completed\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        else
            osascript -e "display dialog \"Could not complete the selected todo(s). Please try again.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
        fi
    fi
}

delete_todo() {
    local todo_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No todos" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Get todos using newline delimiter from current space
    local todos_text=$(get_current_todos | jq -s -r '.[] | .text' 2>/dev/null)

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
        # Find the todo ID by text across all spaces (since we need to delete from the actual space)
        local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

        if [ "$current_space" = "ALL" ]; then
            # For ALL view, find which space contains this todo and delete from there
            local space_list=$(cat "$TODO_DATA_FILE" | jq -r '.spaces | keys[]' 2>/dev/null)
            while IFS= read -r space; do
                if [ -n "$space" ]; then
                    local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" --arg text "$selected" '.spaces[$space].todos[] | select(.text == $text) | .id' 2>/dev/null)
                    if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
                        # Remove todo from this space
                        cat "$TODO_DATA_FILE" | jq --arg space "$space" --argjson id "$todo_id" \
                            '.spaces[$space].todos = [.spaces[$space].todos[] | select(.id != $id)]' \
                            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
                        break
                    fi
                fi
            done <<< "$space_list"
        else
            # For specific space view, delete from current space
            local todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$current_space" --arg text "$selected" '.spaces[$space].todos[] | select(.text == $text) | .id' 2>/dev/null)
            if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
                # Remove todo from current space
                cat "$TODO_DATA_FILE" | jq --arg space "$current_space" --argjson id "$todo_id" \
                    '.spaces[$space].todos = [.spaces[$space].todos[] | select(.id != $id)]' \
                    > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
            fi
        fi

        sketchybar --trigger todo_update
    fi
}

start_timer() {
    local todo_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    if [ "$todo_count" -eq 0 ]; then
        osascript -e 'display dialog "No active todos" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Check if there's already an active timer across all spaces
    local active_timer=$(get_current_todos | jq -s -r '.[] | select(.completed == false and .timer_start != null) | .text' 2>/dev/null | head -1)
    if [ -n "$active_timer" ]; then
        osascript -e "display dialog \"Timer already running for: ${active_timer}\n\nStop the current timer before starting a new one.\" with title \"Timer Already Active\" buttons {\"OK\"} default button \"OK\""
        return
    fi

    # Get todos using newline delimiter from current view
    local todos_text=$(get_current_todos | jq -s -r '.[] | select(.completed == false) | .text' 2>/dev/null)

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
        # Find which space contains this todo and start timer there
        local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")
        local todo_id=""
        local target_space=""

        if [ "$current_space" = "ALL" ]; then
            # For ALL view, find which space contains this todo
            local space_list=$(cat "$TODO_DATA_FILE" | jq -r '.spaces | keys[]' 2>/dev/null)
            while IFS= read -r space; do
                if [ -n "$space" ]; then
                    todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" --arg text "$selected" '.spaces[$space].todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)
                    if [ -n "$todo_id" ] && [ "$todo_id" != "null" ]; then
                        target_space="$space"
                        break
                    fi
                fi
            done <<< "$space_list"
        else
            # For specific space view, find todo in current space
            todo_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$current_space" --arg text "$selected" '.spaces[$space].todos[] | select(.text == $text and .completed == false) | .id' 2>/dev/null)
            target_space="$current_space"
        fi

        if [ -n "$todo_id" ] && [ "$todo_id" != "null" ] && [ -n "$target_space" ]; then
            # Store timestamp as Unix epoch seconds (much simpler and more reliable)
            local current_time=$(date +%s)

            # Set timer start time in the correct space
            cat "$TODO_DATA_FILE" | jq --arg space "$target_space" --argjson id "$todo_id" --argjson time "$current_time" \
                '(.spaces[$space].todos[] | select(.id == $id)).timer_start = $time' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

            # Force immediate update with multiple triggers to ensure it works
            sketchybar --trigger todo_update
            sleep 0.1
            sketchybar --trigger todo_update

            # Show confirmation
            osascript -e "display dialog \"⏱ Timer started for: ${selected}\" with title \"Timer Started\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        fi
    fi
}

stop_timer() {
    # First check if music timer is active
    if stop_music_timer 2>/dev/null; then
        # Music timer was stopped successfully
        return
    fi

    # If music timer wasn't active, check for todo item timer
    # Find the active timer automatically across all spaces (since we only allow one)
    local active_timer_text=""
    local active_timer_id=""
    local active_timer_space=""

    # Search all spaces for active timer
    local space_list=$(cat "$TODO_DATA_FILE" | jq -r '.spaces | keys[]' 2>/dev/null)
    while IFS= read -r space; do
        if [ -n "$space" ]; then
            local timer_text=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" '.spaces[$space].todos[] | select(.completed == false and .timer_start != null) | .text' 2>/dev/null)
            if [ -n "$timer_text" ] && [ "$timer_text" != "null" ]; then
                active_timer_text="$timer_text"
                active_timer_id=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" '.spaces[$space].todos[] | select(.completed == false and .timer_start != null) | .id' 2>/dev/null)
                active_timer_space="$space"
                break
            fi
        fi
    done <<< "$space_list"

    if [ -z "$active_timer_text" ] || [ "$active_timer_text" = "null" ]; then
        osascript -e 'display dialog "No active timer to stop!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    local current_time=$(date +%s)

    # Calculate duration and stop timer
    local start_time=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$active_timer_space" --argjson id "$active_timer_id" '.spaces[$space].todos[] | select(.id == $id) | .timer_start' 2>/dev/null)
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
        local previous_duration=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$active_timer_space" --argjson id "$active_timer_id" '.spaces[$space].todos[] | select(.id == $id) | .timer_duration' 2>/dev/null || echo "0")
        local total_duration=$((previous_duration + duration))

        # Update the todo with total time and clear timer_start in the correct space
        cat "$TODO_DATA_FILE" | jq --arg space "$active_timer_space" --argjson id "$active_timer_id" --argjson total "$total_duration" \
            '(.spaces[$space].todos[] | select(.id == $id)) |= (.timer_duration = $total | .timer_start = null)' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Calculate daily total for this TASK on current date (task-specific, not space-wide)
        local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
        local current_date=$(date "+%Y-%m-%d")
        local daily_total=0

        if [ -f "$log_file" ]; then
            # Sum up all session times for this specific TASK on the current date
            local in_target_date=0
            local in_target_space=0
            local in_target_task=0

            while IFS= read -r line; do
                # Check for date header
                if [[ "$line" == "  $current_date" ]]; then
                    in_target_date=1
                    in_target_space=0
                    in_target_task=0
                elif [[ "$line" =~ ^\ \ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ $in_target_date -eq 1 ]; then
                    # Different date section - stop looking
                    in_target_date=0
                    in_target_space=0
                    in_target_task=0
                fi

                # Check for space header within target date (match both old and new formats)
                if [ $in_target_date -eq 1 ]; then
                    if [[ "$line" == "--- $active_timer_space ---------------" || "$line" == "--- $active_timer_space ---" ]]; then
                        in_target_space=1
                        in_target_task=0
                    elif [[ "$line" =~ ^---\ .* ]]; then
                        # Different space
                        in_target_space=0
                        in_target_task=0
                    fi
                fi

                # Check for task header within target space
                if [ $in_target_date -eq 1 ] && [ $in_target_space -eq 1 ]; then
                    if [[ "$line" == "  \"$active_timer_text\"" ]]; then
                        in_target_task=1
                    elif [[ "$line" =~ ^\ \ \" ]]; then
                        # Different task header
                        in_target_task=0
                    fi
                fi

                # Match new format: lines starting with spaces and brackets under task headers
                # Only count if we're in the target date AND target space AND target task
                if [ $in_target_date -eq 1 ] && [ $in_target_space -eq 1 ] && [ $in_target_task -eq 1 ]; then
                    if [[ "$line" =~ ^\ +\[.*Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
                        local prev_minutes="${BASH_REMATCH[1]}"
                        local prev_seconds="${BASH_REMATCH[2]}"
                        daily_total=$((daily_total + prev_minutes * 60 + prev_seconds))
                    fi
                fi

                # Also match old format for backwards compatibility (no space tracking)
                if [[ "$line" =~ ^\[$current_date.*\].*\"$active_timer_text\".*Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
                    local prev_minutes="${BASH_REMATCH[1]}"
                    local prev_seconds="${BASH_REMATCH[2]}"
                    daily_total=$((daily_total + prev_minutes * 60 + prev_seconds))
                fi
            done < "$log_file"
        fi

        # Add current session to daily total
        daily_total=$((daily_total + duration))

        local session_minutes=$((duration / 60))
        local session_seconds=$((duration % 60))
        local daily_minutes=$((daily_total / 60))
        local daily_seconds=$((daily_total % 60))

        # Calculate decimal hours for time logging software
        local daily_hours
        if command -v bc >/dev/null 2>&1; then
            daily_hours=$(echo "scale=2; $daily_total / 3600" | bc 2>/dev/null)
            if [[ "$daily_hours" =~ ^\..*$ ]]; then
                daily_hours="0$daily_hours"
            fi
        else
            daily_hours=$(awk "BEGIN {printf \"%.2f\", $daily_total / 3600}")
        fi

        if [ -z "$daily_hours" ] || [[ ! "$daily_hours" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            daily_hours="0.00"
        fi

        # Write to organized log (Date -> Space -> Task hierarchy)
        write_organized_log "$active_timer_space" "$active_timer_text" "$duration" "$daily_total" "$daily_hours"

        # Show confirmation with time spent
        osascript -e "display dialog \"⏹ Timer stopped for: ${active_timer_text}\n\nThis session: ${session_minutes}m ${session_seconds}s\nToday's total: ${daily_minutes}m ${daily_seconds}s\nDecimal hours: ${daily_hours}\" with title \"Timer Stopped\" buttons {\"OK\"} default button \"OK\" giving up after 5"
    fi

    sketchybar --trigger todo_update
}

clear_completed_todos() {
    # Use the same logic as detection - count completed items in current space view
    local completed_count=$(get_current_todos | jq -s '[.[] | select(.completed == true)] | length' 2>/dev/null || echo "0")
    if [ "$completed_count" -eq 0 ]; then
        osascript -e 'display dialog "No completed todos to clear!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

    # Confirmation dialog
    local confirm=$(osascript -e "display dialog \"Are you sure you want to delete ${completed_count} completed todo(s)?\n\nThis action cannot be undone.\" with title \"Clear Completed Items\" buttons {\"Cancel\", \"Delete Completed\"} default button \"Delete Completed\"")

    local confirmed=$(echo "$confirm" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    if [ "$confirmed" = "Delete Completed" ]; then
        if [ "$current_space" = "ALL" ]; then
            # Remove completed todos from all spaces
            cat "$TODO_DATA_FILE" | jq '.spaces = (.spaces | with_entries(.value.todos = [.value.todos[] | select(.completed == false)]))' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
        else
            # Remove completed todos from specific space only
            cat "$TODO_DATA_FILE" | jq --arg space "$current_space" \
                '.spaces[$space].todos = [.spaces[$space].todos[] | select(.completed == false)]' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
        fi

        sketchybar --trigger todo_update

        # Show confirmation
        if [ "$completed_count" -eq 1 ]; then
            osascript -e "display dialog \"🗑 Cleared 1 completed todo!\" with title \"Completed Items Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        else
            osascript -e "display dialog \"🗑 Cleared ${completed_count} completed todos!\" with title \"Completed Items Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 2"
        fi
    fi
}

clear_all_todos() {
    # Count todos in current space view using same logic as other functions
    local total_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")
    if [ "$total_count" -eq 0 ]; then
        osascript -e 'display dialog "No todos to clear!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

    # Confirmation dialog
    local confirm=$(osascript -e "display dialog \"Are you sure you want to delete ALL ${total_count} todos?\n\nThis action cannot be undone.\" with title \"Clear All Todos\" buttons {\"Cancel\", \"Delete All\"} default button \"Cancel\"")

    local confirmed=$(echo "$confirm" | grep -o 'button returned:[^,}]*' | cut -d: -f2)

    if [ "$confirmed" = "Delete All" ]; then
        if [ "$current_space" = "ALL" ]; then
            # Clear todos from all spaces but preserve space structure
            cat "$TODO_DATA_FILE" | jq '.spaces = (.spaces | with_entries(.value.todos = []))' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
        else
            # Clear todos from specific space only
            cat "$TODO_DATA_FILE" | jq --arg space "$current_space" \
                '.spaces[$space].todos = []' \
                > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"
        fi

        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"🗑 All todos cleared!\" with title \"Todos Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 2"
    fi
}

show_time_logs() {
    local log_file="$CONFIG_DIR/todo_data/timer_log.txt"

    # Check if timer log exists and has content
    if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then
        osascript -e 'display dialog "No timer logs found!" with title "Info" buttons {"OK"} default button "OK"'
        return
    fi

    # Open the log file directly in the default text editor
    open "$log_file"
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

        # Reset all timer durations to 0 across all spaces in the JSON file, including music timer
        cat "$TODO_DATA_FILE" | jq '.spaces[].todos[].timer_duration = 0 | .music_timer.timer_duration = 0' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Update the display to reflect reset totals
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"🗑 Timer logs cleared!\n\nStarted fresh log session for today.\nAll timer totals have been reset to 0.\" with title \"Logs Cleared\" buttons {\"OK\"} default button \"OK\" giving up after 4"
    fi
}

# Function to start music production timer (no todo item required)
start_music_timer() {
    # Check if there's already an active timer (either music or todo item)
    local active_todo_timer=$(get_current_todos | jq -s -r '.[] | select(.completed == false and .timer_start != null) | .text' 2>/dev/null | head -1)
    if [ -n "$active_todo_timer" ]; then
        osascript -e "display dialog \"Timer already running for: ${active_todo_timer}\n\nStop the current timer before starting a new one.\" with title \"Timer Already Active\" buttons {\"OK\"} default button \"OK\""
        return
    fi

    # Check if music timer is already active
    local music_timer_active=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_start // null' 2>/dev/null)
    if [ -n "$music_timer_active" ] && [ "$music_timer_active" != "null" ]; then
        osascript -e "display dialog \"Video Game Bank timer is already running!\n\nStop the current timer before starting a new one.\" with title \"Timer Already Active\" buttons {\"OK\"} default button \"OK\""
        return
    fi

    # Store timestamp as Unix epoch seconds
    local current_time=$(date +%s)

    # Initialize music_timer object if it doesn't exist, then set timer_start
    cat "$TODO_DATA_FILE" | jq --argjson time "$current_time" \
        '.music_timer = {timer_start: $time, timer_duration: (.music_timer.timer_duration // 0)}' \
        > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

    # Force immediate update
    sketchybar --trigger todo_update
    sleep 0.1
    sketchybar --trigger todo_update

    # Show confirmation
    osascript -e "display dialog \"🎵 Video Game Bank timer started!\" with title \"Timer Started\" buttons {\"OK\"} default button \"OK\" giving up after 2"
}

# Function to stop music production timer
stop_music_timer() {
    local current_time=$(date +%s)

    # Get start time
    local start_time=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_start // null' 2>/dev/null)

    if [ "$start_time" = "null" ] || [ -z "$start_time" ]; then
        return 1  # No music timer active
    fi

    # Calculate duration
    local duration=$((current_time - start_time))

    # Ensure duration is positive and reasonable (less than 24 hours)
    if [ "$duration" -lt 0 ] || [ "$duration" -gt 86400 ]; then
        echo "Warning: Invalid duration ($duration), using 0" >> /tmp/timer_debug.log
        duration=0
    fi

    # Get previous total time and add this session
    local previous_duration=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_duration // 0' 2>/dev/null)
    local total_duration=$((previous_duration + duration))

    # Update the JSON with total time and clear timer_start
    cat "$TODO_DATA_FILE" | jq --argjson total "$total_duration" \
        '.music_timer.timer_duration = $total | .music_timer.timer_start = null' \
        > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

    # Calculate daily total for display and logging
    local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
    local current_date=$(date "+%Y-%m-%d")
    local daily_total=0

    if [ -f "$log_file" ]; then
        # Sum up all session times for Video Game Bank on the current date (check new format)
        while IFS= read -r line; do
            # Match new format: lines starting with spaces and brackets under task headers
            if [[ "$line" =~ ^\ +\[.*Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
                local prev_minutes="${BASH_REMATCH[1]}"
                local prev_seconds="${BASH_REMATCH[2]}"
                daily_total=$((daily_total + prev_minutes * 60 + prev_seconds))
            # Also match old format for backwards compatibility
            elif [[ "$line" =~ ^\[$current_date.*\].*\"Video\ Game\ Bank\".*Session:\ ([0-9]+)m\ ([0-9]+)s ]]; then
                local prev_minutes="${BASH_REMATCH[1]}"
                local prev_seconds="${BASH_REMATCH[2]}"
                daily_total=$((daily_total + prev_minutes * 60 + prev_seconds))
            fi
        done < "$log_file"
    fi

    # Add current session to daily total
    daily_total=$((daily_total + duration))

    local session_minutes=$((duration / 60))
    local session_seconds=$((duration % 60))
    local daily_minutes=$((daily_total / 60))
    local daily_seconds=$((daily_total % 60))

    # Calculate decimal hours for time logging software
    local daily_hours
    if command -v bc >/dev/null 2>&1; then
        daily_hours=$(echo "scale=2; $daily_total / 3600" | bc 2>/dev/null)
        if [[ "$daily_hours" =~ ^\..*$ ]]; then
            daily_hours="0$daily_hours"
        fi
    else
        daily_hours=$(awk "BEGIN {printf \"%.2f\", $daily_total / 3600}")
    fi

    if [ -z "$daily_hours" ] || [[ ! "$daily_hours" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        daily_hours="0.00"
    fi

    # Write to organized log (Date -> Space -> Task hierarchy)
    # Video Game Bank goes under its own "Video Game Bank" space section
    write_organized_log "Video Game Bank" "Video Game Bank" "$duration" "$daily_total" "$daily_hours"

    # Show confirmation
    osascript -e "display dialog \"🎵 Video Game Bank timer stopped!\n\nThis session: ${session_minutes}m ${session_seconds}s\nToday's total: ${daily_minutes}m ${daily_seconds}s\nDecimal hours: ${daily_hours}\" with title \"Timer Stopped\" buttons {\"OK\"} default button \"OK\" giving up after 5"

    sketchybar --trigger todo_update
    return 0  # Success
}

# Function to dump (reset) Video Game Bank timer
dump_video_game_bank() {
    # Get current timer duration
    local current_duration=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_duration // 0' 2>/dev/null)
    local current_minutes=$((current_duration / 60))

    # Show dialog with three button options
    local choice=$(osascript -e "button returned of (display dialog \"Video Game Bank: ${current_minutes} minutes\n\nReset to 0, deduct minutes, or cancel?\" with title \"Dump Video Game Bank\" buttons {\"Cancel\", \"Deduct\", \"Reset\"} default button \"Reset\" cancel button \"Cancel\")" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$choice" ]; then
        # User cancelled
        return
    fi

    if [ "$choice" = "Reset" ]; then
        # Reset the music_timer duration to 0 in the JSON file
        cat "$TODO_DATA_FILE" | jq '.music_timer.timer_duration = 0' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Remove all "Video Game Bank" entries from timer log
        local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
        if [ -f "$log_file" ]; then
            # Check if there are any Video Game Bank entries to remove
            if grep -q '"Video Game Bank"' "$log_file"; then
                # Create a backup before modifying
                cp "$log_file" "${log_file}.backup_dump_$(date +%Y%m%d_%H%M%S)"

                # Create a temp file without Video Game Bank entries
                grep -v '"Video Game Bank"' "$log_file" > "${log_file}.tmp"

                # Only proceed if the temp file has content (more than just the header)
                if [ -s "${log_file}.tmp" ]; then
                    # Remove trailing empty date sections
                    awk '
                        BEGIN { buffer = "" }
                        /^================================$/ {
                            # Store potential date section
                            sep1 = $0
                            getline
                            date_line = $0
                            getline
                            sep2 = $0
                            getline
                            empty = $0

                            # Read ahead to see if there are entries
                            has_entries = 0
                            while (getline > 0) {
                                if ($0 ~ /^================================$/) {
                                    # Another separator means this section was empty
                                    sep1 = $0
                                    getline
                                    date_line = $0
                                    getline
                                    sep2 = $0
                                    getline
                                    empty = $0
                                } else if ($0 ~ /^\[/) {
                                    # Found an entry, print the section
                                    print sep1
                                    print date_line
                                    print sep2
                                    print empty
                                    print $0
                                    has_entries = 1
                                    break
                                }
                            }

                            if (has_entries) {
                                while (getline > 0) {
                                    print
                                }
                            }
                            next
                        }
                        { print }
                    ' "${log_file}.tmp" > "${log_file}.cleaned"

                    mv "${log_file}.cleaned" "$log_file"
                else
                    # If temp file is empty/only header, restore from backup
                    echo "Warning: Filtering would delete all content, restoring from backup" >> /tmp/timer_debug.log
                    cp "${log_file}.backup_dump_"* "$log_file" 2>/dev/null || true
                fi

                rm -f "${log_file}.tmp"
            fi
        fi

        # Update the display
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"🗑 Video Game Bank timer has been reset to 0!\n\nAll Video Game Bank log entries have been removed.\" with title \"Timer Dumped\" buttons {\"OK\"} default button \"OK\" giving up after 3"

    elif [ "$choice" = "Deduct" ]; then
        # Ask user for number of minutes to deduct
        local minutes_to_deduct=$(osascript -e 'text returned of (display dialog "Enter number of minutes to deduct from Video Game Bank:" with title "Deduct Minutes" default answer "0")' 2>/dev/null)

        if [ -z "$minutes_to_deduct" ] || ! [[ "$minutes_to_deduct" =~ ^[0-9]+$ ]]; then
            # Invalid input or cancelled
            osascript -e "display dialog \"Invalid input. No changes made.\" with title \"Error\" buttons {\"OK\"} default button \"OK\" giving up after 2"
            return
        fi

        # Convert minutes to seconds and deduct from current duration
        local seconds_to_deduct=$((minutes_to_deduct * 60))
        local new_duration=$((current_duration - seconds_to_deduct))

        # Ensure we don't go below 0
        if [ $new_duration -lt 0 ]; then
            new_duration=0
        fi

        # Update the JSON file with new duration
        cat "$TODO_DATA_FILE" | jq --argjson new_dur "$new_duration" '.music_timer.timer_duration = $new_dur' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        # Add deduction entry to timer log with current balance
        local log_file="$CONFIG_DIR/todo_data/timer_log.txt"
        local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        local current_date=$(date "+%Y-%m-%d")
        local new_minutes=$((new_duration / 60))
        local new_seconds=$((new_duration % 60))

        # Calculate decimal hours for new balance
        local balance_hours
        if command -v bc >/dev/null 2>&1; then
            balance_hours=$(echo "scale=2; $new_duration / 3600" | bc 2>/dev/null)
            if [[ "$balance_hours" =~ ^\..*$ ]]; then
                balance_hours="0$balance_hours"
            fi
        else
            balance_hours=$(awk "BEGIN {printf \"%.2f\", $new_duration / 3600}")
        fi
        if [ -z "$balance_hours" ] || [[ ! "$balance_hours" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            balance_hours="0.00"
        fi

        # Build log entry for deduction
        local log_entry=""

        # Check if we need to add a date separator
        local last_date=""
        if [ -f "$log_file" ] && [ -s "$log_file" ]; then
            last_date=$(grep -E '^\[' "$log_file" | tail -1 | grep -o '^\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | tr -d '[')
        fi

        # Add date separator if this is a new date
        if [ -n "$last_date" ] && [ "$last_date" != "$current_date" ]; then
            log_entry="${log_entry}\n"
            log_entry="${log_entry}================================\n"
            log_entry="${log_entry}  $current_date\n"
            log_entry="${log_entry}================================\n"
            log_entry="${log_entry}\n"
        fi

        # Check if last item was different
        local last_logged_item=""
        if [ -f "$log_file" ]; then
            last_logged_item=$(tail -1 "$log_file" 2>/dev/null | grep -o '"[^"]*"' | head -1)
        fi

        # Add spacing if needed
        if [ -n "$last_logged_item" ] && [ "$last_logged_item" != "\"Video Game Bank\"" ]; then
            log_entry="${log_entry}\n"
        fi

        # Add the deduction entry with current balance
        log_entry="${log_entry}[$timestamp] \"Video Game Bank\" - Deducted: ${minutes_to_deduct}m | Current Balance: ${new_minutes}m ${new_seconds}s (${balance_hours} hours)\n"

        # Write to log file atomically
        printf "%b" "$log_entry" >> "$log_file"

        # Update the display
        sketchybar --trigger todo_update

        # Show confirmation
        osascript -e "display dialog \"✅ Deducted ${minutes_to_deduct} minutes from Video Game Bank!\n\nPrevious: ${current_minutes} minutes\nNew total: ${new_minutes} minutes\" with title \"Minutes Deducted\" buttons {\"OK\"} default button \"OK\" giving up after 4"
    fi
}

# Function to switch between spaces
switch_space() {
    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

    # Define the custom order you want
    local ordered_spaces=("ALL" "Ujam" "Lonebody" "60 Pleasant" "Personal" "Workflow Tools")
    local space_options=()

    # Add each space in your preferred order using SF Symbol icons
    for space in "${ordered_spaces[@]}"; do
        local sf_icon=$(get_space_sf_icon "$space")
        if [ "$space" = "ALL" ]; then
            local all_count=$(cat "$TODO_DATA_FILE" | jq '[.spaces[].todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
            space_options+=("$sf_icon ALL ($all_count)")
        else
            # Check if this space exists in the JSON
            local exists=$(cat "$TODO_DATA_FILE" | jq -r --arg space "$space" '.spaces[$space] // empty' 2>/dev/null)
            if [ -n "$exists" ]; then
                local count=$(cat "$TODO_DATA_FILE" | jq --arg space "$space" '[.spaces[$space].todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
                space_options+=("$sf_icon $space ($count)")
            fi
        fi
    done

    # Create AppleScript list
    local script_options=""
    for option in "${space_options[@]}"; do
        if [ -n "$script_options" ]; then
            script_options="${script_options}, \"${option}\""
        else
            script_options="\"${option}\""
        fi
    done

    local choice=$(osascript -e "choose from list {${script_options}} with title \"Switch to Space\" with prompt \"Current: $current_space\"")

    if [ "$choice" != "false" ]; then
        local selected_space
        if [ "$choice" = "ALL" ]; then
            selected_space="ALL"
        else
            # Extract space name from "icon SPACE (count)" format
            selected_space=$(echo "$choice" | sed -E 's/^[^[:space:]]+ ([^(]+) \([0-9]+\)$/\1/' | sed 's/[[:space:]]*$//')
        fi

        # Update current space
        cat "$TODO_DATA_FILE" | jq --arg space "$selected_space" '.current_space = $space' \
            > "${TODO_DATA_FILE}.tmp" && mv "${TODO_DATA_FILE}.tmp" "$TODO_DATA_FILE"

        sketchybar --trigger todo_update

        # Show the new space
        show_main_menu
    fi
}

show_main_menu