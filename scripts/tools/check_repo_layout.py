#!/usr/bin/env python3
"""Repo hygiene guards (run in CI):

1. No junk at the repo root — every tracked top-level file must be on an
   allowlist. Catches stray scratch files / exports accidentally committed to
   root (the gitignore is the first line of defense; this is the backstop for
   anything force-added).

2. Binary asset files live under a sanctioned tree — a tracked .glb/.png/etc.
   must be under assets/ (or one of the few other asset homes), never scattered
   into source dirs or the root. SEGA media doesn't get committed at all (it's
   pack-only), but in-repo assets must at least be in the right place.

Operates on `git ls-files` (tracked files only) — untracked scratch is already
handled by .gitignore.
"""

from __future__ import annotations
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Tracked files allowed directly at the repo root. Add new legit root files
# here; anything else fails CI as junk.
ROOT_ALLOWLIST = {
    ".editorconfig", ".env.example", ".gitattributes", ".gitignore",
    "BUILD.md", "CLAUDE.md", "LICENSE", "README.md",
    "VERSION", "package.json", "project.godot", "export_presets.cfg",
    "assets_manifest.json", "assets_manifest.example.json", "asset_tree.txt",
    # App icon / splash + their Godot .import sidecars.
    "icon.svg", "icon.svg.import",
    "logo.png", "logo.png.import",
    "splash_screen.png", "splash_screen.png.import",
    "android_icon.webp", "android_icon.webp.import",
    "android_icon_192.png", "android_icon_192.png.import",
    "android_icon_432.png", "android_icon_432.png.import",
}

ASSET_EXTS = {
    ".glb", ".gltf", ".fbx", ".blend",
    ".png", ".jpg", ".jpeg", ".webp",
    ".ogg", ".wav", ".mp3",
}

# Directory prefixes where binary assets are allowed to live.
ASSET_ALLOWED_PREFIXES = (
    "assets/",            # game assets (committed = original/CC; SEGA is pack-only)
    "web/",               # web tools (public/ + a few src icons)
    "spec/",              # spec site
    "addons/",            # third-party Godot addons ship their own art
    "bootstrap/",         # boot-screen icons
    "data/retarget/",     # retarget reference meshes/textures
)
# Specific root asset files that are allowed (app icon / splash / logo).
ROOT_ASSET_ALLOW = {
    "icon.svg", "logo.png", "splash_screen.png",
    "android_icon.webp", "android_icon_192.png", "android_icon_432.png",
}


def tracked_files() -> list[str]:
    out = subprocess.run(
        ["git", "ls-files"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    )
    return [l for l in out.stdout.splitlines() if l.strip()]


def main() -> int:
    files = tracked_files()
    root_junk: list[str] = []
    misplaced: list[str] = []

    for f in files:
        # 1. root junk
        if "/" not in f and f not in ROOT_ALLOWLIST:
            root_junk.append(f)
        # 2. asset placement
        if Path(f).suffix.lower() in ASSET_EXTS:
            allowed = f.startswith(ASSET_ALLOWED_PREFIXES) or ("/" not in f and f in ROOT_ASSET_ALLOW)
            if not allowed:
                misplaced.append(f)

    rc = 0
    if root_junk:
        rc = 1
        print("[check-repo-layout] unexpected files at repo root (add to ROOT_ALLOWLIST if legit):")
        for f in sorted(root_junk):
            print(f"  {f}")
    if misplaced:
        rc = 1
        print("\n[check-repo-layout] binary asset files outside a sanctioned tree "
              f"({', '.join(ASSET_ALLOWED_PREFIXES)} or a root app-icon) — move them under assets/:")
        for f in sorted(misplaced):
            print(f"  {f}")
    if rc == 0:
        print(f"[check-repo-layout] OK — root clean, all tracked assets are in a sanctioned tree "
              f"({len(files)} tracked files scanned).")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
