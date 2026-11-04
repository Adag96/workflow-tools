#!/bin/bash
# Now Playing watcher — long-running, started by items/media.sh on each config load.
#
# sketchybar's built-in media_change event relies on the MediaRemote API that macOS
# 15.4+ locked down, so it never fires. `media-control` (brew) works around that and
# sees every Now Playing source: Music, Spotify, and browser media (Brave, YouTube...).
# It streams an update on every change, so there's no polling.
#
# Runs under stock bash 3.2 (see .claude/Claude-Lessons.md).

CONFIG_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v media-control >/dev/null 2>&1 || exit 0   # not installed: widget stays hidden
echo $$ > /tmp/sketchybar_media_watcher.pid           # items/media.sh kills this + children on reload
rm -f /tmp/sketchybar_media_art_*                     # artwork left by a previous (killed) watcher

ITEMS="media_gap media_start media.app media.title media.artist media.prev media.play media.next media_end media_bracket"
HIDE_DELAY=8                                  # seconds a paused widget lingers (so "play" is still clickable)
HIDE_PID=/tmp/sketchybar_media_hide.pid
ICON_PLAY="􀊄"                                 # play.fill
ICON_PAUSE="􀊆"                                # pause.fill
SEP=$'\x1f'                                   # field separator (non-whitespace: empty fields survive)

# Artwork: a circle concentric with the pill's rounded end (same inset all round).
# sketchybar draws images 1px = 1pt × scale, so a 2× bitmap at scale 0.5 is retina-sharp.
# A corner radius of exactly half the size silently draws square, hence the x.9.
ART=${ICON_PILL_HEIGHT:-22}
PILL=${PILL_HEIGHT:-32}; EDGE=${PILL_EDGE:-3}; GAP=${GAP_ICON_LABEL:-8}; PAD=${ITEM_PAD:-9}
ART_RADIUS="$((ART / 2 - 1)).9"
ART_INSET=$(( (PILL - ART) / 2 - EDGE ))
ART_FILE=""
ART_N=0

show_artwork() {   # $1 = jpeg/png file
  sketchybar --set media.app icon="" icon.width=$ART icon.padding_right=0 \
                   padding_left=$ART_INSET padding_right=$GAP \
                   background.drawing=on background.color=0x00000000 \
                   background.height=$ART background.image="$1" \
                   background.image.scale=0.5 background.image.corner_radius=$ART_RADIUS
}
show_app_icon() {  # $1 = app name
  sketchybar --set media.app icon="$("$CONFIG_DIR/plugins/icon_map_fn.sh" "$1")" \
                   icon.width=dynamic icon.padding_right=0 \
                   padding_left=$PAD padding_right=$GAP \
                   background.drawing=off
}

set_drawing() {
  local args=() item
  for item in $ITEMS; do args+=(--set "$item" drawing="$1"); done
  sketchybar "${args[@]}"
}
cancel_hide() {
  [ -f "$HIDE_PID" ] && kill "$(cat "$HIDE_PID")" 2>/dev/null
  rm -f "$HIDE_PID"
}
schedule_hide() {
  cancel_hide
  ( sleep "$HIDE_DELAY"; set_drawing off; rm -f "$HIDE_PID" ) &
  echo $! > "$HIDE_PID"
}

VISIBLE=0
LAST_PID=""
LAST_KEY=""     # track whose artwork is on screen ("" = showing the app icon)
APP=""
media-control stream --no-diff --debounce=250 2>/dev/null | while IFS= read -r line; do
  fields=$(printf '%s' "$line" | jq -r --arg s "$SEP" \
    '.payload | [(.playing // false), (.title // ""), (.artist // ""), (.processIdentifier // ""),
                 (.uniqueIdentifier // .contentItemIdentifier // ""), (has("artworkData"))] | map(tostring) | join($s)')
  IFS="$SEP" read -r playing title artist pid track has_art <<< "$fields"

  # Nothing in Now Playing at all
  if [ -z "$title" ]; then
    cancel_hide; set_drawing off || exit 0; VISIBLE=0; continue
  fi

  # Source app (fallback icon), looked up only when the source changes. Browser
  # media comes from helper processes inside the .app, so take the outermost .app.
  if [ "$pid" != "$LAST_PID" ]; then
    LAST_PID=$pid
    comm=$(ps -p "$pid" -o comm= 2>/dev/null)
    APP=${comm%%.app/*}; APP=${APP##*/}
    LAST_KEY="-"   # force the artwork/icon decision below
  fi

  # Album artwork when the source provides it, else the app icon. Decoded once per
  # track — and again if the artwork arrives after the title (browsers often do that).
  key="$track$title$artist"
  if [ "$has_art" = "true" ] && [ "$key" != "$LAST_KEY" ]; then
    ART_N=$((ART_N + 1)); new="/tmp/sketchybar_media_art_$ART_N.jpg"   # new path: sketchybar caches by path
    if printf '%s' "$line" | jq -r '.payload.artworkData' | base64 -D > "$new.src" 2>/dev/null \
       && sips -z $((ART * 2)) $((ART * 2)) "$new.src" --out "$new" >/dev/null 2>&1; then
      show_artwork "$new"
      [ -n "$ART_FILE" ] && rm -f "$ART_FILE"
      ART_FILE=$new; LAST_KEY=$key
    fi
    rm -f "$new.src"
  elif [ "$has_art" != "true" ] && [ -n "$LAST_KEY" ]; then
    show_app_icon "$APP"; LAST_KEY=""
  fi

  # Artist sits PADDING_S after the song; with no artist it collapses to nothing
  if [ -n "$artist" ]; then artist_set=(label="$artist" padding_left=${PADDING_S:-6})
  else artist_set=(label="" padding_left=0); fi

  if [ "$playing" = "true" ]; then
    cancel_hide
    sketchybar --set media.title label="$title" --set media.artist "${artist_set[@]}" \
               --set media.play icon="$ICON_PAUSE" || exit 0
    [ "$VISIBLE" = 0 ] && set_drawing on
    VISIBLE=1
  else
    sketchybar --set media.title label="$title" --set media.artist "${artist_set[@]}" \
               --set media.play icon="$ICON_PLAY" || exit 0
    # Only a widget that's showing lingers; a paused track at startup stays hidden
    [ "$VISIBLE" = 1 ] && schedule_hide
    VISIBLE=0
  fi
done
