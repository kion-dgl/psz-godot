#!/usr/bin/env python3
"""Inventory the original stage-generation floor vocabulary from a retail raw/ extraction.

Walks set/ (per-room object/variant rels), enemy/deploy/ (per-room enemy
deployment rels by mode) and scene/ (room geometry) and emits the per-area
room lists with variant availability — the vocabulary the original random
stage generator sampled from. File-name semantics (documented as hypotheses
in the output; confirmation pending the retail generator code):

  s01a_ga1 = area 01, layout a (a/b per area; e = entry, z = boss/end)
  ga1/ib1/... = room type codes; nr1..nr6 = city/radar rooms (s00 only)
  set variants: _d (dive/story), _f1.._f4 (free-mode layout variants),
    _s (set/standard), _r (rare variant)
  deploy variants: d/f1/f2/f3/f4/s subdirectories mirror the set suffixes
"""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True, help="retail raw/ extraction (psz-asset-viewer)")
    ap.add_argument("--out", default="data/re_reference/stage_room_inventory.json")
    args = ap.parse_args()
    raw = Path(args.raw)

    areas = defaultdict(lambda: defaultdict(lambda: {"rooms": defaultdict(dict)}))

    def stage_of(name: str):
        m = re.match(r"(s\d+\w)_([a-z]+\d+)", name)
        return (m.group(1), m.group(2)) if m else (None, None)

    for rel in sorted((raw / "set").rglob("*.rel")):
        # set/<NN>/<layout>/<roomcode>/<stage>_<variant>.rel
        layout = rel.parent.parent.name
        room = rel.parent.name
        stage, room_code = stage_of(rel.stem)
        if stage is None:
            continue
        variant = rel.stem.split("_")[-1]
        areas[stage[:3]][stage]["rooms"][room].setdefault("set_variants", set()).add(variant)

    for rel in sorted((raw / "enemy/deploy").rglob("*.rel")):
        mode = rel.parent.name
        stage, room = stage_of(rel.stem)
        if stage is None:
            continue
        areas[stage[:3]][stage]["rooms"][room].setdefault("deploy_modes", set()).add(mode)

    for narc in sorted((raw / "scene").rglob("*.narc")):
        stage, room = stage_of(narc.stem)
        if stage is None:
            continue
        areas[stage[:3]][stage]["rooms"][room].setdefault("geometry", set()).add("narc")

    out_areas = {}
    total_rooms = 0
    for area_key in sorted(areas):
        area = {"stages": {}}
        for stage in sorted(areas[area_key]):
            rooms = {}
            for room, data in sorted(areas[area_key][stage]["rooms"].items()):
                total_rooms += 1
                rooms[room] = {
                    "set_variants": sorted(data.get("set_variants", set())),
                    "deploy_modes": sorted(data.get("deploy_modes", set())),
                    "geometry": sorted(data.get("geometry", set())),
                }
            area["stages"][stage] = {"rooms": rooms}
        out_areas[area_key] = area

    out = {
        "source": f"retail PSZ raw/ extraction (psz-asset-viewer) file inventory of set/, enemy/deploy/ and scene/",
        "semantics": "room codes and variant suffixes are filename-derived; per-mode meaning is a working hypothesis until the retail generator code is recovered. _f1.._f4 free-mode variants are the strongest signal: the original generator picks among per-room layout variants, not freeform grids.",
        "room_code_notes": "s00 = city (nr1..nr6 radar rooms); sNNa/sNNb = area NN layout variants; e = entry room; z = boss/end room. Two-letter prefixes (ga ib ic lb lc na nb nc sa tb tc td xb ia nr) are the original room-shape families.",
        "areas": out_areas,
        "total_rooms": total_rooms,
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.out}: {len(out_areas)} areas, {total_rooms} rooms")
    for area_key, area in sorted(out_areas.items()):
        stages = area["stages"]
        counts = {s: len(d["rooms"]) for s, d in stages.items()}
        print(f"  {area_key}: {counts}")


if __name__ == "__main__":
    main()
