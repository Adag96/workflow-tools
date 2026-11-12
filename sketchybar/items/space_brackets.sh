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

# Left pill + per-space capsules (definitions in space_lib.sh). SPACE_ORDER and
# SPACE_CONTROL_ITEMS (the "−" "+" buttons) come from spaces.sh.
if [ -z "$SPACE_ORDER" ]; then
    for sid in "${SPACE_SIDS[@]}"; do SPACE_ORDER+="space.$sid space_icons.$sid "; done
fi
BRACKET_ARGS=()
space_bracket_args "$SPACE_ORDER" "$SPACE_CONTROL_ITEMS" "${SPACE_SIDS[@]}"
sketchybar "${BRACKET_ARGS[@]}"
