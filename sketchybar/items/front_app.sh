#!/bin/bash

source "$CONFIG_DIR/fonts.sh"  # Loads all defined fonts

# padding_right=0: the yabai layout button hugs this pill (its hover capsule sits
# PILL_EDGE from it, the same gap as every other capsule nesting)

sketchybar --add item front_app left \
           --set front_app      background.color=$PILL_COLOR_4 \
                                background.height=$CAPSULE_HEIGHT \
                                background.corner_radius=$CAPSULE_RADIUS \
                                icon.color=$ACCENT_COLOR \
                                icon.font="sketchybar-app-font:Regular:$FONT_SIZE_TEXT.0" \
                                label.font="$TEXT_FONT:Semibold:$FONT_SIZE_TEXT.0"\
                                label.color=$LEFT_TEXT_COLOR \
                                icon.padding_left=$((PADDING_M + 2)) \
                                label.padding_right=$((PADDING_M + 2)) \
                                padding_right=0 \
                                associated_display=active \
                                script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched