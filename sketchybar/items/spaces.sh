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

source "$ITEM_DIR/space_lib.sh"

if [ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ]; then
    # Fallback to static spaces if yabai isn't running
    SPACE_SIDS=(1 2 3 4)
    SPACE_ARGS=()
    REORDER_ARGS=""
    for sid in "${SPACE_SIDS[@]}"; do
        space_item_args $sid
        REORDER_ARGS+="space.$sid space_icons.$sid "
    done
    sketchybar "${SPACE_ARGS[@]}"
    sketchybar --reorder $REORDER_ARGS
else
    SPACE_ARGS=()
    while IFS=$'\t' read -r sid display_id; do
        space_item_args $sid $display_id
    done < <(echo "$SPACES_JSON" | jq -r '.[] | [.index, .display] | @tsv')
    sketchybar "${SPACE_ARGS[@]}"

    # "−" "+" buttons per display (after front_app — see sketchybarrc's final
    # reorder): remove that display's visible desktop / add one. The bar's
    # space items follow live via yabai's space signals (plugins/space_sync.sh).
    for display_id in $(echo "$SPACES_JSON" | jq -r '[.[].display] | unique | .[]'); do
        sketchybar --add item space_remove.$display_id left \
                   --set space_remove.$display_id "${hover_button[@]}" \
                                    icon="$SPACE_REMOVE_ICON" \
                                    icon.color=$ICON_COLOR \
                                    label.drawing=off \
                                    associated_display=$display_id \
                                    click_script="$PLUGIN_DIR/space_remove_click.sh $display_id" \
                                    script="$PLUGIN_DIR/hover.sh" \
                   --subscribe space_remove.$display_id mouse.entered mouse.exited
        sketchybar --add item space_add.$display_id left \
                   --set space_add.$display_id "${hover_button[@]}" \
                                    icon="$SPACE_ADD_ICON" \
                                    icon.color=$ICON_COLOR \
                                    label.drawing=off \
                                    associated_display=$display_id \
                                    click_script="yabai -m space --create $display_id" \
                                    script="$PLUGIN_DIR/hover.sh" \
                   --subscribe space_add.$display_id mouse.entered mouse.exited
    done

    # Reused by space_brackets.sh and sketchybarrc's final reorder
    SPACE_ORDER=$(space_order "$SPACES_JSON")
    SPACE_CONTROL_ITEMS=$(space_control_items "$SPACES_JSON")
    sketchybar --reorder $SPACE_ORDER
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
