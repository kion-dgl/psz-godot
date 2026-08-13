#!/usr/bin/env python3
"""Import psz-re's authored per-room object + trap tables into re_reference.

psz-re decoded `set/<NN>/<v>/<room>/<stage><v>_<room>_<set>.rel` -- the game's
per-room OBJECT table. Boxes, walls, rare boxes and all five trap types are
AUTHORED there with a room-local (x, y, z) in the same frame as
`room_doorways.json`, plus a u16 facing. Nothing is scattered at runtime, which
is why psz-godot's ring placement was never going to line up with anything.

This merges psz-re's two per-room dumps into ONE file psz-godot loads at
runtime, and carries the selection rule with it so FieldPopulation can
reproduce the game's choice rather than inventing one:

    data/object_placement_per_room.json   boxes / rare boxes / walls
    data/trap_placement_per_room.json     the five trap types
        -> data/re_reference/room_objects.json

    python3 scripts/tools/refield/import_re_objects.py           # write
    python3 scripts/tools/refield/import_re_objects.py --check   # drift guard

`--check` re-derives and diffs without writing, so CI catches the file going
stale against psz-re. Point it at a checkout with --psz-re or $PSZ_RE; it skips
cleanly (exit 0) when psz-re is not present, because most contributors will not
have it.

WHAT IS DELIBERATELY LEFT OUT. psz-re's dumps carry every set family (d, s,
f1..f4) over 1,495 files; psz-godot rolls waves from family `d` only
(FieldPopulation.DEPLOY_SET), so importing the other five would quadruple the
file for no consumer. `--all-sets` includes them if that ever changes.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
OUT = ROOT / "data" / "re_reference" / "room_objects.json"

# psz-re's factory index (and, for the elemental trap, its variant byte) mapped
# onto psz-godot ids. The names are psz-re's, read out of the game's own naming
# code -- see psz-re docs/godot-field-parity.md 8.
TRAP_IDS = {
    "Heal Trap": "heal_trap",
    "Heat Trap": "heat_trap",
    "Light Trap": "light_trap",
    "Ice Trap": "ice_trap",
    "Gun Trap": "gun_trap",
    "Burn Trap": "burn_trap",
    "Needler Trap": "needler_trap",
    "Capture Trap": "capture_trap",
}

# The five layout masks at 0x020EC288, as bitfields over the six groups.
LAYOUT_MASKS = [0x21, 0x23, 0x25, 0x28, 0x30]

# rand(100) weight rows at 0x020F2E70, picked by the room's tree depth, that
# choose which layout a room gets. Group 5's count uses its own row.
LAYOUT_WEIGHTS_BY_DEPTH = {"lt4": [50, 20, 20, 10],
                           "4_6": [40, 20, 20, 20],
                           "ge7": [25, 25, 25, 25]}
GROUP5_WEIGHTS = [40, 20, 20, 20]

# A group is truncated at 20 records and a room stops at 20 objects overall.
CAPS = {"per_group": 20, "per_room": 20}

DEFAULT_SETS = ("d",)

## The object kinds this importer takes, and it is an ALLOWLIST on purpose.
##
## psz-re's object dump is being extended to emit every classified kind on the
## same schema (keys, fences, switches, mspack, NPCs, warps -- psz-godot #594).
## Taking a kind the spawner does not handle would be worse than not taking it:
## the record still counts against the 20-object room cap, so an unhandled key
## would silently displace a box or a trap. And an allowlist means this file
## does not churn every time the upstream dump grows.
##
## Widening this is #594's job, together with the spawner cases. Anything not
## listed is counted and reported, never dropped silently.
CONTAINER_KINDS = ("box", "rare_box", "wall")


def psz_re_root(explicit: str | None) -> pathlib.Path | None:
    for candidate in (explicit, os.environ.get("PSZ_RE"),
                      str(ROOT.parent.parent / "psz-re"),
                      str(ROOT.parent / "psz-re")):
        if not candidate:
            continue
        p = pathlib.Path(candidate).expanduser()
        if (p / "data" / "object_placement_per_room.json").exists():
            return p
    return None


def _round(v: float) -> float:
    """Three decimals. The source is 1.19.12 fixed point, so a fourth decimal
    is below the game's own resolution and only makes the file bigger."""
    return round(float(v), 3)


def build(re_root: pathlib.Path, sets: tuple[str, ...]) -> dict:
    objects_doc = json.loads((re_root / "data" / "object_placement_per_room.json").read_text())
    traps_doc = json.loads((re_root / "data" / "trap_placement_per_room.json").read_text())

    rooms: dict[str, dict] = {}
    unknown_traps: set[str] = set()
    deferred: dict[str, int] = {}

    def room_entry(key: str, rec: dict) -> dict:
        entry = rooms.get(key)
        if entry is None:
            entry = {"groups": rec.get("group_sizes"), "objects": []}
            rooms[key] = entry
        elif entry["groups"] is None:
            entry["groups"] = rec.get("group_sizes")
        return entry

    for key, rec in objects_doc.get("per_room", {}).items():
        if str(rec.get("set", "")) not in sets:
            continue
        entry = room_entry(key, rec)
        for box in rec.get("boxes", []):
            kind = str(box.get("kind", "box"))
            if kind not in CONTAINER_KINDS:
                deferred[kind] = deferred.get(kind, 0) + 1
                continue
            entry["objects"].append({
                "g": box.get("group"),
                "k": kind,
                "x": _round(box.get("x", 0.0)),
                "y": _round(box.get("y", 0.0)),
                "z": _round(box.get("z", 0.0)),
                "a": int(box.get("angle", 0)),
            })

    for key, rec in traps_doc.get("per_room", {}).items():
        if str(rec.get("set", "")) not in sets:
            continue
        entry = room_entry(key, rec)
        for trap in rec.get("placements", []):
            name = str(trap.get("name", ""))
            kind = TRAP_IDS.get(name)
            if kind is None:
                unknown_traps.add(name)
                continue
            entry["objects"].append({
                "g": trap.get("group"),
                "k": kind,
                "x": _round(trap.get("x", 0.0)),
                "y": _round(trap.get("y", 0.0)),
                "z": _round(trap.get("z", 0.0)),
                "a": int(trap.get("angle", 0)),
            })

    # Slot order is not carried, so sort for a stable file: group first, then
    # the position. Two records never share a group AND a position.
    for entry in rooms.values():
        entry["objects"].sort(key=lambda o: (o["g"] if o["g"] is not None else -1,
                                             o["x"], o["z"], o["k"]))

    if unknown_traps:
        print("WARNING: psz-re named traps this importer has no id for: %s"
              % sorted(unknown_traps), file=sys.stderr)

    census: dict[str, int] = {}
    for entry in rooms.values():
        for obj in entry["objects"]:
            census[obj["k"]] = census.get(obj["k"], 0) + 1

    return {
        "_": ("Authored per-room objects, imported from psz-re. Positions are "
              "ROOM-LOCAL in the same frame as room_doorways.json; psz-godot "
              "never rotates the room mesh, so they are world coordinates once "
              "the cell origin is added. Regenerate with "
              "scripts/tools/refield/import_re_objects.py."),
        "source": "psz-re data/{object,trap}_placement_per_room.json",
        "sets": list(sets),
        "the_rule": [
            "groups 0..4 are built VERBATIM, whichever the layout mask names",
            "the layout index is a rand(100) draw against a depth-banded weight row",
            "a mask is eligible only if every group it names is non-empty; group 5 is forced in",
            "group 5 is ROLLED: rand(100) against [40,20,20,20] for a count of 0..3, "
            "Fisher-Yates shuffle, take that many",
            "a group is truncated to 20 records and a room stops at 20 objects",
            "THERE ARE FIVE MASKS AND ONLY FOUR ARE REACHABLE, BY DESIGN. The layout "
            "index comes from FUN_02082814, which psz-re reads as a weighted draw "
            "returning a category 0..3 against the table at 0x020f2e70 -- twelve ints "
            "as three rows of four, every row summing to 100 -- and validates on all 44 "
            "values across five captured fields being in 0..3. So mask 4 (0x30), the "
            "only one naming group 4, is never selected by the depth-banded draw and "
            "group 4's objects never spawn in a free field. That is faithful, not a "
            "bug: psz-re's NOT_ESTABLISHED records a mission-guarded path that forces "
            "layout 4, which it has not modelled and which free-roam generation "
            "correctly never takes. Do not 'fix' the mask table or widen the draw.",
        ],
        "layout_masks": LAYOUT_MASKS,
        "layout_weights_by_depth": LAYOUT_WEIGHTS_BY_DEPTH,
        "group5_weights": GROUP5_WEIGHTS,
        "caps": CAPS,
        "census": dict(sorted(census.items(), key=lambda kv: -kv[1])),
        "not_imported_yet": {
            "_": ("Kinds psz-re emits that this importer deliberately does not take "
                  "yet -- psz-godot #594 widens CONTAINER_KINDS and adds the spawner "
                  "cases together. Listed so the gap is visible rather than silent."),
            "counts": dict(sorted(deferred.items(), key=lambda kv: -kv[1])),
        },
        "rooms": dict(sorted(rooms.items())),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--psz-re", default=None, help="path to a psz-re checkout")
    ap.add_argument("--check", action="store_true", help="diff only, write nothing")
    ap.add_argument("--all-sets", action="store_true", help="import every set family")
    args = ap.parse_args()

    re_root = psz_re_root(args.psz_re)
    if re_root is None:
        print("psz-re not found (pass --psz-re or set $PSZ_RE) -- skipping")
        return 0

    sets = ("d", "s", "f1", "f2", "f3", "f4") if args.all_sets else DEFAULT_SETS
    doc = build(re_root, sets)
    text = json.dumps(doc, indent=1, sort_keys=False) + "\n"

    if args.check:
        if not OUT.exists():
            print("FAIL: %s does not exist" % OUT)
            return 1
        if OUT.read_text() != text:
            print("FAIL: %s is stale against psz-re -- re-run without --check" % OUT)
            return 1
        print("ok: %s matches psz-re (%d rooms, %d objects)"
              % (OUT.name, len(doc["rooms"]), sum(doc["census"].values())))
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print("wrote %s -- %d rooms, %d objects, %.0f KB"
          % (OUT, len(doc["rooms"]), sum(doc["census"].values()), len(text) / 1024))
    for kind, n in doc["census"].items():
        print("  %-16s %d" % (kind, n))
    skipped = doc["not_imported_yet"]["counts"]
    if skipped:
        print("  deferred to #594: %d records over %d kinds (%s)"
              % (sum(skipped.values()), len(skipped),
                 ", ".join(list(skipped)[:6])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
