#!/usr/bin/env python3
import os
import subprocess
import sys
import tty
import termios
import re
from datetime import datetime
from collections import defaultdict

# Paths
CONFIG_FILE = os.path.expanduser('~/.big_clean_threshold')
HIDDEN_FILE = os.path.expanduser('~/.big_clean_hidden')
MOLE_PATH = '/usr/local/bin/mo'

# ANSI Color Codes (matching Mole's style)
GREEN = '\033[0;32m'
BLUE = '\033[1;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[0;33m'
PURPLE = '\033[0;35m'
RED = '\033[0;31m'
GRAY = '\033[0;90m'
NC = '\033[0m'
BOLD = '\033[1m'

# Legacy aliases
TEAL = CYAN
PINK = CYAN
GREY = GRAY
ENDC = NC

THRESHOLD_MB = 300
REPEAT_MIN_MB = 50

def load_config():
    global THRESHOLD_MB
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                THRESHOLD_MB = int(f.read().strip())
        except: pass

def save_config():
    try:
        with open(CONFIG_FILE, 'w') as f:
            f.write(str(THRESHOLD_MB))
    except: pass

def load_hidden():
    if os.path.exists(HIDDEN_FILE):
        try:
            with open(HIDDEN_FILE, 'r') as f:
                return set(line.strip() for line in f if line.strip())
        except: pass
    return set()

def add_hidden(paths):
    try:
        with open(HIDDEN_FILE, 'a') as f:
            for p in paths:
                f.write(p + '\n')
    except: pass

def remove_hidden(path):
    hidden = load_hidden()
    hidden.discard(path)
    try:
        with open(HIDDEN_FILE, 'w') as f:
            for p in sorted(hidden):
                f.write(p + '\n')
    except: pass

def getch():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
        if ch == '\x1b':
            ch += sys.stdin.read(2)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def print_main_header():
    os.system('clear')
    print(fr"""{GREEN}
  ______    ______ _____ _____ __  __    ____ _     _____     _     _   _
 / ___ \ \ / / ___|_   _| ____|  \/  |  / ___| |   | ____|   / \   | \ | |
 \___ \ \ V /\___ \ | | |  _| | |\/| | | |   | |   |  _|    / _ \  |  \| |
  ___) | | |  ___) || | | |___| |  | | | |___| |___| |___  / ___ \ | |\  |
 |____/  |_| |____/ |_| |_____|_|  |_|  \____|_____|_____/_/    \_\|_| \_|
{NC}""")

def print_big_clean_header():
    os.system('clear')
    print(fr"""{GREEN}
  ____  ___ ____     ____ _     _____     _      _   _
 | __ )|_ _/ ___|   / ___| |   | ____|   / \    | \ | |
 |  _ \ | | |  _   | |   | |   |  _|    / _ \   |  \| |
 | |_) || | |_| |  | |___| |___| |___  / ___ \  | |\  |
 |____/|___\____|   \____|_____|_____/_/    \_\|_| \_|
{NC}         {GREEN}Find and remove oversized files.{NC}
""")

def format_size(size_bytes):
    if size_bytes == 0: return "0 B"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:3.2f} {unit}"
        size_bytes /= 1024.0

import math
import time

# File type deletion priority tiers (score out of 35)
TYPE_SCORES = {}
for ext in ['.exe', '.msi', '.deb', '.rpm', '.appimage']:
    TYPE_SCORES[ext] = 35
for ext in ['.pkg', '.dmg']:
    TYPE_SCORES[ext] = 30
for ext in ['.zip', '.rar', '.7z', '.tar.gz', '.tar', '.gz', '.tgz', '.bz2', '.xz']:
    TYPE_SCORES[ext] = 25
for ext in ['.iso', '.img']:
    TYPE_SCORES[ext] = 20
for ext in ['.tmp', '.part', '.crdownload']:
    TYPE_SCORES[ext] = 10
for ext in ['.wav', '.psd', '.fbx']:
    TYPE_SCORES[ext] = 5

def score_file(f):
    """Score a file for deletion priority (0-100). Higher = stronger candidate."""
    # Size score (0-40): logarithmic, 50MB=0, 10GB=40
    size_mb = f['size'] / (1024 * 1024)
    size_score = min(40, max(0, (math.log2(size_mb / 50) / math.log2(10240 / 50)) * 40)) if size_mb > 0 else 0

    # Type score (0-35): based on file extension
    name = os.path.basename(f['path']).lower()
    type_score = 0
    if name.endswith('.tar.gz'):
        type_score = TYPE_SCORES['.tar.gz']
    else:
        ext = os.path.splitext(name)[1]
        type_score = TYPE_SCORES.get(ext, 0)

    # Age score (0-25): linear, 0 at today, 25 at 1+ year old
    age_days = (time.time() - f['mtime']) / 86400
    age_score = min(25, (age_days / 365) * 25)

    return size_score + type_score + age_score

LIBRARY_DIRS_DEEP = ['Caches', 'Application Support', 'Messages', 'Developer', 'Containers']

def find_files(directories, threshold_mb, library_dirs=None, hidden=None):
    threshold_bytes, repeat_min = threshold_mb * 1024 * 1024, REPEAT_MIN_MB * 1024 * 1024
    big_files, potential_repeats = [], defaultdict(list)
    hidden = hidden or set()
    home = os.path.expanduser('~')
    lib_allowlist = library_dirs if library_dirs is not None else ['Caches', 'Application Support']
    print(f"\n{BLUE}Scanning...{ENDC}")
    for directory in directories:
        directory = os.path.abspath(directory)
        if not os.path.exists(directory): continue
        for root, dirs, files in os.walk(directory, topdown=True):
            if root == home:
                dirs[:] = [d for d in dirs if d in {'Downloads', 'Movies', 'Desktop', 'Documents', 'Library', 'Music', 'Pictures'} or not d.startswith('.')]
            if root == os.path.join(home, 'Library'): dirs[:] = [d for d in dirs if d in lib_allowlist]
            if 'node_modules' in dirs: dirs.remove('node_modules')
            if '.git' in dirs: dirs.remove('.git')
            for name in files:
                path = os.path.join(root, name)
                try:
                    if not os.path.islink(path) and path not in hidden:
                        size = os.path.getsize(path)
                        if size >= threshold_bytes: big_files.append({'path': path, 'size': size, 'mtime': os.path.getmtime(path), 'type': 'BIG'})
                        elif size >= repeat_min: potential_repeats[(root, re.sub(r'[_.-]v?\d+|\d{4}[-._]\d{2}[-._]\d{2}|copy|final|\(\d+\)', '', name.lower()).strip())].append({'path': path, 'size': size, 'mtime': os.path.getmtime(path)})
                except: continue
    # Score and sort big files by smart ranking
    for f in big_files:
        f['score'] = score_file(f)
    final_list = sorted(big_files, key=lambda x: x['score'], reverse=True)
    # Repeats appended after, sorted by group total size
    for group in sorted([sorted(g, key=lambda x: x['mtime'], reverse=True) for g in potential_repeats.values() if len(g) >= 2], key=lambda g: sum(i['size'] for i in g), reverse=True):
        for i, f in enumerate(group):
            f['type'] = 'REPEAT'; f['group_newest'] = (i == 0); f['score'] = score_file(f)
            final_list.append(f)
    return final_list

def show_menu_option(number, name, description, selected):
    pointer = f"{CYAN}➤ " if selected else "  "
    color = CYAN if selected else NC
    print(f"{pointer}{color}{number}. {name:<14}{NC} {description}")

SORT_MODES = [
    ('Smart',  lambda f: f.get('score', 0)),
    ('Size',   lambda f: f['size']),
    ('Oldest', lambda f: -f['mtime']),
    ('Newest', lambda f: f['mtime']),
]

def results_view(files):
    if not files: print(f"\n✔ No issues found."); getch(); return
    idx, total_saved = 0, 0
    selected = set()
    sort_idx = 0
    files.sort(key=SORT_MODES[sort_idx][1], reverse=True)
    while True:
        print_big_clean_header()
        visible = os.get_terminal_size().lines - 11  # header ~8 lines + footer 3 lines
        visible = max(visible, 5)
        half = visible // 2
        start = max(0, min(idx - half, len(files) - visible))
        end = min(len(files), start + visible)
        term_width = os.get_terminal_size().columns
        for i in range(start, end):
            f = files[i]; path = f['path'].replace(os.path.expanduser('~'), '~')
            label = "[BIG]" if f['type'] == 'BIG' else ("[NEWEST]" if f.get('group_newest') else "[REPEAT]")
            score = f.get('score', 0)
            score_color = RED if score >= 60 else YELLOW if score >= 35 else GRAY
            is_selected = i in selected
            if i == idx:
                marker = f"{PINK}➤ " if not is_selected else f"{YELLOW}◉ "
                color = PINK if not is_selected else YELLOW
            else:
                marker = f"  " if not is_selected else f"{YELLOW}● {ENDC}"
                color = ENDC if not is_selected else YELLOW
            # Visible prefix: "➤ [REPEAT]  999pt    999.99 MB  │  "
            prefix_len = 2 + len(label) + 6 + 12 + 5  # marker + label + score field + size field + " │  "
            max_path = term_width - prefix_len
            if max_path > 0 and len(path) > max_path:
                # Middle-truncate: keep start + end, prioritize the filename
                keep_end = min(len(path) // 2, max_path * 2 // 3)
                keep_start = max_path - keep_end - 1  # 1 for …
                if keep_start < 1: keep_start, keep_end = 1, max_path - 2
                path = path[:keep_start] + '…' + path[-keep_end:]
            print(f"{marker}{color}{label} {score_color}{score:4.0f}pt{ENDC} {color}{format_size(f['size']):>10}  │  {path}{ENDC}")
        print(f"\n{BLUE}───────────────────────────────────────────────────────────────────────{ENDC}")
        saved = f"  {GREEN}{BOLD}Saved: {format_size(total_saved)}{ENDC}" if total_saved > 0 else ""
        sel_info = f"  {YELLOW}{len(selected)} selected ({format_size(sum(files[i]['size'] for i in selected))}){ENDC}" if selected else ""
        sort_label = f"  {CYAN}Sort: {SORT_MODES[sort_idx][0]} (T){ENDC}"
        print(f"{GREY}↑ ↓   |   S Select   |   O Open   |   D Delete   |   H Hide   |   Q Back   |   {idx + 1} of {len(files)}{ENDC}{sort_label}{sel_info}{saved}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(files)
        elif key == '\x1b[B': idx = (idx + 1) % len(files)
        elif key.lower() == 'q': return
        elif key.lower() == 't':
            sort_idx = (sort_idx + 1) % len(SORT_MODES)
            selected.clear()
            files.sort(key=SORT_MODES[sort_idx][1], reverse=True)
            idx = 0
        elif key.lower() == 's':
            if idx in selected: selected.discard(idx)
            else: selected.add(idx)
        elif key.lower() == 'o': subprocess.run(['open', '-R', files[idx]['path']])
        elif key.lower() == 'h':
            targets = sorted(selected, reverse=True) if selected else [idx]
            count = len(targets)
            print(f"\n{YELLOW}Hide {count} file{'s' if count > 1 else ''} from future results? (y/n){NC} ", end='', flush=True)
            if getch().lower() == 'y':
                add_hidden([files[i]['path'] for i in targets])
                for i in targets:
                    files.pop(i)
                selected.clear()
                idx = min(idx, len(files) - 1) if files else 0
                if not files: return
        elif key.lower() == 'd':
            targets = sorted(selected, reverse=True) if selected else [idx]
            count = len(targets)
            total_size = sum(files[i]['size'] for i in targets)
            print(f"\n{YELLOW}Delete {count} file{'s' if count > 1 else ''} ({format_size(total_size)})? (y/n){NC} ", end='', flush=True)
            if getch().lower() == 'y':
                failed = 0
                for i in targets:  # descending order, so pops don't shift pending indices
                    try:
                        os.remove(files[i]['path'])
                        total_saved += files[i]['size']
                        files.pop(i)
                    except OSError:
                        failed += 1
                selected.clear()
                idx = min(idx, len(files) - 1) if files else 0
                if failed:
                    print(f"\n{YELLOW}{failed} file{'s' if failed > 1 else ''} could not be deleted (kept in list) — press any key{NC} ", end='', flush=True)
                    getch()
                if not files: return

def hidden_files_view():
    while True:
        hidden = sorted(load_hidden())
        print_big_clean_header()
        if not hidden:
            print(f"  {GRAY}No hidden files.{NC}")
            print(f"\n{GRAY}Q Back{NC}")
            getch()
            return
        idx = 0
        while True:
            print_big_clean_header()
            visible = os.get_terminal_size().lines - 11
            visible = max(visible, 5)
            half = visible // 2
            start = max(0, min(idx - half, len(hidden) - visible))
            end = min(len(hidden), start + visible)
            for i in range(start, end):
                path = hidden[i].replace(os.path.expanduser('~'), '~')
                if i == idx:
                    print(f"{PINK}➤ {path}{ENDC}")
                else:
                    print(f"  {path}")
            print(f"\n{BLUE}───────────────────────────────────────────────────────────────────────{ENDC}")
            print(f"{GREY}↑ ↓   |   U Unhide   |   Q Back   |   {idx + 1} of {len(hidden)}{ENDC}")
            key = getch()
            if key == '\x1b[A': idx = (idx - 1) % len(hidden)
            elif key == '\x1b[B': idx = (idx + 1) % len(hidden)
            elif key.lower() == 'q': return
            elif key.lower() == 'u':
                path = hidden[idx]
                short = path.replace(os.path.expanduser('~'), '~')
                print(f"\n{YELLOW}Unhide {short}? (y/n){NC} ", end='', flush=True)
                if getch().lower() == 'y':
                    remove_hidden(path)
                    hidden = sorted(load_hidden())
                    if not hidden: return
                    idx = min(idx, len(hidden) - 1)

def big_clean_submenu():
    global THRESHOLD_MB
    idx = 0
    while True:
        hidden = load_hidden()
        hidden_desc = f"Manage hidden paths ({len(hidden)} hidden)" if hidden else "Manage hidden paths (none)"
        options = [
            ("Quick Scan", "Downloads, Desktop, Movies, Documents, Caches"),
            ("Current Dir", "Scan current working directory"),
            ("Deep Scan", "Full home directory scan"),
            ("Threshold", f"Set minimum size ({THRESHOLD_MB} MB)"),
            ("Hidden Files", hidden_desc),
        ]
        print_big_clean_header()
        for i, (name, desc) in enumerate(options):
            show_menu_option(i + 1, name, desc, i == idx)
        print(f"\n{GRAY}↑↓   |   Enter   |   Q Back{NC}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(options)
        elif key == '\x1b[B': idx = (idx + 1) % len(options)
        elif key.lower() == 'q': return
        elif key in ('\r', '\n'):
            if idx == 3:
                print_big_clean_header(); sys.stdout.write(f"{YELLOW}New threshold (MB): {NC}"); sys.stdout.flush()
                termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, termios.tcgetattr(sys.stdin.fileno()))
                try: line = sys.stdin.readline(); THRESHOLD_MB = int(line.strip()); save_config()
                except: pass
                continue
            elif idx == 4:
                hidden_files_view()
                continue
            hidden = load_hidden()
            if idx == 0:
                quick_dirs = [os.path.expanduser(p) for p in [
                    '~/Downloads', '~/Desktop', '~/Movies', '~/Documents',
                    '~/Library/Caches',
                    '~/Library/Application Support/Adobe/Common/Media Cache Files',
                ]]
                results_view(find_files(quick_dirs, THRESHOLD_MB, hidden=hidden))
            elif idx == 1:
                results_view(find_files(['.'], THRESHOLD_MB, hidden=hidden))
            else:
                results_view(find_files([os.path.expanduser('~')], THRESHOLD_MB, library_dirs=LIBRARY_DIRS_DEEP, hidden=hidden))

# ============================================================================
# MEMORY HOGS — find and kill heavy / forgotten processes
# ============================================================================
import signal
import getpass

# Never offer to kill these — killing them can hang or crash the session/OS.
PROTECTED_NAMES = {
    'WindowServer', 'kernel_task', 'launchd', 'loginwindow', 'Finder',
    'Dock', 'SystemUIServer', 'coreaudiod', 'cfprefsd', 'distnoted',
    'mds', 'mds_stores', 'mdworker', 'mdworker_shared', 'mdsync',
    'SkyLight', 'AppleNeuralEngine', 'hidd', 'powerd', 'bluetoothd',
    'Terminal', 'iTerm2', 'iTerm', 'ghostty', 'kitty', 'alacritty', 'WezTerm',
    'tmux', 'tmux: server', 'sshd', 'zsh', 'bash', 'python3', 'Python',
    'sketchybar', 'yabai',
}

# Browser processes whose many helpers get rolled into one grouped row.
BROWSER_PARENTS = {
    'Brave Browser': 'Brave Browser',
    'Google Chrome': 'Google Chrome',
    'Safari': 'Safari',
    'firefox': 'firefox',
    'Arc': 'Arc',
    'Microsoft Edge': 'Microsoft Edge',
}
BROWSER_HELPER_HINT = 'Helper'

# Dev-server / local-host process hints (matched against the full command).
DEV_HINTS = [
    'node', 'vite', 'webpack', 'next', 'nuxt', 'npm', 'pnpm', 'yarn', 'bun',
    'deno', 'http.server', 'flask', 'gunicorn', 'uvicorn', 'rails', 'puma',
    'php -S', 'ngrok', 'webpack-dev-server', 'ng serve', 'astro', 'remix',
    'esbuild', 'rollup', 'parcel', 'jekyll', 'hugo', 'streamlit',
]

def print_memory_header():
    os.system('clear')
    print(fr"""{GREEN}
  __  __ _____ __  __  ___  ______   __  _   _  ___   ____ ____
 |  \/  | ____|  \/  |/ _ \|  _ \ \ / / | | | |/ _ \ / ___/ ___|
 | |\/| |  _| | |\/| | | | | |_) \ V /  | |_| | | | | |  _\___ \
 | |  | | |___| |  | | |_| |  _ < | |   |  _  | |_| | |_| |___) |
 |_|  |_|_____|_|  |_|\___/|_| \_\|_|   |_| |_|\___/ \____|____/
{NC}         {GREEN}Find and kill heavy / forgotten processes.{NC}
""")

def current_user():
    try: return getpass.getuser()
    except: return os.environ.get('USER', '')

def friendly_name(command, comm):
    """Best-effort human name for a process from its full command string."""
    # 1) Prefer the deepest .app bundle name (e.g. "Google Chrome Helper" -> "Google Chrome").
    apps = re.findall(r'/([^/]+)\.app/', command)
    if apps:
        return apps[0]
    # 2) Framework/XPC services and other bundles -> use the bundle basename without extension.
    m = re.search(r'/([^/]+)\.(?:framework|xpc|bundle|appex)/', command)
    if m:
        return m.group(1)
    # 3) Otherwise the basename of the executable path (strip leading args).
    exe = command.split()[0] if command.split() else comm
    base = os.path.basename(exe)
    # A bare truncated comm (e.g. "coreau", "bi") is worse than the real basename.
    if base and base not in ('', '/'):
        return base
    return comm or '?'

def memory_pressure_summary():
    """Return a short human-readable memory / swap status line."""
    lines = []
    try:
        total_bytes = int(subprocess.check_output(['sysctl', '-n', 'hw.memsize']).strip())
    except:
        total_bytes = 0
    try:
        out = subprocess.check_output(['vm_stat'], text=True)
        page_size = 4096
        m = re.search(r'page size of (\d+)', out)
        if m: page_size = int(m.group(1))
        stats = {}
        for line in out.splitlines():
            mm = re.match(r'"?([\w\s]+?)"?:\s+([\d.]+)\.?', line)
            if mm: stats[mm.group(1).strip()] = int(float(mm.group(2)))
        free = (stats.get('Pages free', 0) + stats.get('Pages inactive', 0)) * page_size
        wired = stats.get('Pages wired down', 0) * page_size
        compressed = stats.get('Pages occupied by compressor', 0) * page_size
        if total_bytes:
            lines.append(f"Total RAM: {format_size(total_bytes)}   "
                         f"Free-ish: {format_size(free)}   "
                         f"Wired: {format_size(wired)}   "
                         f"Compressed: {format_size(compressed)}")
    except Exception:
        pass
    try:
        # Current swap usage — the real tell for "out of memory" freezes.
        swap = subprocess.check_output(['sysctl', '-n', 'vm.swapusage'], text=True).strip()
        lines.append(f"Swap: {swap}")
    except Exception:
        pass
    try:
        # macOS's own pressure verdict.
        mp = subprocess.check_output(['memory_pressure', '-Q'], text=True, stderr=subprocess.DEVNULL).strip()
        mm = re.search(r'System-wide memory free percentage:\s*(\d+)%', mp)
        if mm: lines.append(f"System memory free: {mm.group(1)}%")
    except Exception:
        pass
    return lines

def scan_processes(group_browsers=True):
    """Return a list of process dicts sorted by memory. Browsers optionally grouped."""
    user = current_user()
    procs = []
    try:
        # pid, %cpu, rss(KB), user, elapsed-time, full command.
        # NOTE: no comm= — ps truncates comm to 15 chars AND glues it to command,
        # which corrupts the executable path. The full command gives the real path.
        out = subprocess.check_output(
            ['ps', '-axo', 'pid=,%cpu=,rss=,user=,etime=,command='],
            text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    self_pid = os.getpid()
    ppid_self = os.getppid()
    for line in out.splitlines():
        parts = line.split(None, 5)
        if len(parts) < 6: continue
        try:
            pid = int(parts[0]); cpu = float(parts[1]); rss_kb = int(parts[2])
        except ValueError:
            continue
        puser = parts[3]; etime = parts[4]
        command = parts[5]
        # Short name = basename of the (untruncated) executable path.
        comm = os.path.basename(command.split()[0]) if command.split() else command
        friendly = friendly_name(command, comm)
        procs.append({
            'pid': pid, 'cpu': cpu, 'rss': rss_kb * 1024, 'user': puser,
            'etime': etime, 'command': command, 'comm': comm, 'friendly': friendly,
        })
    # Determine killability.
    def killable(p):
        if p['pid'] < 500: return False
        if p['pid'] in (self_pid, ppid_self): return False
        if p['user'] not in (user, ''): return False  # only our own procs
        if p['comm'] in PROTECTED_NAMES or p['friendly'] in PROTECTED_NAMES: return False
        return True

    if group_browsers:
        grouped = {}
        singles = []
        for p in procs:
            parent = None
            for key, label in BROWSER_PARENTS.items():
                # Only group genuine browser processes: the friendly name is exactly
                # the browser (resolved from its .app bundle), or the command runs out
                # of that browser's .app bundle. A bare substring match wrongly sweeps
                # in unrelated XPC helpers (e.g. SafariPlatformSupport) for apps that
                # aren't even running.
                if p['friendly'] == key or f'/{key}.app/' in p['command']:
                    parent = label; break
            if parent:
                g = grouped.setdefault(parent, {
                    'friendly': parent, 'comm': parent, 'rss': 0, 'cpu': 0.0,
                    'pids': [], 'user': p['user'], 'etime': p['etime'],
                    'command': parent, 'is_group': True,
                })
                g['rss'] += p['rss']; g['cpu'] += p['cpu']; g['pids'].append(p['pid'])
            else:
                p['pids'] = [p['pid']]; p['is_group'] = False
                singles.append(p)
        result = list(grouped.values()) + singles
        for g in grouped.values():
            g['killable'] = all(pid >= 500 for pid in g['pids']) and g['user'] in (user, '')
        for s in singles:
            s['killable'] = killable(s)
    else:
        result = procs
        for p in result:
            p['pids'] = [p['pid']]; p['is_group'] = False; p['killable'] = killable(p)

    result.sort(key=lambda x: x['rss'], reverse=True)
    return result

def scan_dev_servers():
    """Return dev-server processes that are LISTENING on a TCP port."""
    user = current_user()
    self_pid = os.getpid()
    listeners = {}  # pid -> set of ports
    try:
        out = subprocess.check_output(
            ['lsof', '-nP', '-iTCP', '-sTCP:LISTEN'],
            text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    for line in out.splitlines()[1:]:
        cols = line.split()
        if len(cols) < 9: continue
        try: pid = int(cols[1])
        except ValueError: continue
        addr = cols[-2] if cols[-1] == '(LISTEN)' else cols[-1]
        pm = re.search(r':(\d+)$', addr)
        if pm: listeners.setdefault(pid, set()).add(pm.group(1))
    if not listeners: return []
    servers = []
    for p in scan_processes(group_browsers=False):
        if p['pid'] not in listeners: continue
        cmd = p['command']
        if not any(h in cmd for h in DEV_HINTS): continue
        cwd = ''
        try:
            cwd_out = subprocess.check_output(
                ['lsof', '-a', '-p', str(p['pid']), '-d', 'cwd', '-Fn'],
                text=True, stderr=subprocess.DEVNULL)
            for l in cwd_out.splitlines():
                if l.startswith('n'): cwd = l[1:]; break
        except Exception:
            pass
        p['ports'] = sorted(listeners[p['pid']], key=lambda x: int(x))
        p['cwd'] = cwd
        p['killable'] = p['pid'] not in (self_pid, os.getppid()) and p['user'] in (user, '')
        servers.append(p)
    servers.sort(key=lambda x: int(x['ports'][0]) if x['ports'] else 0)
    return servers

def kill_pids(pids, label):
    """SIGTERM the pids; if any survive after a grace period, offer SIGKILL. Returns True if all gone."""
    for pid in pids:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
        except PermissionError: pass
    time.sleep(2)
    survivors = []
    for pid in pids:
        try: os.kill(pid, 0); survivors.append(pid)
        except OSError: pass
    if not survivors:
        return True
    print(f"\n{YELLOW}{len(survivors)} process(es) of {label} ignored SIGTERM. Force-kill (SIGKILL)? (y/n){NC} ",
          end='', flush=True)
    if getch().lower() == 'y':
        for pid in survivors:
            try: os.kill(pid, signal.SIGKILL)
            except OSError: pass
        return True
    return False

def process_results_view(procs, mode):
    """Interactive kill view. mode: 'hogs' or 'dev'."""
    if not procs:
        print(f"\n✔ Nothing found."); getch(); return
    idx = 0
    selected = set()
    while True:
        print_memory_header()
        if mode == 'hogs':
            for l in memory_pressure_summary():
                print(f"  {GRAY}{l}{NC}")
            print()
        visible = os.get_terminal_size().lines - (18 if mode == 'hogs' else 13)
        visible = max(visible, 5)
        half = visible // 2
        start = max(0, min(idx - half, len(procs) - visible))
        end = min(len(procs), start + visible)
        term_width = os.get_terminal_size().columns

        # Column layout (widths shared by header + rows so they line up).
        NAME_W, SIZE_W, CPU_W, PROC_W = 26, 10, 8, 6
        if mode == 'hogs':
            header = (f"  {BOLD}{'PROCESS':<{NAME_W}} {'MEMORY':>{SIZE_W}}  {'CPU':>{CPU_W}}  "
                      f"{'PROCS':>{PROC_W}}{NC}")
        else:
            header = (f"  {BOLD}{'PORT':<8} {'PROCESS':<12} {'MEMORY':>{SIZE_W}}  {'DIRECTORY'}{NC}")
        print(header)
        print(f"{BLUE}{'─' * min(term_width, 90)}{ENDC}")

        for i in range(start, end):
            p = procs[i]
            is_selected = i in selected
            can_kill = p.get('killable', False)
            if i == idx:
                marker = f"{PINK}➤ " if not is_selected else f"{YELLOW}◉ "
                color = PINK if not is_selected else YELLOW
            else:
                marker = "  " if not is_selected else f"{YELLOW}● {ENDC}"
                color = ENDC if not is_selected else YELLOW
            rss = format_size(p['rss'])
            lock = f"  {GRAY}🔒{ENDC}" if not can_kill else ""
            if mode == 'hogs':
                grp = f"×{len(p['pids'])}" if p.get('is_group') and len(p['pids']) > 1 else ""
                name = p['friendly']
                if len(name) > NAME_W: name = name[:NAME_W - 1] + '…'
                print(f"{marker}{color}{name:<{NAME_W}} {rss:>{SIZE_W}}  "
                      f"{p['cpu']:>{CPU_W - 2}.1f}%  {GRAY}{grp:>{PROC_W}}{ENDC}{lock}")
            else:
                ports = ','.join(p.get('ports', [])) or '?'
                cwd = p.get('cwd', '').replace(os.path.expanduser('~'), '~')
                name = p['friendly']
                if len(name) > 12: name = name[:11] + '…'
                prefix_len = 2 + 8 + 13 + SIZE_W + 4
                max_cwd = max(10, term_width - prefix_len)
                if len(cwd) > max_cwd:
                    cwd = '…' + cwd[-(max_cwd - 1):]
                print(f"{marker}{color}:{ports:<7} {name:<12} {rss:>{SIZE_W}}{ENDC}  "
                      f"{GRAY}{cwd}{ENDC}{lock}")
        print(f"\n{BLUE}{'─' * min(term_width, 90)}{ENDC}")
        sel_info = (f"  {YELLOW}{len(selected)} selected ({format_size(sum(procs[i]['rss'] for i in selected))}){ENDC}"
                    if selected else "")
        print(f"{GREY}↑ ↓   |   S Select   |   K Kill   |   O Activity Monitor   |   Q Back   |   "
              f"{idx + 1} of {len(procs)}{ENDC}{sel_info}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(procs)
        elif key == '\x1b[B': idx = (idx + 1) % len(procs)
        elif key.lower() == 'q': return
        elif key.lower() == 's':
            if not procs[idx].get('killable', False): continue
            if idx in selected: selected.discard(idx)
            else: selected.add(idx)
        elif key.lower() == 'o':
            subprocess.run(['open', '-a', 'Activity Monitor'])
        elif key.lower() == 'k':
            targets = sorted(selected) if selected else [idx]
            targets = [i for i in targets if procs[i].get('killable', False)]
            if not targets:
                print(f"\n{GRAY}Nothing killable selected (protected process).{NC} ", end='', flush=True)
                getch(); continue
            count = len(targets)
            total_rss = sum(procs[i]['rss'] for i in targets)
            names = ', '.join(procs[i]['friendly'] for i in targets[:3]) + ('…' if count > 3 else '')
            print(f"\n{YELLOW}Kill {count} process group(s) — {names} ({format_size(total_rss)})? (y/n){NC} ",
                  end='', flush=True)
            if getch().lower() != 'y': continue
            for i in sorted(targets, reverse=True):
                p = procs[i]
                if kill_pids(p['pids'], p['friendly']):
                    procs.pop(i)
            selected.clear()
            idx = min(idx, len(procs) - 1) if procs else 0
            if not procs: return

def memory_hogs_submenu():
    idx = 0
    options = [
        ("Resource Hogs", "Biggest RAM / CPU consumers right now"),
        ("Dev Servers", "Local-host servers listening on a port"),
        ("Mem Pressure", "macOS RAM / swap health readout"),
    ]
    while True:
        print_memory_header()
        for i, (name, desc) in enumerate(options):
            show_menu_option(i + 1, name, desc, i == idx)
        print(f"\n{GRAY}↑↓   |   Enter   |   Q Back{NC}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(options)
        elif key == '\x1b[B': idx = (idx + 1) % len(options)
        elif key.lower() == 'q': return
        elif key in ('\r', '\n'):
            if idx == 0:
                print(f"\n{BLUE}Scanning processes...{ENDC}")
                process_results_view(scan_processes(group_browsers=True), 'hogs')
            elif idx == 1:
                print(f"\n{BLUE}Scanning listening ports...{ENDC}")
                process_results_view(scan_dev_servers(), 'dev')
            else:
                print_memory_header()
                lines = memory_pressure_summary()
                if not lines:
                    print(f"  {GRAY}Could not read memory stats.{NC}")
                for l in lines:
                    print(f"  {CYAN}{l}{NC}")
                print(f"\n{GRAY}Q Back{NC}")
                while getch().lower() != 'q': pass

def main():
    load_config()
    options = [
        ("Mole", "Automatic system cleanup"),
        ("Big Clean", "Find and remove oversized files"),
        ("Memory Hogs", "Find and kill heavy / forgotten processes"),
    ]
    idx = 0
    while True:
        print_main_header()
        for i, (name, desc) in enumerate(options):
            show_menu_option(i + 1, name, desc, i == idx)
        print(f"\n{GRAY}↑↓   |   Enter   |   Q Quit{NC}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(options)
        elif key == '\x1b[B': idx = (idx + 1) % len(options)
        elif key.lower() == 'q': sys.exit()
        elif key in ('\r', '\n'):
            if idx == 0: os.system(MOLE_PATH)
            elif idx == 1: big_clean_submenu()
            else: memory_hogs_submenu()

if __name__ == "__main__":
    main()
