#!/usr/bin/env python3
import os
import sys
import tty
import termios
import subprocess

# Config
CONFIG_FILE = os.path.expanduser('~/.repo_tracker_repos')
DISCOVER_DIR = os.path.expanduser('~/Developer')

# ANSI Color Codes (matching big-cleaner style)
GREEN = '\033[0;32m'
BLUE = '\033[1;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[0;33m'
PURPLE = '\033[0;35m'
PINK = '\033[1;35m'
RED = '\033[0;31m'
GRAY = '\033[0;90m'
NC = '\033[0m'
BOLD = '\033[1m'


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


def print_header():
    os.system('clear')
    print(f"""
  {PINK} ____  _____ ____   ___  {CYAN}  ____ _____  _  _____
  {PINK}|  _ \\| ____|  _ \\ / _ \\ {CYAN} / ___|_   _|/ \\|_   _|
  {PINK}| |_) |  _| | |_) | | | |{CYAN} \\___ \\ | | / _ \\ | |
  {PINK}|  _ <| |___|  __/| |_| |{CYAN}  ___) || |/ ___ \\| |
  {PINK}|_| \\_\\_____|_|    \\___/  {CYAN}|____/ |_/_/   \\_\\_|
{NC}         {GREEN}Git repository status dashboard.{NC}
""")


def load_repos():
    """Load repos as list of (path, alias, group) tuples. Config format: path|alias|group (alias/group optional)."""
    if not os.path.exists(CONFIG_FILE):
        return []
    entries = []
    with open(CONFIG_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('|')
            path = parts[0].strip()
            alias = parts[1].strip() if len(parts) > 1 else ''
            group = parts[2].strip() if len(parts) > 2 else ''
            entries.append((path, alias, group))
    return entries


def save_repos(repos):
    """Save list of (path, alias, group) tuples."""
    with open(CONFIG_FILE, 'w') as f:
        for path, alias, group in repos:
            if group:
                f.write(f"{path}|{alias}|{group}\n")
            elif alias:
                f.write(f"{path}|{alias}\n")
            else:
                f.write(f"{path}\n")


def get_display_name(path, alias):
    """Return alias if set, otherwise shortened path."""
    if alias:
        return alias
    return path.replace(os.path.expanduser('~'), '~')


def git_cmd(repo_path, args):
    try:
        result = subprocess.run(
            ['git', '-C', repo_path] + args,
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.rstrip()
    except:
        return ''


def get_repo_status(repo_path, alias='', group=''):
    path = os.path.expanduser(repo_path)
    if not os.path.isdir(os.path.join(path, '.git')):
        return None

    branch = git_cmd(path, ['rev-parse', '--abbrev-ref', 'HEAD']) or '???'

    # Porcelain status for counts
    status_output = git_cmd(path, ['status', '--porcelain'])
    lines = [l for l in status_output.split('\n') if l]
    staged = sum(1 for l in lines if l[0] in 'MADRC')
    modified = sum(1 for l in lines if l[1] in 'MD')
    untracked = sum(1 for l in lines if l[:2] == '??')

    # Ahead/behind
    ahead, behind = 0, 0
    ab_output = git_cmd(path, ['rev-list', '--left-right', '--count', f'{branch}...@{{u}}'])
    if ab_output and '\t' in ab_output:
        parts = ab_output.split('\t')
        ahead, behind = int(parts[0]), int(parts[1])

    # Stash count
    stash_output = git_cmd(path, ['stash', 'list'])
    stash_count = len([l for l in stash_output.split('\n') if l]) if stash_output else 0

    return {
        'path': repo_path,
        'alias': alias,
        'group': group,
        'display': get_display_name(repo_path, alias),
        'branch': branch,
        'staged': staged,
        'modified': modified,
        'untracked': untracked,
        'ahead': ahead,
        'behind': behind,
        'stash': stash_count,
    }


def build_state_parts(status):
    """Build state text parts matching p10k symbols: +staged !modified ?untracked."""
    parts = []
    if status['staged']:
        parts.append(f"+{status['staged']}")
    if status['modified']:
        parts.append(f"!{status['modified']}")
    if status['untracked']:
        parts.append(f"?{status['untracked']}")
    return parts


def build_state_colored(status):
    """Build state string with per-indicator colors.
    +staged = yellow (pending), !modified = red (urgent), ?untracked = gray (info)."""
    if not status['staged'] and not status['modified'] and not status['untracked']:
        return f"{GREEN}clean{NC}", "clean"
    segments = []
    plain_parts = []
    if status['staged']:
        segments.append(f"{YELLOW}+{status['staged']}{NC}")
        plain_parts.append(f"+{status['staged']}")
    if status['modified']:
        segments.append(f"{RED}!{status['modified']}{NC}")
        plain_parts.append(f"!{status['modified']}")
    if status['untracked']:
        segments.append(f"{GRAY}?{status['untracked']}{NC}")
        plain_parts.append(f"?{status['untracked']}")
    return ' '.join(segments), ' '.join(plain_parts)


def format_status_line(status, selected, col_widths):
    name = status['display']
    pointer = f"{CYAN}> " if selected else "  "
    color = CYAN if selected else ''

    # State indicator (colored per type)
    state_colored, state_plain = build_state_colored(status)

    # Remote status
    remote_parts = []
    if status['ahead']:
        remote_parts.append(f"+{status['ahead']}")
    if status['behind']:
        remote_parts.append(f"-{status['behind']}")
    if remote_parts:
        remote_text = ' '.join(remote_parts)
        remote_color = PURPLE
    else:
        remote_text = "--"
        remote_color = GRAY

    # Stash
    stash_text = f"*{status['stash']}" if status['stash'] else ""

    # Build line with exact padding on plain text
    name_col = name.ljust(col_widths[0])
    state_padding = ' ' * (col_widths[1] - len(state_plain))
    remote_col = remote_text.ljust(col_widths[2])
    branch_text = status['branch']

    c = color or ''
    end = NC if c else ''
    return f"{pointer}{c}{name_col}{end} {state_colored}{state_padding} {remote_color}{remote_col}{NC} {GRAY}{branch_text}{NC}{' ' + BLUE + stash_text + NC if stash_text else ''}"


def compute_col_widths(statuses):
    """Compute column widths based on actual content."""
    path_w, state_w, remote_w = 20, 5, 2
    for s in statuses:
        name = s['display']
        path_w = max(path_w, len(name))

        parts = build_state_parts(s)
        state_text = ' '.join(parts) if parts else "clean"
        state_w = max(state_w, len(state_text))

        rp = []
        if s['ahead']:
            rp.append(f"+{s['ahead']}")
        if s['behind']:
            rp.append(f"-{s['behind']}")
        remote_text = ' '.join(rp) if rp else "--"
        remote_w = max(remote_w, len(remote_text))

    return (path_w + 2, state_w + 2, remote_w + 2)


def fetch_all(repos):
    print_header()
    print(f"\n{BLUE}Fetching all repos...{NC}\n")
    for repo_path, alias, _group in repos:
        path = os.path.expanduser(repo_path)
        display = get_display_name(repo_path, alias)
        if os.path.isdir(os.path.join(path, '.git')):
            print(f"  {GRAY}Fetching {display}...{NC}", end='', flush=True)
            result = subprocess.run(
                ['git', '-C', path, 'fetch', '--quiet'],
                capture_output=True, timeout=30
            )
            if result.returncode == 0:
                print(f"\r  {GREEN}OK{NC} {display}              ")
            else:
                print(f"\r  {RED}FAIL{NC} {display}              ")
        else:
            print(f"  {RED}FAIL{NC} {display} (not a git repo)")
    print(f"\n{GRAY}Press any key to continue...{NC}")
    getch()


def pull_all(repos):
    print_header()
    print(f"\n{BLUE}Pulling all repos...{NC}\n")
    for repo_path, alias, _group in repos:
        path = os.path.expanduser(repo_path)
        display = get_display_name(repo_path, alias)
        if os.path.isdir(os.path.join(path, '.git')):
            print(f"  {GRAY}Pulling {display}...{NC}", end='', flush=True)
            result = subprocess.run(
                ['git', '-C', path, 'pull', '--quiet'],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                print(f"\r  {GREEN}OK{NC} {display}              ")
            else:
                err = result.stderr.strip().split('\n')[0] if result.stderr.strip() else "unknown error"
                print(f"\r  {RED}FAIL{NC} {display}  {GRAY}{err}{NC}")
        else:
            print(f"  {RED}FAIL{NC} {display} (not a git repo)")
    print(f"\n{GRAY}Press any key to continue...{NC}")
    getch()


def discover_repos():
    """Scan ~/Developer for git repos (1 level deep)."""
    found = []
    if not os.path.isdir(DISCOVER_DIR):
        return found
    for entry in sorted(os.listdir(DISCOVER_DIR)):
        full = os.path.join(DISCOVER_DIR, entry)
        if os.path.isdir(full) and os.path.isdir(os.path.join(full, '.git')):
            found.append(full)
    return found


def manage_repos_menu():
    repos = load_repos()
    idx = 0
    while True:
        print_header()
        options = []
        for repo_path, alias, group in repos:
            display = get_display_name(repo_path, alias)
            short_path = repo_path.replace(os.path.expanduser('~'), '~')
            group_tag = f"  {PURPLE}[{group}]{NC}" if group else ""
            if alias:
                label = f"{display}  {GRAY}{short_path}{NC}{group_tag}"
            else:
                label = f"{display}{group_tag}"
            options.append(('repo', label, repo_path))
        options.append(('add', f'{BOLD}Add repo path...{NC}', None))
        options.append(('discover', f'{BOLD}Auto-discover repos in ~/Developer{NC}', None))

        print(f"  {BOLD}Manage Tracked Repositories{NC}\n")
        for i, (action, label, _) in enumerate(options):
            pointer = f"{CYAN}> " if i == idx else "  "
            color = CYAN if i == idx else ''
            end = NC if color else ''
            print(f"{pointer}{color}{label}{end}")

        print(f"\n{GRAY}↑↓   |   N rename   |   G group   |   D remove   |   Q Back{NC}")

        key = getch()
        if key == '\x1b[A':
            idx = (idx - 1) % len(options)
        elif key == '\x1b[B':
            idx = (idx + 1) % len(options)
        elif key.lower() == 'q':
            return
        elif key.lower() == 'd' and idx < len(repos):
            repos.pop(idx)
            save_repos(repos)
            idx = min(idx, max(0, len(options) - 2))
        elif key.lower() == 'n' and idx < len(repos):
            current_alias = repos[idx][1]
            hint = f" (current: {current_alias})" if current_alias else ""
            new_alias = prompt_input(f"Alias{hint}:")
            if new_alias:
                repos[idx] = (repos[idx][0], new_alias, repos[idx][2])
                save_repos(repos)
        elif key.lower() == 'g' and idx < len(repos):
            existing_groups = sorted(set(g for _, _, g in repos if g))
            if existing_groups:
                print(f"\n  {BOLD}Existing groups:{NC} {', '.join(existing_groups)}")
            current_group = repos[idx][2]
            hint = f" (current: {current_group})" if current_group else ""
            new_group = prompt_input(f"Group{hint} (empty to clear):")
            repos[idx] = (repos[idx][0], repos[idx][1], new_group)
            save_repos(repos)
        elif key in ('\r', '\n'):
            action = options[idx][0]
            if action == 'add':
                print_header()
                path = prompt_input("Repo path:")
                if path:
                    path = os.path.expanduser(path)
                    if os.path.isdir(os.path.join(path, '.git')):
                        existing_paths = [p for p, _, _ in repos]
                        if path not in existing_paths:
                            alias = prompt_input("Alias (optional):")
                            group = prompt_input("Group (optional):")
                            repos.append((path, alias, group))
                            save_repos(repos)
                    else:
                        print(f"  {RED}Not a git repository.{NC}")
                        getch()
            elif action == 'discover':
                found = discover_repos()
                existing = set(os.path.expanduser(p) for p, _, _ in repos)
                new_repos = [r for r in found if r not in existing]
                if not new_repos:
                    print(f"\n  {GRAY}No new repos found.{NC}")
                    getch()
                else:
                    sel = [True] * len(new_repos)
                    didx = 0
                    while True:
                        print_header()
                        print(f"  {BOLD}Discovered repos ({len(new_repos)} new):{NC}\n")
                        for i, r in enumerate(new_repos):
                            display = r.replace(os.path.expanduser('~'), '~')
                            pointer = f"{CYAN}> " if i == didx else "  "
                            color = CYAN if i == didx else NC
                            check = f"{GREEN}+{NC}" if sel[i] else f"{GRAY}-{NC}"
                            print(f"{pointer}{check} {color}{display}{NC}")
                        print(f"\n{GRAY}↑↓   |   Space toggle   |   Enter confirm   |   Q cancel{NC}")
                        dk = getch()
                        if dk == '\x1b[A':
                            didx = (didx - 1) % len(new_repos)
                        elif dk == '\x1b[B':
                            didx = (didx + 1) % len(new_repos)
                        elif dk == ' ':
                            sel[didx] = not sel[didx]
                        elif dk in ('\r', '\n'):
                            for i, r in enumerate(new_repos):
                                if sel[i]:
                                    repos.append((r, '', ''))
                            save_repos(repos)
                            break
                        elif dk.lower() == 'q':
                            break


def prompt_input(label):
    """Drop into normal terminal mode to read a line of input."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    sys.stdout.write(f"  {YELLOW}{label}{NC} ")
    sys.stdout.flush()
    try:
        return input().strip()
    except (EOFError, KeyboardInterrupt):
        return ''


def run_git_action(repo_path, args, label):
    """Run a git command and show success/failure."""
    result = subprocess.run(
        ['git', '-C', repo_path] + args,
        capture_output=True, text=True, timeout=30
    )
    if result.returncode == 0:
        print(f"  {GREEN}OK{NC} {label}")
        if result.stdout.strip():
            for line in result.stdout.strip().split('\n')[:5]:
                print(f"    {GRAY}{line}{NC}")
    else:
        print(f"  {RED}FAIL{NC} {label}")
        err = result.stderr.strip() or result.stdout.strip()
        if err:
            for line in err.split('\n')[:5]:
                print(f"    {RED}{line}{NC}")
    return result.returncode == 0


def action_resolve(full_path, display_path):
    """Pull -> stage all -> prompt for commit message -> commit -> push."""
    print(f"\n  {BOLD}Resolving {display_path}...{NC}\n")

    # 1. Pull
    if not run_git_action(full_path, ['pull'], 'pull'):
        print(f"\n  {RED}Pull failed. Resolve conflicts before continuing.{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 2. Stage all
    run_git_action(full_path, ['add', '-A'], 'stage all')

    # 3. Check if there's anything to commit
    status_output = git_cmd(full_path, ['status', '--porcelain'])
    if not status_output.strip():
        print(f"\n  {GRAY}Nothing to commit.{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 4. Commit message
    msg = prompt_input('Commit message:')
    if not msg:
        print(f"  {GRAY}Aborted (no message).{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 5. Commit
    if not run_git_action(full_path, ['commit', '-m', msg], 'commit'):
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 6. Push
    run_git_action(full_path, ['push'], 'push')

    print(f"\n  {GREEN}{BOLD}Done.{NC}")
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def action_pull(full_path):
    print()
    run_git_action(full_path, ['pull'], 'pull')
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def action_add_all(full_path):
    print()
    run_git_action(full_path, ['add', '-A'], 'stage all')
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def action_commit(full_path):
    print()
    status_output = git_cmd(full_path, ['status', '--porcelain'])
    staged = [l for l in status_output.split('\n') if l and l[0] in 'MADRC']
    if not staged:
        print(f"  {GRAY}Nothing staged to commit.{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return
    msg = prompt_input('Commit message:')
    if not msg:
        print(f"  {GRAY}Aborted.{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return
    run_git_action(full_path, ['commit', '-m', msg], 'commit')
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def action_push(full_path):
    print()
    run_git_action(full_path, ['push'], 'push')
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def action_stage_commit(full_path):
    """Stage all changes and commit (no pull, no push)."""
    print()

    # 1. Stage all
    run_git_action(full_path, ['add', '-A'], 'stage all')

    # 2. Check if there's anything to commit
    status_output = git_cmd(full_path, ['status', '--porcelain'])
    if not status_output.strip():
        print(f"\n  {GRAY}Nothing to commit.{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 3. Commit message
    msg = prompt_input('Commit message:')
    if not msg:
        print(f"  {GRAY}Aborted (no message).{NC}")
        print(f"\n{GRAY}Press any key to go back...{NC}")
        getch()
        return

    # 4. Commit
    run_git_action(full_path, ['commit', '-m', msg], 'commit')

    print(f"\n  {GREEN}{BOLD}Committed (not pushed).{NC}")
    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def render_detail(status):
    """Render the detail view (no input handling)."""
    full_path = os.path.expanduser(status['path'])
    print_header()
    name = status['display']
    short_path = status['path'].replace(os.path.expanduser('~'), '~')
    path_hint = f"  {GRAY}{short_path}{NC}" if status['alias'] else ""
    print(f"  {BOLD}{name}{NC}  {GRAY}({status['branch']}){NC}{path_hint}")
    print(f"  {GRAY}{'─' * 60}{NC}")

    # Remote status summary
    remote_parts = []
    if status['ahead']:
        remote_parts.append(f"{PURPLE}+{status['ahead']} ahead{NC}")
    if status['behind']:
        remote_parts.append(f"{PURPLE}-{status['behind']} behind{NC}")
    if status['stash']:
        remote_parts.append(f"{BLUE}*{status['stash']} stash{NC}")
    if remote_parts:
        print(f"  {' '.join(remote_parts)}")
    elif not status['staged'] and not status['modified'] and not status['untracked']:
        print(f"  {GREEN}Everything up-to-date and clean.{NC}")
    print()

    # Get actual file lists from git status
    status_output = git_cmd(full_path, ['status', '--porcelain'])
    staged_files, modified_files, untracked_files = [], [], []
    for line in status_output.split('\n'):
        if not line:
            continue
        x, y = line[0], line[1]
        fname = line[3:]
        if x in 'MADRC':
            label = {'M': 'modified', 'A': 'new file', 'D': 'deleted', 'R': 'renamed', 'C': 'copied'}.get(x, x)
            staged_files.append((label, fname))
        if y in 'MD':
            label = {'M': 'modified', 'D': 'deleted'}.get(y, y)
            modified_files.append((label, fname))
        if line[:2] == '??':
            untracked_files.append(fname)

    # Staged files (yellow — pending commit)
    if staged_files:
        print(f"  {YELLOW}{BOLD}+{len(staged_files)} staged{NC}")
        for label, fname in staged_files:
            print(f"    {YELLOW}{label:<10}{NC} {fname}")
        print()

    # Modified files (red — urgent, uncommitted)
    if modified_files:
        print(f"  {RED}{BOLD}!{len(modified_files)} modified{NC}")
        for label, fname in modified_files:
            print(f"    {RED}{label:<10}{NC} {fname}")
        print()

    # Untracked files (gray — informational)
    if untracked_files:
        print(f"  {GRAY}?{len(untracked_files)} untracked{NC}")
        for fname in untracked_files:
            print(f"    {GRAY}{fname}{NC}")
        print()

    # Unpushed commits (committed but not pushed to remote)
    if status['ahead']:
        unpushed = git_cmd(full_path, ['log', '--oneline', '@{u}..HEAD'])
        if unpushed:
            print(f"  {PURPLE}{BOLD}⬆ {status['ahead']} unpushed{NC}")
            for line in unpushed.split('\n'):
                if not line:
                    continue
                hash_end = line.index(' ') if ' ' in line else len(line)
                print(f"    {PURPLE}{line[:hash_end]}{NC} {line[hash_end:]}")
            print()

    # Recent commits (skip unpushed ones if any)
    if status['ahead']:
        log = git_cmd(full_path, ['log', '--oneline', '-5', '@{u}'])
    else:
        log = git_cmd(full_path, ['log', '--oneline', '-5'])
    if log:
        commits_label = "Recent pushed commits:" if status['ahead'] else "Recent commits:"
        print(f"  {BOLD}{commits_label}{NC}")
        for line in log.split('\n'):
            if not line:
                continue
            hash_end = line.index(' ') if ' ' in line else len(line)
            print(f"    {CYAN}{line[:hash_end]}{NC} {GRAY}{line[hash_end:]}{NC}")
        print()


def action_diff(full_path):
    """Show git diff with color-coded output."""
    print_header()
    # Show both staged and unstaged diffs
    diff_unstaged = git_cmd(full_path, ['diff'])
    diff_staged = git_cmd(full_path, ['diff', '--cached'])
    diff_output = ''
    if diff_staged:
        diff_output += diff_staged + '\n'
    if diff_unstaged:
        diff_output += diff_unstaged

    if not diff_output.strip():
        print(f"  {GRAY}No differences to show.{NC}")
    else:
        for line in diff_output.split('\n'):
            if line.startswith('+') and not line.startswith('+++'):
                print(f"  {GREEN}{line}{NC}")
            elif line.startswith('-') and not line.startswith('---'):
                print(f"  {RED}{line}{NC}")
            elif line.startswith('@@'):
                print(f"  {CYAN}{line}{NC}")
            elif line.startswith('diff ') or line.startswith('index ') or line.startswith('---') or line.startswith('+++'):
                print(f"  {BOLD}{line}{NC}")
            else:
                print(f"  {GRAY}{line}{NC}")

    print(f"\n{GRAY}Press any key to go back...{NC}")
    getch()


def detail_view(status):
    full_path = os.path.expanduser(status['path'])
    alias = status.get('alias', '')
    group = status.get('group', '')
    display_name = status['display']
    while True:
        # Refresh status each loop
        fresh = get_repo_status(status['path'], alias, group)
        if not fresh:
            return
        render_detail(fresh)

        print(f"{GRAY}R resolve  |  C commit  |  P pull  |  D diff  |  Q back{NC}")
        key = getch()
        if key.lower() == 'q':
            return
        elif key.lower() == 'r':
            action_resolve(full_path, display_name)
        elif key.lower() == 'c':
            action_stage_commit(full_path)
        elif key.lower() == 'p':
            action_pull(full_path)
        elif key.lower() == 'd':
            action_diff(full_path)


def main():
    repos = load_repos()
    if not repos:
        print_header()
        print(f"  {YELLOW}No repos configured yet.{NC}\n")
        print(f"  Press {BOLD}M{NC} to manage repos, or {BOLD}Q{NC} to quit.")
        while True:
            key = getch()
            if key.lower() == 'm':
                manage_repos_menu()
                repos = load_repos()
                break
            elif key.lower() == 'q':
                sys.exit()

    # Auto-fetch on launch for accurate ahead/behind info
    print_header()
    print(f"  {BLUE}Fetching latest from remotes...{NC}")
    for repo_path, alias, _group in repos:
        path = os.path.expanduser(repo_path)
        if os.path.isdir(os.path.join(path, '.git')):
            subprocess.run(['git', '-C', path, 'fetch', '--quiet'],
                          capture_output=True, timeout=15)

    idx = 0
    refresh = True
    while True:
        if refresh:
            repos = load_repos()
            statuses = []
            for repo_path, alias, group in repos:
                s = get_repo_status(repo_path, alias, group)
                if s:
                    statuses.append(s)

            # Sort repos alphabetically within each group, preserving group order
            seen_groups = []
            for s in statuses:
                g = s.get('group', '') or ''
                if g not in seen_groups:
                    seen_groups.append(g)
            group_order = {g: i for i, g in enumerate(seen_groups)}
            statuses.sort(key=lambda s: (group_order.get(s.get('group', '') or '', 999), s['display'].lower()))

            refresh = False

            if not statuses:
                print_header()
                print(f"  {YELLOW}No valid repos found. Press M to manage.{NC}")
                key = getch()
                if key.lower() == 'm':
                    manage_repos_menu()
                    refresh = True
                    continue
                elif key.lower() == 'q':
                    sys.exit()
                continue

        idx = min(idx, len(statuses) - 1)

        col_widths = compute_col_widths(statuses)
        print_header()

        # Group statuses by group name, preserving order
        grouped = []
        seen_groups = set()
        for s in statuses:
            g = s.get('group', '') or ''
            if g not in seen_groups:
                seen_groups.add(g)
                grouped.append(g)

        flat_idx = 0
        for g in grouped:
            group_statuses = [s for s in statuses if (s.get('group', '') or '') == g]
            if g:
                print(f"\n  {PINK}{BOLD}{g}{NC}")
            elif len(seen_groups) > 1:
                print(f"\n  {GRAY}{BOLD}Ungrouped{NC}")
            for s in group_statuses:
                print(format_status_line(s, flat_idx == idx, col_widths))
                flat_idx += 1

        print(f"\n{GRAY}↑↓   |   Enter detail   |   R refresh   |   P pull all   |   M manage   |   Q quit{NC}")

        key = getch()
        if key == '\x1b[A':
            idx = (idx - 1) % len(statuses)
        elif key == '\x1b[B':
            idx = (idx + 1) % len(statuses)
        elif key.lower() == 'q':
            sys.exit()
        elif key.lower() == 'r':
            fetch_all(repos)
            refresh = True
        elif key.lower() == 'p':
            pull_all(repos)
            refresh = True
        elif key.lower() == 'm':
            manage_repos_menu()
            refresh = True
        elif key in ('\r', '\n'):
            detail_view(statuses[idx])
            refresh = True


if __name__ == "__main__":
    main()
