#!/bin/bash
# Shared sizing tokens — sourced by sketchybarrc and by scripts that add items
# outside a config load (plugins/space_sync.sh). Edit sizes here.

# ----------------------------------------------------
# DYNAMIC SIZING & SPACING SYSTEM
# ----------------------------------------------------

# 1. THE MASTER CONTROL
# Change this one value to scale the entire bar up or down.
# Use integers: 10 = normal size, 12 = 20% larger, 8 = 20% smaller.
export SCALE_FACTOR=10

# 2. THE BASE UNIT
# All measurements are derived from this. (Using 4px as our base)
BASE_UNIT_RAW=4

# 3. THE CALCULATED SCALE (using integer arithmetic)
export BASE_UNIT=$((BASE_UNIT_RAW * SCALE_FACTOR / 10))

# --- Padding Scale ---
export PADDING_S=$((BASE_UNIT * 3 / 2))  # 6px @ scale 10
export PADDING_M=$((BASE_UNIT * 2))      # 8px @ scale 10  
export PADDING_L=$((BASE_UNIT * 3))      # 12px @ scale 10

# --- Layout Tokens (use these, not raw numbers) ---
# Inside a group < between groups: icon↔label 8, item↔item 18 (9 each side),
# pill edge 4 (= vertical inset of the 20px capsules in the 28px pills).
export GAP_ICON_LABEL=$PADDING_M         # 8px  icon ↔ its own label
export ITEM_PAD=$((BASE_UNIT * 9 / 4))   # 9px per side → 18px between items
# Pill nesting (concentric: each level is inset evenly on every side)
export PILL_HEIGHT=$((BASE_UNIT * 8))                 # 32px: outer left/right pills
export PILL_RADIUS=$((PILL_HEIGHT / 2))
export CAPSULE_HEIGHT=$((BASE_UNIT * 13 / 2))         # 26px: active space, front app, hovers
export CAPSULE_RADIUS=$((CAPSULE_HEIGHT / 2))
export ICON_PILL_HEIGHT=$((BASE_UNIT * 11 / 2))       # 22px: icon pill inside the active space
export ICON_PILL_RADIUS=$((ICON_PILL_HEIGHT / 2))
export PILL_GAP=$BASE_UNIT                                # 4px between detached pills (timer, media)
export PILL_EDGE=$(((PILL_HEIGHT - CAPSULE_HEIGHT) / 2))  # 3px  outer pill ↔ capsule, every side
# Vertical optics (measured): SF Pro's cap-height centre and SF Symbols sit ~1pt below
# the line-box centre, so every glyph is lifted 1pt; the pills themselves don't move.
export GLYPH_LIFT=1
export ICON_OVERHANG=2                   # SF Symbols draw past their reported width; icon-only
                                         # items need this much right padding or get clipped

# --- Corner Radius Scale ---
export RADIUS_L1=$((BASE_UNIT * 4))      # 16px @ scale 10
export RADIUS_L2=$((BASE_UNIT * 3))      # 12px @ scale 10
export RADIUS_L3=$((BASE_UNIT * 5 / 2))  # 10px @ scale 10
export RADIUS_L4=$((BASE_UNIT * 2))      # 8px @ scale 10

# --- Height Scale ---
export HEIGHT_L1=$((BASE_UNIT * 11))     # 44px @ scale 10
export HEIGHT_L2=$((BASE_UNIT * 7))      # 28px @ scale 10
export HEIGHT_L3=$((BASE_UNIT * 6))      # 24px @ scale 10
export HEIGHT_L4=$((BASE_UNIT * 5))      # 20px @ scale 10

# Drop-down menus hang from their button as a folder tab: the pressed capsule grows down
# past the bar's bottom (clipped square there) into an opaque panel starting at the pill's
# bottom. The panel's corner radius must fit in the 6px between pill bottom and bar bottom,
# where the tab covers its top corner — so the seam disappears.
export MENU_RADIUS=$(((HEIGHT_L1 - PILL_HEIGHT) / 2))     # 6px
export MENU_TAB_HEIGHT=$((CAPSULE_HEIGHT + 24))          # pressed capsule while its menu is open…
export MENU_TAB_OFFSET=-12                               # …top unchanged, bottom 24px lower

# --- Border Scale ---
export BORDER_THIN=1                     # 1px
export BORDER_THICK=2                    # 2px

# --- Type Scale: two sizes, two weights ---
# Semibold everywhere; Heavy only for the single primary item (the clock time).
# SF Symbols are drawn to match text at the same point size, so icons use TEXT too.
export FONT_SIZE_TEXT=$((BASE_UNIT * 15 / 4))       # 15px @ scale 10: all text + icons
export FONT_SIZE_SECONDARY=$((BASE_UNIT * 13 / 4))  # 13px @ scale 10: secondary text (AM/PM)
# Live numbers sit in fixed, right-aligned boxes sized to their widest value, so a
# changing number can't push its neighbours around (SF Pro digits are proportional).
export CLOCK_WIDTH=$((FONT_SIZE_TEXT * 3 + 7))      # 52px: widest time "10:48" (Heavy); <50 clips the leading "1"
export CPU_WIDTH=$((FONT_SIZE_TEXT * 5 / 2))        # 37px: widest value "88%" (Semibold)

# Export all variables for use in other scripts
export SCALE_FACTOR BASE_UNIT PADDING_S PADDING_M PADDING_L
export RADIUS_L1 RADIUS_L2 RADIUS_L3 RADIUS_L4
export HEIGHT_L1 HEIGHT_L2 HEIGHT_L3 HEIGHT_L4
export BORDER_THIN BORDER_THICK
export FONT_SIZE_TEXT FONT_SIZE_SECONDARY
