#!/usr/bin/env python3
"""Complete the one-camera DS guild hall for an orbit camera (stdlib only).

Run with the original s00e_sa2_m.glb as INPUT and the completion JSON as OUTPUT.
The source hash pins the face selections; an already repaired input is rejected.
Only the added faces are saved; the packed source asset stays untouched.
Runtime inherits source materials so texture fixes and lighting still apply.
The separate hand-authored floor collider is deliberately not regenerated.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


SOURCE_SHA256 = "1c14b39fc8e88f5ee498933885033b91d1ec26fa2640a56467722c94f6cf171e"
TRANSLATION = (0.0, -5.333160877227783, 60.85844039916992)
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
FORMATS = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}


def complete(source: bytes) -> dict:
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError("Expected the original guild hall GLB; refusing to patch a different or already repaired mesh")
    json_size = struct.unpack_from("<I", source, 12)[0]
    doc = json.loads(source[20:20 + json_size])
    binary = bytearray(source[28 + json_size:])
    primitives = doc["meshes"][0]["primitives"]

    def read(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        fmt = "<" + FORMATS[accessor["componentType"]] * COMPONENTS[accessor["type"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", struct.calcsize(fmt))
        return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(accessor["count"])]

    attributes = [{key: read(value) for key, value in p["attributes"].items()} for p in primitives]
    indices = [[v[0] for v in read(p["indices"])] for p in primitives]
    additions = {12: [], 15: []}

    def world(vertex):
        return tuple(a + b for a, b in zip(vertex, TRANSLATION))

    def reflect(surface, triangle, axis, center):
        # Reflection changes handedness: reverse winding and transform normals.
        vertices = []
        for index in reversed(triangle):
            vertex = {key: list(values[index]) for key, values in attributes[surface].items()}
            vertex["POSITION"][axis] = 2 * (center - TRANSLATION[axis]) - vertex["POSITION"][axis]
            vertex["NORMAL"][axis] *= -1
            vertices.append(vertex)
        additions[surface].append(vertices)

    # The north pair of diamond bollards has a top and only its south walls.
    # Reflect those four triangles per pair through each bollard's center.
    for i in range(0, len(indices[15]), 3):
        triangle = indices[15][i:i + 3]
        points = [world(attributes[15]["POSITION"][j]) for j in triangle]
        if (all(1.9 < abs(p[0]) < 3.1 and 109.251 < p[2] < 109.84 for p in points)
                and max(p[1] for p in points) - min(p[1] for p in points) > 1):
            # Exact center from the existing side corners (not rounded probes).
            center = min(p[2] for p in points)
            reflect(15, triangle, 2, center)

    # The octagonal plinth has south, southeast, southwest and east skirts.
    # Mirror the three south segments north; mirror the east segment west.
    # Keep the central bridge opening and the office spur untouched.
    platform_center = (134.759765625 + 108.673828125) / 2
    for i in range(0, len(indices[12]), 3):
        triangle = indices[12][i:i + 3]
        points = [world(attributes[12]["POSITION"][j]) for j in triangle]
        if not (min(p[1] for p in points) < -13 and max(p[1] for p in points) > -10.7):
            continue
        if all(127.11 < p[2] < 134.77 and abs(p[0]) < 13.05 for p in points):
            reflect(12, triangle, 2, platform_center)
        elif all(abs(p[0] - 13.043) < 0.01 and 116.3 < p[2] < 127.13 for p in points):
            reflect(12, triangle, 0, 0)

    assert len(additions[15]) == 8, "Bollard selection changed"
    assert len(additions[12]) == 10, "Plinth selection changed"

    # Three more pairs along the entrance bridge omit their rear walls AND
    # lids. Their diamond is longer than the pair at the octagon.
    bridge_centers = set()
    for i in range(0, len(indices[15]), 3):
        triangle = indices[15][i:i + 3]
        points = [world(attributes[15]["POSITION"][j]) for j in triangle]
        if all(2.49 < abs(p[0]) < 3.64 and 140 < p[2] < 174 for p in points):
            center_z = max(p[2] for p in points)
            center_x = math.copysign(3.06640625, points[0][0])
            bridge_centers.add((center_x, center_z))
            reflect(15, triangle, 2, center_z)
    assert len(bridge_centers) == 6
    for i in range(0, len(indices[15]), 3):
        triangle = indices[15][i:i + 3]
        points = [world(attributes[15]["POSITION"][j]) for j in triangle]
        if all(1.9 < p[0] < 3.1 and 108 < p[2] < 110 and abs(p[1] + 9.307) < 0.01 for p in points):
            for cx, cz in sorted(bridge_centers):
                vertices = []
                for index in triangle:
                    vertex = {key: list(values[index]) for key, values in attributes[15].items()}
                    p = world(vertex["POSITION"])
                    vertex["POSITION"][0] = p[0] - 2.515625 + cx
                    vertex["POSITION"][2] = (p[2] - 109.251953125) * (0.73828125 / 0.578125) + cz - TRANSLATION[2]
                    vertices.append(vertex)
                additions[15].append(vertices)
    assert len(additions[15]) == 44

    # The water-facing half of the low parapet is absent too. Reflect its
    # surviving inner slope about its crest in XZ, not the whole octagon:
    # the office walkway interrupts the northeast segment and must stay open.
    for i in range(0, len(indices[15]), 3):
        triangle = indices[15][i:i + 3]
        points = [world(attributes[15]["POSITION"][j]) for j in triangle]
        if not all(abs(p[0]) < 13 and 108 < p[2] < 117 and
                   (abs(p[1] + 10.666) < 0.01 or abs(p[1] + 9.916) < 0.01) for p in points):
            continue
        crest = [p for p in points if p[1] > -10]
        low = [p for p in points if p[1] < -10]
        if not crest or not low:
            continue
        parallel = crest if len(crest) == 2 else low
        dx, dz = parallel[1][0] - parallel[0][0], parallel[1][2] - parallel[0][2]
        length = math.hypot(dx, dz)
        nx, nz = -dz / length, dx / length
        origin = crest[0]
        vertices = []
        for index in reversed(triangle):
            vertex = {key: list(values[index]) for key, values in attributes[15].items()}
            p = world(vertex["POSITION"])
            distance = (p[0] - origin[0]) * nx + (p[2] - origin[2]) * nz
            vertex["POSITION"][0] -= 2 * distance * nx
            vertex["POSITION"][2] -= 2 * distance * nz
            # Miter the two octagon corners. Reflecting a slope alone leaves
            # its shared corner inset and opens a triangular crack.
            if p[1] < -10 and abs(abs(p[0]) - 4.924) < 0.01 and abs(p[2] - 109.866) < 0.01:
                vertex["POSITION"][0] = math.copysign(5.40234375, p[0])
                vertex["POSITION"][2] = 108.708984375 - TRANSLATION[2]
            elif p[1] < -10 and abs(abs(p[0]) - 11.887) < 0.01 and abs(p[2] - 116.795) < 0.01:
                vertex["POSITION"][0] = math.copysign(13.04296875, p[0])
                vertex["POSITION"][2] = 116.314453125 - TRANSLATION[2]
            normal = vertex["NORMAL"]
            dot = normal[0] * nx + normal[2] * nz
            normal[0] -= 2 * dot * nx
            normal[2] -= 2 * dot * nz
            vertices.append(vertex)
        additions[15].append(vertices)
    for i in range(0, len(indices[15]), 3):
        triangle = indices[15][i:i + 3]
        points = [world(attributes[15]["POSITION"][j]) for j in triangle]
        if all(p[0] > 12.4 and 116 < p[2] < 128 for p in points):
            reflect(15, triangle, 0, 0)

    # The DS mesh is not perfectly symmetric (the northern trim differs by
    # ~0.035 units). Weld skirt corners to the restored trim, avoiding a seam.
    trim = [world(v["POSITION"]) for tri in additions[15][44:] for v in tri
            if abs(world(v["POSITION"])[1] + 10.666) < 0.01]
    for triangle in additions[12]:
        for vertex in triangle:
            p = world(vertex["POSITION"])
            nearest = min(trim, key=lambda q: (p[0]-q[0])**2 + (p[2]-q[2])**2)
            if math.hypot(p[0]-nearest[0], p[2]-nearest[2]) < 0.08:
                vertex["POSITION"][0] = nearest[0] - TRANSLATION[0]
                vertex["POSITION"][2] = nearest[2] - TRANSLATION[2]

    # Rear of the kiosk: join its actual open rear corners, cap the open roof,
    # and provide the service-bay floor visible through its existing side arches.
    # Use the existing stone material, with colors sampled from the kiosk at the
    # nearest height/location. This retains the room's baked teal illumination.
    additions[11] = []
    kiosk_positions = [world(v) for v in attributes[13]["POSITION"]]

    def corner(x, z, y):
        return min(kiosk_positions, key=lambda p: (p[0] - x)**2 + (p[2] - z)**2 + (p[1] - y)**2)

    a = corner(-17.457, 110.397, -5.401)
    b = corner(-11.334, 104.274, -5.404)
    c = corner(-5.760, 109.848, -5.404)
    e = corner(-11.883, 115.971, -5.401)
    floor_y = world(attributes[15]["POSITION"][0])[1]
    assert abs(floor_y + 10.666) < 0.01

    def at_y(p, y):
        return (p[0], y, p[2])

    def quad(points, uv_size, surface=11, uvs=None):
        u = [points[1][i] - points[0][i] for i in range(3)]
        v = [points[2][i] - points[0][i] for i in range(3)]
        normal = [u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0]]
        length = math.sqrt(sum(n*n for n in normal))
        normal = [n / length for n in normal]
        if uvs is None:
            uvs = [(0, 0), (uv_size[0], 0), uv_size, (0, uv_size[1])]
        vertices = []
        for point, uv in zip(points, uvs):
            nearest = min(range(len(kiosk_positions)), key=lambda i: sum((x-y)**2 for x, y in zip(point, kiosk_positions[i])))
            vertices.append({
                "POSITION": [x-y for x, y in zip(point, TRANSLATION)],
                "NORMAL": normal, "TEXCOORD_0": uv,
                "COLOR_0": attributes[13]["COLOR_0"][nearest],
            })
        for tri in [(0, 1, 2), (0, 2, 3)]:
            additions[surface].append([vertices[i] for i in tri])

    quad([b, a, at_y(a, -13.166), at_y(b, -13.166)], (1.0, 0.85))
    quad([a, e, c, b], (0.9, 1.0))
    quad([at_y(p, floor_y) for p in [a, e, c, b]], (0.9, 1.0))

    # A continuous stone foundation below the kiosk, including its projecting
    # counter lip. The small ledge is below the service floor to avoid coplanar
    # faces; its walls sit outside the existing arches and extend below water.
    back_offset = 0.04 / math.sqrt(2)
    front_offset = 0.9 / math.sqrt(2)
    base = [(a[0]-back_offset, floor_y-0.025, a[2]-back_offset),
            (e[0]+front_offset, floor_y-0.025, e[2]+front_offset),
            (c[0]+front_offset, floor_y-0.025, c[2]+front_offset),
            (b[0]-back_offset, floor_y-0.025, b[2]-back_offset)]
    base = [(p[0] + side * back_offset, p[1], p[2] - side * back_offset)
            for p, side in zip(base, [-1, -1, 1, 1])]
    quad(base, (0.9, 1.0))
    for p, q in zip(base, base[1:] + base[:1]):
        repeat = math.hypot(q[0]-p[0], q[2]-p[2]) / 5.4
        quad([p, q, at_y(q, -13.166), at_y(p, -13.166)], (1, 1), 12,
             [(0.75, 0), (0.75, repeat), (1.0, repeat), (1.0, 0)])

    # The office bridge only has its southeast skirt. Copy that strip onto
    # the opposite deck edge, retaining its atlas UVs and vertex illumination.
    deck = [world(v) for v in attributes[12]["POSITION"]]
    near = min(deck, key=lambda p: (p[0]-7.453)**2 + (p[2]-110.764)**2 + (p[1]-floor_y)**2)
    far = min(deck, key=lambda p: (p[0]-12.652)**2 + (p[2]-105.525)**2 + (p[1]-floor_y)**2)
    for i in range(0, len(indices[12]), 3):
        triangle = indices[12][i:i+3]
        points = [world(attributes[12]["POSITION"][j]) for j in triangle]
        if not (all(10.9 < p[0] < 16.2 and 109 < p[2] < 114.4 for p in points)
                and min(p[1] for p in points) < -13):
            continue
        vertices = []
        for index in reversed(triangle):
            vertex = {key: list(values[index]) for key, values in attributes[12].items()}
            p = world(vertex["POSITION"])
            target = near if p[0] < 12 else far
            vertex["POSITION"][0] = target[0] - TRANSLATION[0]
            vertex["POSITION"][2] = target[2] - TRANSLATION[2]
            normal = vertex["NORMAL"]
            normal[0], normal[2] = -normal[2], -normal[0]
            vertices.append(vertex)
        additions[12].append(vertices)
    assert len(additions[12]) == 20, "Office bridge skirt selection changed"
    # Close the underside at the same depth as the surviving skirt.
    south_near = min(deck, key=lambda p: (p[0]-10.988)**2 + (p[2]-114.299)**2 + (p[1]-floor_y)**2)
    south_far = min(deck, key=lambda p: (p[0]-16.191)**2 + (p[2]-109.065)**2 + (p[1]-floor_y)**2)
    quad([at_y(p, -13.166) for p in [near, south_near, south_far, far]], (0.9, 1.0))

    # Both office lantern roofs only contain their camera-facing half.
    # Mirror the outer base corner, keeping the shared ridge/apex untouched
    # (the apex sits slightly off the base diagonal in the authored mesh).
    roof_added = 0
    for start in (42, 45, 48, 51):
        triangle = indices[12][start:start + 3]
        points = [world(attributes[12]["POSITION"][j]) for j in triangle]
        assert all(9 < p[0] < 18 and -7.8 < p[1] < -7.4 for p in points), "Lantern selection changed"
        base = [p for p in points if p[1] < -7.7]
        center_z = min(p[2] for p in base)
        vertices = []
        for index in reversed(triangle):
            vertex = {key: list(values[index]) for key, values in attributes[12].items()}
            if world(vertex["POSITION"])[1] < -7.7:
                vertex["POSITION"][2] = 2 * (center_z - TRANSLATION[2]) - vertex["POSITION"][2]
            vertex["NORMAL"][2] *= -1
            vertices.append(vertex)
        additions[12].append(vertices)
        roof_added += 1
    assert roof_added == 4

    report = {"pillar_triangles": 44, "parapet_triangles": len(additions[15]) - 44,
              "plinth_triangles": 10, "kiosk_triangles": 6,
              "kiosk_base_triangles": 10, "office_bridge_triangles": 4,
              "lantern_roof_triangles": roof_added, "source_sha256": SOURCE_SHA256}
    return {"report": report, "surfaces": [
        {"material": doc["materials"][primitives[surface]["material"]]["name"],
         "triangles": triangles} for surface, triangles in sorted(additions.items())]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = complete(args.input.read_bytes())
    args.output.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(json.dumps(result["report"], indent=2))
