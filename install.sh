#!/bin/sh
# Installer for tile (macOS / Terminal.app). Safe to run repeatedly.
#   ./install.sh              … install the scripts, the tile command, an example config and the Claude Code /tile skill
#   ./install.sh --no-skill   … skip the Claude Code skill
# Locations can be changed with TILE_HOME (scripts) / TILE_BIN_DIR (tile command) / CLAUDE_SKILLS_DIR (skill).
# An existing file that differs is moved to <name>.bak.<timestamp> first. The config file is never overwritten.
set -eu

[ "$(uname -s)" = "Darwin" ] || { echo "tile only supports macOS" >&2; exit 1; }

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
    *) echo "Unknown argument: $a" >&2; exit 2 ;;
  esac
done

backup_if_foreign() { # $1 = destination, $2 = file to compare with (optional)
  if [ -e "$1" ] || [ -L "$1" ]; then
    if [ -n "${2-}" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then return 0; fi
    mv "$1" "$1.bak.$STAMP"
    echo "Backed up: $1 → $1.bak.$STAMP"
  fi
}

# 1. Scripts
mkdir -p "$TILE_HOME/libexec" "$TILE_HOME/bin"
cp "$SRC"/libexec/*.py "$SRC"/libexec/*.applescript "$TILE_HOME/libexec/"
chmod 755 "$TILE_HOME"/libexec/*.py
cp "$SRC/bin/tile" "$TILE_HOME/bin/tile"
chmod 755 "$TILE_HOME/bin/tile"
VERSION="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || echo local)"
echo "$VERSION" > "$TILE_HOME/VERSION"
# Compile for faster startup (if this fails, tile runs the .applescript directly)
if /usr/bin/osacompile -o "$TILE_HOME/tile-terminals.scpt" "$TILE_HOME/libexec/tile-terminals.applescript"; then
  echo "Scripts: $TILE_HOME ($VERSION)"
else
  rm -f "$TILE_HOME/tile-terminals.scpt"
  echo "Warning: osacompile failed; tile will run the .applescript directly" >&2
fi

# 2. tile command
mkdir -p "$TILE_BIN_DIR"
LINK="$TILE_BIN_DIR/tile"
if [ "$(readlink "$LINK" 2>/dev/null || true)" != "$TILE_HOME/bin/tile" ]; then
  backup_if_foreign "$LINK"
  ln -s "$TILE_HOME/bin/tile" "$LINK"
fi
echo "Command: $LINK"
case ":$PATH:" in
  *":$TILE_BIN_DIR:"*) ;;
  *) echo "Note: $TILE_BIN_DIR is not on your PATH. Add export PATH=\"$TILE_BIN_DIR:\$PATH\" to ~/.zshrc" ;;
esac

# 3. Config (left untouched if present)
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/priorities.json" ]; then
  cp "$SRC/config/priorities.example.json" "$CONFIG_DIR/priorities.json"
  echo "Config: created $CONFIG_DIR/priorities.json (replace the example keywords with your own)"
else
  echo "Config: kept existing $CONFIG_DIR/priorities.json"
fi

# 4. Claude Code /tile skill
if [ "$WITH_SKILL" = 1 ]; then
  mkdir -p "$CLAUDE_SKILLS_DIR/tile"
  backup_if_foreign "$CLAUDE_SKILLS_DIR/tile/SKILL.md" "$SRC/skill/SKILL.md"
  cp "$SRC/skill/SKILL.md" "$CLAUDE_SKILLS_DIR/tile/SKILL.md"
  echo "Skill: $CLAUDE_SKILLS_DIR/tile/SKILL.md"
fi

echo "Done. If macOS asks for Accessibility access on the first run, allow the app you run tile from (Terminal, etc.)."
