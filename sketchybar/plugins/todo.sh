#!/bin/bash

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
TODO_DATA_FILE="$CONFIG_DIR/todo_data/todos.json"

# Source the sketchybar configuration to get variables
source "$CONFIG_DIR/items/scheme.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme" 2>/dev/null || echo "moon")"
source "$CONFIG_DIR/icons.sh"

# Ensure todo data file exists
if [ ! -f "$TODO_DATA_FILE" ]; then
    mkdir -p "$(dirname "$TODO_DATA_FILE")"
    echo '{"todos": [], "next_id": 1}' > "$TODO_DATA_FILE"
fi

update_todo_display() {
    # Count active (incomplete) todos
    local active_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(cat "$TODO_DATA_FILE" | jq '.todos | length' 2>/dev/null || echo "0")

    # Check if any todo has an active timer
    local active_timer_count=$(cat "$TODO_DATA_FILE" | jq '[.todos[] | select(.completed == false and .timer_start != null)] | length' 2>/dev/null || echo "0")
    local active_timer=$(cat "$TODO_DATA_FILE" | jq -r '.todos[] | select(.completed == false and .timer_start != null) | .id' 2>/dev/null | head -1)

    # Set icon and color based on state
    local icon_color="$RIGHT_TEXT_COLOR"
    local icon="$TODO_ICON"
    local label_text="$active_count"

    if [ -n "$active_timer" ] && [ "$active_timer" != "null" ] && [ "$active_timer" != "" ]; then
        # Active timer - use accent color and timer icon
        icon_color="$ACCENT_COLOR"
        icon="$TODO_TIMER_ICON"

        # Show that a timer is active (now only one timer allowed)
        label_text="$active_count"
    elif [ "$active_count" -gt 0 ]; then
        # Active todos but no timer - use normal color
        icon_color="$RIGHT_TEXT_COLOR"
        icon="$TODO_ICON"
        label_text="$active_count"
    else
        # No active todos - use dimmed color
        icon_color="0x60ffffff"
        icon="$TODO_ICON"
        label_text=""
    fi

    # Update the todo item
    sketchybar --set todo \
        icon="$icon" \
        icon.color="$icon_color"

    # Show count in label - always show if there are active todos
    if [ "$active_count" -gt 0 ]; then
        sketchybar --set todo label="$label_text" label.drawing=on
    else
        sketchybar --set todo label.drawing=off
    fi
}

# Handle different triggers
case "$SENDER" in
    "todo_update")
        update_todo_display
        ;;
    *)
        update_todo_display
        ;;
esac