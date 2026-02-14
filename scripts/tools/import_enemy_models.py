#!/usr/bin/env python3
"""Import enemy GLB models and textures from psz-sketch into psz-godot.

Reads info.json from each psz-sketch/public/enemies/{enemy_id}/ to get
modelBaseName, then copies:
  - {modelBaseName}/{modelBaseName}.glb → assets/enemies/{enemy_id}/{enemy_id}.glb
  - {modelBaseName}/*.png              → assets/enemies/{enemy_id}/
  - textures/*.png                     → assets/enemies/{enemy_id}/

Skips multi-part bosses that need special handling.
"""

import json
import os
import shutil
import sys

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GODOT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))
SKETCH_ROOT = os.path.abspath(os.path.join(GODOT_ROOT, "../psz-sketch"))
ENEMIES_SRC = os.path.join(SKETCH_ROOT, "public/enemies")
ENEMIES_DST = os.path.join(GODOT_ROOT, "assets/enemies")

# Multi-part bosses to skip (need special import handling)
SKIP_ENEMIES = {
    "boss_dragon",
    "boss_octopus",
    "boss_robot",
    "boss_darkfalz",
    "boss_mother",
    "boss_mother_piece",
    "boss_robot_cmb",
}


def import_enemy(enemy_id: str) -> bool:
    """Import a single enemy's model and textures. Returns True on success."""
    src_dir = os.path.join(ENEMIES_SRC, enemy_id)
    info_path = os.path.join(src_dir, "info.json")

    if not os.path.exists(info_path):
        print(f"  SKIP {enemy_id}: no info.json")
        return False

    with open(info_path) as f:
        info = json.load(f)

    model_base = info.get("modelBaseName", "")
    if not model_base:
        print(f"  SKIP {enemy_id}: no modelBaseName in info.json")
        return False

    # Source model directory
    model_dir = os.path.join(src_dir, model_base)
    glb_src = os.path.join(model_dir, f"{model_base}.glb")

    if not os.path.exists(glb_src):
        print(f"  SKIP {enemy_id}: GLB not found at {glb_src}")
        return False

    # Destination directory
    dst_dir = os.path.join(ENEMIES_DST, enemy_id)
    os.makedirs(dst_dir, exist_ok=True)

    # Copy GLB (rename to enemy_id.glb)
    glb_dst = os.path.join(dst_dir, f"{enemy_id}.glb")
    shutil.copy2(glb_src, glb_dst)

    # Copy PNGs from model directory
    png_count = 0
    for fname in os.listdir(model_dir):
        if fname.lower().endswith(".png"):
            shutil.copy2(os.path.join(model_dir, fname), os.path.join(dst_dir, fname))
            png_count += 1

    # Copy PNGs from textures/ directory
    textures_dir = os.path.join(src_dir, "textures")
    if os.path.isdir(textures_dir):
        for fname in os.listdir(textures_dir):
            if fname.lower().endswith(".png"):
                dst_path = os.path.join(dst_dir, fname)
                if not os.path.exists(dst_path):  # Don't overwrite model dir PNGs
                    shutil.copy2(os.path.join(textures_dir, fname), dst_path)
                    png_count += 1

    print(f"  OK   {enemy_id} ({model_base}.glb + {png_count} textures)")
    return True


def main():
    if not os.path.isdir(ENEMIES_SRC):
        print(f"ERROR: Source directory not found: {ENEMIES_SRC}")
        sys.exit(1)

    os.makedirs(ENEMIES_DST, exist_ok=True)

    enemy_dirs = sorted(
        d for d in os.listdir(ENEMIES_SRC)
        if os.path.isdir(os.path.join(ENEMIES_SRC, d))
    )

    imported = 0
    skipped_boss = 0
    failed = 0

    print(f"Importing enemy models from {ENEMIES_SRC}")
    print(f"Destination: {ENEMIES_DST}")
    print(f"Found {len(enemy_dirs)} enemy directories\n")

    for enemy_id in enemy_dirs:
        if enemy_id in SKIP_ENEMIES:
            print(f"  SKIP {enemy_id}: multi-part boss")
            skipped_boss += 1
            continue

        if import_enemy(enemy_id):
            imported += 1
        else:
            failed += 1

    print(f"\nDone: {imported} imported, {skipped_boss} bosses skipped, {failed} failed")


if __name__ == "__main__":
    main()
