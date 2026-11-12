# Claude Lessons — workflow-tools

Patterns learned from mistakes, corrections, and hard-won debugging.
Read this at session start. Follow these rules to avoid repeating past issues.

## Entry Format
Each lesson follows this structure:
- **Date**: When it was learned
- **Category**: `Shell` | `Sketchybar` | `Yabai` | `Performance` | `Workflow`
- **What happened**: Brief description of the problem
- **Root cause**: Why it happened
- **Rule**: A concrete, followable instruction to prevent recurrence

---

## Lessons

### Scripts invoked by yabai/sketchybar run under stock bash 3.2
- **Date**: 2026-07-03
- **Category**: Shell
- **What happened**: A `$BASHPID` fix for the move_window_to_display.sh debounce silently expanded to empty — the debounce PID file was blank, so the fix didn't work despite correct-looking code.
- **Root cause**: yabai signals and sketchybar scripts execute with a minimal PATH, so `#!/usr/bin/env bash` resolves to macOS stock `/bin/bash` (3.2, from 2007) even if Homebrew bash is installed. Bash 3.2 lacks `$BASHPID`, associative arrays (`declare -A` — this is also why items/space_brackets.sh:18 errors), `${var,,}`, and other bash 4+ features.
- **Rule**: In any script this repo's daemons invoke, write for bash 3.2. For a subshell's own PID use `( ... ) & echo $! > pidfile` from the parent (or `$(sh -c 'echo $PPID')` inside), never `$BASHPID`. No `declare -A`. Test features in `/bin/bash` before assuming they work.

### Never let two sketchybar --reload runs overlap
- **Date**: 2026-07-04
- **Category**: Sketchybar
- **What happened**: The reload widget button produced a wrecked bar — items interleaved out of order, pills missing. Its script ran `sketchybar --reload`, restarted yabai, which fired display_watcher, which issued a second `--reload` while the first config load was still executing. Two rc processes interleaved their --add/--reorder calls.
- **Root cause**: `sketchybar --reload` re-runs the whole rc; nothing serializes concurrent runs, and item order is add-order. Any script chain that can trigger a second reload mid-load corrupts the bar layout.
- **Rule**: A bar-reload action must only reload the bar (no yabai restarts, no watcher chaining). If a script needs both, restart yabai first, wait for it, then reload the bar exactly once. Note: the bar background is transparent BY DESIGN (`color=0x00000000` in rc) — wallpaper showing through is not a color-loading bug; look at the bracket pills instead.

### Polling plugins must never outlive their update interval
- **Date**: 2026-07-03
- **Category**: Performance
- **What happened**: cpu.sh used `top -l 1` (full process-table scan). One slow sample overran the widget's update_freq, sketchybar spawned the next instance anyway, and each stuck instance made the process table bigger and every scan slower. ~1400 processes accumulated, load average hit 327, the whole machine crawled.
- **Root cause**: sketchybar re-runs a plugin every update_freq with no awareness of whether the previous run finished. Any plugin whose worst-case runtime can exceed its interval (top/ps scans, osascript, yabai queries, network, reads from a sleepable external drive) will pile up under load — a positive feedback loop.
- **Rule**: Every polling plugin needs (a) a reentrancy guard (`pgrep -fq <unique cmdline> && exit 0` or an mkdir lock) and (b) a bounded worst case — timeout hang-prone calls (`perl -e 'alarm 5; exec @ARGV' <cmd>`, since macOS has no `timeout`). osascript specifically can hang forever on stalled Apple Events; never call it from a poller without the alarm wrapper.

### The active space number keeps turning black (recurring) — orphaned mkdir lock
- **Date**: 2026-07-28
- **Category**: Sketchybar
- **What happened**: The active space's leading number rendered black instead of the accent color. Diagnosed and "fixed" multiple times before, always recurring. Live query showed active spaces with `icon.highlight=on`, `highlight_color=0xff000000`, `icon.color=0xffffffff` — raw sketchybar defaults, never the accent. `plugins/space.sh` (the batch styler that sets `icon.color`/`icon.highlight_color=$ACCENT_COLOR`) was exiting without painting. Cause: a stale `/tmp/sketchybar_space_refresh.lock` dir orphaned days earlier.
- **Root cause**: space.sh's mkdir-lock reentrancy guard removes the lock via `trap ... EXIT`, which only fires on a *clean* exit. When the script is hard-killed mid-update (yabai restart, sketchybar reload, sleep during a space switch), the trap never runs and the lock dir is orphaned. From then on EVERY run sees the lock, assumes a live concurrent instance, sets the `rerun` flag, and exits without repainting — permanently wedged until `/tmp` is purged (reboot) or the lock is manually removed. Meanwhile sketchybar's native highlight flips the active space's icon to its (black default) `highlight_color` on each switch. That's the black number. This is why it recurs: any hard kill silently wedges styling forever.
- **Rule**: An mkdir/flock-style lock whose owner can be hard-killed MUST have a stale-lock reaper, not just a cleanup trap. In space.sh: if the lock is held, check its age via `stat -f %m` and reap (`rm -rf` + re-`mkdir`) anything older than 10s (real updates finish in <1s) before deferring. A `trap EXIT` alone is not a lock lifecycle. Quick manual fix if it happens again: `rm -rf /tmp/sketchybar_space_refresh.lock && sketchybar --update`.

### sketchybar-app-font glyphs: viewBox sets size, and evenodd holes are ignored
- **Date**: 2026-11-03
- **Category**: Sketchybar
- **What happened**: Contributing new icons upstream, wide logos (YLM, UA diamond, MAX) rendered tiny, and traced icons with holes (Output Hub "O") rendered as solid blobs.
- **Root cause**: The font build (svgicons2svgfont, `normalize` + `preserveAspectRatio` + `fixedWidth`) scales every glyph by its *viewBox's* longer side, not the path bounds — a 2:1 logo in a 24×24 box renders at half height. It also ignores `fill-rule="evenodd"`; potrace emits all subpaths in the same direction, so holes fill in.
- **Rule**: Wide logos: either redesign to ~square or let the path overflow the 24-unit viewBox horizontally (~1.2–1.5×; with single-space icon joins it doesn't collide). Holes: wind them opposite to their parent contour (nonzero-safe). Always verify in the live bar at 15pt — CoreText renders of the built TTF are a good proxy, raw SVG previews are not. Popups DO draw above normal windows (gear menu) — an early test only looked broken because it used white text on a light window; always give popups an explicit background color.

### The active-space icon pill is intentional depth — don't flatten it
- **Date**: 2026-11-03
- **Category**: Sketchybar
- **What happened**: A design audit removed all nested pills, including the inner pill around the active space's app icons. Adam rejected that part: the space capsule + inner icon pill gives the active space depth and distinguishes number from windows while keeping them one group.
- **Root cause**: Treated every nesting level as noise. Only the meaningless layers were noise (spaces group band, front-app ring, control sub-pill, 1–2px borders).
- **Rule**: Keep the two-level active space (space capsule → icon pill). Container layers must each group something; remove ones that don't, never ones that carry hierarchy. Before/after demos for bar changes go over the fixed teal backdrop (`bar color=0xff387184` during capture) so wallpaper changes can't skew comparisons.

### Subtle color means "inactive" — never use it on always-available controls
- **Date**: 2026-11-03
- **Category**: Sketchybar
- **What happened**: Muting all SF Symbol icons to `SUBTLE_TEXT_COLOR` (#908caa) for an icon/label tier made the always-live buttons (scheme, reload, yabai, cpu, calendar) read as disabled. Adam rejected it.
- **Root cause**: The subtle tone already encodes "inactive" on the spaces strip; reusing it for "secondary" gave one color two meanings.
- **Rule**: One color, one meaning. Subtle = inactive spaces only. Icons/controls stay at full text color (`ICON_COLOR=$RIGHT_TEXT_COLOR`); build icon/label hierarchy with size or weight, not the inactive tone.

### SF Pro digits are proportional — give live numbers a fixed, right-aligned box
- **Date**: 2026-11-03
- **Category**: Sketchybar
- **What happened**: CPU % and the clock shifted their neighbours on every update. Per-digit slots fixed it but made "1"s look stranded; SF Mono fixed that but Adam rejected the font.
- **Root cause**: SF Pro digits are proportional (a "1" ~30% narrower than an "8"), sketchybar can't enable tabular figures, and it sizes/aligns text by ink bounds.
- **Rule**: Live numbers get `label.width`/`icon.width` sized to the widest value + ink slack, `align=right` (CLOCK_WIDTH 52px for Heavy "10:48"; <50 clips the leading "1"). Stay in SF Pro. No seconds on the clock (they'd wobble visibly).

### Vertical alignment: measure glyph ink, don't trust sketchybar's centring
- **Date**: 2026-11-03
- **Category**: Sketchybar
- **What happened**: The bar "looked off" with no obvious cause. Measuring ink bounds showed text sat 0.75pt low, SF Symbols 1pt low, the volume symbol 1.5pt low, app-font icons 1.25pt above the space numbers, and the 13pt AM/PM baseline 1pt above the time's.
- **Root cause**: sketchybar centres each glyph's line box, not its visible ink; SF Pro caps and SF Symbols sit low in that box, app-font glyphs sit high.
- **Rule**: Defaults lift glyphs by `GLYPH_LIFT=1` (icon/label y_offset; pills unaffected). space_icons keep `label.y_offset=-1`, volume_icon gets +1 more, the clock's AM/PM label gets -1 so it shares the time's baseline. Verify with the ink-bounds script (all centres should land within ~0.75pt of the bar centre), not by eye.

### Live demo captures: detach space.sh first, and verify the value before every capture
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: A Semibold/Bold/Heavy comparison came out pixel-identical. Changing `--bar color/topmost` for the capture backdrop fired an event that re-ran plugins/space.sh, which re-applied Semibold before the screenshot. (A zsh `for s in $(...)` loop also failed to word-split, silently malforming the --set.)
- **Rule**: For live A/B captures, `sketchybar --set spaces_watcher script=""` first (a reload restores it), use explicit item lists or bash, and query the property right before each screenshot. Recreate the "before" state live from the current window state rather than reusing an older capture.

### Now Playing: media_change is dead on macOS 15.4+; long-running watchers must kill their children
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: The old media item never showed (sketchybar's media_change relies on MediaRemote, locked down in 15.4). The replacement watcher (plugins/media.sh, `media-control stream`) leaked its reader on every reload: media-control execs a perl adapter whose cmdline doesn't contain "media-control", so `pkill -f "media-control stream"` missed it.
- **Rule**: Use `media-control` (brew) for Now Playing. Any long-running process started from the rc writes its PID (`echo $$ > /tmp/...pid`) and the rc kills it with `pkill -P <pid>; kill <pid>` before starting a new one. Verify with `ps` across two reloads that exactly one instance survives.

### Animating an item open/closed inside a pill: animate icon/label widths, not `width`
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: The Gamify pause section animated `width` 0↔80. After resume the item was width 0 but the pill stayed 72pt too wide (and jumped to full width on the first opening frame).
- **Root cause**: A bracket's background spans its members' *drawn* extent. Text overflowing a 0-width item (even fully transparent) still counts.
- **Rule**: To collapse/expand an item, animate `icon.width`, `icon.padding_right`, `label.width` and `padding_left` to 0 / their open values (a fully collapsed item reports a 0 bounding rect). Verify by checking the bracket's width returns exactly to its pre-animation value after a full cycle.

### Volume widget vs. the Apollo + SoundSource
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: The volume icon showed "muted" and the slider did nothing on the UA Apollo Twin X, yet the keyboard volume knob worked. Initially misdiagnosed as "the Apollo can't be controlled from the Mac".
- **Root cause**: The Apollo exposes no CoreAudio volume/mute (`output volume` = "missing value"). SoundSource adds its own software volume for it and intercepts the volume keys; sketchybar's slider/volume_change only see macOS's volume. SoundSource has no AppleScript, only Shortcuts actions (Set Device Volume/Mute — no getter); its live level sits in a private archive (Sources.plist).
- **Rule**: When `output volume` is "missing value", show `hifispeaker.fill` and keep the slider closed (plugins/volume.sh, volume_click.sh); devices with a macOS volume get the normal icons + slider. Don't read SoundSource's private files. UA Mixer Engine (TCP 4710) exposes the MONITOR output's CRMonitorLevel/Mute if hardware monitor control is ever wanted.

### Fixed widths swallow padding — item `width`, `icon.width` and `label.width` alike
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: Three separate spacing bugs today: "UJAM45m" (tag label.width ate its padding_right), a cramped timer icon (icon.width ate icon.padding_right), and media equalizer bars overlapping into a blob (item width=3 ate padding_left).
- **Rule**: When a box has a fixed width, its own padding is ignored. Fold the gap into the width (label.width = text + gap), or size the content another way (bars: an empty `icon=""` with icon.width=3 keeps the item's padding). Verify spacing from bounding rects/screenshots, not from the config values.

### Popups: one row OR one column; `--query` takes one item; exited.global is per window
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: The Gamify start menu needed a chip row above a tag list. A popup is all-horizontal or all-vertical, so it's two popups: chips on a zero-width `gamify_anchor` (same x as the pill's start), tags on `gamify_start`, y_offsets stacked with PILL_GAP. The close-on-leave check first used `sketchybar --query a b`, which silently returns only `a`, so the menu closed under the cursor.
- **Rule**: Stack popups via separate anchors + y_offset. Query items one per call. `mouse.exited.global` fires when the cursor leaves the bar or any popup window — but not reliably when it leaves the bar straight after a click, and never while it slides along the bar — so menus also run the close check from the trigger items' `mouse.exited`, and every close re-checks the real cursor (JXA `NSEvent.mouseLocation`, as in gamify_menu.sh/media_hover.sh). A popup item's bounding_rect is in bar coordinates (top-left origin), usable for that check.

### sketchybar can't see horizontal scroll; JXA can't synthesize it
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: Swipe-to-spin for the Gamify length carousel. `mouse.scrolled` fires for a sideways swipe but `SCROLL_DELTA`/`INFO.delta` is the vertical axis only (always 0). Testing was also misleading: JXA's `CGEventCreateScrollWheelEvent` (variadic) drops wheel2, so synthetic horizontal scrolls arrived as dx=0.
- **Rule**: Horizontal gestures need a helper: `plugins/gamify_scroll.swift` (NSEvent global scroll monitor — no permission needed for mouse events), built by items/gamify.sh into ~/.cache, run only while the menu is open and killed on close (it also self-exits when `gamify_menu.sh is_open` fails). Synthesize test scrolls from Swift (`CGEvent(scrollWheelEvent2Source:…)`), not JXA.

### Folder-tab menus: extend the pressed capsule past the bar's bottom
- **Date**: 2026-11-04
- **Category**: Sketchybar
- **What happened**: Drop-downs looked detached from their buttons. Sketchybar has no per-corner radii or custom shapes, but the bar window clips items at its bottom edge: growing the pressed capsule's background downward (height +24, y_offset −12 → top unchanged) clips its rounded bottom away, leaving a square-bottomed tab that runs into a popup anchored on the same item (y_offset −6 → starts at the pill's bottom). The panel's corner radius (MENU_RADIUS = 6) fits inside the tab's covered strip, so the seam disappears. Also: tokens derived from HEIGHT_L1 must be defined after it in sketchybarrc — an early definition silently produced −16 (shown as 4294967280).
- **Rule**: Use MENU_RADIUS / MENU_TAB_HEIGHT / MENU_TAB_OFFSET for any new drop-down (gear: controls.sh; Gamify: gamify_menu.sh). Never clean up test items with a loose regex like `/p\..*/` — it matched real items (`gamify.step.prev`).

### display_added fires before the new display has a space — never act on focus
- **Date**: 2026-11-11
- **Category**: Yabai
- **What happened**: Plugging in the external monitor left 3 laptop spaces + 1 external space instead of 3 + 6. Log: "Display 2: creating 6 spaces (0 -> 6)" then "Display 1: removing 8 spaces (11 -> 3)". Separately, manually adding a desktop never showed up in the bar.
- **Root cause**: At display_added time yabai lists the new display with `spaces: []`. `display --focus 2` failed (nothing to focus), so bare `space --create` used the laptop's active space, and the destroy pass deleted them all. The bar's space items are built once at rc load, and nothing rebuilt them on space_created/space_destroyed.
- **Rule**: Never act once on a snapshot taken right after a hotplug/wake — the timing varies by monitor and connection. display_watcher is a converge loop: every round it re-reads real state, treats "a display with 0 spaces" as not-settled-yet, fixes what's off, and verifies next round (up to 20). Triggers that arrive mid-run wait for the lock instead of being dropped (no cooldown skip — runs are idempotent). Always `yabai -m space --create <display>` (explicit target), never focus-then-create. Space count changes go through `plugins/space_count_changed.sh` (debounced, defers to display_watcher so reloads never overlap).

### Never destroy a space that has windows
- **Date**: 2026-11-11
- **Category**: Yabai
- **What happened**: display_watcher's trim pass moved windows off "extra" spaces and destroyed them. It runs on system_woke too, so desktops Adam added (e.g. via the bar's "+") were wiped after every sleep, piling their windows onto the first space.
- **Root cause**: Space targets (3 laptop / 6 external / 5 standalone) were treated as exact counts instead of defaults.
- **Rule**: Targets are minimums for creation; the trim pass may only destroy *empty* spaces (`query --windows --space` length 0, which includes minimized/hidden). A space with windows is intentional — keep it, even if that leaves the display above target.

### bounding_rects has one entry per display — never take `[0]`
- **Date**: 2026-11-12
- **Category**: Sketchybar
- **What happened**: On the MacBook + external monitor, the Gamify menu opened and closed itself a second later. The close-on-leave check (gamify_menu.sh) took `[.bounding_rects[]][0]` (display-1's pill) and tested the cursor's y against `0..bar height`, so a cursor on the external display's bar (global y −203) always read as "outside". The swipe helper and media_hover.sh had the same bug.
- **Root cause**: `bounding_rects` is keyed `display-N`, in global coordinates with a top-left origin (y = primary screen height − NSEvent y). A display that isn't showing the item (e.g. a popup open on another display) reports origin −9999.
- **Rule**: Hit-test the cursor against every display's rect, using each rect's own y-range, and skip −9999 entries. Test multi-display with a compiled `CGWarpMouseCursorPosition` helper. Let animations settle (~1s) between steps, and remember a script-run `toggle` opens the popup on the *focused* display, not the one under the cursor.
