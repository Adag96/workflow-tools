#!/bin/bash

# Now Playing widget: its own pill on the right, just left of the right pill (next
# to volume). Shows the album artwork (or the source app's icon), the song and
# artist (styled apart, no separator), and prev / play-pause / next. Hidden unless
# something is playing; plugins/media.sh (a long-running watcher) drives it.

# Get the machine name
MACHINE_NAME=$(scutil --get ComputerName)

# Characters shown before the song / artist start scrolling
if [[ "$MACHINE_NAME" == *"Studio"* ]]; then
    TITLE_CHARS=22; ARTIST_CHARS=16
else
    TITLE_CHARS=16; ARTIST_CHARS=12  # MacBook Pro
fi

EQ_BAR_WIDTH=3                 # equalizer bar width (px)

MEDIA_ITEMS="media_gap media_start media.app media.title media.artist media.eq.1 media.eq.2 media.eq.3 media.eq.4 media.prev media.play media.next media_end"

# Right-side items are added right-to-left: gap to the right pill first, then the
# pill's contents from its right end to its left end.
sketchybar --add item media_gap right \
           --set media_gap width=$PILL_GAP padding_left=0 padding_right=0 \
                           icon.drawing=off label.drawing=off background.drawing=off
pill_edge media_end right

# Controls: touching 26px circles (hover = a circle, the last one concentric with the
# pill's rounded end). Play/pause is the primary action, so prev/next are a size down.
# Collapsed: just artwork, title and artist. Hovering anywhere on the widget expands
# back / play-pause / skip (plugins/media_hover.sh); the pill grows leftward.
media_button=(
  icon.width=$((CAPSULE_HEIGHT - 2))              # SF Symbols sit ~1pt right: centre in 24 +
  icon.align=center                               # 2pt right pad = optically centred in the
  icon.padding_left=0                             # 26px hover circle
  icon.padding_right=2
  icon.color=$ICON_COLOR
  label.drawing=off
  padding_left=0
  padding_right=0
  background.color=$PILL_COLOR_4
  background.height=$CAPSULE_HEIGHT
  background.corner_radius=$CAPSULE_RADIUS
  background.drawing=off                          # last: setting a color re-enables drawing
  script="$PLUGIN_DIR/media_hover.sh"
)
# Right side is added right-to-left: skip, play/pause, back (all start collapsed)
collapsed_button=(icon.width=0 icon.padding_right=0 icon.color=0x00000000)
sketchybar --add item media.next right \
           --set media.next "${media_button[@]}" "${collapsed_button[@]}" icon=􀊌 \
                 icon.font="$ICON_FONT:Semibold:$FONT_SIZE_SECONDARY.0" \
                 click_script="media-control next-track" \
           --add item media.play right \
           --set media.play "${media_button[@]}" "${collapsed_button[@]}" icon=􀊆 \
                 icon.font="$ICON_FONT:Semibold:$FONT_SIZE_TEXT.0" \
                 click_script="media-control toggle-play-pause" \
           --add item media.prev right \
           --set media.prev "${media_button[@]}" "${collapsed_button[@]}" icon=􀊊 \
                 icon.font="$ICON_FONT:Semibold:$FONT_SIZE_SECONDARY.0" \
                 click_script="media-control previous-track"

# Fake equalizer (plugins/media_eq.sh): 4 thin bars at the collapsed pill's right end —
# bouncing while playing, still while paused, hidden while the controls are expanded.
# Added right-to-left: bar 4 first; the last bar's right padding + media_end = the
# artist's 9px on the other side. Bars are sized by an empty icon, not `width`
# (a fixed item width swallows the padding that spaces the bars).
for n in 4 3 2 1; do
  pad_l=2; pad_r=0
  [ $n = 1 ] && pad_l=0
  [ $n = 4 ] && pad_r=$((ITEM_PAD - PILL_EDGE))
  sketchybar --add item media.eq.$n right \
             --set media.eq.$n icon="" icon.width=$EQ_BAR_WIDTH icon.padding_left=0 icon.padding_right=0 \
                   label.drawing=off \
                   padding_left=$pad_l padding_right=$pad_r \
                   background.drawing=on background.color=$RIGHT_TEXT_COLOR \
                   background.height=4 background.corner_radius=1
done

# Song (Semibold 15) and artist (Regular 13, on the song's baseline): size + weight
# carry the hierarchy, same color — the subtle tone would read as "inactive"
sketchybar --add item media.artist right \
           --set media.artist icon.drawing=off \
                 label.font="$TEXT_FONT:Regular:$FONT_SIZE_SECONDARY.0" \
                 label.color=$RIGHT_TEXT_COLOR \
                 label.y_offset=$((GLYPH_LIFT - 1)) \
                 label.max_chars=$ARTIST_CHARS \
                 scroll_texts=on \
                 padding_left=$PADDING_S

sketchybar --add item media.title right \
           --set media.title icon.drawing=off \
                 label.color=$RIGHT_TEXT_COLOR \
                 label.max_chars=$TITLE_CHARS \
                 scroll_texts=on \
                 padding_left=0 \
                 padding_right=0

sketchybar --add item media.app right \
           --set media.app icon=":default:" \
                 icon.font="sketchybar-app-font:Regular:$FONT_SIZE_TEXT.0" \
                 icon.color=$RIGHT_TEXT_COLOR \
                 label.drawing=off \
                 padding_right=0
pill_edge media_start right

sketchybar --add bracket media_bracket media_start media.app media.title media.artist media.eq.1 media.eq.2 media.eq.3 media.eq.4 media.prev media.play media.next media_end \
           --set media_bracket background.color=$PILL_COLOR_1 \
                               background.height=$PILL_HEIGHT \
                               background.corner_radius=$PILL_RADIUS

# The whole widget is one hover zone (media_hover.sh keeps it open while the pointer
# moves between its parts, and collapses it ~⅓s after leaving)
for item in media_start media.app media.title media.artist media.eq.1 media.eq.2 media.eq.3 media.eq.4 media.prev media.play media.next media_end; do
  sketchybar --set "$item" script="$PLUGIN_DIR/media_hover.sh" \
             --subscribe "$item" mouse.entered mouse.exited
done

# Hidden until something plays
for item in $MEDIA_ITEMS media_bracket; do sketchybar --set "$item" drawing=off; done

# One watcher per config load: kill the previous one AND its children (the
# media-control reader is a perl process that would otherwise survive as an orphan)
WATCHER_PID=/tmp/sketchybar_media_watcher.pid
if [ -f "$WATCHER_PID" ]; then
  old=$(cat "$WATCHER_PID")
  pkill -P "$old" 2>/dev/null
  kill "$old" 2>/dev/null
fi
# ...the equalizer loop...
[ -f /tmp/sketchybar_media_eq.pid ] && kill "$(cat /tmp/sketchybar_media_eq.pid)" 2>/dev/null
rm -f /tmp/sketchybar_media_eq.pid
# ...and a pending pause→hide timer, which would otherwise hide the new widget
[ -f /tmp/sketchybar_media_hide.pid ] && kill "$(cat /tmp/sketchybar_media_hide.pid)" 2>/dev/null
rm -f /tmp/sketchybar_media_hide.pid
( "$PLUGIN_DIR/media.sh" >/dev/null 2>&1 & )
