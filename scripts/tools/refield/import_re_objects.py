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

# psz-re model name -> the object `type` the spawner already understands.
#
# These are AUTHORED the same way boxes and traps are; the only reason they
# waited is that psz-re's dump emitted three kinds out of thirty until aef6d1b.
# The spawner has carried `fence` and `step_switch` cases for the static quests
# all along, so this is a mapping job rather than new gameplay code.
#
# o0c_poisonm is a PLACEHOLDER: it is a real authored trap in the corpus (78
# records) with no behaviour of its own here yet, so it rides the shared
# needle_trap script through `trap_kind` like the other contact traps. That
# keeps the object in the world -- which is the point -- without inventing a
# poison mechanic nobody has measured.
MODEL_TO_TYPE = {
    "o0c_fence": "fence",
    "o0c_shfence": "fence",
    "o0c_dgfance": "fence",
    "o0c_fence4": "fence",
    "o0c_remswitch": "step_switch",
    "o0c_switchf": "step_switch",
    "o0c_switchs": "step_switch",
    "o0c_poisonm": "poison_trap",
}

# A fence is opened by a switch, and the pairing is NOT in psz-re's dump -- the
# record carries group/kind/model/x/y/z/angle/slot/factory_index/variant and no
# link or event flag, because the linkage lives in the parameter block that the
# per-room dump does not publish.
#
# psz-re also measures o0c_fence sitting 1.31 cells from a doorway, against a
# 5.14 floor for walls: fences STAND IN DOORWAYS on purpose, because a fence is
# a barrier you open rather than scenery you walk past. So an unlinked fence is
# not cosmetic, it is a sealed room.
#
# Until the flag is published, fences are imported ONLY into rooms that also
# carry a switch, and every fence in such a room is linked to every switch in
# it. In set d that covers 43 rooms; 33 rooms hold fences with no switch at all
# and are skipped and counted rather than barricaded. Replacing this with the
# real pairing changes this function and nothing else.
FENCE_LINK_ID = "authored"


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
    unlinked_fences: dict[str, int] = {}

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
        # A fence needs a switch in the same room to be openable -- see
        # FENCE_LINK_ID. Decided per room, before anything is emitted.
        room_kinds = [str(b.get("kind", "")) for b in rec.get("boxes", [])]
        room_has_switch = any(MODEL_TO_TYPE.get(k) == "step_switch" for k in room_kinds)
        for box in rec.get("boxes", []):
            kind = str(box.get("kind", "box"))
            mapped = MODEL_TO_TYPE.get(kind)
            if mapped is None and kind not in CONTAINER_KINDS:
                deferred[kind] = deferred.get(kind, 0) + 1
                continue
            if mapped == "fence" and not room_has_switch:
                unlinked_fences[key] = unlinked_fences.get(key, 0) + 1
                continue
            obj = {
                "g": box.get("group"),
                "k": mapped or kind,
                "x": _round(box.get("x", 0.0)),
                "y": _round(box.get("y", 0.0)),
                "z": _round(box.get("z", 0.0)),
                "a": int(box.get("angle", 0)),
            }
            if mapped in ("fence", "step_switch"):
                # One link id per room: every switch in a room opens every fence
                # in it. `_fence_links` is per-cell at runtime, so a constant is
                # unambiguous inside a room.
                obj["link"] = FENCE_LINK_ID
            if mapped is not None:
                # Keep the source model: four fence models and three switch
                # models share two spawner cases today, and the art can diverge
                # later without another import.
                obj["m"] = kind
            entry["objects"].append(obj)

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
        "fences_skipped_no_switch": {
            "_": ("Rooms holding a fence with no switch to open it. psz-re does "
                  "not publish the fence/switch pairing (it lives in the object "
                  "parameter block), and a fence stands IN a doorway -- 1.31 "
                  "cells from one, against 5.14 for walls -- so importing one "
                  "with nothing to open it seals the room. Skipped and counted "
                  "until the flag is published."),
            "rooms": len(unlinked_fences),
            "records": sum(unlinked_fences.values()),
        },
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
