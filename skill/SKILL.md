---
name: tile
description: Arrange every Terminal.app window running Claude Code / Codex with the same font size and window size, edge to edge, on external monitors (up to 6 per monitor in one full-height row, overflow to the next monitor on the right; the current display if there are none). Use for "/tile", "tile the terminals", "arrange the terminal windows", "make the terminals the same size" or "fill the screen with the terminals".
---

# Tile the Claude Code terminals

## Run

Run `tile` once. It takes a few seconds to a few tens of seconds, so use a 300000ms timeout. If `tile` is not on the PATH, use `"${TILE_HOME:-$HOME/.local/share/tile}/bin/tile"`.

## Arguments (can be combined)

- Font size: `tile 14` (pt). For "a bit bigger / smaller", change the previous size by 1–2pt
- `row`: one full-height row with equal widths ("put them side by side", "make them tall")
- `grid`: floor(√n) rows ("use three or more rows")
- `--no-close`: keep windows that are not running Claude Code / Codex ("don't close anything")

## Result and report

The command prints two lines, for example:

```
Terminal: Closed 5 idle window(s), kept 9 running Claude Code/Codex
2 display(s): 6 in 1 row(s) + 3 in 1 row(s) / 18pt
```

Check that the counts and rows look right, then report briefly: windows closed, windows arranged, row and column layout, and font size.

## Notes

- Windows come to the front one by one while it runs, so ask the user not to type until it finishes
- Errors -1719 / -25211 mean Accessibility access is missing. Ask the user to allow the app running tile (Terminal, etc.) in System Settings → Privacy & Security → Accessibility
- The theme order lives in `~/.config/tile/priorities.json`. When the user wants a different order, change the theme's `owner_rank` (add a theme with `window_keys` if it doesn't exist). To see how each window is classified, run `/usr/bin/python3 "${TILE_HOME:-$HOME/.local/share/tile}/libexec/terminal-agent-dirs.py"` (column 5 is the theme)
