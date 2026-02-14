## Style
- Be concise. User wants working solutions, not explanations.
- Skip verbose justifications — just fix it.

## Quick Reference

### Reload Commands
```bash
sketchybar --reload          # Reload sketchybar config
brew services restart yabai  # Restart yabai
```

### Debug Logs
- Timer debug: `/tmp/ableton_timer_debug.log`
- Yabai status: `/tmp/yabai_status`

### Dependencies
- `jq` — used extensively for JSON manipulation in timer scripts

## Project Context

Yabai (tiling WM) + Sketchybar (status bar) for macOS. Two machines: Mac Studio and MacBook Pro.

### Repository Structure
- **Main repo**: `~/workflow-tools`
- **Sub-repo**: `sketchybar/sketchybar-app-font` — forked font repo, branch `add-new-icons`
- **Symlink**: `~/workflow-tools/sketchybar` → `~/.config/sketchybar`

### Key Files
| File | Purpose |
|------|---------|
| `yabairc` | Yabai config |
| `sketchybar/sketchybarrc` | Main config + scaling system (`SCALE_FACTOR`) |
| `sketchybar/plugins/ableton_project_timer.sh` | Ableton session timer |
| `sketchybar/items/scheme.sh` | Color scheme definitions |
| `sketchybar/plugins/todo.sh` | Todo widget (syncs via Dropbox) |
| `install.sh` | Setup script — symlinks, directories, timer init |

### Ableton Project Timer
Tracks time per Ableton Live project. Auto-pauses on focus loss, resumes on focus gain (unless manually overridden).

**Data locations** (never in git):
- **Primary**: `/Volumes/T7/Ableton Timer Data/timer_state.json`
- **Fallback**: `~/.local/share/sketchybar_timer_data/timer_state.json`
- Shows "No Drive!" when T7 disconnected; syncs automatically when reconnected

**State files** (in `~/.local/share/sketchybar_timer_data/`):
- `timer_state.json` — project times
- `last_ableton_state.json` — focus tracking
- `manual_override.json` — pause override

### Color Scheme
- Current scheme stored in `~/.cache/sketchybar/current_scheme`
- `items/scheme.sh` defines all color variables via `get_colors()`

## Prohibited Changes
- Do NOT modify `timer_state.json` without explicit permission
- Do NOT change T7 drive path or local fallback path without asking
- Timer data files live outside the repo — never commit them
