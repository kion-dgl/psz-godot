#!/usr/bin/env python3
"""Sample Makara A/B rooms' lower hana2 triangles for a single room-local emitter."""
import json
import math
import random
from pathlib import Path
from author_shrine_b_lights import primitives

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/stage_configs/makara-particles'


def author():
    OUT.mkdir(parents=True, exist_ok=True)
    folders = sorted((ROOT / 'assets/stages/makara_a').glob('s04a_*'))
    folders.extend(sorted((ROOT / 'assets/stages/makara_b').glob('s04b_*')))
    for folder in folders:
        triangles = [t for name, ts in primitives(folder / 'lndmd' / f'{folder.name}_m.glb')
                     if name == '1_hana2' for t in ts if max(v[1] for v in t) < 0]
        if not triangles:
            continue
        weights = [abs((b[0]-a[0])*(c[2]-a[2])-(c[0]-a[0])*(b[2]-a[2])) for a,b,c in triangles]
        rng = random.Random(folder.name)
        points = []
        for a,b,c in rng.choices(triangles, weights=weights, k=128):
            u, v = math.sqrt(rng.random()), rng.random()
            points.append([round((1-u)*a[k]+u*(1-v)*b[k]+u*v*c[k], 4) for k in range(3)])
        (OUT / f'{folder.name}.json').write_text(json.dumps({
            'source_material': '1_hana2', 'source_texture': 's04_1_hana2.png',
            'points': points}, separators=(',', ':'))+'\n')
        print(folder.name, len(triangles), 'triangles,', len(points), 'points')


if __name__ == '__main__':
    author()
