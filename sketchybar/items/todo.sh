#!/bin/bash

# Add todo list item
sketchybar --add item todo right \
           --set todo \
             icon="$TODO_ICON" \
             icon.font="$ICON_FONT:Semibold:$FONT_SIZE_LARGE.0" \
             icon.color=$RIGHT_TEXT_COLOR \
             icon.padding_left=8 \
             icon.padding_right=4 \
             label.drawing=off \
             label.font="$TEXT_FONT:Semibold:$FONT_SIZE_SMALL.0" \
             label.color=$RIGHT_TEXT_COLOR \
             label.padding_left=2 \
             label.padding_right=8 \
             background.drawing=off \
             click_script="$PLUGIN_DIR/todo_click.sh" \
             script="$PLUGIN_DIR/todo.sh" \
             update_freq=1