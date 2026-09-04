#!/usr/bin/env python3
"""Which portals now sit off the end of their stage's floor.

#617. Moving a gate onto psz-re's measured doorway drags the spawn and trigger
with it, and on some stages that lands them past the edge of the floor mesh --
so the autopilot walks straight at a point with nothing under it and stalls.

FINDING THESE ONE AUTOPILOT RUN AT A TIME IS THE SLOW WAY. Each floor fixed
reveals the next stage behind it, three deep so far, with no way to know how
many remain. And it cannot be predicted from how far the gate moved: s01b_ic1's
south gate moved 3.14 units and broke, s01b_lb1's east moved 1.90 and broke,
while s05a_sa1 moved 13.4 and is fine. Distance is not the question. Whether
the point has floor under it is the question, and that is answerable offline.

So this loads each stage's floor mesh, projects it to XZ (the floors are flat
slabs), and asks whether each portal's spawn and trigger positions land inside
an actual triangle -- not a bounding box, which would pass points sitting in an
L-shaped room's missing corner.

Output is the full list of doorways needing a floor extension, with how far
past the edge each one reaches, so they can be authored in one pass.
"""
import json, math, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
CONFIGS = ROOT / "data/stage_configs/unified-stage-configs.json"
AXIS = {"north": 2, "south": 2, "east": 0, "west": 0}
OUTWARD = {"north": -1, "south": 1, "east": 1, "west": -1}

# The engine's trigger is BoxShape3D(6, 3, 6), so it reaches 3 either side of
# its centre. The player never walks to the centre -- the cell loads the moment
# they cross the NEAR FACE, and the walk is abandoned there. Testing the centre
# for floor flags 155 doorways, nearly all of them a uniform ~3 units past a
# +/-25 floor edge, which is exactly the half-depth of the box. The near face is
# what has to be reachable.
TRIGGER_HALF = 3.0

# THE POINT BEING ON FLOOR IS NOT ENOUGH. player.gd refuses to move unless it
# finds floor FLOOR_CHECK_DISTANCE ahead of itself and FLOOR_CHECK_SIDE either
# side of that -- the same three probes a stuck-walk logs. So reaching a point
# needs floor about a metre BEYOND it, laterally too.
#
# s01b_tb3 is what taught this: floor to z=26.5, trigger face at 26.0, so a
# plain point test passed it -- and search_and_rescue stalled at 25.5 with 0/3
# probes, because standing at 26.0 wants floor at 27.0.
FLOOR_CHECK_DISTANCE = 1.0
FLOOR_CHECK_SIDE = 0.5


def floor_triangles(glb: pathlib.Path):
    """XZ triangles of the collision floor, or None if the file has no mesh."""
    raw = glb.read_bytes()
    jlen = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + jlen])
    blob = raw[20 + jlen + 8:]

    # Prefer the collision node; some floors are a single unnamed mesh.
    mesh_idx = None
    for n in doc.get("nodes", []):
        if "colonly" in str(n.get("name", "")) and "mesh" in n:
            mesh_idx = n["mesh"]
            break
    if mesh_idx is None:
        for n in doc.get("nodes", []):
            if "mesh" in n:
                mesh_idx = n["mesh"]
                break
    if mesh_idx is None:
        return None

    tris = []
    for prim in doc["meshes"][mesh_idx]["primitives"]:
        acc = doc["accessors"][prim["attributes"]["POSITION"]]
        bv = doc["bufferViews"][acc["bufferView"]]
        base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or 12
        pts = []
        for i in range(acc["count"]):
            x, _y, z = struct.unpack_from("<fff", blob, base + i * stride)
            pts.append((x, z))
        if "indices" in prim:
            ia = doc["accessors"][prim["indices"]]
            ibv = doc["bufferViews"][ia["bufferView"]]
            ibase = ibv.get("byteOffset", 0) + ia.get("byteOffset", 0)
            fmt = {5121: "<B", 5123: "<H", 5125: "<I"}[ia["componentType"]]
            size = struct.calcsize(fmt)
            idx = [struct.unpack_from(fmt, blob, ibase + i * size)[0]
                   for i in range(ia["count"])]
        else:
            idx = list(range(acc["count"]))
        for i in range(0, len(idx) - 2, 3):
            tris.append((pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]))
    return tris


def inside(tris, x, z, pad=0.0):
    """Is (x, z) inside any triangle? `pad` grows each triangle outward."""
    for (ax, az), (bx, bz), (cx, cz) in tris:
        d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
        if abs(d) < 1e-9:
            continue
        a = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
        b = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
        c = 1.0 - a - b
        lo = -pad
        if a >= lo and b >= lo and c >= lo:
            return True
    return False


def edge_gap(tris, x, z):
    """Roughly how far (x, z) is from the nearest floor triangle vertex."""
    best = math.inf
    for tri in tris:
        for vx, vz in tri:
            best = min(best, math.hypot(x - vx, z - vz))
    return best


def main() -> int:
    cfgs = json.loads(CONFIGS.read_text())
    floors = {p.stem[:-6]: p for p in ROOT.glob("assets/stages/*/*/lndmd/*-floor.glb")}

    missing_floor, bad, checked = [], [], 0
    for stage_id, st in sorted(cfgs.items()):
        if not isinstance(st, dict):
            continue
        portals = [p for p in st.get("portals", []) if p.get("triggerPosition")]
        if not portals:
            continue
        glb = floors.get(stage_id)
        if glb is None:
            missing_floor.append(stage_id)
            continue
        tris = floor_triangles(glb)
        if not tris:
            missing_floor.append(stage_id)
            continue
        for p in portals:
            checked += 1
            ax = AXIS[p["direction"]]
            out = OUTWARD[p["direction"]]
            for kind in ("spawnPosition", "triggerPosition"):
                pt = p.get(kind)
                if not pt:
                    continue
                x, z = float(pt[0]), float(pt[2])
                if kind == "triggerPosition":
                    # Step back to the near face -- the first point of the box
                    # the player touches coming from inside the room.
                    if ax == 2:
                        z -= out * TRIGGER_HALF
                    else:
                        x -= out * TRIGGER_HALF
                # Probe as the player would: ahead along the approach, plus
                # both shoulders. All three must land, matching can_move_to.
                ax_is_z = (ax == 2)
                fx = out * FLOOR_CHECK_DISTANCE if not ax_is_z else 0.0
                fz = out * FLOOR_CHECK_DISTANCE if ax_is_z else 0.0
                sx, sz = (FLOOR_CHECK_SIDE, 0.0) if ax_is_z else (0.0, FLOOR_CHECK_SIDE)
                probes = [(x + fx, z + fz),
                          (x + fx + sx, z + fz + sz),
                          (x + fx - sx, z + fz - sz)]
                if not inside(tris, x, z) or not all(inside(tris, px, pz) for px, pz in probes):
                    coord = z if ax == 2 else x
                    bad.append((stage_id, p["direction"],
                                "spawn" if kind == "spawnPosition" else "trigger face",
                                round(coord, 2), round(edge_gap(tris, x, z), 2)))
                    break

    print("portal points checked: %d across %d stages" % (checked, len(cfgs)))
    if missing_floor:
        print("stages with no floor mesh found: %d %s"
              % (len(missing_floor), missing_floor[:6]))

    if not bad:
        print("\nevery spawn and trigger lands on floor.")
        return 0

    print("\n%d DOORWAYS NEED THE FLOOR EXTENDED" % len(bad))
    print("%-14s %-7s %-8s %9s %10s" % ("stage", "door", "point", "coord", "gap"))
    for stage_id, direction, kind, coord, gap in sorted(bad, key=lambda r: -r[4]):
        print("%-14s %-7s %-8s %9.2f %10.2f" % (stage_id, direction, kind, coord, gap))

    by_stage = {}
    for stage_id, *_ in bad:
        by_stage[stage_id] = by_stage.get(stage_id, 0) + 1
    print("\n%d stages affected: %s" % (len(by_stage), ", ".join(sorted(by_stage))))
    return 1


if __name__ == "__main__":
    sys.exit(main())
