#!/bin/sh

source "$CONFIG_DIR/icons.sh"
source "$CONFIG_DIR/items/scheme.sh"  # Source the scheme file instead of colors.sh

# Get the current color scheme
current_scheme=$(cat "$COLOR_SCHEME_CACHE")
get_colors "$current_scheme"

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

case "${PERCENTAGE}" in
  9[0-9]|100) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_FULL" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [6-8][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_HIGH" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [3-5][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_MED" \
      icon.color=$RIGHT_TEXT_COLOR \
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  [1-2][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_LOW" \
      icon.color=0xfff7941c \ 
      label="${PERCENTAGE}%" \
      label.color=$RIGHT_TEXT_COLOR
    ;;
  *) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_CRIT" \
      icon.color=0xffee1924 \
      label="${PERCENTAGE}%"
    ;;
esac

if [[ "$CHARGING" != "" ]]; then
  sketchybar --set "$NAME" icon="$BATTERY_CHARGING"
fi