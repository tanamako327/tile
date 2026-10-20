#!/bin/sh
# tile を取り除く。設定（~/.config/tile）と退避した .bak ファイルは残す。
set -eu
TILE_HOME="${TILE_HOME:-$HOME/.local/share/tile}"
TILE_BIN_DIR="${TILE_BIN_DIR:-$HOME/.local/bin}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

if [ "$(readlink "$TILE_BIN_DIR/tile" 2>/dev/null || true)" = "$TILE_HOME/bin/tile" ]; then
  rm "$TILE_BIN_DIR/tile" && echo "削除: $TILE_BIN_DIR/tile"
fi
if [ -f "$TILE_HOME/VERSION" ]; then
  rm -r "$TILE_HOME" && echo "削除: $TILE_HOME"
fi
SKILL="$CLAUDE_SKILLS_DIR/tile/SKILL.md"
if [ -f "$SKILL" ] && grep -q 'TILE_HOME' "$SKILL"; then
  rm "$SKILL" && rmdir "$CLAUDE_SKILLS_DIR/tile" 2>/dev/null || true
  echo "削除: $SKILL"
fi
echo "設定 ~/.config/tile は残しています（不要なら手で削除してください）"
