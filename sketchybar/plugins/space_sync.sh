#!/bin/bash

# Add/remove space items live when spaces are created or destroyed, instead of
# reloading the whole bar. Items are keyed by space index, so only the highest
# indices are added/removed; space.sh then reassigns each to its display.
# Called by space_count_changed.sh. Falls back to a full reload whenever it
# can't do the job safely (scheme not loaded, set of displays changed).

export CONFIG_DIR="$HOME/workflow-tools/sketchybar"   # space.sh's scheme load needs it
ITEM_DIR="$CONFIG_DIR/items"
PLUGIN_DIR="$CONFIG_DIR/plugins"

source "$CONFIG_DIR/vars.sh"
source "$ITEM_DIR/scheme.sh"
get_colors "$(cat "$HOME/.cache/sketchybar/current_scheme" 2>/dev/null)"
source "$ITEM_DIR/space_lib.sh"

[ -z "$PILL_COLOR_1" ] || [ -z "$PILL_COLOR_3" ] && { sketchybar --reload; exit 0; }

SPACES_JSON=$(yabai -m query --spaces 2>/dev/null)
[ -z "$SPACES_JSON" ] || [ "$SPACES_JSON" = "null" ] && exit 0
BAR_ITEMS=$(sketchybar --query bar 2>/dev/null | jq -r '.items[]')
[ -z "$BAR_ITEMS" ] && exit 0

# A display appeared/disappeared: its "+" button needs (un)building — full reload
YABAI_DISPLAYS=$(echo "$SPACES_JSON" | jq -r '[.[].display] | unique | join(" ")')
BAR_DISPLAYS=$(echo "$BAR_ITEMS" | sed -n 's/^space_add\.//p' | sort -n | tr '\n' ' ' | sed 's/ $//')
if [ "$YABAI_DISPLAYS" != "$BAR_DISPLAYS" ]; then
    sketchybar --reload
    exit 0
fi

YABAI_COUNT=$(echo "$SPACES_JSON" | jq 'length')
BAR_COUNT=$(echo "$BAR_ITEMS" | grep -cE '^space\.[0-9]+$')
[ "$YABAI_COUNT" -eq "$BAR_COUNT" ] && exit 0

# Everything happens in ONE sketchybar call so the bar never draws a half state
ARGS=()

# New spaces: add their items
SPACE_ARGS=()
for ((sid=BAR_COUNT+1; sid<=YABAI_COUNT; sid++)); do
    space_item_args $sid "$(echo "$SPACES_JSON" | jq -r ".[] | select(.index == $sid) | .display")"
done
ARGS+=("${SPACE_ARGS[@]}")

# Gone spaces: remove their items
REMOVED=" "
for ((sid=YABAI_COUNT+1; sid<=BAR_COUNT; sid++)); do
    ARGS+=(--remove space.$sid --remove space_icons.$sid)
    REMOVED+="space.$sid space_icons.$sid "
done

# Brackets can't change members: remove and re-add the left pill and capsules
for item in $(echo "$BAR_ITEMS" | grep -E '^(left_bracket|space_[0-9]+_bracket)$'); do
    ARGS+=(--remove $item)
    REMOVED+="$item "
done

# Full reorder: current order with the space segment rebuilt after left_edge
# and the "−" "+" buttons after front_app.
# (A partial --reorder would push left_end past items added since config load.)
SPACE_ORDER=$(space_order "$SPACES_JSON")
SPACE_CONTROL_ITEMS=$(space_control_items "$SPACES_JSON")
ORDER=""
for item in $BAR_ITEMS; do
    case "$item" in
        space.[0-9]*|space_icons.[0-9]*|space_add.*|space_remove.*) continue ;;
    esac
    case "$REMOVED" in *" $item "*) continue ;; esac
    ORDER+="$item "
    [ "$item" = "left_edge" ] && ORDER+="$SPACE_ORDER "
    [ "$item" = "front_app" ] && ORDER+="$SPACE_CONTROL_ITEMS "
done
ARGS+=(--reorder $ORDER)

BRACKET_ARGS=()
space_bracket_args "$SPACE_ORDER" "$SPACE_CONTROL_ITEMS" $(seq 1 "$YABAI_COUNT")
ARGS+=("${BRACKET_ARGS[@]}")
# Only the visible spaces' capsules draw (space.sh owns this; preset it so the
# re-added capsules don't all flash on)
for sid in $(echo "$SPACES_JSON" | jq -r '.[] | select(."is-visible" | not) | .index'); do
    ARGS+=(--set space_${sid}_bracket background.drawing=off)
done

sketchybar "${ARGS[@]}"

# Style the spaces (accent number, display assignment) and repaint the app
# icons — indices may have shifted between displays
"$PLUGIN_DIR/space.sh"
SENDER=refresh_all "$PLUGIN_DIR/space_windows.sh"
