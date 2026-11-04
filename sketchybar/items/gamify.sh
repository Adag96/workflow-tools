#!/bin/bash

# Gamify Timer widget: its own pill, just right of the left pill.
#   Idle  — the credit balance ("1642 FC") as one 26px hover capsule; clicking it opens
#           the start menu (length carousel + tag list, plugins/gamify_menu.sh).
#   Active — while the session runs/is paused, it animates open into
#            "<tag> <minutes left> [pause countdown] [pause/resume]", grown out of the
#            clock button itself.
# Primary text (balance / tag) Semibold 15, secondary ("FC" / minutes left) Regular 13 on
# the same baseline — the media widget's song/artist pairing.
# Data flow: the Gamify engine (gamify-timer/gamify_engine.py, a LaunchAgent) owns the one
# session shared by every browser profile; it mirrors it to
# ~/.cache/sketchybar/gamify/session.json and triggers gamify_update → plugins/gamify.sh.
# Buttons talk back through gamify-timer/gamifyctl.
#
# Everything animates via icon.width / label.width / paddings, never `width`: a
# collapsed item must report a 0 bounding rect or it still stretches the left pill.

export GAMIFY_TIME_WIDTH=$((FONT_SIZE_SECONDARY * 2 + 7))  # 33px: "88m" (27, Regular 13) + 6 → time↔button gap ≈ GAP_ICON_LABEL (100m+ goes dynamic)
export GAMIFY_PAUSE_WIDTH=$((FONT_SIZE_TEXT * 12 / 5 + 2)) # 38px for "8:08"; +8 per extra char ("+" / 10m+)
export GAMIFY_PAUSE_ICON_WIDTH=18                         # hourglass and ⚠ take identical space
export GAMIFY_BUTTON_WIDTH=$((CAPSULE_HEIGHT - 2))        # pause/resume button glyph box
export GAMIFY_INSET=10                                    # idle: text ↔ balance capsule ends
CLEAR=0x00000000

sketchybar --add event gamify_update    # host.py triggers this on every timer change

# Pause/resume button: a 26px circle, same as the media controls (start collapsed)
gamify_button=(
  icon.font="$ICON_FONT:Semibold:$FONT_SIZE_TEXT.0"   # same as the media play/pause
  icon.width=0                                    # open: GAMIFY_BUTTON_WIDTH (SF Symbols sit ~1pt
  icon.align=center                               # right: centre in 24 + 2pt right pad = optically
  icon.padding_left=0                             # centred in the 26px hover circle)
  icon.padding_right=0                            # open: 2
  icon.color=$CLEAR
  label.drawing=off
  padding_left=0
  padding_right=0
  background.color=$PILL_COLOR_4
  background.height=$CAPSULE_HEIGHT
  background.corner_radius=$CAPSULE_RADIUS
  background.drawing=off                          # last: setting a color re-enables drawing
  script="$PLUGIN_DIR/hover.sh"
)

# Closed state shared by the text/icon parts
collapsed=(icon.width=0 icon.padding_left=0 icon.padding_right=0
           label.width=0 label.padding_left=0 label.padding_right=0
           icon.color=$CLEAR label.color=$CLEAR padding_left=0 padding_right=0)

# Own pill: PILL_GAP from the left pill (same as media ↔ right pill), then the contents
sketchybar --add item gamify_gap left \
           --set gamify_gap width=$PILL_GAP padding_left=0 padding_right=0 \
                            icon.drawing=off label.drawing=off background.drawing=off
pill_edge gamify_start left
# Start menu (plugins/gamify_menu.sh): clicking the balance stretches the pill right into
# a length carousel (20 · 25m · 30, below) and opens the tag list as a folder tab hanging
# from the balance capsule (popup on gamify.1, left-aligned; see MENU_RADIUS in the rc).
sketchybar --set gamify_start script="$PLUGIN_DIR/gamify_menu.sh" \
           --subscribe gamify_start mouse.exited.global

# The button: balance (idle) or clock + tag (session). Idle, the icon is empty and its
# box is just the capsule's left inset; in a session it's the 26px clock circle. The clock is
# drawn from SF Pro (which carries the SF Symbols glyphs): there it sits 0.5px right of
# centre vs 1px in the SF Symbols font, and sketchybar offers no x-offset/padding fix
# inside a fixed-width icon box.
sketchybar --add item gamify.1 left \
           --set gamify.1 "${hover_button[@]}" \
                 icon="" \
                 icon.font="$TEXT_FONT:Semibold:$FONT_SIZE_TEXT.0" \
                 icon.color=$ICON_COLOR \
                 icon.width=$GAMIFY_INSET icon.align=center \
                 icon.padding_left=0 icon.padding_right=0 \
                 label.width=0 label.padding_left=0 label.padding_right=0 \
                 label.color=$CLEAR \
                 padding_left=0 padding_right=0 \
                 script="$PLUGIN_DIR/hover.sh" \
                 click_script="$PLUGIN_DIR/gamify_menu.sh toggle" \
                 popup.align=left popup.height=$PILL_HEIGHT \
                 popup.y_offset=-$(((HEIGHT_L1 - PILL_HEIGHT) / 2)) \
                 popup.background.drawing=on popup.background.color=$PILL_COLOR_4 \
                 popup.background.corner_radius=$MENU_RADIUS \
           --subscribe gamify.1 mouse.entered mouse.exited
# Swipe-to-spin helper for the carousel (see plugins/gamify_scroll.swift); rebuilt in the
# background whenever the source is newer than the binary. Needs swiftc (Xcode CLT).
GAMIFY_SPINNER="$HOME/.cache/sketchybar/gamify/gamify_scroll"
if [ ! -x "$GAMIFY_SPINNER" ] || [ "$PLUGIN_DIR/gamify_scroll.swift" -nt "$GAMIFY_SPINNER" ]; then
  ( mkdir -p "$(dirname "$GAMIFY_SPINNER")" &&
    swiftc -O "$PLUGIN_DIR/gamify_scroll.swift" -o "$GAMIFY_SPINNER" ) >/dev/null 2>&1 &
fi

# Length carousel neighbours (start menu): the lengths either side of the chosen one,
# secondary type in a 26px hover circle; clicking one steps to it
gamify_neighbour=(
  icon.drawing=off
  "${collapsed[@]}"
  label.align=center
  label.font="$TEXT_FONT:Regular:$FONT_SIZE_SECONDARY.0"
  label.y_offset=$((GLYPH_LIFT - 1))              # on the centre value's baseline
  background.color=$PILL_COLOR_4
  background.height=$CAPSULE_HEIGHT
  background.corner_radius=$CAPSULE_RADIUS
  background.drawing=off                          # last: setting a color re-enables drawing
  script="$PLUGIN_DIR/hover.sh"
)

# Secondary text: "FC" while idle (drawn inside the balance capsule, so it clicks the
# same menu), minutes left during a session. Then the length carousel (open only while
# the start menu is), the pause countdown and the pause/resume button.
sketchybar --add item gamify.1.time left \
           --set gamify.1.time icon.drawing=off "${collapsed[@]}" label.align=left \
                 label.font="$TEXT_FONT:Regular:$FONT_SIZE_SECONDARY.0" \
                 label.y_offset=$((GLYPH_LIFT - 1)) \
                 click_script="$PLUGIN_DIR/gamify_menu.sh toggle" \
           --add item gamify.step.prev left \
           --set gamify.step.prev "${gamify_neighbour[@]}" \
                 click_script="$PLUGIN_DIR/gamify_menu.sh step -1" \
           --subscribe gamify.step.prev mouse.entered mouse.exited \
           --add item gamify.step.value left \
           --set gamify.step.value icon.drawing=off "${collapsed[@]}" label.align=center \
           --add item gamify.step.next left \
           --set gamify.step.next "${gamify_neighbour[@]}" \
                 click_script="$PLUGIN_DIR/gamify_menu.sh step 1" \
           --subscribe gamify.step.next mouse.entered mouse.exited \
           --add item gamify.1.pause left \
           --set gamify.1.pause icon="􀖇" "${collapsed[@]}" label.align=left \
           --add item gamify.1.btn left \
           --set gamify.1.btn "${gamify_button[@]}" \
           --subscribe gamify.1.btn mouse.entered mouse.exited
GAMIFY_ITEMS="gamify.1 gamify.1.time gamify.step.prev gamify.step.value gamify.step.next gamify.1.pause gamify.1.btn"
pill_edge gamify_end left
export GAMIFY_ITEMS   # gamify pill members + reorder list (sketchybarrc)

sketchybar --add bracket gamify_bracket gamify_start $GAMIFY_ITEMS gamify_end \
           --set gamify_bracket background.color=$PILL_COLOR_1 \
                                background.height=$PILL_HEIGHT \
                                background.corner_radius=$PILL_RADIUS

# Text measurer: zero layout width, transparent, outside any pill. The plugin sets a
# tag on it and reads the rendered width, so a slot can animate open to that exact width.
sketchybar --add item gamify_measure left \
           --set gamify_measure width=0 icon.drawing=off label.color=$CLEAR \
                 label.padding_left=0 label.padding_right=0 padding_left=0 padding_right=0

# Hidden driver (hidden items don't run scripts, so the visible ones can't host it).
# Every 10s keeps the minutes current (every 1s while paused — plugins/gamify.sh
# switches it for the pause countdown); gamify_update makes changes instant.
sketchybar --add item gamify_watcher left \
           --set gamify_watcher drawing=off updates=on update_freq=10 \
                 script="$PLUGIN_DIR/gamify.sh" \
           --subscribe gamify_watcher gamify_update system_woke
