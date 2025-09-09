#!/bin/bash

# Hard-coded to only support 4 spaces maximum
SPACE_SIDS=(1 2 3 4)

for sid in "${SPACE_SIDS[@]}"
do
   # Create the space number item
   sketchybar --add space space.$sid left \
              --set space.$sid space=$sid \
                               icon=$sid \
                               label.drawing=off \
                               script="$PLUGIN_DIR/space.sh"
   
   # Create a separate item for space icons
   sketchybar --add item space_icons.$sid left \
              --set space_icons.$sid label.font="sketchybar-app-font:Regular:$FONT_SIZE_MEDIUM.0" \
                                    label.padding_right=$PADDING_M \
                                    label.padding_left=$PADDING_M \
                                    label.y_offset=-1 \
                                    background.drawing=off \
                                    icon.drawing=off
done

sketchybar --add item space_separator left \
          --set space_separator icon=">" \
                               icon.color=$LEFT_ITEM_COLOR \
                               icon.padding_left=4 \
                               label.drawing=off \
                               background.drawing=off \
                               script="$PLUGIN_DIR/space_windows.sh" \
          --subscribe space_separator space_windows_change