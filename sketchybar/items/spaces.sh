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
                                    padding_left=$PILL_EDGE \
                                    padding_right=0 \
                                    label.drawing=off

        sketchybar --add item space_icons.$sid left \
                   --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_TEXT.0" \
                                         label.padding_right=$PADDING_S \
                                         label.padding_left=$PADDING_S \
                                         padding_left=0 \
                                         padding_right=2 \
                                         background.height=$ICON_PILL_HEIGHT \
                                         background.corner_radius=$ICON_PILL_RADIUS \
                                         label.y_offset=-1 \
                                         background.drawing=off \
                                         icon.drawing=off
    done

    # Force correct ordering: space.N then space_icons.N for each space
    REORDER_ARGS=""
    for sid in "${SPACE_SIDS[@]}"; do
        REORDER_ARGS+="space.$sid space_icons.$sid "
    done
    sketchybar --reorder $REORDER_ARGS
else
    # Parse spaces from yabai - get index and display for each
    SPACE_COUNT=$(echo "$SPACES_JSON" | jq 'length')

    for ((i=0; i<SPACE_COUNT; i++)); do
        sid=$(echo "$SPACES_JSON" | jq -r ".[$i].index")
        display_id=$(echo "$SPACES_JSON" | jq -r ".[$i].display")

        sketchybar --add space space.$sid left \
                   --set space.$sid space=$sid \
                                    icon=$sid \
                                    padding_left=$PILL_EDGE \
                                    padding_right=0 \
                                    label.drawing=off \
                                    associated_display=$display_id

        sketchybar --add item space_icons.$sid left \
                   --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_TEXT.0" \
                                         label.padding_right=$PADDING_S \
                                         label.padding_left=$PADDING_S \
                                         padding_left=0 \
                                         padding_right=2 \
                                         background.height=$ICON_PILL_HEIGHT \
                                         background.corner_radius=$ICON_PILL_RADIUS \
                                         label.y_offset=-1 \
                                         background.drawing=off \
                                         icon.drawing=off \
                                         associated_display=$display_id
    done

    # Force correct ordering: space.N then space_icons.N for each space
    REORDER_ARGS=""
    for ((i=0; i<SPACE_COUNT; i++)); do
        sid=$(echo "$SPACES_JSON" | jq -r ".[$i].index")
        REORDER_ARGS+="space.$sid space_icons.$sid "
    done
    sketchybar --reorder $REORDER_ARGS
fi

# Single hidden watcher drives styling for ALL space items via one batched
# script run — replaces the old per-space-item script/subscription fan-out.
# (No manual initial run needed: sketchybarrc's final `sketchybar --update`
# fires this after the whole config has loaded — a manual run here would race
# the rest of the config load.)
sketchybar --add item spaces_watcher left \
           --set spaces_watcher drawing=off \
                                script="$PLUGIN_DIR/space.sh" \
           --subscribe spaces_watcher space_change display_change

# Hidden host for space_windows.sh (updates each space's app icons). The ">"
# glyph is no longer drawn — the gap + front-app pill already separate the groups.
sketchybar --add item space_separator left \
          --set space_separator drawing=off \
                               icon=">" \
                               icon.color=$LEFT_TEXT_COLOR \
                               icon.font="$TEXT_FONT:Semibold:$FONT_SIZE_TEXT.0" \
                               icon.padding_right=0 \
                               label.drawing=off \
                               background.drawing=off \
                               script="$PLUGIN_DIR/space_windows.sh" \
          --subscribe space_separator space_windows_change display_change
