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
sketchybar --add bracket left_bracket $ALL_SPACE_ITEMS space_separator front_app ableton_timer_toggle yabai_mode yabai.toggle \
           --set left_bracket background.color=$PILL_COLOR_1 \
                              background.height=$HEIGHT_L2 \
                              background.corner_radius=$RADIUS_L1 \
                              border_color=$PILL_LEVEL_2_BORDER \
                              border_width=$BORDER_THIN \
                              y_offset=$Y_OFFSET

# Spaces container pill (PILL LEVEL 2) - contains all spaces and their icons
sketchybar --add bracket spaces_bracket $ALL_SPACE_ITEMS \
           --set spaces_bracket background.color=$PILL_COLOR_2 \
                               background.height=$HEIGHT_L3 \
                               background.corner_radius=$RADIUS_L2 \
                               border_color=$PILL_LEVEL_2_BORDER \
                               border_width=$BORDER_THICK \
                               padding_left=$PADDING_L \
                               padding_right=$PADDING_M \
                               y_offset=$Y_OFFSET

# Individual space + icons pills (PILL LEVEL 3) - concentric within spaces container
for sid in "${SPACE_SIDS[@]}"; do
    sketchybar --add bracket space_${sid}_bracket space.$sid space_icons.$sid \
               --set space_${sid}_bracket background.color=$PILL_COLOR_3 \
                                    background.height=$HEIGHT_L4 \
                                    background.corner_radius=$RADIUS_L3 \
                                    y_offset=$Y_OFFSET
done
