#!/usr/bin/env python3
"""Claude Code / Codex が動いていない Terminal.app のウィンドウを閉じる（/tile の前処理）。

判定は各タブの tty のプロセス名（ps の comm）が claude / codex で始まるかだけで、argv は読まない（secret を含み得るため）。
別デスクトップ・最小化のウィンドウも閉じる。

使い方: close-idle-windows.py [--dry-run]
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
        sys.exit(f"Terminal のウィンドウ一覧を取得できません: {r.stderr.strip()}")
    wins = []
    for line in r.stdout.splitlines():
        parts = [p for p in line.strip().split(",") if p]
        if parts:
            wins.append((parts[0], parts[1:]))
    return wins


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="閉じずに枚数だけ出す")
    args = ap.parse_args()

    closed, kept = 0, 0
    for wid, ttys in terminal_windows():
        if any(tty_has_agent(t) for t in ttys):
            kept += 1
            continue
        closed += 1
        if not args.dry_run:
            osa(f'tell application "Terminal" to close (every window whose id is {wid}) saving no')
    verb = "閉じる予定" if args.dry_run else "閉じた"
    print(f"Terminal: {closed}枚を{verb}（Claude Code/Codex 実行中の{kept}枚は残す）")


if __name__ == "__main__":
    main()
