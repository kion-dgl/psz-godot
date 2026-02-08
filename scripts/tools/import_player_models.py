#!/usr/bin/env python3
"""Import player model assets from psz-sketch into psz-godot.

Copies 56 player variation directories (pc_000–pc_133, skipping pc_a0X specials).
Each variation gets: 1 GLB model + all PNG textures (~45 per variation).

Source: psz-sketch/public/player/pc_XXX/
Dest:   psz-godot/assets/player/pc_XXX/

Usage:
    python3 scripts/tools/import_player_models.py
"""

import os
import re
import shutil
import sys

SKETCH_ROOT = os.path.expanduser("~/Github/psz-sketch/public/player")
GODOT_ROOT = os.path.expanduser("~/Github/psz-godot/assets/player")

# Match pc_000 through pc_133 (skip pc_a0X specials)
VARIATION_RE = re.compile(r"^pc_\d{3}$")


def import_variation(name: str) -> tuple[int, int]:
    """Copy GLB + textures for one variation. Returns (glb_count, png_count)."""
    src_dir = os.path.join(SKETCH_ROOT, name)
    dst_dir = os.path.join(GODOT_ROOT, name)

    glb_count = 0
    png_count = 0

    # Copy GLB from inner directory: pc_XXX/pc_XXX/pc_XXX_000.glb
    inner_dir = os.path.join(src_dir, name)
    if os.path.isdir(inner_dir):
        for f in os.listdir(inner_dir):
            if f.endswith(".glb"):
                os.makedirs(dst_dir, exist_ok=True)
                shutil.copy2(os.path.join(inner_dir, f), os.path.join(dst_dir, f))
                glb_count += 1

    # Copy PNG textures from textures/ directory
    tex_src = os.path.join(src_dir, "textures")
    tex_dst = os.path.join(dst_dir, "textures")
    if os.path.isdir(tex_src):
        os.makedirs(tex_dst, exist_ok=True)
        for f in os.listdir(tex_src):
            if f.endswith(".png"):
                shutil.copy2(os.path.join(tex_src, f), os.path.join(tex_dst, f))
                png_count += 1

    return glb_count, png_count


def main():
    if not os.path.isdir(SKETCH_ROOT):
        print(f"ERROR: Source directory not found: {SKETCH_ROOT}")
        sys.exit(1)

    # Find all valid variation directories
    variations = sorted(
        d for d in os.listdir(SKETCH_ROOT) if VARIATION_RE.match(d)
    )
    print(f"Found {len(variations)} player variations to import")

    total_glb = 0
    total_png = 0
    imported = 0

    for name in variations:
        glb, png = import_variation(name)
        if glb > 0:
            imported += 1
            total_glb += glb
            total_png += png
            print(f"  {name}: {glb} GLB, {png} PNG")
        else:
            print(f"  {name}: SKIPPED (no GLB found)")

    print(f"\nDone: {imported} variations, {total_glb} GLB files, {total_png} textures")


if __name__ == "__main__":
    main()
