#!/bin/sh

source "$CONFIG_DIR/icons.sh"
source "$CONFIG_DIR/colors.sh"  # Make sure we have access to colors too

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

case "${PERCENTAGE}" in
  9[0-9]|100) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_FULL" \
      icon.color=$BATTERY_FULL_COLOR \
      label="${PERCENTAGE}%"
    ;;
  [6-8][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_HIGH" \
      icon.color=$BATTERY_GOOD_COLOR \
      label="${PERCENTAGE}%"
    ;;
  [3-5][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_MED" \
      icon.color=$BATTERY_MED_COLOR \
      label="${PERCENTAGE}%"
    ;;
  [1-2][0-9]) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_LOW" \
      icon.color=$BATTERY_LOW_COLOR \
      label="${PERCENTAGE}%"
    ;;
  *) 
    sketchybar --set "$NAME" \
      icon="$BATTERY_CRIT" \
      icon.color=$BATTERY_CRIT_COLOR \
      label="${PERCENTAGE}%"
    ;;
esac

if [[ "$CHARGING" != "" ]]; then
  sketchybar --set "$NAME" icon="$BATTERY_CHARGING"
fi