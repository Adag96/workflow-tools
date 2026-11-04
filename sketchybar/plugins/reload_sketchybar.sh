#!/bin/bash

# Reload the bar only. Restarting yabai here caused a reload storm: the yabai
# restart fired the display watcher, whose own `sketchybar --reload` ran
# concurrently with this one — two config loads interleaving left the bar
# transparent, mis-ordered, and missing pills. Restart yabai via its toggle
# widget or `yabai --restart-service` when actually needed.
sketchybar --reload