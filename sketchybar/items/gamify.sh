#!/bin/bash

# Gamify Timer widget: a centered pill listing every running/paused Pomodoro across
# all Brave profiles — "<tag> 18m" plus a pause/resume button that controls that
# profile's timer.
# Data flow: extension (each profile) → gamify-timer/host.py → one JSON per profile
# in ~/.cache/sketchybar/gamify/ → plugins/gamify.sh. Button clicks go back the other
# way via ~/.cache/sketchybar/gamify/cmd/<profile> (see host.py listen_commands).
# Hidden when nothing is running.

GAMIFY_SLOTS=3
export GAMIFY_TIME_WIDTH=$((FONT_SIZE_TEXT * 12 / 5 + 2))  # 38px: "88m" + 2 → time↔button gap ≈ GAP_ICON_LABEL (100m+ goes dynamic)
export GAMIFY_PAUSE_WIDTH=$GAMIFY_TIME_WIDTH            # 38px for "8:08"; +8 per extra char ("+" / 10m+)
export GAMIFY_PAUSE_ICON_WIDTH=18                         # hourglass and ⚠ take identical space
# The pause section opens/closes by animating its icon.width, icon.padding_right,
# label.width and padding_left between 0 and these values (plugins/gamify.sh).
# Not the item's `width`: text overflowing a 0-width item still stretches the pill.

sketchybar --add event gamify_update    # host.py triggers this on every timer change

# Pause/resume buttons: 26px circles, same as the media controls
gamify_button=(
  icon.font="$ICON_FONT:Semibold:$FONT_SIZE_TEXT.0"   # same as the media play/pause
  icon.width=$((CAPSULE_HEIGHT - 2))              # SF Symbols sit ~1pt right of centre:
  icon.align=center                               # centre in 24 + 2pt right pad = optically
  icon.padding_left=0                             # centred in the 26px hover circle
  icon.padding_right=2
  icon.color=$ICON_COLOR
  label.drawing=off
  padding_left=0
  padding_right=0
  background.color=$PILL_COLOR_4
  background.height=$CAPSULE_HEIGHT
  background.corner_radius=$CAPSULE_RADIUS
  background.drawing=off                          # last: setting a color re-enables drawing
  script="$PLUGIN_DIR/hover.sh"
)

# Center items are laid out in the order they're added (left → right)
pill_edge gamify_start center
members="gamify_start"
for n in $(seq 1 $GAMIFY_SLOTS); do
  sketchybar --add item gamify.$n center \
             --set gamify.$n icon="$TODO_TIMER_ICON" \
                   icon.color=$ACCENT_COLOR \
                   label.color=$RIGHT_TEXT_COLOR \
                   label.padding_right=$GAP_ICON_LABEL \
                   padding_right=0 \
             --add item gamify.$n.time center \
             --set gamify.$n.time icon.drawing=off \
                   label.color=$RIGHT_TEXT_COLOR \
                   label.width=$GAMIFY_TIME_WIDTH \
                   label.align=left \
                   padding_left=0 \
                   padding_right=0 \
             --add item gamify.$n.pause center \
             --set gamify.$n.pause icon="􀖇" \
                   icon.width=0 \
                   icon.padding_right=0 \
                   icon.color=0x00000000 \
                   label.color=0x00000000 \
                   label.width=0 \
                   label.align=left \
                   padding_left=0 \
                   padding_right=0 \
             --add item gamify.$n.btn center \
             --set gamify.$n.btn "${gamify_button[@]}" \
             --subscribe gamify.$n.btn mouse.entered mouse.exited
  members+=" gamify.$n gamify.$n.time gamify.$n.pause gamify.$n.btn"
done
pill_edge gamify_end center
members+=" gamify_end"

sketchybar --add bracket gamify_bracket $members \
           --set gamify_bracket background.color=$PILL_COLOR_1 \
                                background.height=$PILL_HEIGHT \
                                background.corner_radius=$PILL_RADIUS

for item in $members gamify_bracket; do sketchybar --set "$item" drawing=off; done

# Hidden driver (hidden items don't run scripts, so the visible ones can't host it).
# Every 10s keeps the minutes current (every 1s while paused — plugins/gamify.sh
# switches it for the pause countdown); gamify_update makes changes instant.
sketchybar --add item gamify_watcher center \
           --set gamify_watcher drawing=off updates=on update_freq=10 \
                 script="$PLUGIN_DIR/gamify.sh" \
           --subscribe gamify_watcher gamify_update system_woke
