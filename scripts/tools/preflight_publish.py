#!/usr/bin/env python3
"""Pre-flight check before `npm run upload-pack` — catches a partial local
/assets/ tree that would silently strip whole asset buckets from the
published pack.

The pack publish is built from on-disk `/assets/`; any subdir missing
locally just produces a `⚠ missing asset dir` warning and ships an
incomplete pack. CI's check-asset-refs then fails because data/*.tres
references paths that aren't in the freshly-written asset_tree.txt.

This script greps source for `res://assets/...` references the same way
check_asset_refs.py does, then asserts each path EXISTS on disk under
/assets/. Pass = safe to spend AR on a publish. Fail = run
scripts/tools/fetch_assets_dev.sh first.

Usage:
    scripts/tools/preflight_publish.py             # exit 0 on green
    scripts/tools/preflight_publish.py --summary   # also list per-dir counts

Returns non-zero if any reference doesn't resolve to a local file.
"""

from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ASSETS_DIR = REPO_ROOT / "assets"
IGNORE_FILE = Path(__file__).resolve().parent / "asset_refs_ignore.txt"

PATH_RE = re.compile(r'res://(assets/[^"\'\s\)]+)')
SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".cs"}
IN_REPO_PREFIXES = ("assets/kenney_", "assets/ui/")


def load_ignore() -> set[str]:
    if not IGNORE_FILE.exists():
        return set()
    out: set[str] = set()
    for line in IGNORE_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


def find_references() -> dict[str, list[str]]:
    refs: dict[str, list[str]] = {}
    for path in REPO_ROOT.rglob("*"):
        if path.is_dir():
            continue
        if path.suffix not in SCAN_SUFFIXES:
            continue
        if any(p.startswith(".") for p in path.relative_to(REPO_ROOT).parts):
            continue
        parts = path.relative_to(REPO_ROOT).parts
        if parts[0] in ("build", "dist", "node_modules", ".godot"):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for m in PATH_RE.finditer(text):
            asset_path = m.group(1)
            refs.setdefault(asset_path, []).append(str(path.relative_to(REPO_ROOT)))
    return refs


def per_dir_summary() -> list[tuple[str, int, int]]:
    """[(subdir, file_count, total_bytes)] for each direct child of assets/."""
    out: list[tuple[str, int, int]] = []
    if not ASSETS_DIR.is_dir():
        return out
    for child in sorted(ASSETS_DIR.iterdir()):
        if not child.is_dir():
            continue
        n = 0
        sz = 0
        for f in child.rglob("*"):
            if f.is_file() and not f.name.endswith(".import"):
                n += 1
                try:
                    sz += f.stat().st_size
                except OSError:
                    pass
        out.append((child.name, n, sz))
    return out


def fmt_bytes(n: int) -> str:
    if n > 1024 * 1024 * 1024:
        return f"{n / 1024 / 1024 / 1024:.1f} GB"
    if n > 1024 * 1024:
        return f"{n / 1024 / 1024:.1f} MB"
    if n > 1024:
        return f"{n / 1024:.1f} KB"
    return f"{n} B"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--summary", action="store_true", help="print /assets/ per-dir file counts")
    args = p.parse_args()

    if args.summary:
        print(f"=== {ASSETS_DIR} per-dir file counts ===")
        for name, n, sz in per_dir_summary():
            tag = "(empty)" if n == 0 else fmt_bytes(sz)
            print(f"  assets/{name}/  {n:>6} files  {tag}")
        print()

    ignore = load_ignore()
    refs = find_references()

    missing: list[tuple[str, list[str]]] = []
    for asset_path, sources in sorted(refs.items()):
        if any(asset_path.startswith(p) for p in IN_REPO_PREFIXES):
            continue
        if asset_path in ignore:
            continue
        if "%" in asset_path or "*" in asset_path:
            continue
        # Resolve against on-disk /assets/. We accept a hit if the file
        # exists, OR if any file under the path-as-prefix exists (matches
        # check_asset_refs.py behavior for directory-style references).
        on_disk_path = REPO_ROOT / asset_path
        if on_disk_path.exists():
            continue
        # Directory-prefix reference?
        parent_dir = on_disk_path.parent
        if parent_dir.is_dir():
            stem = on_disk_path.name
            if any(c.name.startswith(stem) for c in parent_dir.iterdir() if c.is_file()):
                continue
        missing.append((asset_path, sources))

    if not missing:
        print(f"ok: all {len(refs)} asset references resolve to on-disk files under /assets/")
        return 0

    print("::error::Assets referenced in code but missing from local /assets/:")
    print()
    by_top_dir: dict[str, list[tuple[str, list[str]]]] = {}
    for asset_path, sources in missing:
        # Group by second segment ("assets/<top>/...")
        parts = asset_path.split("/")
        top = parts[1] if len(parts) > 1 else "(root)"
        by_top_dir.setdefault(top, []).append((asset_path, sources))
    for top, items in sorted(by_top_dir.items()):
        print(f"  assets/{top}/  ({len(items)} missing references)")
        for asset_path, sources in items[:3]:
            print(f"    res://{asset_path}")
            for src in sources[:2]:
                print(f"      referenced by {src}")
            if len(sources) > 2:
                print(f"      ... and {len(sources) - 2} more")
        if len(items) > 3:
            print(f"    ... and {len(items) - 3} more missing files in this dir")
        print()
    print("Fix: run scripts/tools/fetch_assets_dev.sh to populate the local")
    print("/assets/ tree from R2 before publishing.  ($AR not yet spent — that's the point.)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
