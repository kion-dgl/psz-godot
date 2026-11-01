#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif [[ -x "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT_BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
  else
    GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
  fi
fi
# Same resources/import cache, separate application name and user:// saves.
# All writes from the bake still target the shared asset/data directories.
review_dir="$(mktemp -d "${TMPDIR:-/tmp}/psz-valley-tool.XXXXXX")"
python3 - "$repo" "$review_dir" <<'PY'
from pathlib import Path
import sys
root, review = map(Path, sys.argv[1:])
for path in root.iterdir():
    if path.name not in ('project.godot', 'assets_manifest.json', '.git'):
        (review / path.name).symlink_to(path, target_is_directory=path.is_dir())
text = (root / 'project.godot').read_text()
(review / 'project.godot').write_text(text.replace('config/name="PSZ Godot"', 'config/name="PSZ Valley Material Tool"'))
PY
case "${1:-review}" in
  bake) exec "$GODOT_BIN" --headless --path "$review_dir" --script tools/valley_mirror_bake/bake.gd ;;
  audit) exec "$GODOT_BIN" --headless --path "$review_dir" res://tools/valley_mirror_bake/audit.tscn ;;
  render) exec "$GODOT_BIN" --path "$review_dir" --resolution 1600x1000 res://tools/valley_mirror_bake/viewer.tscn -- --verify ;;
  review) exec "$GODOT_BIN" --path "$review_dir" --resolution 1600x1000 res://tools/valley_mirror_bake/viewer.tscn ;;
  *) echo 'Usage: run.sh [bake|audit|render|review]' >&2; exit 2 ;;
esac
