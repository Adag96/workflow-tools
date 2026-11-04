#!/bin/bash
# Gamify Timer widget driver: reads the per-profile timer mirrors written by
# gamify-timer/host.py and fills up to 3 slots with "<tag> <minutes left>", the
# pause-time section (animated open while paused) and a pause/resume button wired
# to that profile.
# Bounded: local file reads + one jq + a few sketchybar calls (no hang-prone calls),
# and idempotent, so an overlapping run is harmless. Runs under stock bash 3.2.

source "$CONFIG_DIR/items/scheme.sh"   # ACCENT_COLOR, CRITICAL_COLOR
source "$CONFIG_DIR/icons.sh"          # TODO_TIMER_ICON

DIR="$HOME/.cache/sketchybar/gamify"
SLOTS=3
ICON_PAUSE="􀊆"            # pause.fill: shown while running (click pauses)
ICON_PLAY="􀊄"             # play.fill:  shown while paused  (click resumes)
ICON_FREE="􀖇"             # hourglass: free pause time left
ICON_PENALTY="􀇿"          # exclamationmark.triangle.fill: pause penalty accruing
SEP=$'\x1f'

# Pause section: red to draw attention; animated open/closed (see items/gamify.sh)
PAUSE_COLOR=$CRITICAL_COLOR
PAUSE_CLEAR="0x00${PAUSE_COLOR:4}"                 # same color, fully transparent
# Open/closed geometry (sketchybar doesn't pass rc exports to plugins, hence defaults).
# Animating these — not the item's `width` — is what makes the pill itself resize:
# text overflowing a 0-width item still counts toward the pill's extent.
OPEN="icon.width=${GAMIFY_PAUSE_ICON_WIDTH:-18} icon.padding_right=${GAP_ICON_LABEL:-8} padding_left=${ITEM_PAD:-9}"
# Countdown box: fits "8:08"; one more char ("+" for penalty, or 10m+) adds 8px
pause_width() { echo $(( ${GAMIFY_PAUSE_WIDTH:-38} + 8 * (${#1} - 4) )); }
CLOSED="icon.width=0 icon.padding_right=0 label.width=0 padding_left=0"
STRETCH=12                                         # frames (60fps): pill stretches, then...
FADE=10                                            # ...countdown fades in (reverse on resume)

# Files untouched for 12h are from a browser closed mid-session — ignore them
files=$(find "$DIR" -maxdepth 1 -name '*.json' -mmin -720 2>/dev/null)

lines=""
if [ -n "$files" ]; then
  # shellcheck disable=SC2086
  lines=$(jq -rn --argjson now "$(date +%s)" --arg s "$SEP" '
    [inputs | . + {id: (input_filename | split("/") | last | rtrimstr(".json"))}]
    | map(select(.status == "running" or .status == "paused")
        | . as $t
        | ((if $t.status == "paused" then $t.pausedAt else $now * 1000 end) - $t.startedAt) as $elapsedMs
        | ($t.sessionMinutes * 60 - $elapsedMs / 1000 + ($t.totalPausedSeconds // 0)) as $rem
        | select($rem > -60)                       # long past its end: stale
        | . + {rem: $rem})
    | sort_by(.startedAt) | .[:3] | .[]
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
        (if .rem < 60 then "<1m" else "\(((.rem + 59) / 60) | floor)m" end),
        .status, .id, $p.pauseKind, $p.pauseText ]
    | join($s)' $files 2>/dev/null)
fi

is_open() {   # is slot $1's pause section currently open?
  [ "$(sketchybar --query "gamify.$1.pause" 2>/dev/null | jq -r '.label.width')" -gt 0 ] 2>/dev/null
}

args=()
anims=()       # transitions, run in the background after the static update
n=0
any_paused=0
while IFS="$SEP" read -r label left status id pause_kind pause_text; do
  [ -z "$label" ] && continue
  n=$((n + 1))
  button=$ICON_PAUSE
  [ "$status" = "paused" ] && button=$ICON_PLAY

  if [ "$status" = "paused" ]; then
    any_paused=1
    icon=$ICON_FREE
    [ "$pause_kind" = "penalty" ] && icon=$ICON_PENALTY
    if is_open $n; then
      # Already open: just tick the countdown
      args+=(--set gamify.$n.pause drawing=on icon="$icon" label="$pause_text"
                   label.width=$(pause_width "$pause_text")
                   icon.color=$PAUSE_COLOR label.color=$PAUSE_COLOR)
    else
      # Just paused: stretch the pill open, then fade the countdown in
      args+=(--set gamify.$n.pause drawing=on icon="$icon" label="$pause_text")
      anims+=("sketchybar --animate tanh $STRETCH --set gamify.$n.pause $OPEN label.width=$(pause_width "$pause_text");
               sleep 0.2;
               sketchybar --animate linear $FADE --set gamify.$n.pause icon.color=$PAUSE_COLOR label.color=$PAUSE_COLOR")
    fi
  elif is_open $n; then
    # Just resumed: fade the countdown out, then collapse the pill
    anims+=("sketchybar --animate linear $FADE --set gamify.$n.pause icon.color=$PAUSE_CLEAR label.color=$PAUSE_CLEAR;
             sleep 0.17;
             sketchybar --animate tanh $STRETCH --set gamify.$n.pause $CLOSED")
  fi

  # Time box fits "88m"; a 100m+ countdown (long sessions only) sizes itself
  time_width=${GAMIFY_TIME_WIDTH:-38}
  [ ${#left} -gt 3 ] && time_width=dynamic
  args+=(--set gamify.$n drawing=on icon.color=$ACCENT_COLOR label="$label"
         --set gamify.$n.time drawing=on label="$left" label.width=$time_width
         --set gamify.$n.btn drawing=on icon="$button"
               click_script="mkdir -p '$DIR/cmd' && echo toggle > '$DIR/cmd/$id'")
done <<< "$lines"

# Unused slots: hidden, pause section reset to closed
i=$((n + 1))
while [ $i -le $SLOTS ]; do
  args+=(--set gamify.$i drawing=off --set gamify.$i.time drawing=off --set gamify.$i.btn drawing=off
         --set gamify.$i.pause drawing=off $CLOSED
               icon.color=$PAUSE_CLEAR label.color=$PAUSE_CLEAR)
  i=$((i + 1))
done

state=off
[ $n -gt 0 ] && state=on
args+=(--set gamify_start drawing=$state --set gamify_end drawing=$state --set gamify_bracket drawing=$state)
# The pause countdown is in seconds: tick every second only while something is paused
freq=10
[ $any_paused = 1 ] && freq=1
args+=(--set gamify_watcher update_freq=$freq)
sketchybar "${args[@]}"

for a in "${anims[@]}"; do
  ( eval "$a" ) >/dev/null 2>&1 &
done
