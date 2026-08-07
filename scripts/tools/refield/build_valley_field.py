#!/usr/bin/env python3
"""Build data/field_quests/valley_field.json from psz-re measured data.

Reproduces the original PSZ Gurhacia Valley free field to layout parity:

  * grid section "a"  -> the 9-room area-A layout measured from a savestate
                         (data/re_reference/level_{layouts,maps,graph}_observed)
  * transition "e"    -> the single s01e_ia1 room the game loads between areas
  * grid section "b"  -> the 8-room area-B ("valley_B") layout measured from a
                         second savestate (shapes + gates + keys)
  * boss section "z"  -> s01z_na1 holding Reyburn (the s01z assignment table's
                         single entry is boss_dragon)

Topology, gate types (0 open / 1-2 key / 4 enemy-defeat) and key placement come
straight from the observations. Room rotation is DERIVED (not stored by the
game): the room's config door directions are rotated until they cover the layout
slots this cell needs. Enemy content is drawn from the measured weighted wave
tables (enemy_wave_templates + enemy_room_assignment), mapping psz-re internal
names to psz-godot enemy ids.

Re-run after touching the RE reference data. Output is deterministic.
"""
import json, os, math

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
RE = os.path.join(ROOT, "data/re_reference")
def load(p): return json.load(open(p))
re_ = lambda n: load(os.path.join(RE, n))

CFG = load(os.path.join(ROOT, "data/stage_configs/unified-stage-configs.json"))
DIRS = ["north", "east", "south", "west"]
CW = {"north": "east", "east": "south", "south": "west", "west": "north"}
OPP = {"north": "south", "south": "north", "east": "west", "west": "east"}
def rot(d, steps):  # rotate a direction CW by `steps` 90-degree turns
    for _ in range(steps % 4): d = CW[d]
    return d
def cfg_doors(code):  # config portal directions -> id, in the room's authored orientation
    c = CFG.get(code) or {}
    return {p["direction"]: p["id"] for p in c.get("portals", [])}

# psz-re internal enemy name -> psz-godot enemy id (data/enemies/<id>.tres).
# snake/vulture/lion/hyena from the psz-re bestiary + anchor; lizard->ghowl by
# elimination (the 5th Gurhacia base species); rares fall back to the base model
# where psz-godot has no rare variant.
RE_TO_GODOT = {
    "lizard": "ghowl", "vulture": "vulkure", "snake": "garapython",
    "snake_rare": "garapython", "lion": "helion", "lion_rare": "blaze_helion",
    "hyena": "grimble", "hyena_rare": "grimble", "rappy": "rappy",
}

WAVES = re_("enemy_wave_templates.json")          # deploy-set -> {templates, waves[]}
ASSIGN = re_("enemy_room_assignment.json")["assignment"]   # "s01a_lb1" -> [{template,weight}]

def _seed(*parts):
    """Small deterministic hash so each room instance rolls a stable wave."""
    h = 2166136261
    for p in parts:
        for ch in str(p):
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h

def rolled_template(room_code, cell, deploy_set="d"):
    """Weighted, deterministic per-cell pick from the room code's allowed list.

    The real per-room roll (which allowed template, driven by the room seed at
    +0x14) is not decoded, so we roll one ourselves against the measured weights
    — keeping the "mostly ordinary, occasional rare" texture instead of making
    every instance of a room code identical."""
    lst = ASSIGN.get(room_code)
    if not lst:
        lst = ASSIGN.get("s01a_" + room_code.split("_", 1)[1])   # area B reuses area A
    if not lst: return None
    total = sum(e["weight"] for e in lst)
    roll = _seed(room_code, cell) % total
    for e in sorted(lst, key=lambda e: e["template"]):
        roll -= e["weight"]
        if roll < 0:
            return WAVES[deploy_set]["waves"][e["template"]]
    return WAVES[deploy_set]["waves"][lst[0]["template"]]

def wave_enemies(room_code, cell):
    """godot enemy ids for a room's rolled wave, or [] for start/goal rooms."""
    tpl = rolled_template(room_code, cell)
    if not tpl: return []
    return [RE_TO_GODOT.get(n, n) for n in tpl["names"]]

# psz-re measured box counts per area-A cell (level-generation.md "Boxes"):
# real in-game observations; the game's placement formula is not decoded, so we
# transcribe the counts rather than derive them. Unlisted cells -> 0.
AREA_A_BOXES = {"B3": 4, "B2": 0, "B1": 2, "A2": 3, "C4": 4, "C1": 4}

def ring_positions(n, r=5.0):
    """n spawn positions on a ring around room centre (rooms are 44x44, safe)."""
    if n == 0: return []
    return [[round(r*math.cos(2*math.pi*i/n), 2), 0, round(r*math.sin(2*math.pi*i/n), 2)]
            for i in range(n)]

# Floor traps. psz-re has no observed object table (only layouts + enemies), so
# unlike box counts these are NOT transcribed measurements — they are a seeded
# roll, deterministic per room instance so a rebuild is a no-op.
#
# Deliberately additive-only: needle and bear traps damage/immobilise but never
# block, so a bad roll can't wall off an exit the way a fence or gate could.
# Combat rooms only, and never the start or goal room, so nobody walks in or
# out onto one. Their ring sits between the enemy ring (r=5) and the box ring
# (r=8) rather than on top of either.
TRAP_TYPES = ["needle_trap", "bear_trap"]
TRAP_RING_RADIUS = 6.5
MAX_TRAPS_PER_CELL = 2


def cell_traps(room_code, cell, is_combat):
    """Seeded 0..MAX_TRAPS_PER_CELL floor traps for one cell, as object dicts."""
    if not is_combat:
        return []
    h = _seed("trap", room_code, cell)
    count = h % (MAX_TRAPS_PER_CELL + 1)
    out = []
    for i, p in enumerate(ring_positions(count, r=TRAP_RING_RADIUS)):
        kind = TRAP_TYPES[_seed("trapkind", room_code, cell, i) % len(TRAP_TYPES)]
        out.append({"type": kind, "position": p})
    return out

# ---- measured layouts -------------------------------------------------------
# Each room: (index, room_code_suffix, cell, shape). Doors are derived from the
# edge list. gate attr is set on the OUTWARD edge; the way-back edge is 0.
AREA_A = {
    "prefix": "s01a",
    "rooms": [  # index -> (suffix, cell, shape)  (from level_layouts/maps_observed valley)
        ("sa1", "B4", "s"), ("tb3", "B3", "t"), ("td2", "B2", "t"),
        ("lb3", "C3", "l"), ("lb3", "B1", "l"), ("lb1", "A2", "l"),
        ("nb2", "C4", "n"), ("ga1", "A1", "g"), ("nb2", "C1", "n"),
    ],
    "edges": [  # (from, to, gate_attr) outward edges only
        (0, 1, 0), (1, 2, 4), (1, 3, 4), (2, 4, 4),
        (2, 5, 4), (3, 6, 0), (4, 8, 2), (5, 7, 4),
    ],
    "keys": {2: 2},     # room index -> keys held (B2 holds 2, opens the B1->C1 gate)
    "start": 0, "goal": 7,
}
AREA_B = {
    "prefix": "s01b",
    "rooms": [  # from level_maps_observed valley_B grid + shapes
        ("sa1", "B4", "s"), ("xb2", "B3", "x"), ("ib1", "B2", "i"),
        ("nb2", "A3", "n"), ("ib2", "C3", "i"), ("lb1", "D3", "l"),
        ("ga1", "D2", "g"), ("na1", "B1", "n"),
    ],
    "edges": [
        (0, 1, 0), (1, 2, 0), (1, 3, 0), (1, 4, 0),
        (2, 7, 4), (4, 5, 1), (5, 6, 4),
    ],
    "keys": {3: 1},     # A3 holds 1 key, opens the C3->D3 (room4->room5) gate
    "start": 0, "goal": 6,
}

def cell_xy(c): return (ord(c[0]) - ord("A"), int(c[1:]))
def dir_between(a, b):
    (ax, ay), (bx, by) = cell_xy(a), cell_xy(b)
    if bx == ax and by == ay - 1: return "north"
    if bx == ax and by == ay + 1: return "south"
    if bx == ax + 1 and by == ay: return "east"
    if bx == ax - 1 and by == ay: return "west"
    raise ValueError(f"{a}->{b} not adjacent")
def pos_key(cell):  # "B4" -> "row,col" (0-indexed; north = row-1, matches runtime)
    x, y = cell_xy(cell); return f"{y-1},{x}"

def build_grid_section(spec, area_letter):
    rooms = spec["rooms"]; n = len(rooms)
    codes = [f"{spec['prefix']}_{s}" for (s, _, _) in rooms]
    cells = [c for (_, c, _) in rooms]
    # per-room required door directions (+ gate) from edges (both ways)
    doors = [dict() for _ in range(n)]
    for (a, b, attr) in spec["edges"]:
        doors[a][dir_between(cells[a], cells[b])] = {"to": b, "gate": attr}
        doors[b][dir_between(cells[b], cells[a])] = {"to": a, "gate": 0}
    out_cells = []
    for i, (suffix, cell, shape) in enumerate(rooms):
        code = codes[i]
        cdoors = cfg_doors(code)                 # {dir: portal_id} in config orientation
        needed = set(doors[i].keys())
        # derive rotation: rotate config doors until they cover the needed slots
        rotation = None
        for steps in range(4):
            if needed <= {rot(d, steps) for d in cdoors}:
                rotation = steps; break
        assert rotation is not None, f"{code}: cfg {list(cdoors)} cannot cover {needed}"
        # bake portals: config door at native dir appears at rot(native, rotation)
        baked = {rot(d, rotation): pid for d, pid in cdoors.items()}
        connections, key_gate_dir, required_keys = {}, "", 0
        for d, info in doors[i].items():
            connections[d] = pos_key(cells[info["to"]])
            if info["gate"] in (1, 2):
                key_gate_dir, required_keys = d, info["gate"]
        # objects: enemies (rolled wave) for combat rooms; start/goal stay empty
        objects = []
        if i not in (spec["start"], spec["goal"]):
            ids = wave_enemies(code, cell)
            for eid, p in zip(ids, ring_positions(len(ids))):
                objects.append({"type": "enemy", "position": p, "enemy_id": eid})
        # boxes: area A uses measured per-cell counts; others get a light default
        nbox = AREA_A_BOXES.get(cell, 0) if spec["prefix"] == "s01a" else (
            0 if i in (spec["start"], spec["goal"]) else 2)
        for p in ring_positions(nbox, r=8.0):
            objects.append({"type": "box", "position": p})
        objects.extend(cell_traps(code, cell, i not in (spec["start"], spec["goal"])))
        # keys held in this room
        has_key = i in spec["keys"]
        key_count = spec["keys"].get(i, 0)
        cellrec = {
            "pos": pos_key(cell), "stage_id": code, "rotation": rotation * 90,
            "connections": connections,
            "portals": {**baked, **({"default": "default"} if CFG.get(code, {}).get("defaultSpawn") else {})},
            "is_start": i == spec["start"], "is_end": i == spec["goal"],
            "is_branch": len(connections) >= 3,
            "has_key": has_key, "key_count": key_count, "key_for_cell": "",
            "is_key_gate": required_keys > 0, "key_gate_direction": key_gate_dir,
            "key_drop": "", "required_keys": required_keys,
            "warp_edge": "", "path_order": i, "objects": objects,
        }
        out_cells.append(cellrec)
    # goal room becomes the section exit (warp to next section) on a free door
    goal = out_cells[spec["goal"]]
    goal_code = codes[spec["goal"]]
    used = set(out_cells[spec["goal"]]["connections"].keys())
    goal_rot = out_cells[spec["goal"]]["rotation"] // 90
    free = [rot(d, goal_rot) for d in cfg_doors(goal_code)]
    exit_dir = next((d for d in free if d not in used), OPP[next(iter(used))] if used else "north")
    goal["is_end"] = True; goal["warp_edge"] = exit_dir
    # link keys to their gate cell (by matching required_keys count on the path)
    gate_cells = [c for c in out_cells if c["required_keys"] > 0]
    for kc in [c for c in out_cells if c["has_key"]]:
        if gate_cells: kc["key_for_cell"] = gate_cells[0]["pos"]
    # entry_direction: the door the player materialises at when this section is
    # entered from the previous one. Prefer a FREE door (a config portal not used
    # by a connection) so the player spawns at an unused opening and walks toward
    # the room's connection — matching how the game enters an area's start room.
    # Spawning on the connection door itself (the old behaviour) left the player
    # jammed on the exit gate facing inward. Fall back to a connection, then N.
    start_cell = out_cells[spec["start"]]
    start_conns = set(start_cell["connections"].keys())
    start_doors = [d for d in start_cell["portals"].keys() if d != "default"]
    free_doors = [d for d in start_doors if d not in start_conns]
    if free_doors:
        entry_dir = free_doors[0]
    elif start_conns:
        entry_dir = next(iter(start_conns))
    else:
        entry_dir = "north"
    return {
        "type": "grid", "area": area_letter,
        "start_pos": pos_key(cells[spec["start"]]), "end_pos": pos_key(cells[spec["goal"]]),
        "entry_direction": entry_dir, "exit_direction": exit_dir, "cells": out_cells,
    }

def build_transition():
    baked = cfg_doors("s01e_ia1")
    # The transition room is NOT empty in the original: s01e_ia1 carries an enemy
    # assignment (psz-re enemy_room_assignment) — a small fight before the area-B
    # warp. Draw its wave the same way grid rooms do.
    ids = wave_enemies("s01e_ia1", "E0")
    objects = [{"type": "enemy", "position": p, "enemy_id": eid}
               for eid, p in zip(ids, ring_positions(len(ids)))]
    return {
        "type": "transition", "area": "e", "start_pos": "0,0", "end_pos": "0,0",
        "entry_direction": "south", "exit_direction": "north",
        "cells": [{
            "pos": "0,0", "stage_id": "s01e_ia1", "rotation": 0, "connections": {},
            "portals": baked, "is_start": True, "is_end": True, "is_branch": False,
            "has_key": False, "key_count": 0, "key_for_cell": "", "is_key_gate": False,
            "key_gate_direction": "", "key_drop": "", "required_keys": 0,
            "warp_edge": "north", "path_order": 0, "objects": objects,
        }],
    }

def build_boss():
    return {
        "type": "boss", "area": "z", "start_pos": "0,0", "end_pos": "0,0",
        "cells": [{
            "pos": "0,0", "stage_id": "s01z_na1", "rotation": 0, "connections": {},
            "portals": {"default": "default"}, "is_start": True, "is_end": True,
            "is_branch": False, "has_key": False, "key_count": 0, "key_for_cell": "",
            "is_key_gate": False, "key_gate_direction": "", "key_drop": "",
            "required_keys": 0, "warp_edge": "", "path_order": 0,
            "objects": [{"type": "enemy", "position": [0, 0, 0], "enemy_id": "reyburn"}],
        }],
    }

def main():
    field = {
        "version": 1,
        "last_updated": "2026-07-31",
        "id": "valley_field",
        "name": "Gurhacia Valley",
        "description": "The valley's winding paths, reproduced from the original game's measured layout.",
        "area_id": "gurhacia",
        "source": "psz-re measured layout (level_{layouts,maps,graph}_observed) — built by scripts/tools/refield/build_valley_field.py",
        "sections": [
            build_grid_section(AREA_A, "a"),
            build_transition(),
            build_grid_section(AREA_B, "b"),
            build_boss(),
        ],
    }
    out = os.path.join(ROOT, "data/field_quests/valley_field.json")
    with open(out, "w") as f:
        json.dump(field, f, indent=2)
    # summary
    for sec in field["sections"]:
        ne = sum(len([o for o in c.get("objects", []) if o["type"] == "enemy"]) for c in sec["cells"])
        kg = sum(1 for c in sec["cells"] if c["is_key_gate"])
        print(f"  {sec['type']:11} area {sec['area']}: {len(sec['cells'])} cells, "
              f"{ne} enemies, {kg} key-gate(s)")
    print("wrote", out)

if __name__ == "__main__":
    main()
