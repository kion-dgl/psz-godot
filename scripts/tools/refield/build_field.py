#!/usr/bin/env python3
"""Build wetlands / snowfield / paru free fields from psz-re observations.

The Valley field (build_valley_field.py) is the reference build and stays
RE-faithful down to the exact enemy species (it had two savestates + a decoded
species mapping). For the other stages we have LESS: one observed area-A layout
each and no area-B observation, and no clean RE-internal→species map. So this
builder is honest about the split:

  * LAYOUT + wave STRUCTURE (rooms, cells, gates, keys, rotation, which rooms
    fight and how big the wave is) comes from psz-re — derive_layout.derive()
    over level_{layouts,maps,graph}_observed + enemy_room_assignment.
  * SPECIES comes from psz-godot's own per-area roster (each enemy .tres lists
    its `locations`), so the fights use the right creatures for the area even
    though the exact RE species-per-wave isn't mapped for these stages.
  * area B reuses the area-A tree with s0Xb art codes (no second observation).
  * the boss room spawns the stage's boss/mini-boss.

Deterministic. Re-run after touching the reference data.
    python3 scripts/tools/refield/build_field.py ozette
"""
import json, os, sys, glob, math

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import derive_layout as dl                       # layout/gates/keys/doors
import build_valley_field as bvf                 # cfg_doors, rot, CFG, WAVES, ASSIGN, ring_positions
ROOT = bvf.ROOT

# area_id -> stage prefix, observed-layout key, boss-room enemy, field-quest id,
# display name, and the .tres `locations` string that tags the area's roster.
AREA_META = {
    "ozette":   {"stage": "s02", "obs": "wetlands",  "boss": ["octo_diablo"],            "field": "wetlands_field",  "name": "Ozette Wetland",     "loc": "Ozette Wetland"},
    "rioh":     {"stage": "s03", "obs": "snowfield",  "boss": ["hildegigas", "hildegao", "hildegao"], "field": "snowfield_field", "name": "Rioh Snowfield", "loc": "Rioh Snowfield"},
    "paru":     {"stage": "s05", "obs": "paru",       "boss": ["humilias"],               "field": "paru_field",      "name": "Oblivion City Paru", "loc": "Oblivion City Paru"},
}


def area_pool(loc: str):
    """psz-godot enemies whose `locations` include this area, split normal/rare,
    bosses excluded."""
    normal, rare = [], []
    for f in glob.glob(os.path.join(ROOT, "data/enemies/*.tres")):
        eid = os.path.splitext(os.path.basename(f))[0]
        txt = open(f).read()
        if loc not in txt or "is_boss = true" in txt:
            continue
        (rare if "is_rare = true" in txt else normal).append(eid)
    return sorted(normal), sorted(rare)


def _seed(*parts):
    h = 2166136261
    for p in parts:
        for ch in str(p):
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def wave_species(room_code, cell, size, normal, rare):
    """`size` enemies of area-appropriate species (deterministic per cell): each
    slot picks from the normal pool, with a ~1-in-8 chance of a rare."""
    if not normal and not rare:
        return []
    out = []
    for i in range(size):
        r = _seed(room_code, cell, i)
        if rare and r % 8 == 0:
            out.append(rare[(r >> 3) % len(rare)])
        elif normal:
            out.append(normal[(r >> 3) % len(normal)])
    return out


def re_wave_size(room_code):
    """Enemy count the RE assigns this room code's modal wave (or 0 if none)."""
    lst = bvf.ASSIGN.get(room_code)
    if not lst:
        return 0
    best = sorted(lst, key=lambda e: (-e["weight"], e["template"]))[0]
    return len(bvf.WAVES["d"]["waves"][best["template"]]["names"])


def _cell(code, cell, rotation, connections, portals, objects, is_start, is_end,
          key_gate_dir="", req_keys=0, key_count=0, warp_edge="", path_order=0):
    return {
        "pos": bvf.pos_key(cell), "stage_id": code, "rotation": rotation * 90,
        "connections": connections, "portals": portals,
        "is_start": is_start, "is_end": is_end, "is_branch": len(connections) >= 3,
        "has_key": key_count > 0, "key_count": key_count, "key_for_cell": "",
        "is_key_gate": req_keys > 0, "key_gate_direction": key_gate_dir,
        "key_drop": "", "required_keys": req_keys, "warp_edge": warp_edge,
        "path_order": path_order, "objects": objects,
    }


def build_grid(rooms, keys_by_cell, start_idx, goal_idx, prefix, area_letter,
               normal, rare, boxes_default):
    """rooms: derive_layout room dicts (with .cell, .doors world-dir keyed, .code)."""
    out = []
    goal_pos = None
    for r in rooms:
        code = f"{prefix}_{r['code'].split('_', 1)[1]}"   # re-prefix (a→b for area B)
        cell = r["cell"]
        cdoors = bvf.cfg_doors(code)
        needed = set(r["doors"].keys())
        rotation = next((s for s in range(4) if needed <= {bvf.rot(d, s) for d in cdoors}), 0)
        baked = {bvf.rot(d, rotation): pid for d, pid in cdoors.items()}
        if bvf.CFG.get(code, {}).get("defaultSpawn"):
            baked["default"] = "default"
        connections, kg_dir, req = {}, "", 0
        for d, info in r["doors"].items():
            connections[d] = bvf.pos_key(info["to_cell"])
            if info["gate"] in (1, 2):
                kg_dir, req = d, info["gate"]
        is_start = r["index"] == start_idx
        is_end = r["index"] == goal_idx
        objects = []
        if not is_start and not is_end:
            size = re_wave_size(code) or re_wave_size(f"{prefix[:-1]}a_" + code.split("_", 1)[1]) or 3
            for eid, p in zip(wave_species(code, cell, size, normal, rare), bvf.ring_positions(size)):
                objects.append({"type": "enemy", "position": p, "enemy_id": eid})
            for p in bvf.ring_positions(boxes_default, r=8.0):
                objects.append({"type": "box", "position": p})
        kc = keys_by_cell.get(cell, 0)
        out.append(_cell(code, cell, rotation, connections, baked, objects,
                         is_start, is_end, kg_dir, req, kc, path_order=r["index"]))
        if is_end:
            goal_pos = cell
    # goal cell warps out on a free door
    goal = next(c for c in out if c["is_end"])
    grot = goal["rotation"] // 90
    goal_code = goal["stage_id"]
    used = set(goal["connections"].keys())
    free = [bvf.rot(d, grot) for d in bvf.cfg_doors(goal_code)]
    exit_dir = next((d for d in free if d not in used),
                    bvf.OPP[next(iter(used))] if used else "north")
    goal["warp_edge"] = exit_dir
    # Route key cells to gates. Assigning every key to the FIRST gate leaves
    # any second gate with no key at all — unopenable, since key_gate.gd only
    # counts keys whose id names that gate (paru shipped an orphaned A 0,1
    # this way). Walk gates in path order and consume key cells until each
    # gate's required_keys is covered.
    gates = sorted([c for c in out if c["required_keys"] > 0],
                   key=lambda c: c["path_order"])
    key_cells = sorted([c for c in out if c["has_key"]],
                       key=lambda c: c["path_order"])
    ki = 0
    for g in gates:
        need = g["required_keys"]
        while need > 0 and ki < len(key_cells):
            kc = key_cells[ki]
            kc["key_for_cell"] = g["pos"]
            need -= max(1, kc["key_count"])
            ki += 1
    # Any leftover key cells (more keys than gates require) feed the last gate
    # so they still resolve to something real rather than dangling.
    for kc in key_cells[ki:]:
        if gates:
            kc["key_for_cell"] = gates[-1]["pos"]
    start_conns = set(out[[c["is_start"] for c in out].index(True)]["connections"].keys())
    start_doors = [d for d in out[[c["is_start"] for c in out].index(True)]["portals"] if d != "default"]
    free_doors = [d for d in start_doors if d not in start_conns]
    entry_dir = free_doors[0] if free_doors else (next(iter(start_conns)) if start_conns else "north")
    return {
        "type": "grid", "area": area_letter,
        "start_pos": bvf.pos_key(rooms[start_idx]["cell"]),
        "end_pos": bvf.pos_key(goal_pos),
        "entry_direction": entry_dir, "exit_direction": exit_dir, "cells": out,
    }


def build(area):
    m = AREA_META[area]
    prefix_a, prefix_b = m["stage"] + "a", m["stage"] + "b"
    normal, rare = area_pool(m["loc"])
    der = dl.derive(m["obs"])                    # area-A layout from observation
    rooms = der["rooms"]
    keys = {}                                     # cell -> keys, from derive's keys_by_cell
    for cell, n in der["keys_by_cell"].items():
        keys[cell] = n
    start_idx, goal_idx = der["start_room"] if "start_room" in der else 0, None
    # derive marks start=index of start cell, goal=is_end; find them
    start_idx = next(r["index"] for r in rooms if r["cell"] == der["start"])
    goal_idx = next(r["index"] for r in rooms if r["cell"] == der["goal"])

    sec_a = build_grid(rooms, keys, start_idx, goal_idx, prefix_a, "a", normal, rare, boxes_default=2)
    sec_b = build_grid(rooms, keys, start_idx, goal_idx, prefix_b, "b", normal, rare, boxes_default=2)

    e_baked = bvf.cfg_doors(f"{m['stage']}e_ia1")
    e_size = re_wave_size(f"{m['stage']}e_ia1")
    e_objs = [{"type": "enemy", "position": p, "enemy_id": eid}
              for eid, p in zip(wave_species(f"{m['stage']}e_ia1", "E0", e_size, normal, rare),
                                bvf.ring_positions(e_size))]
    sec_e = {"type": "transition", "area": "e", "start_pos": "0,0", "end_pos": "0,0",
             "entry_direction": "south", "exit_direction": "north",
             "cells": [_cell(f"{m['stage']}e_ia1", "A1", 0, {}, e_baked, e_objs,
                             True, True, warp_edge="north")]}
    # fix E cell pos to 0,0 (single room)
    sec_e["cells"][0]["pos"] = "0,0"

    boss_objs = [{"type": "enemy", "position": [0, 0, 0] if i == 0 else
                  [round(3*math.cos(2*math.pi*i/len(m["boss"])), 1), 0, round(3*math.sin(2*math.pi*i/len(m["boss"])), 1)],
                  "enemy_id": b} for i, b in enumerate(m["boss"])]
    sec_z = {"type": "boss", "area": "z", "start_pos": "0,0", "end_pos": "0,0",
             "cells": [_cell(f"{m['stage']}z_na1", "A1", 0, {}, {"default": "default"},
                             boss_objs, True, True)]}
    sec_z["cells"][0]["pos"] = "0,0"

    field = {
        "version": 1, "last_updated": "2026-08-02", "id": m["field"], "name": m["name"],
        "description": "%s — layout & wave structure from psz-re observations; species from the area roster." % m["name"],
        "area_id": area,
        "source": "psz-re layout (level_*_observed) + psz-godot area roster — scripts/tools/refield/build_field.py",
        "sections": [sec_a, sec_e, sec_b, sec_z],
    }
    out = os.path.join(ROOT, "data/field_quests/%s.json" % m["field"])
    json.dump(field, open(out, "w"), indent=2)
    ne = sum(len([o for o in c["objects"] if o["type"] == "enemy"]) for s in field["sections"] for c in s["cells"])
    print("  %-9s -> %s: %d sections, %d enemies, boss=%s, pool=%dN/%dR" % (
        area, m["field"], len(field["sections"]), ne, "+".join(m["boss"]), len(normal), len(rare)))


if __name__ == "__main__":
    for a in ([sys.argv[1]] if len(sys.argv) > 1 else list(AREA_META)):
        build(a)
