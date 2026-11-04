#!/bin/bash
# Install (or refresh) the Gamify Timer engine as a per-user LaunchAgent. Idempotent.
# The engine owns the single focus session for every browser profile + sketchybar,
# and completes/awards sessions even when no browser is open.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL=com.gamifytimer.engine
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG=/tmp/gamify-engine.log
PY=/usr/bin/python3                    # stock macOS python (3.9+): no extra installs

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$PY</string><string>-B</string><string>$DIR/gamify_engine.py</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PYTHONDONTWRITEBYTECODE</key><string>1</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PL

# (Re)load: bootout ignores "not loaded", bootstrap starts it fresh with the new plist
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Gamify engine installed ($PLIST); log: $LOG"
