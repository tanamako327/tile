#!/usr/bin/env python3
"""Close Terminal.app windows that are not running Claude Code / Codex (first step of tile).

A window is kept if any of its tabs has a process whose name (ps comm) starts with claude or codex.
argv is never read because it can contain secrets. Windows on other desktops and minimized windows are closed too.

Usage: close-idle-windows.py [--dry-run]
"""
import argparse
import os
import subprocess
import sys

AGENT_NAMES = ("claude", "codex")


def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True)


def tty_has_agent(tty):
    out = subprocess.run(["ps", "-o", "comm=", "-t", tty.replace("/dev/", "")],
                         capture_output=True, text=True).stdout
    return any(os.path.basename(c.strip()).lower().startswith(AGENT_NAMES) for c in out.splitlines())


def terminal_windows():
    """[(window_id, [tty, ...]), ...]"""
    r = osa('tell application "Terminal"\n'
            'set out to ""\n'
            'repeat with w in windows\n'
            'set line_ to (id of w as text)\n'
            'repeat with t in tabs of w\n'
            'set line_ to line_ & "," & (tty of t)\n'
            'end repeat\n'
            'set out to out & line_ & linefeed\n'
            'end repeat\n'
            'return out\n'
            'end tell')
    if r.returncode != 0:
        sys.exit(f"Could not list Terminal windows: {r.stderr.strip()}")
    wins = []
    for line in r.stdout.splitlines():
        parts = [p for p in line.strip().split(",") if p]
        if parts:
            wins.append((parts[0], parts[1:]))
    return wins


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="only count, do not close")
    args = ap.parse_args()

    closed, kept = 0, 0
    for wid, ttys in terminal_windows():
        if any(tty_has_agent(t) for t in ttys):
            kept += 1
            continue
        closed += 1
        if not args.dry_run:
            osa(f'tell application "Terminal" to close (every window whose id is {wid}) saving no')
    verb = "Would close" if args.dry_run else "Closed"
    print(f"Terminal: {verb} {closed} idle window(s), kept {kept} running Claude Code/Codex")


if __name__ == "__main__":
    main()
