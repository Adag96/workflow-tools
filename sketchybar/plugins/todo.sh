#!/bin/bash

CONFIG_DIR="$HOME/workflow-tools/sketchybar"
TODO_DATA_FILE="$CONFIG_DIR/todo_data/todos.json"

# Source the sketchybar configuration to get variables
source "$CONFIG_DIR/items/scheme.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme" 2>/dev/null || echo "moon")"
source "$CONFIG_DIR/icons.sh"

# Ensure todo data file exists with spaces format
# Check if the file exists, or if the parent is a symlink (don't break symlinks)
if [ ! -f "$TODO_DATA_FILE" ] && [ ! -L "$(dirname "$TODO_DATA_FILE")" ]; then
    mkdir -p "$(dirname "$TODO_DATA_FILE")"
    echo '{"spaces": {"Personal": {"name": "Personal", "color": "🏠", "todos": []}}, "current_space": "ALL", "next_id": 1}' > "$TODO_DATA_FILE"
fi

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

# Helper function to get SF Symbol icon for current space
get_space_icon() {
    local current_space=$(cat "$TODO_DATA_FILE" | jq -r '.current_space' 2>/dev/null || echo "ALL")

    case "$current_space" in
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
            # Fallback to list icon for unknown spaces
            echo "$TODO_SPACE_ALL"
            ;;
    esac
}

update_todo_display() {
    # Count active (incomplete) todos from current view
    local active_count=$(get_current_todos | jq -s '[.[] | select(.completed == false)] | length' 2>/dev/null || echo "0")
    local total_count=$(get_current_todos | jq -s 'length' 2>/dev/null || echo "0")

    # Check if any todo has an active timer
    local active_timer_count=$(get_current_todos | jq -s '[.[] | select(.completed == false and .timer_start != null)] | length' 2>/dev/null || echo "0")
    local active_timer=$(get_current_todos | jq -s -r '.[] | select(.completed == false and .timer_start != null) | .id' 2>/dev/null | head -1)

    # Check if music timer is active
    local music_timer_active=$(cat "$TODO_DATA_FILE" | jq -r '.music_timer.timer_start // null' 2>/dev/null)

    # Get the space icon for current space
    local space_icon=$(get_space_icon)

    # Set icon and colors based on state
    # Space icon is always shown as the main icon with consistent color
    local icon_color="$RIGHT_TEXT_COLOR"
    local label_color="$RIGHT_TEXT_COLOR"
    local icon="$space_icon"
    local label_text="$active_count"

    # Priority: music timer > todo timer > active todos > no todos
    if [ -n "$music_timer_active" ] && [ "$music_timer_active" != "null" ]; then
        # Music timer active - space icon white, just timer icon in label (red)
        icon_color="$RIGHT_TEXT_COLOR"
        label_color="$ACCENT_COLOR"
        icon="$space_icon"
        label_text="$TODO_TIMER_ICON"
    elif [ -n "$active_timer" ] && [ "$active_timer" != "null" ] && [ "$active_timer" != "" ]; then
        # Active todo timer - space icon white, just timer icon in label (red)
        icon_color="$RIGHT_TEXT_COLOR"
        label_color="$ACCENT_COLOR"
        icon="$space_icon"
        label_text="$TODO_TIMER_ICON"
    elif [ "$active_count" -gt 0 ]; then
        # Active todos but no timer - normal colors, show count
        icon_color="$RIGHT_TEXT_COLOR"
        label_color="$RIGHT_TEXT_COLOR"
        icon="$space_icon"
        label_text="$active_count"
    else
        # No active todos - show space icon dimmed
        icon_color="0x60ffffff"
        label_color="$RIGHT_TEXT_COLOR"
        icon="$space_icon"
        label_text=""
    fi

    # Update the todo item - space icon color never changes based on timer state
    sketchybar --set todo \
        icon="$icon" \
        icon.color="$icon_color" \
        label.color="$label_color"

    # Show count in label - always show if there are active todos or music timer
    if [ "$active_count" -gt 0 ] || { [ -n "$music_timer_active" ] && [ "$music_timer_active" != "null" ]; }; then
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