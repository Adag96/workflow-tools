#!/bin/bash
# Fake equalizer for the collapsed media widget — 4 bars that bounce while music plays
# and freeze while paused. Not real audio data, just a "something is playing" cue.
#   media_eq.sh start   bounce (no-op if already running)
#   media_eq.sh stop    freeze in a calm still shape
# Driven by plugins/media.sh (play/pause) and plugins/media_hover.sh (hidden while the
# controls are expanded). One loop at most (pid file); it exits when sketchybar is gone,
# and items/media.sh kills it on reload. Runs under stock bash 3.2.

PID_FILE=/tmp/sketchybar_media_eq.pid
BARS="media.eq.1 media.eq.2 media.eq.3 media.eq.4"
STILL=(5 9 7 4)            # paused shape
MIN=3; MAX=14              # bar heights (px) while bouncing
STEP=12                    # animation frames per move (60fps)...
TICK=0.22                  # ...and a new target this often

running() { [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }

case "$1" in
  start)
    running && exit 0
    (
      while :; do
        args=(--animate sin $STEP)
        for bar in $BARS; do
          args+=(--set "$bar" background.height=$(( MIN + RANDOM % (MAX - MIN + 1) )))
        done
        sketchybar "${args[@]}" 2>/dev/null || exit 0
        sleep $TICK
      done
    ) >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    ;;
  stop)
    running && kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
    args=(--animate sin $STEP)
    i=0
    for bar in $BARS; do args+=(--set "$bar" background.height=${STILL[$i]}); i=$((i + 1)); done
    sketchybar "${args[@]}" 2>/dev/null
    ;;
esac
