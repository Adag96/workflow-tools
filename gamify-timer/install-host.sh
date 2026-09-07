#!/bin/bash
#
# Registers the Gamify Timer native messaging host for Brave/Chrome.
#
# Usage:
#   ./install-host.sh <extension-id-1> [extension-id-2] [extension-id-3]
#
# After loading the extension in each Brave profile, find each profile's
# extension ID on brave://extensions and pass them all as arguments.

set -e

if [ $# -eq 0 ]; then
  echo "Usage: ./install-host.sh <extension-id-1> [extension-id-2] [extension-id-3]"
  echo ""
  echo "Find your extension IDs at brave://extensions (or chrome://extensions)"
  echo "after loading the unpacked extension in each profile."
  exit 1
fi

HOST_NAME="com.gamifytimer.host"
HOST_PATH="$(cd "$(dirname "$0")" && pwd)/host-wrapper.sh"

# Build allowed_origins array
ORIGINS=""
for id in "$@"; do
  if [ -n "$ORIGINS" ]; then
    ORIGINS="$ORIGINS, "
  fi
  ORIGINS="$ORIGINS\"chrome-extension://$id/\""
done

MANIFEST="{
  \"name\": \"$HOST_NAME\",
  \"description\": \"Gamify Timer shared data host\",
  \"path\": \"$HOST_PATH\",
  \"type\": \"stdio\",
  \"allowed_origins\": [$ORIGINS]
}"

# Install for both Chrome and Brave (they share the same paths on macOS)
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
BRAVE_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"

for DIR in "$CHROME_DIR" "$BRAVE_DIR"; do
  mkdir -p "$DIR"
  echo "$MANIFEST" > "$DIR/$HOST_NAME.json"
  echo "Installed: $DIR/$HOST_NAME.json"
done

echo ""
echo "Native messaging host registered for extension IDs: $*"
echo "You may need to restart Brave/Chrome for it to take effect."
