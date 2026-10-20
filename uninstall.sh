#!/bin/sh
# Remove tile. Your config (~/.config/tile) and any .bak files are kept.
set -eu
TILE_HOME="${TILE_HOME:-$HOME/.local/share/tile}"
TILE_BIN_DIR="${TILE_BIN_DIR:-$HOME/.local/bin}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

if [ "$(readlink "$TILE_BIN_DIR/tile" 2>/dev/null || true)" = "$TILE_HOME/bin/tile" ]; then
  rm "$TILE_BIN_DIR/tile" && echo "Removed: $TILE_BIN_DIR/tile"
fi
if [ -f "$TILE_HOME/VERSION" ]; then
  rm -r "$TILE_HOME" && echo "Removed: $TILE_HOME"
fi
# Remove the skill only if it is the one installed by tile (it mentions TILE_HOME)
SKILL="$CLAUDE_SKILLS_DIR/tile/SKILL.md"
if [ -f "$SKILL" ] && grep -q 'TILE_HOME' "$SKILL"; then
  rm "$SKILL" && rmdir "$CLAUDE_SKILLS_DIR/tile" 2>/dev/null || true
  echo "Removed: $SKILL"
fi
echo "Kept ~/.config/tile (delete it manually if you no longer need it)"
