#!/usr/bin/env python3
"""Detect the s03b cave glow anchors from stage art (#657).

Adapts the #646 flame-UV lantern method to the B caves' glow props: instead
of a flame UV column, the anchors are whole MATERIALS — the bioluminescent
kinoko mushrooms (s03_1_kinoko) and the ga1 goal room's star sprite
(s03_0_0star). Everything else in the B sheets was checked and carries no
authored glow (rock/view/yuka are matte; tree6's shards are non-emissive
icicles).

Method per stage GLB: gather the vertices indexed by the anchor material's
primitives, cluster them on a 2-unit grid with union-find (same clustering
as lanternDetect.ts), and report each cluster's centroid and top. Clusters
outside the plausible prop band (floor-scatter noise, backdrop copies) are
dropped by --min-verts / --band.

Usage:
  python3 scripts/tools/detect_s03b_anchors.py --stats          # survey all stages
  python3 scripts/tools/detect_s03b_anchors.py --stage s03b_xb2 # anchors as JSON
"""
import argparse
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STAGE_ROOT = REPO / "assets/stages/snowfield_b"

# Anchor materials — the art's own glow props.
ANCHOR_MATERIALS = ("1_kinoko", "1_0star")


def read_glb(path: Path):
    data = path.read_bytes()
    off = 12
    gl = None
    blob = b""
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off : off + 8])
        chunk = data[off + 8 : off + 8 + clen]
        if ctype == 0x4E4F534A:  # JSON
            gl = json.loads(chunk)
        elif ctype == 0x004E4942:  # BIN
            blob = chunk
        off += 8 + clen + ((4 - (clen % 4)) % 4)
    if gl is None:
        raise SystemExit(f"no JSON chunk in {path}")
    return gl, blob


def accessor_reader(gl, blob):
    """Return a function(accessor_idx) -> flat component list."""
    accs = gl["accessors"]
    bvs = gl["bufferViews"]

    def read(idx):
        acc = accs[idx]
        bv = bvs[acc["bufferView"]]
        comp_type = acc["componentType"]
        count = acc["count"]
        fmts = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
        fmt, size = fmts[comp_type]
        n_comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or n_comp * size
        vals = []
        endian = "<" + fmt * n_comp
        for i in range(count):
            o = base + i * stride
            vals.extend(struct.unpack_from(endian, blob, o))
        return vals

    return read


def node_matrix(gl, node_idx):
    """World transform of a node (GLB roots are scene children → apply TRS)."""
    node = gl["nodes"][node_idx]
    m = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]
    if "matrix" in node:
        m = [node["matrix"][i * 4 : (i + 1) * 4] for i in range(4)]
    else:  # TRS
        t = node.get("translation", [0, 0, 0])
        q = node.get("rotation", [0, 0, 0, 1])
        s = node.get("scale", [1, 1, 1])
        x, y, z, w = q
        rot = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
        m = [
            [rot[0][0] * s[0], rot[0][1] * s[1], rot[0][2] * s[2], t[0]],
            [rot[1][0] * s[0], rot[1][1] * s[1], rot[1][2] * s[2], t[1]],
            [rot[2][0] * s[0], rot[2][1] * s[1], rot[2][2] * s[2], t[2]],
            [0, 0, 0, 1],
        ]
    parent = next((i for i, n in enumerate(gl["nodes"]) if node_idx in n.get("children", [])), None)
    if parent is not None:
        pm = node_matrix(gl, parent)
        m = mat_mul(pm, m)
    return m


def mat_mul(a, b):
    return [
        [sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] + [0]
        for i in range(3)
    ] + [[0, 0, 0, 1]]


def apply(m, p):
    return [sum(m[i][k] * p[k] for k in range(3)) + m[i][3] for i in range(3)]


def cluster(points, cell=2.0):
    """Grid + union-find clustering (the lanternDetect method)."""
    cells = {}
    for p in points:
        k = (int(p[0] // cell), int(p[2] // cell))
        cells.setdefault(k, []).append(p)
    parent = {k: k for k in cells}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for (ix, iz) in cells:
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                nk = (ix + dx, iz + dz)
                if nk in parent:
                    parent[find(nk)] = find((ix, iz))
    regions = {}
    for k, pts in cells.items():
        regions.setdefault(find(k), []).extend(pts)
    return list(regions.values())


def detect(stage_id: str, min_verts: int, band, materials=ANCHOR_MATERIALS):
    glb = STAGE_ROOT / stage_id / "lndmd" / f"{stage_id}_m.glb"
    gl, blob = read_glb(glb)
    read = accessor_reader(gl, blob)
    pos = read(0)  # shared POSITION accessor (verified: all primitives use 0)
    meshes = []
    for n_idx, node in enumerate(gl["nodes"]):
        if "mesh" in node:
            meshes.append((node_matrix(gl, n_idx), node["mesh"]))
    anchors = []
    for mat_idx, mat in enumerate(gl["materials"]):
        if mat.get("name") not in materials:
            continue
        pts = []
        for world, mesh_idx in meshes:
            for prim in gl["meshes"][mesh_idx]["primitives"]:
                if prim.get("material") != mat_idx:
                    continue
                idx = read(prim["indices"])
                seen = set()
                for vi in idx:
                    if vi in seen:
                        continue
                    seen.add(vi)
                    p = apply(world, pos[vi * 3 : vi * 3 + 3])
                    pts.append(p)
        if not pts:
            continue
        for region in cluster(pts):
            top = max(p[1] for p in region)
            if band and not (band[0] <= top <= band[1]):
                continue
            if len(region) < min_verts:
                continue
            cx = sum(p[0] for p in region) / len(region)
            cy = sum(p[1] for p in region) / len(region)
            cz = sum(p[2] for p in region) / len(region)
            anchors.append(
                {
                    "material": mat["name"],
                    "verts": len(region),
                    "top": round(top, 2),
                    "centroid": [round(cx, 2), round(cy, 2), round(cz, 2)],
                }
            )
    return sorted(anchors, key=lambda a: (a["material"], a["centroid"][0], a["centroid"][2]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stats", action="store_true", help="survey clusters in all stages")
    ap.add_argument("--stage")
    ap.add_argument("--min-verts", type=int, default=6)
    ap.add_argument("--band", type=float, nargs=2, metavar=("LO", "HI"))
    args = ap.parse_args()

    if args.stats:
        for d in sorted(STAGE_ROOT.iterdir()):
            if not d.is_dir() or not d.name.startswith("s03b"):
                continue
            try:
                found = detect(d.name, 1, None)
            except Exception as e:  # noqa: BLE001 — survey keeps going
                print(f"{d.name}: ERROR {e}")
                continue
            by_mat = {}
            for a in found:
                by_mat.setdefault(a["material"], []).append(a)
            for mat, lst in by_mat.items():
                tops = ", ".join(f"v{a['verts']}@top{a['top']}" for a in lst)
                print(f"{d.name} {mat}: {len(lst)} clusters — {tops}")
        return 0

    if not args.stage:
        ap.error("--stage or --stats required")
    print(json.dumps(detect(args.stage, args.min_verts, args.band), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
