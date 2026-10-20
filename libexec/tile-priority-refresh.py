#!/usr/bin/env python3
"""/tile の並び順に使うテーマの順位を、外部コマンドから作り直す（任意機能。terminal-agent-dirs.py が古くなったら裏で呼ぶ）。

priorities.json の rank_command を設定したときだけ動く。rank_command は引数の配列で、"{query}" をテーマの rank_queries の
各語に置き換えて実行する（rank_cwd があればそこで実行）。コマンドは未完了の項目を JSON で標準出力に返す:
  [{"id": "...", "deadline": "YYYY-MM-DD"}, ...]  または  {"tasks": [...]}
テーマを「一番近い期限 → 件数」の順に並べて ~/.cache/tile-theme-order.json に書く。owner_rank のあるテーマはその順が先で、
ここの順位は使わない。コマンドが失敗したテーマは前回の値を残す（失敗を 0 件として扱わない）。項目のタイトルは保存しない。
"""
import datetime
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG = os.path.expanduser(os.environ.get("TILE_CONFIG", "~/.config/tile/priorities.json"))
CACHE = os.path.join(HOME, ".cache", "tile-theme-order.json")
# 期限切れは 7 日前までを「今の仕事」として数える（古い期限切れが先頭を取り続けないようにする）
OVERDUE_DAYS = 7
# Homebrew の node などを見つけられるよう PATH に足す
EXTRA_PATH = ("/opt/homebrew/bin", "/usr/local/bin")


def find_items(command, cwd, query):
    """検索語 → 未完了の項目の一覧。取れなかったら None"""
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
        sys.exit("rank_command が未設定です（順位は owner_rank と記載順だけで決まります）")
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
            print(f"{s['rank']}\t{name}\t未完了{s.get('open', 0)}件\t期限{s.get('nearest_deadline') or '-'}{' (前回値)' if s.get('stale') else ''}")


if __name__ == "__main__":
    main()
