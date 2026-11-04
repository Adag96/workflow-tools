#!/bin/bash
# Gamify start menu. Clicking the idle balance:
#   1. stretches the pill right into a length carousel  20 · 25m · 30  — the chosen
#      length in primary type, its neighbours (10…60, wrapping) smaller either side;
#      clicking a neighbour steps to it; a horizontal swipe/scroll over the pill spins
#      it (gamify_scroll helper, running only while the menu is open). The last used
#      length is remembered. Then
#   2. opens the tag list as a folder tab: the pressed balance capsule grows down through
#      the pill's bottom edge into the tag panel (popup on gamify.1, same colour), which
#      spans the pill's inner width.
# Clicking a tag starts the session with the shown length. Tag rows are rebuilt on every
# open, so tags edited in the extension show up.
#   gamify_menu.sh toggle | close | step <±1> | spin <±n> | start <tag> | is_open
#   check                     close if the cursor is outside the pill + tag list
#   (and mouse.exited.global, via gamify_start)
# Stock bash 3.2.

source "$CONFIG_DIR/items/scheme.sh"   # TEXT_COLOR, PILL_COLOR_3
source "$CONFIG_DIR/fonts.sh"          # TEXT_FONT, ICON_FONT

CTL="$HOME/workflow-tools/gamify-timer/gamifyctl"
LAST="$HOME/.cache/sketchybar/gamify/last_minutes"
SPINNER="$HOME/.cache/sketchybar/gamify/gamify_scroll"   # built by items/gamify.sh
SPINNER_PID=/tmp/sketchybar_gamify_scroll.pid
LENGTHS=(10 15 20 25 30 45 60)
DOT="􀀁"                                  # circle.fill, in the tag's own colour
CLEAR=0x00000000
EDGE=${PILL_EDGE:-3}
GAP=${GAP_ICON_LABEL:-8}
NEIGHBOUR_W=${CAPSULE_HEIGHT:-26}             # a 26px hover circle around "10"…"60"
VALUE_W=$(( ${FONT_SIZE_TEXT:-15} * 2 + 12 ))  # 42px: widest value "60m" (32) + 5 air each side
TAB_PAD=${PILL_EDGE:-3}                        # panel inset = the capsules' inset in the pill
STRETCH=12                                     # frames (60fps), same as the session open
FADE=8
SWAP=5                                         # carousel step crossfade (frames, each way)

last_minutes() {
  local m; m=$(cat "$LAST" 2>/dev/null)
  case " ${LENGTHS[*]} " in *" $m "*) echo "$m" ;; *) echo 25 ;; esac
}
is_open() { [ "$(sketchybar --query gamify.step.value | jq -r '.label.width')" -gt 0 ] 2>/dev/null; }
neighbour() {   # $1 minutes, $2 ±n → the length that many steps away (wrapping)
  local i n=${#LENGTHS[@]} idx=0
  for i in "${!LENGTHS[@]}"; do [ "${LENGTHS[$i]}" = "$1" ] && idx=$i; done
  echo "${LENGTHS[$(( ((idx + $2) % n + n) % n ))]}"
}
carousel_text() {   # $1 minutes → the three labels
  echo "--set gamify.step.prev label=$(neighbour "$1" -1) --set gamify.step.value label=${1}m --set gamify.step.next label=$(neighbour "$1" 1)"
}
idle()    { [ "$(sketchybar --query gamify.1.btn | jq -r '.icon.width')" = 0 ]; }   # no session shown

# Carousel geometry: neighbour circles either side of the value box
STEP_OPEN="--set gamify.step.prev padding_left=$EDGE label.width=$NEIGHBOUR_W --set gamify.step.value label.width=$VALUE_W --set gamify.step.next label.width=$NEIGHBOUR_W"
STEP_CLOSED="--set gamify.step.prev padding_left=0 label.width=0 background.drawing=off --set gamify.step.value label.width=0 --set gamify.step.next label.width=0 background.drawing=off"
STEP_SHOWN="--set gamify.step.prev label.color=$TEXT_COLOR --set gamify.step.value label.color=$TEXT_COLOR --set gamify.step.next label.color=$TEXT_COLOR"
STEP_HIDDEN="--set gamify.step.prev label.color=$CLEAR --set gamify.step.value label.color=$CLEAR --set gamify.step.next label.color=$CLEAR"

# The tab: the capsule's bottom pushed past the bar's bottom edge (clipped there), so it
# reads square-bottomed and runs into the panel; its top stays where it was
TAB_OPEN="--set gamify.1 background.height=${MENU_TAB_HEIGHT:-50} background.y_offset=${MENU_TAB_OFFSET:--12} background.drawing=on"
TAB_CLOSED="--set gamify.1 background.height=${CAPSULE_HEIGHT:-26} background.y_offset=0 background.drawing=off"

show_tags() {   # one row per tag, spanning the pill's inner width
  local args=() i=0 name color pill_w
  pill_w=$(sketchybar --query gamify_bracket | jq -r '[.bounding_rects[]][0].size[0] | floor')
  sketchybar --remove '/gamify\.tag\..*/' 2>/dev/null   # (errors when there are none yet)
  while IFS=$'\t' read -r name color; do
    [ -z "$name" ] && continue
    i=$((i + 1))
    args+=(--add item gamify.tag.$i popup.gamify.1
           --set gamify.tag.$i width=$((pill_w - 2 * TAB_PAD - 2 * EDGE))
                 padding_left=$EDGE padding_right=$EDGE
                 icon="$DOT" icon.color="$color"
                 icon.font="$ICON_FONT:Semibold:$((${FONT_SIZE_SECONDARY:-13} - 3)).0"
                 icon.padding_left=$((GAP + 2)) icon.padding_right=0
                 label="$name" label.color=$TEXT_COLOR
                 label.font="$TEXT_FONT:Semibold:${FONT_SIZE_TEXT:-15}.0"
                 label.padding_left=$GAP
                 background.color=$PILL_COLOR_3
                 background.height=${CAPSULE_HEIGHT:-26}
                 background.corner_radius=$(( ${MENU_RADIUS:-6} - EDGE ))
                 background.drawing=off
                 script="$CONFIG_DIR/plugins/hover.sh"
                 click_script="$0 start $(printf '%q' "$name")"
           --subscribe gamify.tag.$i mouse.entered mouse.exited)
  done < <("$CTL" tags 2>/dev/null | jq -r '.[] | [.name, ("0xff" + ((.color // "#6C5CE7") | ltrimstr("#")))] | @tsv')
  sketchybar "${args[@]}" --set gamify.1 popup.drawing=on
}

open_menu() {
  # shellcheck disable=SC2086
  sketchybar $(carousel_text "$(last_minutes)") \
             --animate tanh $STRETCH $STEP_OPEN $TAB_OPEN
  sleep 0.22                                  # let the pill finish stretching
  show_tags
  # shellcheck disable=SC2086
  sketchybar --animate linear $FADE $STEP_SHOWN
  start_spinner
}

start_spinner() {   # horizontal swipe → spin (sketchybar can't see horizontal scroll)
  stop_spinner
  [ -x "$SPINNER" ] || return 0
  local span
  span=$(sketchybar --query gamify_bracket | jq -r '[.bounding_rects[]][0] | "\(.origin[0]) \(.origin[0] + .size[0])"')
  # shellcheck disable=SC2086
  "$SPINNER" "$0" $span "${HEIGHT_L1:-44}" >/dev/null 2>&1 &
  echo $! > "$SPINNER_PID"
}
stop_spinner() {
  [ -f "$SPINNER_PID" ] && kill "$(cat "$SPINNER_PID")" 2>/dev/null
  rm -f "$SPINNER_PID"
}

close_menu() {
  stop_spinner
  # shellcheck disable=SC2086
  sketchybar --set gamify.1 popup.drawing=off $TAB_CLOSED \
             --animate linear $FADE $STEP_HIDDEN
  sleep 0.14
  # shellcheck disable=SC2086
  sketchybar --animate tanh $STRETCH $STEP_CLOSED
}

# Is the mouse over the pill or the tag list? (one box: the pill's x-range, from the
# bar's top down to the last tag row; bar coordinates, top-left origin)
cursor_in_menu() {
  local box pos last bottom
  box=$(sketchybar --query gamify_bracket | jq -r '[.bounding_rects[]][0] | "\(.origin[0]) \(.origin[0] + .size[0])"')
  last=$(sketchybar --query gamify.1 | jq -r '.popup.items | last // empty')
  bottom=$( [ -n "$last" ] && sketchybar --query "$last" | jq -r '[.bounding_rects[]][0] | .origin[1] + .size[1]')
  pos=$(perl -e 'alarm 2; exec @ARGV' osascript -l JavaScript -e \
    'ObjC.import("AppKit"); var p = $.NSEvent.mouseLocation;
     var h = $.NSScreen.screens.objectAtIndex(0).frame.size.height;
     Math.round(p.x) + " " + Math.round(h - p.y)' 2>/dev/null)
  [ -n "$pos" ] || return 1
  awk -v b="$box" -v p="$pos" -v bot="${bottom:-${HEIGHT_L1:-44}}" 'BEGIN {
    split(b, x, " "); split(p, m, " ")
    exit !(m[1] >= x[1] && m[1] <= x[2] && m[2] >= 0 && m[2] <= bot)
  }'
}

case "${1:-$SENDER}" in
  toggle)
    if is_open; then close_menu; elif idle; then open_menu; fi ;;
  close)
    close_menu ;;
  step)   # turn the carousel one step (the clicked neighbour becomes the value)
    new=$(neighbour "$(last_minutes)" "$2")
    echo "$new" > "$LAST"
    # shellcheck disable=SC2086
    sketchybar --animate linear $SWAP $STEP_HIDDEN
    sleep 0.09
    # shellcheck disable=SC2046,SC2086
    sketchybar $(carousel_text "$new") --animate linear $SWAP $STEP_SHOWN ;;
  spin)   # from the swipe helper: turn n notches at once, no fade (it may be spinning fast)
    new=$(neighbour "$(last_minutes)" "$2")
    echo "$new" > "$LAST"
    # shellcheck disable=SC2046
    sketchybar $(carousel_text "$new") ;;
  is_open)
    is_open ;;
  start)
    "$CTL" start "$(last_minutes)" "$2" >/dev/null   # the widget opens on the engine's trigger
    close_menu ;;
  mouse.exited.global|check)
    # exited.global fires when the cursor leaves the bar or the tag list — including
    # crossing between them; `check` comes from hover.sh when it leaves the balance or a
    # carousel neighbour (e.g. sliding along the bar). Close only once it's outside both.
    is_open || exit 0
    sleep 0.3
    cursor_in_menu || close_menu ;;
esac
