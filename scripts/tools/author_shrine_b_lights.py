#!/usr/bin/env python3
"""Rebuild the tracked Shrine B rig from collision floors and pillar locations.

Run after changing source art. Requires the local stage asset pack. The ga1
reference rig is hand-authored and preserved; other rooms use floor-tested
pools and their own doorway/fixture coordinates, never copied ga1 positions.
"""
import json
import math
from pathlib import Path
from detect_s03b_anchors import read_glb, accessor_reader

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/stage_configs/shrine-lights'
WARM = [1.0, 0.85, 0.55]
TEAL = [0.3, 0.95, 0.9]


def primitives(path):
    doc, blob = read_glb(path)
    read = accessor_reader(doc, blob)
    # These stage/floor exports have identity node transforms. Fail if that
    # changes instead of silently authoring lights in the wrong space.
    for node in doc['nodes']:
        assert not any(k in node for k in ('matrix', 'translation', 'rotation', 'scale')), path
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            flat = read(prim['attributes']['POSITION'])
            vertices = [tuple(flat[i:i+3]) for i in range(0, len(flat), 3)]
            indices = read(prim['indices']) if 'indices' in prim else list(range(len(vertices)))
            name = doc.get('materials', [{}])[prim.get('material', 0)].get('name', '')
            yield name, [tuple(vertices[i] for i in indices[j:j+3]) for j in range(0, len(indices), 3)]


def components(triangles):
    groups = []
    for tri in triangles:
        points = set(tri)
        touched = [g for g in groups if points & g]
        for group in touched:
            points |= group
            groups.remove(group)
        groups.append(points)
    return groups


def bounds(points):
    return ([min(v[k] for v in points) for k in range(3)],
            [max(v[k] for v in points) for k in range(3)])


def floor_at(triangles, x, z):
    heights = []
    for a, b, c in triangles:
        det = (b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2])
        if abs(det) < 1e-6:
            continue
        u = ((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/det
        v = ((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/det
        if min(u, v, 1-u-v) >= -1e-5:
            heights.append(u*a[1]+v*b[1]+(1-u-v)*c[1])
    return max(heights) if heights else None


def light(position, energy, radius, target=None, shadow=False, color=WARM):
    entry = dict(type='light', category='placed', position=[round(v, 3) for v in position],
                 color=color, intensity=energy, radius=radius)
    if target:
        entry['targets'] = target
    if shadow:
        entry['shadows'] = True
    return entry


def author(stage, config):
    folder = ROOT / f'assets/stages/shrine_b/{stage}/lndmd'
    pillars, lamps, doors = [], [], []
    for name, triangles in primitives(folder / f'{stage}_m.glb'):
        if name not in ('1_line', '1_blight', '1_door'):
            continue
        for group in components(triangles):
            lo, hi = bounds(group)
            x, z = (lo[0]+hi[0])/2, (lo[2]+hi[2])/2
            if name == '1_line' and hi[1]-lo[1] > 5 and max(hi[0]-lo[0], hi[2]-lo[2]) < 4:
                pillars.append([round(x, 3), round(z, 3)])
            if name == '1_door':
                doors.append([x, (lo[1]+hi[1])/2, z])
            if name == '1_blight' and max(hi[0]-lo[0], hi[2]-lo[2]) < 3 and hi[1] < 4:
                # Crossed lamp cards are disconnected; merge their common XZ.
                point = [round(x, 2), round(z, 2)]
                if not any(math.dist(point, p) < .1 for p in lamps):
                    lamps.append(point)
    pillars.sort()
    lamps.sort()
    if stage == 's07b_ga1':
        reference = OUT / f'{stage}.json'
        effects = json.loads(reference.read_text())['effects'] if reference.exists() else json.loads(
            (folder / f'{stage}_effects.json').read_text())['effects']
    else:
        floor = [t for _, tris in primitives(folder / f'{stage}-floor.glb') for t in tris]
        lo, hi = bounds([p for t in floor for p in t])
        pools = []
        for x in range(math.ceil(lo[0]/14)*14, math.floor(hi[0]/14)*14+1, 14):
            for z in range(math.ceil(lo[2]/14)*14, math.floor(hi[2]/14)*14+1, 14):
                y = floor_at(floor, x, z)
                if y is not None and all(floor_at(floor, x+dx, z+dz) is not None
                                         for dx, dz in ((2,0),(-2,0),(0,2),(0,-2))):
                    pools.append((x,y,z))
        # Narrow or offset platforms can fall between grid points. Add their
        # triangle centroids where no existing pool reaches the walkable floor.
        for a,b,c in sorted(floor):
            x,y,z = [(a[k]+b[k]+c[k])/3 for k in range(3)]
            if all(math.hypot(x-p[0], z-p[2]) > 10 for p in pools):
                pools.append((x,y,z))
        effects = []
        for x,y,z in pools:
            center = abs(x)<1 and abs(z)<1
            effects.append(light([x,y+.5,z],1.2 if center or abs(x)<1 else .8,20 if center else 10,'stage'))
            effects.append(light([x,y+2.5,z],1.5 if center else .7,12 if center else 9,shadow=True))
        for portal in config.get('portals', []):
            for key in ('spawnPosition','triggerPosition'):
                pos = portal.get(key)
                if pos:
                    effects.append(light([pos[0],pos[1]+2,pos[2]],.8,6,'stage'))
        for x,z in pillars:
            effects.append(light([x,1.5,z],.084,7,color=[.173,.682,.62]))
        for x,z in lamps:
            effects.append(light([x,.5,z],2.5,13,color=TEAL))
    # Replace the old sprite-card accent light with a placeable 3D lantern.
    for effect in effects:
        x, y, z = effect['position']
        if effect['color'][0] < .5 and any(math.dist([x,z], point) < .1 for point in lamps):
            effect.update(type='shrine_lantern', position=[x,0,z], color=[.173,.682,.62], intensity=1.4, radius=7)
    # The doorway is farther out than the threshold washes. Light its
    # actual vertical mesh from the room-facing side, above the lanterns.
    effects = [e for e in effects if not str(e.get('id','')).startswith('door_beacon_')]
    for i, (x,y,z) in enumerate(doors):
        length = math.hypot(x,z) or 1
        wash = light([x-x/length*3.5, y, z-z/length*3.5], 2.5, 11, 'stage', color=[.7,.85,.8])
        wash['id'] = f'door_beacon_{i}'
        effects.append(wash)
    assert len(effects) <= 64, (stage, len(effects))
    result = {'stage_id':stage, 'pillar_centers':pillars, 'effects':effects}
    (OUT / f'{stage}.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'{stage}: {len(pillars)} pillars, {len(effects)} lights')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    configs = json.loads((ROOT / 'data/stage_configs/unified-stage-configs.json').read_text())
    for stage in sorted(k for k in configs if k.startswith('s07b_')):
        author(stage, configs[stage])
