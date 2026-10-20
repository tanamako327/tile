#!/usr/bin/env python3
"""Rebuild the theme ranking used by tile from an external command (optional; terminal-agent-dirs.py runs it when stale).

Runs only when rank_command is set in priorities.json. rank_command is an argument array; "{query}" is replaced with
each word in a theme's rank_queries, and the command runs in rank_cwd if given. The command prints the open items as JSON:
  [{"id": "...", "deadline": "YYYY-MM-DD"}, ...]  or  {"tasks": [...]}
Themes are ordered by nearest deadline, then by item count, and written to ~/.cache/tile-theme-order.json. Themes with
owner_rank keep that order and ignore this ranking. A theme whose command fails keeps its previous value (a failure is
never counted as zero items). Item titles are not stored.

Usage: tile-priority-refresh.py [--print]
"""
import datetime
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG = os.path.expanduser(os.environ.get("TILE_CONFIG", "~/.config/tile/priorities.json"))
CACHE = os.path.join(HOME, ".cache", "tile-theme-order.json")
# Count overdue items only from the last 7 days so old overdue items don't hold the top spot forever
OVERDUE_DAYS = 7
# Add Homebrew locations so commands such as node can be found
EXTRA_PATH = ("/opt/homebrew/bin", "/usr/local/bin")


def find_items(command, cwd, query):
    """Query → list of open items, or None if the command failed"""
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join(EXTRA_PATH) + os.pathsep + env.get("PATH", "")
    argv = [a.replace("{query}", query) for a in command]
    try:
        r = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
        d = json.loads(r.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    if isinstance(d, dict):
        if d.get("degraded"):
            return None
        d = d.get("tasks")
    return d if isinstance(d, list) else None


def main():
    with open(CONFIG) as f:
        config = json.load(f)
    themes = config.get("themes", [])
    command = config.get("rank_command")
    if not command or not isinstance(command, list):
        sys.exit("rank_command is not set (themes are ordered by owner_rank and file order only)")
    cwd = os.path.expanduser(config["rank_cwd"]) if config.get("rank_cwd") else None
    try:
        with open(CACHE) as f:
            prev = json.load(f).get("themes", {})
    except (OSError, ValueError):
        prev = {}
    today = datetime.date.today()
    floor = (today - datetime.timedelta(days=OVERDUE_DAYS)).isoformat()
    stats = {}
    for th in themes:
        seen, failed = {}, False
        for q in th.get("rank_queries", []):
            items = find_items(command, cwd, q)
            if items is None:
                failed = True
                break
            for it in items:
                seen[it.get("id")] = it.get("deadline")
        if failed:
            if th["name"] in prev:
                stats[th["name"]] = dict(prev[th["name"]], stale=True)
            continue
        deadlines = sorted(d for d in seen.values() if d and d >= floor)
        stats[th["name"]] = {"open": len(seen), "nearest_deadline": deadlines[0] if deadlines else None}
    order = sorted(stats, key=lambda n: (stats[n].get("nearest_deadline") or "9999-12-31", -stats[n].get("open", 0), n))
    for i, name in enumerate(order):
        stats[name]["rank"] = i + 1
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"generated_at": datetime.datetime.now().isoformat(timespec="seconds"), "themes": stats},
                  f, ensure_ascii=False, indent=1)
    os.replace(tmp, CACHE)
    if "--print" in sys.argv[1:]:
        for name in order:
            s = stats[name]
            print(f"{s['rank']}\t{name}\topen {s.get('open', 0)}\tdeadline {s.get('nearest_deadline') or '-'}{' (previous value)' if s.get('stale') else ''}")


if __name__ == "__main__":
    main()
