#!/usr/bin/env python3
"""Derive a measured free-field layout from psz-re reference data.

Ground truth: data/re_reference/{level_layouts_observed,level_maps_observed,
level_graph_observed,room_doorways}.json — read out of PSZ savestates by the
psz-re project. This transcribes those observations into a runtime-agnostic
layout: rooms with grid cell, room code, per-compass-direction adjacency,
gate value, key count, and the derived rotation (native doors -> layout doors).

Rotation is DERIVED, not stored by the game (psz-re/docs/level-generation.md):
match the room model's native door walls against the layout's occupied slots;
there is exactly one 90-degree multiple that fits.
"""
import json, sys, os

RE = os.path.join(os.path.dirname(__file__), "../../../data/re_reference")
def load(n): return json.load(open(os.path.join(RE, n)))

CW = {"north": "east", "east": "south", "south": "west", "west": "north"}
OPP = {"north": "south", "south": "north", "east": "west", "west": "east"}
# grid: column letter -> x, row number -> y. north = row-1 (up), matches psz-re.
def cell_xy(cell):  # "B4" -> (col=1, row=4)
    return (ord(cell[0]) - ord("A"), int(cell[1:]))
def dir_between(a, b):  # compass dir from cell a to cell b (adjacent)
    (ax, ay), (bx, by) = cell_xy(a), cell_xy(b)
    if bx == ax and by == ay - 1: return "north"
    if bx == ax and by == ay + 1: return "south"
    if bx == ax + 1 and by == ay: return "east"
    if bx == ax - 1 and by == ay: return "west"
    raise ValueError(f"{a}->{b} not adjacent")

def rotate_set(walls, steps):
    s = set(walls)
    for _ in range(steps % 4):
        s = {CW[w] for w in s}
    return s

def derive(area):
    layouts = load("level_layouts_observed.json")["layouts"][area]
    maps = load("level_maps_observed.json")[area]
    graph = load("level_graph_observed.json")[area]
    doorways = load("room_doorways.json")["rooms"]

    rooms = layouts["rooms"]                      # index -> "s01a_tb3"
    n = len(rooms)
    # cell for each index: match by shape letter + position agreement.
    # maps["cells"] gives cell -> shape; build index->cell by walking the graph.
    # Start: index 0 is start (shape s) at maps["start"].
    idx_cell = {0: maps["start"]}
    # adjacency (undirected) with direction, from graph edges + grid walk
    edges = graph["edges_outward"]
    # place children by trying all 4 dirs consistent with a free cell whose
    # shape matches the child room's shape letter.
    shape_of = lambda i: rooms[i][-3]              # 's01a_tb3' -> 't'... wait
    # room code is sXXv_YZn; shape letter is first char of YZn group => rooms[i][5]
    def shp(i):
        code = rooms[i]                            # s01a_tb3
        return code.split("_")[1][0]               # 't'
    # Build undirected adjacency list from edges
    adj = {i: [] for i in range(n)}
    for e in edges:
        adj[e["from"]].append((e["to"], e["attr"]))
        adj[e["to"]].append((e["from"], 0))       # back edge, attr 0 (way back)
    # BFS place
    from collections import deque
    q = deque([0]); placed = {0}
    cellmap = dict(maps["cells"])                  # cell -> shape
    while q:
        i = q.popleft()
        ci = idx_cell[i]
        (cx, cy) = cell_xy(ci)
        for (j, attr) in adj[i]:
            if j in placed: continue
            # find the cell adjacent to ci whose shape matches shp(j)
            cand = {
                "north": (cx, cy - 1), "south": (cx, cy + 1),
                "east": (cx + 1, cy), "west": (cx - 1, cy),
            }
            target = None
            for d, (nx, ny) in cand.items():
                if nx < 0 or ny < 1: continue
                name = chr(ord("A") + nx) + str(ny)
                if cellmap.get(name) == shp(j) and name not in idx_cell.values():
                    target = name; break
            assert target, f"cannot place room {j} ({shp(j)}) from {ci}"
            idx_cell[j] = target; placed.add(j); q.append(j)

    # Now build per-direction adjacency + gate + rotation
    out_rooms = []
    for i in range(n):
        ci = idx_cell[i]
        code = rooms[i]                            # s01a_tb3
        native = [w["wall"] for w in doorways[code]["walls"]]
        # required directions with gate + neighbor
        req = {}   # dir -> {to, gate}
        for (j, attr) in adj[i]:
            d = dir_between(ci, idx_cell[j])
            # gate value: attr is set on outward side; way-back is 0
            req[d] = {"to_cell": idx_cell[j], "to_index": j, "gate": attr}
        # derive rotation: native doors rotated == required dirs
        needed = set(req.keys())
        rot = None
        for steps in range(4):
            if rotate_set(native, steps) == needed:
                rot = steps; break
        assert rot is not None, f"no rotation for {code}: native {native} need {needed}"
        out_rooms.append({
            "index": i, "code": code, "cell": ci,
            "shape": shp(i), "rotation_cw90": rot,
            "native_walls": native,
            "doors": {d: req[d] for d in ["north","east","south","west"] if d in req},
        })

    # keys: from maps_observed area-level (valley: B2 holds 2). Use level-generation doc facts.
    KEYS = {"valley": {"B2": 2}, "wetlands": {"D3": 2},
            "snowfield": {"B4": 1}, "paru": {"C1": 2, "E3": 1}}
    keys = KEYS.get(area, {})
    return {
        "area": area, "stage": layouts["stage"], "count": n,
        "start": maps["start"], "goal": maps["goal"],
        "keys_by_cell": keys, "rooms": out_rooms,
        "_source": "derived from psz-re savestate observations by scripts/tools/refield/derive_layout.py",
    }

if __name__ == "__main__":
    area = sys.argv[1] if len(sys.argv) > 1 else "valley"
    print(json.dumps(derive(area), indent=2))
