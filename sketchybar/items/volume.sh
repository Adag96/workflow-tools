#!/bin/bash

# Add volume slider first, then icon (so icon appears on left of slider)
sketchybar --add slider volume right \
           --set volume \
             script="$PLUGIN_DIR/volume.sh" \
             updates=on \
             label.drawing=off \
             icon.drawing=off \
             slider.highlight_color=$RIGHT_TEXT_COLOR \
             slider.background.height=5 \
             slider.background.corner_radius=3 \
             slider.background.color=0x60ffffff \
             slider.knob=􀀁 \
             slider.knob.color=$RIGHT_TEXT_COLOR \
             slider.knob.drawing=off \
             slider.width=0 \
             padding_left=0 \
             padding_right=0 \
           --subscribe volume volume_change mouse.entered mouse.exited mouse.clicked \
           \
           --add item volume_icon right \
           --set volume_icon "${hover_button[@]}" \
             icon.y_offset=$((GLYPH_LIFT + 1)) \
             icon.font="$ICON_FONT:Semibold:$FONT_SIZE_TEXT.0" \
             icon.color=$ICON_COLOR \
             label.drawing=off \
             click_script="$PLUGIN_DIR/volume_click.sh" \
             script="$PLUGIN_DIR/volume.sh" \
             update_freq=300 \
           --subscribe volume_icon volume_change mouse.entered mouse.exited