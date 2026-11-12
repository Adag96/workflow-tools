#!/bin/bash

# Space item builders, shared by the config load (items/spaces.sh,
# items/space_brackets.sh) and the live add/remove path (plugins/space_sync.sh),
# so a space added at runtime looks exactly like one built at load.
# Needs vars.sh + scheme colors loaded. Bash 3.2 safe.

# space_item_args <sid> [display] — appends to SPACE_ARGS the sketchybar args
# for one space's number + app-icon strip
space_item_args() {
    local sid=$1 display=$2
    SPACE_ARGS+=(--add space space.$sid left
                 --set space.$sid space=$sid
                                  icon=$sid
                                  padding_left=$PILL_EDGE
                                  padding_right=0
                                  label.drawing=off
                                  ${display:+associated_display=$display}
                 --add item space_icons.$sid left
                 --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_TEXT.0"
                                       label.padding_right=$PADDING_M
                                       label.padding_left=$PADDING_M
                                       padding_left=0
                                       padding_right=2
                                       background.height=$ICON_PILL_HEIGHT
                                       background.corner_radius=$ICON_PILL_RADIUS
                                       label.y_offset=-1
                                       background.drawing=off
                                       icon.drawing=off
                                       ${display:+associated_display=$display})
}

# space_order <spaces_json> — space.N space_icons.N for every space
space_order() {
    echo "$1" | jq -r '[.[] | "space.\(.index) space_icons.\(.index)"] | join(" ")'
}

# space_control_items <spaces_json> — the per-display "−" "+" buttons. They
# share one slot (after front_app); each pair draws only on its own display.
space_control_items() {
    echo "$1" | jq -r '[.[].display] | unique | map("space_remove.\(.) space_add.\(.)") | join(" ")'
}

# space_bracket_args <space items> <control items> <sids...> — appends to BRACKET_ARGS the
# sketchybar args for the left pill (PILL LEVEL 1) and each space's capsule
# (PILL LEVEL 2; plugins/space.sh decides which capsule draws)
space_bracket_args() {
    local items=$1 control_items=$2 sid; shift 2
    BRACKET_ARGS+=(--add bracket left_bracket left_edge $items space_separator front_app $control_items yabai_mode left_end
                   --set left_bracket background.color=$PILL_COLOR_1
                                      background.height=$PILL_HEIGHT
                                      background.corner_radius=$PILL_RADIUS
                                      y_offset=${Y_OFFSET:-0})
    for sid in "$@"; do
        BRACKET_ARGS+=(--add bracket space_${sid}_bracket space.$sid space_icons.$sid
                       --set space_${sid}_bracket background.color=$PILL_COLOR_3
                                                  background.height=$CAPSULE_HEIGHT
                                                  background.corner_radius=$CAPSULE_RADIUS
                                                  y_offset=${Y_OFFSET:-0})
    done
}
