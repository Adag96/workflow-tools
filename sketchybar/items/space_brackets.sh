#!/bin/bash

# Dynamic bracket creation for spaces
# Called after spaces.sh to create brackets for all detected spaces

# Get all spaces from yabai
SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)

if [ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ]; then
    # Fallback to static spaces
    SPACE_SIDS=(1 2 3 4)
else
    # Get all space indices
    SPACE_SIDS=($(echo "$SPACES_JSON" | jq -r '.[].index'))
fi

# Build arrays for bracket items - grouped by display
declare -A DISPLAY_SPACES
for sid in "${SPACE_SIDS[@]}"; do
    if [ -n "$SPACES_JSON" ] && [ "$SPACES_JSON" != "null" ]; then
        display_id=$(echo "$SPACES_JSON" | jq -r ".[] | select(.index == $sid) | .display")
    else
        display_id=1
    fi
    DISPLAY_SPACES[$display_id]+="space.$sid space_icons.$sid "
done

# Build the full list of all space items for left_bracket
ALL_SPACE_ITEMS=""
for sid in "${SPACE_SIDS[@]}"; do
    ALL_SPACE_ITEMS+="space.$sid space_icons.$sid "
done

# Left pill: all spaces, front app, and yabai controls (PILL LEVEL 1)
sketchybar --add bracket left_bracket left_edge $ALL_SPACE_ITEMS space_separator front_app yabai_mode left_end \
           --set left_bracket background.color=$PILL_COLOR_1 \
                              background.height=$PILL_HEIGHT \
                              background.corner_radius=$PILL_RADIUS \
                              y_offset=$Y_OFFSET

# Active-space highlight (PILL LEVEL 2) - drawn only for the visible space (see plugins/space.sh)
for sid in "${SPACE_SIDS[@]}"; do
    sketchybar --add bracket space_${sid}_bracket space.$sid space_icons.$sid \
               --set space_${sid}_bracket background.color=$PILL_COLOR_3 \
                                    background.height=$CAPSULE_HEIGHT \
                                    background.corner_radius=$CAPSULE_RADIUS \
                                    y_offset=$Y_OFFSET
done
