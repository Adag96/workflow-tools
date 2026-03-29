#!/usr/bin/env python3
import os
import sys
import tty
import termios
import re
from datetime import datetime
from collections import defaultdict

# Paths
CONFIG_FILE = os.path.expanduser('~/.big_clean_threshold')
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

def find_files(directories, threshold_mb):
    threshold_bytes, repeat_min = threshold_mb * 1024 * 1024, REPEAT_MIN_MB * 1024 * 1024
    big_files, potential_repeats = [], defaultdict(list)
    home = os.path.expanduser('~')
    print(f"\n{BLUE}Scanning...{ENDC}")
    for directory in directories:
        directory = os.path.abspath(directory)
        if not os.path.exists(directory): continue
        for root, dirs, files in os.walk(directory, topdown=True):
            if root == home:
                dirs[:] = [d for d in dirs if d in {'Downloads', 'Movies', 'Desktop', 'Documents', 'Library', 'Music', 'Pictures'} or not d.startswith('.')]
            if root == os.path.join(home, 'Library'): dirs[:] = [d for d in dirs if d in ['Caches', 'Application Support']]
            if 'node_modules' in dirs: dirs.remove('node_modules')
            if '.git' in dirs: dirs.remove('.git')
            for name in files:
                path = os.path.join(root, name)
                try:
                    if not os.path.islink(path):
                        size = os.path.getsize(path)
                        if size >= threshold_bytes: big_files.append({'path': path, 'size': size, 'mtime': os.path.getmtime(path), 'type': 'BIG'})
                        elif size >= repeat_min: potential_repeats[(root, re.sub(r'[_.-]v?\d+|\d{4}[-._]\d{2}[-._]\d{2}|copy|final|\(\d+\)', '', name.lower()).strip())].append({'path': path, 'size': size, 'mtime': os.path.getmtime(path)})
                except: continue
    final_list = []
    for f in sorted(big_files, key=lambda x: x['size'], reverse=True): final_list.append(f)
    for group in sorted([sorted(g, key=lambda x: x['mtime'], reverse=True) for g in potential_repeats.values() if len(g) >= 2], key=lambda g: sum(i['size'] for i in g), reverse=True):
        for i, f in enumerate(group): f['type'] = 'REPEAT'; f['group_newest'] = (i == 0); final_list.append(f)
    return final_list

def show_menu_option(number, name, description, selected):
    pointer = f"{CYAN}➤ " if selected else "  "
    color = CYAN if selected else NC
    print(f"{pointer}{color}{number}. {name:<14}{NC} {description}")

def results_view(files):
    if not files: print(f"\n✔ No issues found."); getch(); return
    idx, total_saved = 0, 0
    while True:
        print_big_clean_header()
        start, end = max(0, idx - 7), min(len(files), max(0, idx - 7) + 15)
        for i in range(start, end):
            f = files[i]; path = f['path'].replace(os.path.expanduser('~'), '~')
            label = "[BIG]" if f['type'] == 'BIG' else ("[NEWEST]" if f.get('group_newest') else "[REPEAT]")
            pointer = f"{PINK}➤ {ENDC}" if i == idx else "  "
            color = PINK if i == idx else ENDC
            print(f"{pointer}{color}{label} {format_size(f['size']):>10}  │  {path}{ENDC}")
        print(f"\n{BLUE}───────────────────────────────────────────────────────────────────────{ENDC}")
        saved = f" {GREEN}{BOLD}Saved: {format_size(total_saved)}{ENDC}" if total_saved > 0 else ""
        print(f"{GREY}↑ ↓   |   O Open   |   D Delete   |   Q Back{ENDC}{saved}")
        key = getch()
        if key == '\x1b[A': idx = (idx - 1) % len(files)
        elif key == '\x1b[B': idx = (idx + 1) % len(files)
        elif key.lower() == 'q': return
        elif key.lower() == 'o': os.system(f'open -R "{files[idx]["path"]}"')
        elif key.lower() == 'd':
            print(f"\n{YELLOW}Delete this file? (y/n){NC} ", end='', flush=True)
            if getch().lower() == 'y':
                try: os.remove(files[idx]['path']); total_saved += files[idx]['size']; files.pop(idx); idx = min(idx, len(files)-1)
                except: pass

def big_clean_submenu():
    global THRESHOLD_MB
    idx = 0
    while True:
        options = [
            ("Quick Scan", "Downloads, Movies, Desktop"),
            ("Current Dir", "Scan current working directory"),
            ("Deep Scan", "Full home directory scan"),
            ("Threshold", f"Set minimum size ({THRESHOLD_MB} MB)"),
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
            results_view(find_files([os.path.expanduser('~/Downloads'), os.path.expanduser('~/Library/Application Support/Adobe/Common/Media Cache Files'), os.path.expanduser('~/Movies'), os.path.expanduser('~/Desktop')] if idx == 0 else (['.'] if idx == 1 else [os.path.expanduser('~')]), THRESHOLD_MB))

def main():
    load_config()
    options = [
        ("Mole", "Automatic system cleanup"),
        ("Big Clean", "Find and remove oversized files"),
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
            else: big_clean_submenu()

if __name__ == "__main__":
    main()
