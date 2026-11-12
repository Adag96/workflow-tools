#!/bin/bash
# The bar's "−" button: destroy the space currently shown on display $1.
# Its windows aren't closed — macOS moves them to a neighbouring space.
# yabai refuses to destroy a display's last space or a native-fullscreen space.
sid=$(yabai -m query --spaces --display "$1" 2>/dev/null | jq -r '.[] | select(."is-visible") | .index')
[ -n "$sid" ] && yabai -m space --destroy "$sid"
