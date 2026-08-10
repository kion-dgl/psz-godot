#!/usr/bin/env python3
"""Copy an authored waypoint graph between two stages that share a floor plan.

Dark Shrine's `a` (dark) and `b` (light) variants are the same rooms with
different textures — their floor footprints match at 0.92-1.00 IoU on a 1m
grid, even though the meshes are triangulated differently. So a graph
authored for one variant is walkable in the other, and the 15 rooms left in
Shrine collapse to a handful of genuinely new ones.

What transplants and what doesn't:

  * Interior points and the edges between them are copied verbatim — that's
    the authored routing, and it's the part that took the work.
  * Spawn/exit nodes are NOT copied. The portals drift 0.3-1.1m between
    variants, and those two nodes are pinned to engine geometry (spawn pose
    at gate+3m, scene-change trigger at gate+7m). They're re-derived from
    the target's own portals, then wired to whichever interior points the
    source's spawn connected to, preserving the authored topology.

Every node and every edge is checked against the TARGET's collision mesh
(`-floor.glb`, with the stage's `floorCollision.triangles` filter applied)
before anything is written. A transplant that lands off the floor is refused,
not warned about — the whole point is that this is safe to trust.

Output is a payload for `wp apply`, which re-validates against the authoring
contract before merging. This script does geometry; wp_tool.mjs does the
graph contract.

Usage:
    python3 scripts/tools/waypoints/transplant.py <src_stage> <dst_stage> [-o out.json]
    python3 scripts/tools/waypoints/transplant.py --shrine -o out.json   # all a/b pairs
"""

import argparse
import json
import math
import os
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CFG_PATH = os.path.join(REPO, "data", "stage_configs", "unified-stage-configs.json")
STAGES = os.path.join(REPO, "assets", "stages")

# Engine offsets — must match wp_tool.mjs / the editor's "Seed from gates".
SPAWN_OUTSET = 3.0
EXIT_OUTSET = 7.0
OUTWARD = {"north": (0, -1), "south": (0, 1), "east": (1, 0), "west": (-1, 0)}

AREA_FOLDER = {
    "s01": "valley", "s02": "wetlands", "s03": "snowfield", "s04": "makara",
    "s05": "paru", "s06": "arca", "s07": "shrine", "s08": "tower",
}


def stage_floor_path(stage_id):
    """assets/stages/<area>_<variant>/<stage>/lndmd/<stage>-floor.glb"""
    folder = AREA_FOLDER.get(stage_id[:3], stage_id[:3])
    variant = stage_id[3] if len(stage_id) > 3 else ""
    sub = f"{folder}_{variant}" if variant else folder
    return os.path.join(STAGES, sub, stage_id, "lndmd", f"{stage_id}-floor.glb")


# ── GLB ────────────────────────────────────────────────────

def glb_primitives(path):
    """Minimal GLB reader → [(positions, indices)] per primitive."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, _ver, _len = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"{path}: not a GLB")
    off, js, binary = 12, None, None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binary = chunk

    def accessor(i):
        a = js["accessors"][i]
        bv = js["bufferViews"][a["bufferView"]]
        base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        fmt, size = {
            5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
            5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
        }[a["componentType"]]
        ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        stride = bv.get("byteStride") or size * ncomp
        return [struct.unpack_from("<" + fmt * ncomp, binary, base + k * stride)
                for k in range(a["count"])]

    out = []
    for mesh in js.get("meshes", []):
        for prim in mesh["primitives"]:
            pos = accessor(prim["attributes"]["POSITION"])
            idx = ([v[0] for v in accessor(prim["indices"])]
                   if "indices" in prim else list(range(len(pos))))
            out.append((pos, idx))
    return out


def floor_triangles(stage_id, cfg):
    """XZ triangles of the stage's collision floor, with tri_N:false applied.

    The index counter runs across every triangle examined, matching how the
    editor assigns tri_N ids, so the saved exclusions line up.
    """
    path = stage_floor_path(stage_id)
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    excluded = (cfg.get("floorCollision") or {}).get("triangles") or {}
    tris, n = [], 0
    for pos, idx in glb_primitives(path):
        for i in range(0, len(idx) - 2, 3):
            keep = excluded.get(f"tri_{n}") is not False
            n += 1
            if not keep:
                continue
            v = [pos[idx[i + k]] for k in range(3)]
            tris.append(((v[0][0], v[0][2]), (v[1][0], v[1][2]), (v[2][0], v[2][2])))
    return tris


def on_floor(point, tris, eps=0.02):
    px, pz = point
    for (x1, z1), (x2, z2), (x3, z3) in tris:
        d = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
        if abs(d) < 1e-9:
            continue
        a = ((z2 - z3) * (px - x3) + (x3 - x2) * (pz - z3)) / d
        b = ((z3 - z1) * (px - x3) + (x1 - x3) * (pz - z3)) / d
        if a >= -eps and b >= -eps and 1 - a - b >= -eps:
            return True
    return False


def edge_clear(p, q, tris, samples=8):
    """Every sample along the segment sits over floor."""
    for k in range(1, samples):
        f = k / samples
        if not on_floor((p[0] + (q[0] - p[0]) * f, p[2] + (q[2] - p[2]) * f), tris):
            return False
    return True


# ── transplant ─────────────────────────────────────────────

def transplant(src_id, dst_id, configs):
    """Build dst's graph from src's. Returns (payload, problems)."""
    src, dst = configs[src_id], configs[dst_id]
    src_wps = src.get("waypoints") or []
    if not src_wps:
        return None, [f"{src_id} has no graph to copy"]

    tris = floor_triangles(dst_id, dst)
    if not tris:
        return None, [f"{dst_id}: no floor triangles"]

    by_src = {w["id"]: w for w in src_wps}
    interior = [w for w in src_wps if w.get("kind") not in ("spawn", "exit")]

    problems = []
    waypoints, edges = [], []
    remap = {}

    # 1. Interior points, verbatim positions, ids namespaced to the target.
    for i, w in enumerate(interior):
        new_id = f"wp_tp_{i}_{dst_id}"
        remap[w["id"]] = new_id
        pos = [w["position"][0], 0, w["position"][2]]
        if not on_floor((pos[0], pos[2]), tris):
            problems.append(f"interior point {pos[0]:.1f},{pos[2]:.1f} is off {dst_id}'s floor")
        entry = {"id": new_id, "position": pos, "kind": w.get("kind", "point")}
        if w.get("label"):
            entry["label"] = w["label"]
        waypoints.append(entry)

    # 2. Spawn/exit re-derived from the TARGET's portals — never copied.
    spawn_by_dir = {}
    for i, portal in enumerate(dst.get("portals") or []):
        o = OUTWARD.get(portal["direction"])
        if not o:
            problems.append(f"{dst_id}: portal with unknown direction {portal['direction']}")
            continue
        gx, gz = portal["position"][0], portal["position"][2]
        sid, lid = f"wp_spawn_{i}_{dst_id}", f"wp_load_{i}_{dst_id}"
        waypoints.append({"id": sid, "position": [gx + o[0] * SPAWN_OUTSET, 0, gz + o[1] * SPAWN_OUTSET],
                          "kind": "spawn", "label": f"spawn {portal['direction']}"})
        waypoints.append({"id": lid, "position": [gx + o[0] * EXIT_OUTSET, 0, gz + o[1] * EXIT_OUTSET],
                          "kind": "exit", "label": f"load {portal['direction']}"})
        edges.append([lid, sid])
        spawn_by_dir[portal["direction"]] = sid

    # 3. Extend the remap over spawns, matched by portal direction, so the
    #    source's wiring copies wholesale. Rooms with no interior points at
    #    all — a bare corridor is just spawn↔spawn — depend on this.
    for w in src_wps:
        if w.get("kind") == "spawn" and w.get("label", "").startswith("spawn "):
            direction = w["label"][len("spawn "):]
            if direction in spawn_by_dir:
                remap[w["id"]] = spawn_by_dir[direction]
            else:
                problems.append(f"{dst_id} has no {direction} portal to match {src_id}'s spawn")

    for direction in spawn_by_dir:
        if not any(w.get("kind") == "spawn" and w.get("label") == f"spawn {direction}" for w in src_wps):
            problems.append(f"{src_id} has no spawn labelled '{direction}' to copy wiring from")

    # 4. Copy every source edge except the exit leaves — those were re-seeded
    #    against the target's own gates in step 2 and are already wired.
    exits = {w["id"] for w in src_wps if w.get("kind") == "exit"}
    for a, b in src.get("waypointEdges") or []:
        if a in exits or b in exits:
            continue
        if a in remap and b in remap:
            edges.append([remap[a], remap[b]])
        else:
            problems.append(f"{src_id}: edge {a} ↔ {b} has no counterpart in {dst_id}")

    # 5. Every edge must stay over the target's floor.
    pos_of = {w["id"]: w["position"] for w in waypoints}
    for a, b in edges:
        if not edge_clear(pos_of[a], pos_of[b], tris):
            problems.append(f"edge {a} ↔ {b} crosses off-floor space in {dst_id}")

    payload = {"mapId": dst_id, "waypoints": waypoints, "waypointEdges": edges}
    return payload, problems


SHRINE_PAIRS = [
    ("s07a_ib2", "s07b_ib2"), ("s07a_ic3", "s07b_ic3"), ("s07a_lb3", "s07b_lb3"),
    ("s07a_nb2", "s07b_nb2"), ("s07a_nc2", "s07b_nc2"), ("s07a_tc3", "s07b_tc3"),
    ("s07b_td2", "s07a_td2"),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", nargs="?", help="stage id to copy the graph FROM")
    ap.add_argument("dst", nargs="?", help="stage id to copy the graph TO")
    ap.add_argument("--shrine", action="store_true", help="run every Dark Shrine a/b pair")
    ap.add_argument("-o", "--out", default="-", help="payload output path for `wp apply` (default stdout)")
    args = ap.parse_args()

    with open(CFG_PATH) as fh:
        configs = json.load(fh)

    if args.shrine:
        pairs = SHRINE_PAIRS
    elif args.src and args.dst:
        pairs = [(args.src, args.dst)]
    else:
        ap.error("give <src> <dst>, or --shrine")

    payloads, failed = [], 0
    for src_id, dst_id in pairs:
        if src_id not in configs or dst_id not in configs:
            print(f"✗ {src_id} → {dst_id}: unknown stage", file=sys.stderr)
            failed += 1
            continue
        payload, problems = transplant(src_id, dst_id, configs)
        if problems:
            failed += 1
            print(f"✗ {src_id} → {dst_id}", file=sys.stderr)
            for p in problems:
                print(f"    {p}", file=sys.stderr)
            continue
        interior = sum(1 for w in payload["waypoints"] if w["kind"] not in ("spawn", "exit"))
        print(f"✓ {src_id} → {dst_id}  {len(payload['waypoints'])} wpts "
              f"({interior} interior), {len(payload['waypointEdges'])} edges", file=sys.stderr)
        payloads.append(payload)

    if not payloads:
        return 1
    blob = json.dumps(payloads, indent=2) + "\n"
    if args.out == "-":
        print(blob)
    else:
        with open(args.out, "w") as fh:
            fh.write(blob)
        print(f"\nWrote {len(payloads)} payload(s) → {args.out}\n"
              f"Merge with: npm run wp:apply -- {args.out}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
