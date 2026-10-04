#!/usr/bin/env python3
"""Replace Shrine A lantern cards at their source-art positions.

Preserve each room's existing effects, including ga1's overhead prototype.
Requires the local stage assets; rerunning updates lanterns without duplicates.
"""
import json
from author_shrine_b_lights import ROOT, OUT, primitives, components, bounds


def author(folder):
    stage = folder.name
    lamps = set()
    for name, triangles in primitives(folder / 'lndmd' / f'{stage}_m.glb'):
        if name != '1_light3':
            continue
        for group in components(triangles):
            lo, hi = bounds(group)
            if max(hi[0]-lo[0], hi[2]-lo[2]) < 3 and hi[1] < 4:
                lamps.add((round((lo[0]+hi[0])/2, 3), round((lo[2]+hi[2])/2, 3)))
    target = OUT / f'{stage}.json'
    source = target if target.exists() else folder / 'lndmd' / f'{stage}_effects.json'
    data = json.loads(source.read_text()) if source.exists() else {}
    effects = [e for e in data.get('effects', []) if e.get('type') != 'shrine_lantern']
    for i, (x, z) in enumerate(sorted(lamps)):
        effects.append(dict(id=f'lantern_{i+1}', type='shrine_lantern', category='placed',
                            position=[x, 0, z], color=[.35, .85, .82], intensity=3.0, radius=7))
    data.update(stage_id=stage, effects=effects)
    target.write_text(json.dumps(data, indent=2)+'\n')
    print(f'{stage}: {len(lamps)} lanterns')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for folder in sorted((ROOT / 'assets/stages/shrine_a').glob('s07a_*')):
        if (folder / 'lndmd' / f'{folder.name}_m.glb').exists():
            author(folder)
