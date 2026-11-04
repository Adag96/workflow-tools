#!/bin/bash
# Gamify Timer widget driver (detached pill after the left pill — see items/gamify.sh).
# Reads the mirrors the Gamify engine writes and animates the pill between:
#   idle    — "<balance> FC" as one button (balance file; red when in debt)
#   session — the clock grown into "<tag> <minutes left>", a pause countdown (animated
#             open while paused) and a pause/resume button (gamifyctl toggle)
# Primary text (balance / tag) is Semibold 15 on gamify.1's label; secondary text
# ("FC" / minutes left) is Regular 13 on gamify.1.time — the media widget's song/artist
# pairing. While idle, gamify.1's icon is empty (its box = the capsule's left inset) and
# "FC" is pulled back inside gamify.1's hover capsule (negative padding into space
# reserved by gamify.1's label.width), so balance + unit read as one button.
# Bounded: local file reads + one jq + a few sketchybar calls (no hang-prone calls),
# and idempotent, so an overlapping run is harmless. Runs under stock bash 3.2.

source "$CONFIG_DIR/items/scheme.sh"   # ACCENT_COLOR, CRITICAL_COLOR, TEXT_COLOR

DIR="$HOME/.cache/sketchybar/gamify"
CTL="$HOME/workflow-tools/gamify-timer/gamifyctl"
ICON_PAUSE="􀊆"            # pause.fill: shown while running (click pauses)
ICON_PLAY="􀊄"             # play.fill:  shown while paused  (click resumes)
ICON_FREE="􀖇"             # hourglass: free pause time left
ICON_PENALTY="􀇿"          # exclamationmark.triangle.fill: pause penalty accruing
SEP=$'\x1f'
CLEAR=0x00000000
BUTTON_COLOR=$TEXT_COLOR   # = ICON_COLOR in sketchybarrc (rc exports don't reach plugins)
PAUSE_COLOR=$CRITICAL_COLOR
PAUSE_CLEAR="0x00${PAUSE_COLOR:4}"

# Geometry (sketchybar doesn't pass rc exports to plugins, hence the defaults)
GAP=${GAP_ICON_LABEL:-8}   # tag ↔ minutes left
UNIT_GAP=4                 # balance ↔ "FC": a word space, it's one value
INSET=${GAMIFY_INSET:-10}  # idle text ↔ the hover capsule's ends
CLOCK_W=${CAPSULE_HEIGHT:-26}
PAD=${ITEM_PAD:-9}
BTN_W=${GAMIFY_BUTTON_WIDTH:-24}
STRETCH=12                 # frames (60fps): the pill stretches, then...
FADE=10                    # ...the content fades in (reverse when closing)

# Pause section open/closed (animating these — not `width` — resizes the pill itself)
PAUSE_OPEN="icon.width=${GAMIFY_PAUSE_ICON_WIDTH:-18} icon.padding_right=$GAP padding_left=$PAD"
PAUSE_CLOSED="icon.width=0 icon.padding_right=0 label.width=0 padding_left=0"
# Text boxes: "88m" / "8:08" fit the base width; each extra character adds 8px
time_width()  { echo $(( ${GAMIFY_TIME_WIDTH:-33}  + 8 * (${#1} - 3) )); }
pause_width() { echo $(( ${GAMIFY_PAUSE_WIDTH:-38} + 8 * (${#1} - 4) )); }

# Rendered width of a text in the primary (default) or secondary font
measure() {   # $1 text [$2 font]
  sketchybar --set gamify_measure label="$1" label.font="${2:-$TEXT_FONT:Semibold:${FONT_SIZE_TEXT:-15}.0}"
  sketchybar --query gamify_measure | jq -r '[.bounding_rects[]][0].size[0] | ceil'
}
session_open() {   # the pause/resume button only has width during a session
  [ "$(sketchybar --query gamify.1.btn 2>/dev/null | jq -r '.icon.width')" -gt 0 ] 2>/dev/null
}
pause_open() {
  [ "$(sketchybar --query gamify.1.pause 2>/dev/null | jq -r '.label.width')" -gt 0 ] 2>/dev/null
}
q() { printf '%q' "$1"; }   # quote text for the eval'd animation strings

source "$CONFIG_DIR/fonts.sh"   # TEXT_FONT
SECONDARY_FONT="$TEXT_FONT:Regular:${FONT_SIZE_SECONDARY:-13}.0"

# ── Idle: balance + unit ────────────────────────────────────────────────────────
balance=$(tr -d '[:space:]' < "$DIR/balance" 2>/dev/null)
if [ -n "$balance" ]; then
  unit=FC
  num_w=$(measure "$balance")
  unit_w=$(measure "$unit" "$SECONDARY_FONT")
  bal_color=$TEXT_COLOR
  [ "${balance#-}" != "$balance" ] && bal_color=$CRITICAL_COLOR
  # gamify.1 reserves room for the unit; gamify.1.time draws it there (net width 0)
  idle_w=$((num_w + UNIT_GAP + unit_w + INSET))
  IDLE_GEOMETRY="--set gamify.1 icon.width=$INSET label.width=$idle_w --set gamify.1.time label.width=$unit_w padding_left=-$((unit_w + INSET)) padding_right=$INSET"
  IDLE_ICON=""
else
  unit="" bal_color=$CLEAR idle_w=0          # engine not up yet: just the clock
  IDLE_ICON=$TODO_TIMER_ICON
  IDLE_GEOMETRY="--set gamify.1 icon.width=$CLOCK_W label.width=0 --set gamify.1.time label.width=0 padding_left=0 padding_right=0"
fi
IDLE_TEXT="--set gamify.1 icon=$(q "$IDLE_ICON") label=$(q "$balance") --set gamify.1.time label=$(q "$unit")"
IDLE_SHOWN="--set gamify.1 icon.color=$BUTTON_COLOR label.color=$bal_color --set gamify.1.time label.color=$bal_color"

# ── Session ────────────────────────────────────────────────────────────────────
line=""
if [ -f "$DIR/session.json" ]; then
  line=$(jq -r --argjson now "$(date +%s)" --arg s "$SEP" '
    select(.status == "running" or .status == "paused")
    | . as $t
    | ((if $t.status == "paused" then $t.pausedAt else $now * 1000 end) - $t.startedAt) as $elapsedMs
    | ($t.sessionMinutes * 60 - $elapsedMs / 1000 + ($t.totalPausedSeconds // 0)) as $rem
    | select($rem > -60)                       # long past its end: stale
    # Pause allowance, same math as popup.js: free = floor(session × maxPausePercent),
    # used = earlier pauses + this one; past the allowance it is penalty time
    | (if .status == "paused" then
         ((.sessionMinutes * 60 * ((.maxPausePercent // 10) / 100)) | floor) as $free
         | (((.totalPausedSeconds // 0) + ($now * 1000 - .pausedAt) / 1000) | floor) as $used
         | (if $used < $free then {kind: "free", s: ($free - $used)} else {kind: "penalty", s: ($used - $free)} end)
         | ((if .kind == "penalty" then "+" else "" end)
            + "\((.s / 60) | floor):\(.s % 60 | tostring | if length < 2 then "0" + . else . end)") as $txt
         | {pauseKind: .kind, pauseText: $txt}
       else {pauseKind: "", pauseText: ""} end) as $p
    | [ (if .mode == "rest" then "Rest" else (.tag // "Focus") end),
        (if $rem < 60 then "<1m" else "\((($rem + 59) / 60) | floor)m" end),
        .status, $p.pauseKind, $p.pauseText ]
    | join($s)' "$DIR/session.json" 2>/dev/null)
fi

args=()
anims=()       # transitions, run in the background after the static update
any_paused=0
IFS="$SEP" read -r label left status pause_kind pause_text <<< "$line"

if [ -n "$label" ]; then
  button=$ICON_PAUSE
  [ "$status" = "paused" ] && button=$ICON_PLAY
  # Single-line strings: they're eval'd for the animations, where a newline ends a command.
  # Every fragment starts with its own --set, so fragments can be joined in any order.
  # A fixed label.width swallows padding, so the tag ↔ time gap is part of the width.
  open="--set gamify.1 icon.width=$CLOCK_W label.width=$(( $(measure "$label") + GAP )) background.drawing=off --set gamify.1.time label.width=$(time_width "$left") padding_left=0 padding_right=0 --set gamify.1.btn icon.width=$BTN_W icon.padding_right=2"
  text="--set gamify.1 icon=$(q "$TODO_TIMER_ICON") label=$(q "$label") --set gamify.1.time label=$(q "$left")"
  shown="--set gamify.1 icon.color=$ACCENT_COLOR label.color=$TEXT_COLOR --set gamify.1.time label.color=$TEXT_COLOR --set gamify.1.btn icon.color=$BUTTON_COLOR"

  args+=(--set gamify.1.btn icon="$button" click_script="'$CTL' toggle >/dev/null")
  if session_open; then
    # Already open: tick (sizes follow the text, colors stay shown)
    eval "args+=($text $open $shown)"
  else
    # Opening: the balance fades out, the pill stretches to the session's size, then
    # the session fades in
    anims+=("sketchybar --animate linear $FADE --set gamify.1 icon.color=$CLEAR label.color=$CLEAR --set gamify.1.time label.color=$CLEAR;
             sleep 0.17;
             sketchybar $text;
             sketchybar --animate tanh $STRETCH $open;
             sleep 0.2;
             sketchybar --animate linear $FADE $shown")
  fi

  # Pause countdown section (its own open/close animation)
  if [ "$status" = "paused" ]; then
    any_paused=1
    icon=$ICON_FREE
    [ "$pause_kind" = "penalty" ] && icon=$ICON_PENALTY
    pw=$(pause_width "$pause_text")
    if pause_open; then
      args+=(--set gamify.1.pause icon="$icon" label="$pause_text" label.width=$pw
                   icon.color=$PAUSE_COLOR label.color=$PAUSE_COLOR)
    else
      args+=(--set gamify.1.pause icon="$icon" label="$pause_text")
      anims+=("sketchybar --animate tanh $STRETCH --set gamify.1.pause $PAUSE_OPEN label.width=$pw;
               sleep 0.2;
               sketchybar --animate linear $FADE --set gamify.1.pause icon.color=$PAUSE_COLOR label.color=$PAUSE_COLOR")
    fi
  elif pause_open; then
    anims+=("sketchybar --animate linear $FADE --set gamify.1.pause icon.color=$PAUSE_CLEAR label.color=$PAUSE_CLEAR;
             sleep 0.17;
             sketchybar --animate tanh $STRETCH --set gamify.1.pause $PAUSE_CLOSED")
  fi

elif session_open; then
  # Session ended: it fades out, the pill shrinks back to the balance, which fades in
  anims+=("sketchybar --animate linear $FADE --set gamify.1 icon.color=$CLEAR label.color=$CLEAR --set gamify.1.time label.color=$CLEAR --set gamify.1.btn icon.color=$CLEAR --set gamify.1.pause icon.color=$PAUSE_CLEAR label.color=$PAUSE_CLEAR;
           sleep 0.17;
           sketchybar $IDLE_TEXT;
           sketchybar --animate tanh $STRETCH $IDLE_GEOMETRY --set gamify.1.btn icon.width=0 icon.padding_right=0 --set gamify.1.pause $PAUSE_CLOSED;
           sleep 0.2;
           sketchybar --animate linear $FADE $IDLE_SHOWN")

else
  # Idle: keep the balance current (the width eases to fit a new number)
  eval "args+=($IDLE_TEXT $IDLE_SHOWN)"
  [ "$(sketchybar --query gamify.1 | jq -r '.label.width')" = "$idle_w" ] \
    || anims+=("sketchybar --animate tanh $STRETCH $IDLE_GEOMETRY")
fi

# The pause countdown is in seconds: tick every second only while paused
freq=10
[ $any_paused = 1 ] && freq=1
args+=(--set gamify_watcher update_freq=$freq)
sketchybar "${args[@]}"

for a in "${anims[@]}"; do
  ( eval "$a" ) >/dev/null 2>&1 &
done
