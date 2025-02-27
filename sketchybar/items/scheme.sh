# items/color_scheme.sh
#!/bin/bash

source "$CONFIG_DIR/icons.sh"  # Loads all defined icons

# Define the color schemes
SCHEMES=(
  "KANDY"
  "DEUS"
  "BONEYARD"
)

COLOR_SCHEME_CACHE="$HOME/.cache/sketchybar/current_scheme"

# Create cache directory if it doesn't exist
mkdir -p "$(dirname "$COLOR_SCHEME_CACHE")"

# Initialize with KANDY if no scheme is set
if [ ! -f "$COLOR_SCHEME_CACHE" ]; then
  echo "KANDY" > "$COLOR_SCHEME_CACHE"
fi

# Color definitions based on scheme

# Active space text color and media color should match

get_colors() {
  local scheme=$1
  case $scheme in
    "KANDY")
      export BAR_COLOR=0xff3C4CA6
      export LEFT_ITEM_COLOR=0xffD996C7
      export LEFT_ITEM_FEEDBACK_COLOR=0xff9D7191
      export LEFT_TEXT_COLOR=0xffD996C7
      export LEFT_TEXT_FEEDBACK_COLOR=0xff313E89
      export ACTIVE_SPACE_ITEM_COLOR=0xffD996C7
      export ACTIVE_SPACE_TEXT_COLOR=0xff3C4CA6
      export RIGHT_ITEM_COLOR=0xffD996C7
      export RIGHT_ITEM_FEEDBACK_COLOR=0xff9D7191
      export RIGHT_TEXT_COLOR=0xff3C4CA6
      export RIGHT_TEXT_FEEDBACK_COLOR=0xff313E89
      export MEDIA_COLOR=0xffD996C7
      export ACCENT_COLOR=0xffD959AC
      ;;
    "DEUS")
      export BAR_COLOR=0xffffffff  
      export LEFT_ITEM_COLOR=0xff6A8C61
      export LEFT_ITEM_FEEDBACK_COLOR=0xff546F4D
      export LEFT_TEXT_COLOR=0xff6A8C61
      export LEFT_TEXT_FEEDBACK_COLOR=0xffC5C5C5
      export ACTIVE_SPACE_ITEM_COLOR=0xff6A8C61
      export ACTIVE_SPACE_TEXT_COLOR=0xfffda1d7  
      export RIGHT_ITEM_COLOR=0xff6A8C61
      export RIGHT_ITEM_FEEDBACK_COLOR=0xff546F4D
      export RIGHT_TEXT_COLOR=0xffffffff  
      export RIGHT_TEXT_FEEDBACK_COLOR=0xffC5C5C5
      export MEDIA_COLOR=0xfffda1d7    
      export ACCENT_COLOR=0xffF288C2   

      # COLOR PALETTE:
      # 0xffD9D2D5
      # 0xfffda1d7
      # 0xff6A8C61
      # 0xff736D6C
      ;;
    "BONEYARD")
      export BAR_COLOR=0xffdee5de
      export LEFT_ITEM_COLOR=0xff816f65
      export LEFT_ITEM_FEEDBACK_COLOR=0xff65574E
      export LEFT_TEXT_COLOR=0xff816f65
      export LEFT_TEXT_FEEDBACK_COLOR=0xffA6ABA6
      export ACTIVE_SPACE_ITEM_COLOR=0xffaa2224
      export ACTIVE_SPACE_TEXT_COLOR=0xffdee5de
      export RIGHT_ITEM_COLOR=0xff816f65
      export RIGHT_ITEM_FEEDBACK_COLOR=0xff65574E
      export RIGHT_TEXT_COLOR=0xffdee5de
      export RIGHT_TEXT_FEEDBACK_COLOR=0xffA6ABA6
      export MEDIA_COLOR=0xffaa2224
      export ACCENT_COLOR=0xffd89048

      # COLOR PALETTE:
      # 0xff816f65 brown
      # 0xffd89048 orange
      # 0xffdee5de white
      # 0xffaa2224 red

  esac
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