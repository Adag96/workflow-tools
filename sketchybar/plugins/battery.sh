#!/bin/sh


source "$CONFIG_DIR/icons.sh"
source "$CONFIG_DIR/items/scheme.sh"  # Source the scheme file instead of colors.sh


# Get the current color scheme
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

# Extract battery percentage from InternalBattery line only
PERCENTAGE="$(pmset -g batt | grep 'InternalBattery' | grep -Eo '[0-9]+%' | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

# Debug logging
echo "$(date '+%Y-%m-%d %H:%M:%S') PERCENTAGE=$PERCENTAGE CHARGING=$CHARGING" >> "$CONFIG_DIR/debug.log"

if [ "$PERCENTAGE" = "" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') No percentage found, exiting." >> "$CONFIG_DIR/debug.log"
  exit 0
fi

case "${PERCENTAGE}" in
  9[0-9]|100)
    echo "$(date '+%Y-%m-%d %H:%M:%S') Case: FULL" >> "$CONFIG_DIR/debug.log"
    sketchybar --set "$NAME" \
      icon="$BATTERY_FULL" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [6-8][0-9])
    echo "$(date '+%Y-%m-%d %H:%M:%S') Case: HIGH" >> "$CONFIG_DIR/debug.log"
    sketchybar --set "$NAME" \
      icon="$BATTERY_HIGH" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [3-5][0-9])
    echo "$(date '+%Y-%m-%d %H:%M:%S') Case: MED" >> "$CONFIG_DIR/debug.log"
    sketchybar --set "$NAME" \
      icon="$BATTERY_MED" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [1-2][0-9])
    echo "$(date '+%Y-%m-%d %H:%M:%S') Case: LOW" >> "$CONFIG_DIR/debug.log"
    sketchybar --set "$NAME" \
      icon="$BATTERY_LOW" \
      icon.color=0xfff7941c \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  *)
    echo "$(date '+%Y-%m-%d %H:%M:%S') Case: CRIT" >> "$CONFIG_DIR/debug.log"
    sketchybar --set "$NAME" \
      icon="$BATTERY_CRIT" \
      icon.color=0xffee1924 \
      label="${PERCENTAGE}%"
    ;;
esac

if [[ "$CHARGING" != "" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') Charging detected, setting charging icon." >> "$CONFIG_DIR/debug.log"
  sketchybar --set "$NAME" icon="$BATTERY_CHARGING"
fi