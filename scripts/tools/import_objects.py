#!/usr/bin/env python3
"""Import object / effect GLBs from a psz-asset-viewer checkout into psz-godot.

The viewer stores each model as a `{name}.imd/` directory containing
`{name}.glb` plus its external PNG textures (the GLB references the PNGs by
bare filename). The Godot repo keeps objects flat — `assets/objects/{set}/`
with every model's glb + textures side by side (see assets/objects/valley).

Two import modes:

  objects <viewer_root> <set_id> [--dst assets/objects/<name>]
      Flatten every `.imd` under public/objects/<set_id>/ into one flat dir.

  effects <viewer_root> <enemy_id> [--dst assets/enemies/<id>/effects]
      Copy public/enemies/<enemy_id>/effects/{name}/ subdirs (glb + png)
      preserving the per-effect subdir, plus the enemy's effects.json.

  parts <viewer_root> <enemy_id> [--dst assets/enemies/<id>/parts]
      Copy public/enemies/<enemy_id>/parts/{name}/ subdirs (glb + png)
      preserving the per-part subdir, plus the enemy's parts.json. Parts are
      the multi-part boss pieces (octopus tentacles z_002_tt/z_002_st,
      mother faces z_004_kao_*) — separate skinned meshes carrying the same
      clip names as the body, played in sync.

Only .glb and .png are copied — Godot regenerates .import/.uid sidecars on
next editor open. Run `npm run sync-tree` (R2) after importing new files.
"""

import argparse
import json
import os
import shutil
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GODOT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))

COPY_EXTS = (".glb", ".png")


def _copy_file(src: str, dst: str) -> str:
    """Copy src→dst. Returns 'new' | 'same' | 'CONFLICT' (existing differs)."""
    if os.path.exists(dst):
        if os.path.getsize(dst) == os.path.getsize(src):
            with open(dst, "rb") as a, open(src, "rb") as b:
                if a.read() == b.read():
                    return "same"
        return "CONFLICT"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    return "new"


def import_objects(viewer_root: str, set_id: str, dst: str) -> int:
    src_set = os.path.join(viewer_root, "public", "objects", set_id)
    if not os.path.isdir(src_set):
        print(f"ERROR: {src_set} not found", file=sys.stderr)
        return 1
    dst = dst or os.path.join(GODOT_ROOT, "assets", "objects", set_id)
    new = same = conflict = 0
    for imd in sorted(os.listdir(src_set)):
        imd_dir = os.path.join(src_set, imd)
        if not (imd.endswith(".imd") and os.path.isdir(imd_dir)):
            continue
        for f in sorted(os.listdir(imd_dir)):
            if not f.lower().endswith(COPY_EXTS):
                continue
            r = _copy_file(os.path.join(imd_dir, f), os.path.join(dst, f))
            if r == "new":
                new += 1
            elif r == "same":
                same += 1
            else:
                conflict += 1
                print(f"  CONFLICT: {f} already exists with different bytes", file=sys.stderr)
    # Copy the set manifest so the web tool can enumerate the set's models
    # (models[] lists .imd names; the loader maps .imd -> .glb).
    info = os.path.join(src_set, "info.json")
    if os.path.exists(info):
        _copy_file(info, os.path.join(dst, "info.json"))
    print(f"{set_id} -> {os.path.relpath(dst, GODOT_ROOT)}: {new} new, {same} shared, {conflict} conflict")
    return 1 if conflict else 0


def import_effects(viewer_root: str, enemy_id: str, dst: str) -> int:
    src_fx = os.path.join(viewer_root, "public", "enemies", enemy_id, "effects")
    if not os.path.isdir(src_fx):
        print(f"  SKIP {enemy_id}: no effects/ dir")
        return 0
    dst = dst or os.path.join(GODOT_ROOT, "assets", "enemies", enemy_id, "effects")
    new = same = conflict = 0
    for name in sorted(os.listdir(src_fx)):
        eff_dir = os.path.join(src_fx, name)
        if not os.path.isdir(eff_dir):
            continue
        for f in sorted(os.listdir(eff_dir)):
            if not f.lower().endswith(COPY_EXTS):
                continue
            r = _copy_file(os.path.join(eff_dir, f), os.path.join(dst, name, f))
            if r == "new":
                new += 1
            elif r == "same":
                same += 1
            else:
                conflict += 1
    # Copy the effects.json index alongside the effects dir so the web tool
    # can enumerate effects without re-fetching from the viewer.
    fx_json = os.path.join(viewer_root, "public", "enemies", enemy_id, "effects.json")
    if os.path.exists(fx_json):
        _copy_file(fx_json, os.path.join(os.path.dirname(dst), "effects.json"))
    print(f"{enemy_id}: {new} new, {same} shared, {conflict} conflict")
    return 1 if conflict else 0


def import_parts(viewer_root: str, enemy_id: str, dst: str) -> int:
    src_parts = os.path.join(viewer_root, "public", "enemies", enemy_id, "parts")
    if not os.path.isdir(src_parts):
        print(f"  SKIP {enemy_id}: no parts/ dir")
        return 0
    dst = dst or os.path.join(GODOT_ROOT, "assets", "enemies", enemy_id, "parts")
    new = same = conflict = 0
    for name in sorted(os.listdir(src_parts)):
        part_dir = os.path.join(src_parts, name)
        if not os.path.isdir(part_dir):
            continue
        for f in sorted(os.listdir(part_dir)):
            if not f.lower().endswith(COPY_EXTS):
                continue
            r = _copy_file(os.path.join(part_dir, f), os.path.join(dst, name, f))
            if r == "new":
                new += 1
            elif r == "same":
                same += 1
            else:
                conflict += 1
                print(f"  CONFLICT: {name}/{f} already exists with different bytes", file=sys.stderr)
    # parts.json indexes the part names for tooling.
    parts_json = os.path.join(viewer_root, "public", "enemies", enemy_id, "parts.json")
    if os.path.exists(parts_json):
        _copy_file(parts_json, os.path.join(os.path.dirname(dst), "parts.json"))
    print(f"{enemy_id}: {new} new, {same} shared, {conflict} conflict")
    return 1 if conflict else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)

    po = sub.add_parser("objects", help="import an object set (flatten .imd dirs)")
    po.add_argument("viewer_root")
    po.add_argument("set_id", help="e.g. special_c3, valley_z (dir under public/objects/)")
    po.add_argument("--dst", default="", help="target dir (default assets/objects/<set_id>)")

    pe = sub.add_parser("effects", help="import an enemy's effect models")
    pe.add_argument("viewer_root")
    pe.add_argument("enemy_id")
    pe.add_argument("--dst", default="", help="target dir (default assets/enemies/<id>/effects)")

    pp = sub.add_parser("parts", help="import an enemy's multi-part boss pieces")
    pp.add_argument("viewer_root")
    pp.add_argument("enemy_id")
    pp.add_argument("--dst", default="", help="target dir (default assets/enemies/<id>/parts)")

    a = ap.parse_args()
    if a.mode == "objects":
        return import_objects(a.viewer_root, a.set_id, a.dst)
    if a.mode == "effects":
        return import_effects(a.viewer_root, a.enemy_id, a.dst)
    if a.mode == "parts":
        return import_parts(a.viewer_root, a.enemy_id, a.dst)
    return 2


if __name__ == "__main__":
    sys.exit(main())
