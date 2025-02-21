# items/color_scheme.sh
#!/bin/bash

source "$CONFIG_DIR/icons.sh"  # Loads all defined icons

# Define the color schemes
SCHEMES=(
  "KANDY"
  "NEON"
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
get_colors() {
  local scheme=$1
  case $scheme in
    "KANDY")
      export BAR_COLOR=0xff3C4CA6
      export LEFT_ITEM_COLOR=0xffD996C7
      export LEFT_ITEM_FEEDBACK_COLOR=0xff9D7191
      export LEFT_TEXT_COLOR=0xff3C4CA6
      export LEFT_TEXT_FEEDBACK_COLOR=0xff313E89
      export RIGHT_ITEM_COLOR=0xffD996C7
      export RIGHT_ITEM_FEEDBACK_COLOR=0xff9D7191
      export RIGHT_TEXT_COLOR=0xff3C4CA6
      export RIGHT_TEXT_FEEDBACK_COLOR=0xff313E89
      export MEDIA_COLOR=0xffD996C7
      export ACCENT_COLOR=0xffD959AC
      ;;
    "NEON")
      export BAR_COLOR=0xff8A2BE2          
      export LEFT_ITEM_COLOR=0xffFF69B4     
      export LEFT_ITEM_FEEDBACK_COLOR=0xffDDA0DD  
      export LEFT_TEXT_COLOR=0xff8A2BE2     
      export LEFT_TEXT_FEEDBACK_COLOR=0xff9370DB  
      export RIGHT_ITEM_COLOR=0xffFF69B4    
      export RIGHT_ITEM_FEEDBACK_COLOR=0xffDDA0DD 
      export RIGHT_TEXT_COLOR=0xff8A2BE2    
      export RIGHT_TEXT_FEEDBACK_COLOR=0xff9370DB 
      export MEDIA_COLOR=0xffFF69B4         
      export ACCENT_COLOR=0xffBA55D3        
      ;;
    "BONEYARD")
      export BAR_COLOR=0xffF2F2F2
      export LEFT_ITEM_COLOR=0xff8C7972
      export LEFT_ITEM_FEEDBACK_COLOR=0xff
      export LEFT_TEXT_COLOR=0xffF2F2F2
      export LEFT_TEXT_FEEDBACK_COLOR=0xff
      export RIGHT_ITEM_COLOR=0xff8C7972
      export RIGHT_ITEM_FEEDBACK_COLOR=0xff
      export RIGHT_TEXT_COLOR=0xffF2F2F2
      export RIGHT_TEXT_FEEDBACK_COLOR=0xff
      export MEDIA_COLOR=0xffA63333   
      export ACCENT_COLOR=0xff 
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

# Initial setup of the color scheme item with properly loaded colors
sketchybar --add item color_scheme right \
           --set color_scheme \
                icon=$SCHEME_ICON \
                icon.color=$RIGHT_TEXT_COLOR \
                icon.padding_left=8 \
                icon.padding_right=8 \
                label="" \
                background.color=$RIGHT_ITEM_COLOR \
                background.corner_radius=50 \
                background.height=27 \
                background.drawing=on \
                padding_left=10 \
                padding_right=10 \
                click_script="$HOME/.config/sketchybar/plugins/color_scheme_click.sh"

# Update colors based on current scheme
get_colors "$(cat "$COLOR_SCHEME_CACHE")"