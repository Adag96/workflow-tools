## Style
- Be concise. User wants working solutions, not explanations.
- Skip verbose justifications — just fix it.

## Lessons
`.claude/Claude-Lessons.md` — **read at session start**. Key gotchas: scripts run under stock bash 3.2 (no `$BASHPID`/`declare -A`); polling plugins need reentrancy guards.

## Quick Reference

### Reload Commands
```bash
sketchybar --reload          # Reload sketchybar config
yabai --restart-service      # Restart yabai
```

### After upgrading/rebuilding yabai
The sudoers rule for the scripting addition is sha256-pinned; a new binary breaks `--load-sa` until re-pinned:
```bash
echo "adam ALL=(root) NOPASSWD: sha256:$(shasum -a 256 /opt/homebrew/bin/yabai | awk '{print $1}') /opt/homebrew/bin/yabai --load-sa" | sudo tee /etc/sudoers.d/yabai
```

### Debug Logs
- Yabai status: `/tmp/yabai_status`
- Display watcher: `/tmp/display_watcher.log`

### Dependencies
- `jq` — used extensively for JSON manipulation across scripts

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
| `sketchybar/items/scheme.sh` | Color scheme definitions |
| `sketchybar/plugins/todo.sh` | Todo widget (disabled; syncs via Dropbox) |
| `install.sh` | Setup script — symlinks, directories |
| `big-cleaner.py` | TUI disk cleanup tool (shell alias: `clean`) |

### Retired Features
- **Ableton Project Timer** — removed July 2026. Old on-disk data may still exist at `/Volumes/T7/Ableton Timer Data/` and `~/.local/share/sketchybar_timer_data/` (intentionally not deleted).

### Color Scheme
- Current scheme stored in `~/.cache/sketchybar/current_scheme`
- `items/scheme.sh` defines all color variables via `get_colors()`

## Prohibited Changes
- Do NOT delete the retired timer's data dirs (`/Volumes/T7/Ableton Timer Data/`, `~/.local/share/sketchybar_timer_data/`) without explicit permission
