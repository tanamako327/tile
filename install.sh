#!/bin/sh
# tile のインストーラ（macOS / Terminal.app 用）。何度実行しても同じ状態になる。
#   ./install.sh              … 本体・tile コマンド・設定例・Claude Code の /tile スキルを入れる
#   ./install.sh --no-skill   … Claude Code のスキルは入れない
# 置き場所は環境変数で変えられる: TILE_HOME（本体）/ TILE_BIN_DIR（tile コマンド）/ CLAUDE_SKILLS_DIR（スキル）
# 既存のファイルが別物のときは <名前>.bak.<日時> に退避してから置き換える。設定ファイルは上書きしない。
set -eu

[ "$(uname -s)" = "Darwin" ] || { echo "tile は macOS 専用です" >&2; exit 1; }

SRC="$(cd "$(dirname "$0")" && pwd)"
TILE_HOME="${TILE_HOME:-$HOME/.local/share/tile}"
TILE_BIN_DIR="${TILE_BIN_DIR:-$HOME/.local/bin}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CONFIG_DIR="$HOME/.config/tile"
STAMP="$(date +%Y%m%d%H%M%S)"
WITH_SKILL=1
for a in "$@"; do
  case "$a" in
    --no-skill) WITH_SKILL=0 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "不明な引数: $a" >&2; exit 2 ;;
  esac
done

backup_if_foreign() { # $1=置き先 $2=置く予定の中身（比較用）
  if [ -e "$1" ] || [ -L "$1" ]; then
    if [ -n "${2-}" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then return 0; fi
    mv "$1" "$1.bak.$STAMP"
    echo "退避: $1 → $1.bak.$STAMP"
  fi
}

# 1. 本体
mkdir -p "$TILE_HOME/libexec" "$TILE_HOME/bin"
cp "$SRC"/libexec/*.py "$SRC"/libexec/*.applescript "$TILE_HOME/libexec/"
chmod 755 "$TILE_HOME"/libexec/*.py
cp "$SRC/bin/tile" "$TILE_HOME/bin/tile"
chmod 755 "$TILE_HOME/bin/tile"
VERSION="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || echo local)"
echo "$VERSION" > "$TILE_HOME/VERSION"
# 起動を速くするためにコンパイルしておく（失敗したら tile は .applescript をそのまま実行する）
if /usr/bin/osacompile -o "$TILE_HOME/tile-terminals.scpt" "$TILE_HOME/libexec/tile-terminals.applescript"; then
  echo "本体: $TILE_HOME ($VERSION)"
else
  rm -f "$TILE_HOME/tile-terminals.scpt"
  echo "警告: osacompile に失敗したため .applescript を直接実行します" >&2
fi

# 2. tile コマンド
mkdir -p "$TILE_BIN_DIR"
LINK="$TILE_BIN_DIR/tile"
if [ "$(readlink "$LINK" 2>/dev/null || true)" != "$TILE_HOME/bin/tile" ]; then
  backup_if_foreign "$LINK"
  ln -s "$TILE_HOME/bin/tile" "$LINK"
fi
echo "コマンド: $LINK"
case ":$PATH:" in
  *":$TILE_BIN_DIR:"*) ;;
  *) echo "注意: $TILE_BIN_DIR が PATH にありません。~/.zshrc に export PATH=\"$TILE_BIN_DIR:\$PATH\" を足してください" ;;
esac

# 3. 設定（あれば触らない）
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/priorities.json" ]; then
  cp "$SRC/config/priorities.example.json" "$CONFIG_DIR/priorities.json"
  echo "設定: $CONFIG_DIR/priorities.json を作成（例のテーマを自分の作業に合わせて直してください）"
else
  echo "設定: $CONFIG_DIR/priorities.json は既存のまま"
fi

# 4. Claude Code の /tile スキル
if [ "$WITH_SKILL" = 1 ]; then
  mkdir -p "$CLAUDE_SKILLS_DIR/tile"
  backup_if_foreign "$CLAUDE_SKILLS_DIR/tile/SKILL.md" "$SRC/skill/SKILL.md"
  cp "$SRC/skill/SKILL.md" "$CLAUDE_SKILLS_DIR/tile/SKILL.md"
  echo "スキル: $CLAUDE_SKILLS_DIR/tile/SKILL.md"
fi

echo "完了。初回の tile 実行時に「アクセシビリティ」の許可を求められたら、実行元のアプリ（Terminal 等）を許可してください。"
