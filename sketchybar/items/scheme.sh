# items/color_scheme.sh
#!/bin/bash

source "$CONFIG_DIR/icons.sh"  # Loads all defined icons

# Import configuration variables
CORNER_RADIUS=${CORNER_RADIUS:-12}  # Default to 12 if not set

# Define the color schemes
SCHEMES=(
  "KANDY"
  "DEUS"
  "BONEYARD"
  "MOON"
)

COLOR_SCHEME_CACHE="$HOME/.cache/sketchybar/current_scheme"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$COLOR_SCHEME_CACHE")"

# Initialize with KANDY if no scheme is set
if [ ! -f "$COLOR_SCHEME_CACHE" ]; then
  echo "KANDY" > "$COLOR_SCHEME_CACHE"
fi

# Color roles — every scheme must define all of these (nothing else is read):
#   PILL_COLOR_1      outer pill background (with alpha; the gear menu uses it opaque)
#   PILL_COLOR_3      active-space capsule, gear-menu hover row
#   PILL_COLOR_4      icon pill inside the active space, front-app pill, button hover
#   TEXT_COLOR        all text and icons (LEFT_/RIGHT_TEXT_COLOR are aliases)
#   SUBTLE_TEXT_COLOR inactive spaces only — means "inactive", never use for live controls
#   ACCENT_COLOR      "where you are": active space number + front-app icon
#   WARN_COLOR        low battery
#   CRITICAL_COLOR    critical battery
get_colors() {
  local scheme=$1
  case $scheme in
    "KANDY")       # dark blue + candy pink
      export PILL_COLOR_1=0xc8313E89
      export PILL_COLOR_3=0xff3C4CA6
      export PILL_COLOR_4=0xff5563C0
      export TEXT_COLOR=0xfff4dcee
      export SUBTLE_TEXT_COLOR=0xffb48fab
      export ACCENT_COLOR=0xffD959AC
      export WARN_COLOR=0xfff6c177
      export CRITICAL_COLOR=0xffff6b8b
      ;;
    "DEUS")        # light: white + sage green + pink
      export PILL_COLOR_1=0xc8ffffff
      export PILL_COLOR_3=0xffD9D2D5
      export PILL_COLOR_4=0xffC9D8C4
      export TEXT_COLOR=0xff3F5539
      export SUBTLE_TEXT_COLOR=0xff8A9A86
      export ACCENT_COLOR=0xffD6458F
      export WARN_COLOR=0xffC98A2E
      export CRITICAL_COLOR=0xffC0392B
      ;;
    "BONEYARD")    # light: bone + brown + red
      export PILL_COLOR_1=0xc8dee5de
      export PILL_COLOR_3=0xffC9CFC8
      export PILL_COLOR_4=0xffB8ADA6
      export TEXT_COLOR=0xff4A3F39
      export SUBTLE_TEXT_COLOR=0xff8F8580
      export ACCENT_COLOR=0xffaa2224
      export WARN_COLOR=0xffd89048
      export CRITICAL_COLOR=0xffaa2224
      ;;
    "MOON")        # Rosé Pine Moon
      export PILL_COLOR_1=0xc8232136   # base, ~78% opaque (wallpaper shows through softly)
      export PILL_COLOR_3=0xff43415A   # highlight med
      export PILL_COLOR_4=0xff56526E   # highlight high
      export TEXT_COLOR=0xffe0def4     # text
      export SUBTLE_TEXT_COLOR=0xff908caa
      export ACCENT_COLOR=0xffeb6f92   # love
      export WARN_COLOR=0xfff6c177     # gold
      export CRITICAL_COLOR=0xffeb6f92 # love
      ;;
  esac
  export LEFT_TEXT_COLOR=$TEXT_COLOR RIGHT_TEXT_COLOR=$TEXT_COLOR
}

toggle_scheme() {
  current_scheme=$(cat "$COLOR_SCHEME_CACHE")
  
  # Find the index of the current scheme
  for i in "${!SCHEMES[@]}"; do
    if [[ "${SCHEMES[$i]}" = "${current_scheme}" ]]; then
      current_index=$i
      break
    fi
  done
  
  # Calculate the next scheme index
  next_index=$(( (current_index + 1) % ${#SCHEMES[@]} ))
  next_scheme="${SCHEMES[$next_index]}"
  
  # Save the new scheme
  echo "$next_scheme" > "$COLOR_SCHEME_CACHE"
  
  # Apply the new colors
  get_colors "$next_scheme"
  
  # Update sketchybar
  sketchybar --update
}

# First, make sure we load the current scheme
get_colors "$(cat "$COLOR_SCHEME_CACHE")"

# Removed the button creation part - will be moved to sketchybarrc

# Update colors based on current scheme
get_colors "$(cat "$COLOR_SCHEME_CACHE")"