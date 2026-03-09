#!/bin/bash

# Dynamic space detection - queries yabai for all spaces and their displays
# Each space item is assigned to its respective display via associated_display

# Get all spaces from yabai, retrying if external display isn't detected yet
SPACES_JSON=""
for attempt in 1 2 3; do
    SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
    if [ -n "$SPACES_JSON" ] && [ "$SPACES_JSON" != "null" ]; then
        # Check if all spaces are on display 1 (external display not recognized yet)
        DISPLAY_COUNT=$(echo "$SPACES_JSON" | jq '[.[].display] | unique | length')
        if [ "$DISPLAY_COUNT" -gt 1 ] || [ "$attempt" -eq 3 ]; then
            break
        fi
    fi
    sleep 1
done

if [ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ]; then
    # Fallback to static spaces if yabai isn't running
    SPACE_SIDS=(1 2 3 4)
    for sid in "${SPACE_SIDS[@]}"; do
        sketchybar --add space space.$sid left \
                   --set space.$sid space=$sid \
                                    icon=$sid \
                                    label.drawing=off \
                                    script="$PLUGIN_DIR/space.sh"

        sketchybar --add item space_icons.$sid left \
                   --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_MEDIUM.0" \
                                         label.padding_right=$PADDING_M \
                                         label.padding_left=$PADDING_M \
                                         label.y_offset=-1 \
                                         background.drawing=off \
                                         icon.drawing=off
    done
else
    # Parse spaces from yabai - get index and display for each
    SPACE_COUNT=$(echo "$SPACES_JSON" | jq 'length')

    for ((i=0; i<SPACE_COUNT; i++)); do
        sid=$(echo "$SPACES_JSON" | jq -r ".[$i].index")
        display_id=$(echo "$SPACES_JSON" | jq -r ".[$i].display")

        # Create the space number item with display association
        sketchybar --add space space.$sid left \
                   --set space.$sid space=$sid \
                                    icon=$sid \
                                    label.drawing=off \
                                    associated_display=$display_id \
                                    script="$PLUGIN_DIR/space.sh" \
                   --subscribe space.$sid display_change space_change

        # Create a separate item for space icons with same display association
        sketchybar --add item space_icons.$sid left \
                   --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_MEDIUM.0" \
                                         label.padding_right=$PADDING_M \
                                         label.padding_left=$PADDING_M \
                                         label.y_offset=-1 \
                                         background.drawing=off \
                                         icon.drawing=off \
                                         associated_display=$display_id
    done
fi

sketchybar --add item space_separator left \
          --set space_separator icon=">" \
                               icon.color=$LEFT_TEXT_COLOR \
                               icon.font="$TEXT_FONT:Bold:$FONT_SIZE_MEDIUM.0" \
                               icon.padding_left=4 \
                               label.drawing=off \
                               background.drawing=off \
                               script="$PLUGIN_DIR/space_windows.sh" \
          --subscribe space_separator space_windows_change display_change
