# plugins/color_scheme_click.sh
#!/bin/bash

# Create debug log
echo "----------------------------------------" > /tmp/scheme_debug.log
echo "Color scheme click handler started at $(date)" >> /tmp/scheme_debug.log

# Source the scheme file
echo "Sourcing scheme.sh" >> /tmp/scheme_debug.log
source "$HOME/.config/sketchybar/items/scheme.sh"

# Check current scheme before toggle
current_before=$(cat "$COLOR_SCHEME_CACHE")
echo "Current scheme before toggle: $current_before" >> /tmp/scheme_debug.log

# Toggle the scheme
echo "Calling toggle_scheme()" >> /tmp/scheme_debug.log
toggle_scheme

# Check current scheme after toggle
current_after=$(cat "$COLOR_SCHEME_CACHE")
echo "Current scheme after toggle: $current_after" >> /tmp/scheme_debug.log

# Update the label to show current scheme
#echo "Updating color_scheme label" >> /tmp/scheme_debug.log
#sketchybar --set color_scheme label="$current_after"

# Log current color values
echo "Current color values:" >> /tmp/scheme_debug.log
echo "BAR_COLOR=$BAR_COLOR" >> /tmp/scheme_debug.log
echo "LEFT_ITEM_COLOR=$LEFT_ITEM_COLOR" >> /tmp/scheme_debug.log
echo "RIGHT_ITEM_COLOR=$RIGHT_ITEM_COLOR" >> /tmp/scheme_debug.log

# Reload sketchybar to apply the new color scheme
echo "Calling reload_sketchybar.sh" >> /tmp/scheme_debug.log
"$HOME/.config/sketchybar/plugins/reload_sketchybar.sh"

echo "Color scheme click handler completed" >> /tmp/scheme_debug.log