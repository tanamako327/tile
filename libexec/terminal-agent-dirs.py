#!/usr/bin/env python3
"""Find the working directory of each Terminal.app window running Claude Code / Codex (called by tile).

Output: one line per window, "window id<TAB>working directory<TAB>1 if pinned<TAB>1 if it matches a theme<TAB>theme name".
Lines are sorted by theme priority, then by working directory, so tile can place them left to right in output order
and windows with the same directory end up next to each other.
Themes come from ~/.config/tile/priorities.json (override with TILE_CONFIG). Themes with owner_rank come first, then
the optional rank_command ranking (~/.cache/tile-theme-order.json, rebuilt in the background by tile-priority-refresh.py
in this directory when stale), then the order in the file.
With --label, an OSC 7 sequence (working directory notification) is written to each tab so the window title starts
with the directory name. Claude Code is often started on the same command line as cd, which leaves the title showing
the directory the shell last reported (such as the home directory).

Only the process name (ps comm) and cwd (lsof) are read. argv is never read because it can contain secrets.
"""
import glob
import json
import os
import socket
import subprocess
import sys
import time
from urllib.parse import quote

AGENT_NAMES = ("claude", "codex")
# A window whose session title (the /rename name or the generated title) contains any of pin_title_keys in
# priorities.json is pinned by tile as a full-height column on the far left (no pinning when unset)
THEME_CONFIG = os.path.expanduser(os.environ.get("TILE_CONFIG", "~/.config/tile/priorities.json"))
REFRESH_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tile-priority-refresh.py")
THEME_ORDER_CACHE = os.path.expanduser("~/.cache/tile-theme-order.json")
THEME_ORDER_TTL_SEC = 6 * 3600


def load_config():
    try:
        with open(THEME_CONFIG) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def load_themes(config):
    """Return themes in priority order: owner_rank, then the rank_command ranking, then the order in the file"""
    themes = config.get("themes", [])
    if not themes:
        return []
    db_rank = {}
    try:
        age = time.time() - os.path.getmtime(THEME_ORDER_CACHE)
        with open(THEME_ORDER_CACHE) as f:
            db_rank = {n: s.get("rank") for n, s in json.load(f).get("themes", {}).items()}
    except (OSError, ValueError):
        age = None
    if config.get("rank_command") and (age is None or age > THEME_ORDER_TTL_SEC):
        # Rebuilding can take tens of seconds, so don't wait: this run uses the previous ranking
        try:
            subprocess.Popen(["/usr/bin/python3", REFRESH_SCRIPT],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError:
            pass
    indexed = list(enumerate(themes))
    indexed.sort(key=lambda it: (0, it[1]["owner_rank"], it[0]) if it[1].get("owner_rank") is not None
                 else (1, db_rank.get(it[1].get("name")) or 9999, it[0]))
    return [th for _, th in indexed]


def theme_rank(themes, cwd, title, prompt):
    """Window → (rank, theme name). The latest prompt is used only when the directory and title match nothing"""
    parts = cwd.split(os.sep)
    primary = f"{cwd}\n{title}".lower()
    for i, th in enumerate(themes):
        if any(k in parts for k in th.get("dir_keys", [])) or any(k.lower() in primary for k in th.get("window_keys", [])):
            return i, th.get("name", "")
    last = prompt.lower()
    for i, th in enumerate(themes):
        if any(k.lower() in last for k in th.get("window_keys", [])):
            return i, th.get("name", "")
    return len(themes), ""


def session_info(pid):
    """claude pid → sessionId in ~/.claude/sessions/<pid>.json → (title, generated title, latest prompt) from the session log"""
    home = os.path.expanduser("~")
    try:
        with open(os.path.join(home, ".claude", "sessions", f"{pid}.json")) as f:
            sid = json.load(f).get("sessionId", "")
    except (OSError, ValueError):
        return "", "", ""
    title = ai_title = prompt = ""
    for path in glob.glob(os.path.join(home, ".claude", "projects", "*", f"{sid}.jsonl")):
        with open(path, errors="ignore") as f:
            for line in f:
                if '"custom-title"' in line or '"ai-title"' in line or '"last-prompt"' in line:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    title = d.get("customTitle") or title
                    ai_title = d.get("aiTitle") or ai_title
                    if d.get("type") == "last-prompt":
                        prompt = d.get("lastPrompt") or prompt
    return title, ai_title, prompt


def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True)


def agent_pid(tty):
    out = subprocess.run(["ps", "-o", "pid=,comm=", "-t", tty.replace("/dev/", "")],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        pid, _, comm = line.strip().partition(" ")
        if os.path.basename(comm.strip()).lower().startswith(AGENT_NAMES):
            return pid
    return None


def process_cwd(pid):
    out = subprocess.run(["lsof", "-a", "-p", pid, "-d", "cwd", "-Fn"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("n"):
            return line[1:]
    return None


def main():
    label = "--label" in sys.argv[1:]
    r = osa('tell application "Terminal"\n'
            'set out to ""\n'
            'repeat with w in windows\n'
            'set b to bounds of w\n'
            'set line_ to (id of w as text) & "," & (item 1 of b) & ":" & (item 2 of b) & ":" & (item 3 of b) & ":" & (item 4 of b)\n'
            'repeat with t in tabs of w\n'
            'set line_ to line_ & "," & (tty of t)\n'
            'end repeat\n'
            'set out to out & line_ & linefeed\n'
            'end repeat\n'
            'return out\n'
            'end tell')
    if r.returncode != 0:
        sys.exit(f"Could not list Terminal windows: {r.stderr.strip()}")
    host = socket.gethostname()
    config = load_config()
    themes = load_themes(config)
    pin_keys = config.get("pin_title_keys", [])
    rows = []
    for line in r.stdout.splitlines():
        parts = [p for p in line.strip().split(",") if p]
        if not parts:
            continue
        wid, frame, ttys = parts[0], parts[1], parts[2:]
        win_dir, pinned, rank, theme = None, False, len(themes), ""
        for tty in ttys:
            pid = agent_pid(tty)
            cwd = process_cwd(pid) if pid else None
            if not cwd:
                continue
            win_dir = win_dir or cwd
            custom, ai_title, prompt = session_info(pid)
            title = (custom or ai_title).lower()
            pinned = pinned or any(k.lower() in title for k in pin_keys)
            r, name = theme_rank(themes, cwd, f"{custom}\n{ai_title}", prompt)
            if r < rank:
                rank, theme = r, name
            if label:
                try:
                    with open(tty, "w") as f:
                        f.write(f"\033]7;file://{host}{quote(cwd)}\007")
                except OSError:
                    pass
        if win_dir:
            rows.append((rank, win_dir, int(wid), pinned, theme, frame))
    # Tabs merged into one window share a frame and are placed as one, so give them the best theme among them
    best = {}
    for row in rows:
        if row[5] not in best or row[0] < best[row[5]][0]:
            best[row[5]] = (row[0], row[4])
    rows = [(best[f][0], d, w, p, best[f][1]) for _, d, w, p, _, f in rows]
    for rank, cwd, wid, pinned, theme in sorted(rows):
        print(f"{wid}\t{cwd}\t{1 if pinned else 0}\t{1 if theme else 0}\t{theme}")


if __name__ == "__main__":
    main()
