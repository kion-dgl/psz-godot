#!/usr/bin/env python3
"""Rewrite free-roam field JSONs to use the AUTHORED box/trap positions measured
from the original game (psz-re set table, Q6), replacing the old blind ring
placement.

Source: data/re_reference/room_objects.json (extracted by psz-re tools/setobj.py;
records are room-local x/y/z in 1.19.12, same frame as room_doorways.json). Groups
0-4 are placed exactly as authored; group 5 is the game's randomised pool and is
left to the runtime, so we skip it here.

For each field cell we key by stage_id, drop the old box/trap objects, keep
everything else (enemies, start/goal, messages), and splice in the authored
boxes and traps. The mesh is never rotated (stage rotation is only a direction
relabel), so authored room-local positions map straight to world positions.

Trap type map (psz-re Q6) -> psz-godot actor + per-instance damage:
  0x1415 needler  -> needle_trap  dmg 25   (Q6: constant 25)
  0x2414 burn     -> needle_trap  dmg 50   (Q6: constant 50)
  0x2C10 gun      -> needle_trap  dmg 40   (Q6: varies; use a representative)
  0x1C13 elemental-> needle_trap  dmg 30   (Q6: element via record+0x12 -> `flag`)
  0x1427 capture  -> bear_trap             (holds then releases)

Only needle_trap and bear_trap have GLB assets in the pack, so the four contact
traps share the needle actor (parameterised by damage + trap_kind) until
dedicated burn/gun/elemental models exist; capture is the bear trap. box uses the
existing Box actor.

    python3 scripts/tools/refield/apply_authored_objects.py [--check]

--check exits non-zero if any field JSON is out of sync with room_objects.json
(used by CI / the test layer), without writing.
"""
from __future__ import annotations
import json, os, sys, glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
RO = os.path.join(ROOT, "data/re_reference/room_objects.json")
FIELDS = sorted(glob.glob(os.path.join(ROOT, "data/field_quests/*_field.json")))

ELEMENTS = {0: "heal", 1: "heat", 2: "light", 3: "ice"}

# psz-re object name -> (godot object type, extra fields)
def _trap(kind, dmg):
    return {"type": "needle_trap", "trap_kind": kind, "damage": dmg}

def map_object(o: dict):
    name = o["name"]
    base = {"position": [o["x"], o["y"], o["z"]]}
    if name == "treasure_box":
        return {"type": "box", **base}
    if name == "needler_trap":
        return {**_trap("needler", 25), **base}
    if name == "burn_trap":
        return {**_trap("burn", 50), **base}
    if name == "gun_trap":
        return {**_trap("gun", 40), **base}
    if name == "elemental_trap":
        return {**_trap("elemental", 30), "element": ELEMENTS.get(o["flag"], "heal"), **base}
    if name == "capture_trap":
        return {"type": "bear_trap", **base}
    return None  # keys/warps/containers/switches handled elsewhere or skipped

KEEP_TYPES = {"enemy", "message", "start", "goal", "npc"}
DROP_TYPES = {"box", "rare_box", "needle_trap", "bear_trap"}

def authored_for(stage_id: str, rooms: dict) -> list:
    rec = rooms.get(stage_id)
    if not rec:
        return []
    out = []
    for o in rec["objects"]:
        g = o.get("group")
        # Skip only the randomised group-5 pool of GROUPED files. Ungrouped
        # files (no six-entry group table) report group=None and are loaded
        # verbatim, so every record is authored — keep them all.
        if g == 5:
            continue
        m = map_object(o)
        if m is not None:
            out.append(m)
    return out

def rebuild_cell_objects(cell: dict, rooms: dict) -> list:
    kept = [o for o in cell.get("objects", []) if o.get("type") not in DROP_TYPES]
    return kept + authored_for(cell["stage_id"], rooms)

def main() -> int:
    check = "--check" in sys.argv
    rooms = json.load(open(RO))["rooms"]
    drift = []
    for fp in FIELDS:
        f = json.load(open(fp))
        changed = False
        for sec in f.get("sections", []):
            for cell in sec.get("cells", []):
                new_objs = rebuild_cell_objects(cell, rooms)
                if new_objs != cell.get("objects", []):
                    changed = True
                    cell["objects"] = new_objs
        if changed:
            drift.append(os.path.basename(fp))
            if not check:
                with open(fp, "w") as fh:
                    json.dump(f, fh, indent=2)
    if check:
        if drift:
            print("OUT OF SYNC with room_objects.json:", ", ".join(drift))
            return 1
        print("all field JSONs in sync with authored objects")
        return 0
    # summary
    boxes = traps = 0
    for fp in FIELDS:
        f = json.load(open(fp))
        for sec in f["sections"]:
            for c in sec["cells"]:
                for o in c.get("objects", []):
                    if o["type"] == "box": boxes += 1
                    elif o["type"] in ("needle_trap", "bear_trap"): traps += 1
    print(f"updated {len(drift)} field(s): {', '.join(drift) if drift else 'none'}")
    print(f"authored boxes: {boxes}  traps: {traps}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
