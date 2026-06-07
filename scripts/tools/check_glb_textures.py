#!/usr/bin/env python3
"""Fail if a GLB references an external texture (images[].uri) that doesn't exist.

GLBs embed glTF JSON in their first chunk; `images[].uri` is a bare filename
that Godot resolves as a sibling of the .glb. When that sibling PNG is missing,
the weapon/model renders untextured — but `check_asset_refs.py` can't see it,
because the ref lives *inside the binary GLB*, not in any .gd/.tscn/.tres text.
That blind spot shipped issue #245. This check closes it.

Scans every assets/**/*.glb, parses the JSON chunk, and for each image whose
`uri` is an external file (not a `data:` embed) verifies the resolved sibling
exists on disk. Exits non-zero (listing each offender) if any are missing.

See spec asset-distribution page for the invariant this enforces.
"""

from __future__ import annotations
import json
import struct
import sys
from pathlib import Path
from urllib.parse import unquote

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ASSETS = REPO_ROOT / "assets"
# Known-pending offenders to skip (repo-relative GLB paths, one per line, '#'
# comments). Seeded with the issue-#245 GLBs whose fix + republish is tracked
# separately; emptied when that lands. New offenders are NOT ignored.
IGNORE_FILE = Path(__file__).resolve().parent / "glb_texture_ignore.txt"

_GLB_MAGIC = 0x46546C67  # 'glTF'
_CHUNK_JSON = 0x4E4F534A  # 'JSON'


def gltf_json(glb: Path) -> dict | None:
    """Return the parsed glTF JSON chunk of a .glb, or None if not a valid GLB."""
    data = glb.read_bytes()
    if len(data) < 12:
        return None
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != _GLB_MAGIC:
        return None
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        if ctype == _CHUNK_JSON:
            return json.loads(data[off:off + clen].decode("utf-8"))
        off += clen
    return None


def missing_textures(glb: Path) -> list[str]:
    """Sibling texture URIs referenced by `glb` that don't exist on disk."""
    try:
        gltf = gltf_json(glb)
    except (ValueError, OSError) as exc:
        return [f"<unparseable GLB: {exc}>"]
    if not gltf:
        return []
    missing: list[str] = []
    for img in gltf.get("images", []):
        uri = img.get("uri")
        if not uri or uri.startswith("data:"):
            continue  # embedded texture — nothing to resolve
        target = (glb.parent / unquote(uri)).resolve()
        if not target.exists():
            missing.append(uri)
    return missing


def load_ignore() -> set[str]:
    if not IGNORE_FILE.exists():
        return set()
    out: set[str] = set()
    for line in IGNORE_FILE.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
    return out


def main() -> int:
    if not ASSETS.is_dir():
        print(f"[check-glb-textures] no assets/ dir at {ASSETS}", file=sys.stderr)
        return 0
    ignore = load_ignore()
    offenders: list[tuple[Path, list[str]]] = []
    ignored_hits = 0
    count = 0
    for glb in sorted(ASSETS.rglob("*.glb")):
        count += 1
        miss = missing_textures(glb)
        if not miss:
            continue
        if str(glb.relative_to(REPO_ROOT)) in ignore:
            ignored_hits += 1
            continue
        offenders.append((glb, miss))
    if offenders:
        print("[check-glb-textures] GLBs referencing missing sibling textures:\n")
        for glb, miss in offenders:
            rel = glb.relative_to(REPO_ROOT)
            for uri in miss:
                print(f"  {rel}  ->  missing '{uri}'  (expected {glb.parent.relative_to(REPO_ROOT)}/{uri})")
        print(
            f"\n{len(offenders)} GLB(s) with missing textures. Co-locate the PNG "
            "next to the GLB (the canonical copy usually lives under "
            "assets/weapons/<id>/), then re-publish the pack. See issue #245.",
            file=sys.stderr,
        )
        return 1
    extra = f" ({ignored_hits} known-pending ignored, see {IGNORE_FILE.name})" if ignored_hits else ""
    print(f"[check-glb-textures] OK — {count} GLB(s) scanned, all texture URIs resolve{extra}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
