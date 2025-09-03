#!/bin/bash

# Add volume slider first, then icon (so icon appears on left of slider)
sketchybar --add slider volume right \
           --set volume \
             script="$PLUGIN_DIR/volume.sh" \
             updates=on \
             label.drawing=off \
             icon.drawing=off \
             slider.highlight_color=$ACCENT_COLOR \
             slider.background.height=5 \
             slider.background.corner_radius=3 \
             slider.background.color=0x60ffffff \
             slider.knob=􀀁 \
             slider.knob.color=$ACCENT_COLOR \
             slider.knob.drawing=off \
             slider.width=0 \
             padding_left=0 \
             padding_right=5 \
           --subscribe volume volume_change mouse.entered mouse.exited mouse.clicked \
           \
           --add item volume_icon right \
           --set volume_icon \
             icon.font="$ICON_FONT:Regular:17.0" \
             icon.color=$RIGHT_TEXT_COLOR \
             label.drawing=off \
             click_script="$PLUGIN_DIR/volume_click.sh" \
             script="$PLUGIN_DIR/volume.sh" \
             padding_left=5 \
             padding_right=3 \
           --subscribe volume_icon volume_change