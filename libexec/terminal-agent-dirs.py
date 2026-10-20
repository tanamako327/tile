#!/usr/bin/env python3
"""Claude Code / Codex が動いている Terminal.app ウィンドウの作業ディレクトリを調べる（/tile から呼ぶ）。

出力: 1行1ウィンドウで「window id<TAB>作業ディレクトリ<TAB>左端に固定するなら1<TAB>優先テーマなら1<TAB>テーマ名」。
優先度の高いテーマ → 作業ディレクトリの順に並べるので、/tile は出力順のまま左から置けばよく、同じディレクトリのウィンドウも隣り合う。
テーマは ~/.config/tile/priorities.json（環境変数 TILE_CONFIG で変えられる）。owner_rank のあるテーマが先で、残りはタスクDBから作った順位
（任意。~/.cache/tile-theme-order.json。rank_command を設定したときだけ、古くなったら同じディレクトリの tile-priority-refresh.py を裏で起動して作り直す）
→ 設定ファイルの記載順。
--label を付けると、各タブへ OSC 7（作業ディレクトリ通知）を送り、ウィンドウのタイトル先頭にディレクトリ名を出す。
Claude Code は cd と同じコマンド行で起動されるため、シェルが最後に通知したディレクトリ（ホーム等）が表示されたままになっているのを直す。

プロセスは ps の comm と lsof の cwd だけを読む（argv は secret を含み得るので読まない）。
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
# セッションのタイトル（/rename の名前か自動タイトル）に priorities.json の pin_title_keys のどれかを含むウィンドウは、
# /tile が左端に縦いっぱいで固定する（未設定なら固定しない）
# 優先テーマ（/tile が優先度の高い順に左から置く）の定義と、タスクDBから作った順位の置き場
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
    """優先テーマを優先度の高い順で返す。owner_rank → タスクDBの順位 → 設定ファイルの記載順"""
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
        # 作り直しは数十秒かかるので待たない（今回は前回の順位を使い、次回から新しい順位になる）
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
    """ウィンドウ → (順位, テーマ名)。作業ディレクトリとタイトルで決まらないときだけ直近の依頼文を見る"""
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
    """claude の pid → ~/.claude/sessions/<pid>.json の sessionId → 会話ログの (タイトル, 自動タイトル, 直近の依頼文)"""
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
        sys.exit(f"Terminal のウィンドウ一覧を取得できません: {r.stderr.strip()}")
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
        win_dir, auto, rank, theme = None, False, len(themes), ""
        for tty in ttys:
            pid = agent_pid(tty)
            cwd = process_cwd(pid) if pid else None
            if not cwd:
                continue
            win_dir = win_dir or cwd
            custom, ai_title, prompt = session_info(pid)
            title = (custom or ai_title).lower()
            auto = auto or any(k.lower() in title for k in pin_keys)
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
            rows.append((rank, win_dir, int(wid), auto, theme, frame))
    # タブでまとめたウィンドウは枠が共通で /tile は1枚として置くので、その中で一番優先度の高いテーマにそろえる
    best = {}
    for row in rows:
        if row[5] not in best or row[0] < best[row[5]][0]:
            best[row[5]] = (row[0], row[4])
    rows = [(best[f][0], d, w, a, best[f][1]) for _, d, w, a, _, f in rows]
    for rank, cwd, wid, auto, theme in sorted(rows):
        print(f"{wid}\t{cwd}\t{1 if auto else 0}\t{1 if theme else 0}\t{theme}")


if __name__ == "__main__":
    main()
