#!/usr/bin/env python3
"""Generate assets/uid_map.json: {"uid://abc": "res://assets/..."}.

Why this exists: pack-only assets are mounted at runtime with
ProjectSettings.load_resource_pack(), which does NOT merge the pack's UID
registry into the running binary's. Imported scenes inside the pack that
reference textures externally (glTF `"uri":"foo.png"`) therefore hit
"invalid UID ... using text path instead" on every load. Harmless — the
text-path fallback resolves — but it's constant log noise (issue #539).

bootstrap.gd reads this map after mounting the pack and re-registers the
ids via ResourceUID, which makes the uid:// references resolve normally.

Run from the repo root; the publish scripts call it before --export-pack.
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT = REPO_ROOT / "assets" / "uid_map.json"

UID_RE = re.compile(r'^uid="(uid://[^"]+)"', re.M)
SRC_RE = re.compile(r'^source_file="(res://[^"]+)"', re.M)


def main() -> int:
    assets = REPO_ROOT / "assets"
    if not assets.is_dir():
        print("✗ no assets/ dir — run from a checkout with assets present", file=sys.stderr)
        return 1

    mapping: dict[str, str] = {}
    for imp in sorted(assets.rglob("*.import")):
        text = imp.read_text(encoding="utf-8", errors="replace")
        uid = UID_RE.search(text)
        src = SRC_RE.search(text)
        if uid and src:
            mapping[uid.group(1)] = src.group(1)

    OUT.write_text(json.dumps(mapping, separators=(",", ":"), sort_keys=True) + "\n")
    print(f"→ Wrote {OUT.relative_to(REPO_ROOT)} ({len(mapping)} ids)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
