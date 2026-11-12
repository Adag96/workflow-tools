#!/bin/bash
# Media widget hover: the whole pill is one hover zone.
#   Enter any part → expand back / play-pause / skip (the pill grows leftward; it's
#   anchored on the right) and hide the equalizer.
#   Leave a part   → start a collapse watch that only collapses once the CURSOR is
#   actually outside the pill's bounds. Per-item enter/exit events alone are unreliable:
#   they arrive as separate, racing processes, and the gaps between items belong to no
#   item at all — so the pill used to collapse under a cursor that never left it.
# Every state change is a single sketchybar call, so a cancelled watch can never leave a
# half-collapsed state. Stock bash 3.2.

source "$CONFIG_DIR/items/scheme.sh"       # TEXT_COLOR (= ICON_COLOR)
COLOR=$TEXT_COLOR
CLEAR=0x00000000
BTN_W=$(( ${CAPSULE_HEIGHT:-26} - 2 ))
BAR_H=${HEIGHT_L1:-44}
WATCH=/tmp/sketchybar_media_collapse.pid
STRETCH=10                                  # frames (60fps)
BUTTONS="media.prev media.play media.next"
EQ_BARS="media.eq.1 media.eq.2 media.eq.3 media.eq.4"
ICON_PAUSE="􀊆"                              # pause.fill = music is playing

is_button() { case " $BUTTONS " in *" $1 "*) return 0 ;; esac; return 1; }
expanded()  { [ "$(sketchybar --query media.play | jq -r '.icon.width')" -gt 0 ] 2>/dev/null; }
cancel_watch() { [ -f "$WATCH" ] && kill "$(cat "$WATCH")" 2>/dev/null; rm -f "$WATCH"; }

# Is the mouse inside the media pill on any display? (global coords, top-left origin)
cursor_in_pill() {
  local boxes pos
  boxes=$(sketchybar --query media_bracket | jq -r '.bounding_rects[] | [.origin[0], .origin[0] + .size[0], .origin[1], .origin[1] + .size[1]] | @tsv')
  # osascript can hang on stalled Apple Events: alarm-killed after 2s (→ treated as outside)
  pos=$(perl -e 'alarm 2; exec @ARGV' osascript -l JavaScript -e \
    'ObjC.import("AppKit"); var p = $.NSEvent.mouseLocation;
     var h = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
     Math.round(p.x) + " " + Math.round(h - p.y)' 2>/dev/null)
  [ -n "$pos" ] || return 1
  echo "$boxes" | awk -v p="$pos" 'BEGIN { split(p, m, " ") }
    m[1] >= $1 && m[1] <= $2 && m[2] >= $3 && m[2] <= $4 { hit = 1 }
    END { exit !hit }'
}

state_args() {   # $1 = expanded|collapsed → one sketchybar argument list for everything
  local a=() b
  if [ "$1" = expanded ]; then
    for b in $BUTTONS; do a+=(--set $b icon.width=$BTN_W icon.padding_right=2 icon.color=$COLOR); done
    for b in $EQ_BARS; do a+=(--set $b drawing=off); done
  else
    for b in $BUTTONS; do a+=(--set $b icon.width=0 icon.padding_right=0 icon.color=$CLEAR background.drawing=off); done
    # Bars only come back if the widget itself is showing (else they'd float on their own)
    if [ "$(sketchybar --query media_bracket | jq -r '.geometry.drawing')" = on ]; then
      for b in $EQ_BARS; do a+=(--set $b drawing=on); done
    fi
  fi
  echo "${a[@]}"
}

case "$SENDER" in
  mouse.entered)
    cancel_watch
    if ! expanded; then
      "$CONFIG_DIR/plugins/media_eq.sh" stop          # bars give way to the buttons
      # shellcheck disable=SC2046
      sketchybar --animate tanh $STRETCH $(state_args expanded)
    fi
    is_button "$NAME" && sketchybar --set "$NAME" background.drawing=on
    ;;
  mouse.exited)
    is_button "$NAME" && sketchybar --set "$NAME" background.drawing=off
    cancel_watch
    (
      # Poll the real cursor; collapse the moment it's outside the pill (≤ 60s watch —
      # the next enter/exit event starts a fresh one)
      for _ in $(seq 1 200); do
        sleep 0.3
        if ! cursor_in_pill; then
          # shellcheck disable=SC2046
          sketchybar --animate tanh $STRETCH $(state_args collapsed)
          # Bars bounce again only if music is playing (play/pause shows ⏸ then)
          [ "$(sketchybar --query media.play | jq -r '.icon.value')" = "$ICON_PAUSE" ] \
            && "$CONFIG_DIR/plugins/media_eq.sh" start
          break
        fi
      done
      rm -f "$WATCH"
    ) &
    echo $! > "$WATCH"
    ;;
esac
