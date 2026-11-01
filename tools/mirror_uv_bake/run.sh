#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif [[ -x "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT_BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  else
    echo 'Set GODOT_BIN to a Godot 4.5.1 executable.' >&2
    exit 1
  fi
fi
if [[ "${1:-}" == --test ]]; then
  exec "$GODOT_BIN" --headless --path "$project_dir" --script tests.gd
fi
exec "$GODOT_BIN" --path "$project_dir" -- "$@"
