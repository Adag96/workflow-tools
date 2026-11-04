#!/bin/bash
# Time (h:mm) as the icon, AM/PM as the label. One `date` + one `sketchybar` call.
T=$(date '+%-I:%M %p')
sketchybar --set clock icon="${T% *}" label="${T#* }" 2>/dev/null
