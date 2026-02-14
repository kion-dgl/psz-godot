#!/usr/bin/env python3
"""Export enemy data from .tres files to a JSON list for the quest editor.

Usage:
    python3 scripts/tools/export_enemy_list.py

Writes to: ../psz-sketch/public/data/enemies.json
"""

import os
import re
import json

ENEMIES_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'enemies')
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'psz-sketch', 'public', 'data', 'enemies.json')

# Map location display names to area keys used by the editor
LOCATION_TO_AREA = {
    'Gurhacia Valley': 'valley',
    'Ozette Wetland': 'wetlands',
    'Ozette Wetlands': 'wetlands',
    'Rioh Snowfield': 'snowfield',
    'Makara Ruins': 'makara',
    'Oblivion City Paru': 'paru',
    'Arca Plant': 'arca',
    'Dark Shrine': 'shrine',
    'Eternal Tower': 'tower',
}

ELEMENT_MAP = {
    '0': 'Native',
    '1': 'Beast',
    '2': 'Machine',
    '3': 'Dark',
}


def parse_tres(path: str) -> dict | None:
    """Parse a .tres file and extract enemy data fields."""
    with open(path, 'r') as f:
        text = f.read()

    def get_field(name: str, default: str = '') -> str:
        m = re.search(rf'^{name}\s*=\s*(.+)$', text, re.MULTILINE)
        if not m:
            return default
        val = m.group(1).strip()
        # Strip quotes
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        return val

    enemy_id = get_field('id')
    if not enemy_id:
        return None

    name = get_field('name')
    model_id = get_field('model_id')
    element = ELEMENT_MAP.get(get_field('element', '0'), 'Native')
    is_rare = get_field('is_rare', 'false') == 'true'
    is_boss = get_field('is_boss', 'false') == 'true'

    # Parse locations from PackedStringArray
    locations_raw = get_field('locations')
    locations = []
    if locations_raw:
        # Format: PackedStringArray("Gurhacia Valley", "Eternal Tower")
        m = re.search(r'PackedStringArray\((.+)\)', locations_raw)
        if m:
            for loc in re.findall(r'"([^"]+)"', m.group(1)):
                area = LOCATION_TO_AREA.get(loc, '')
                if area:
                    locations.append(area)

    return {
        'id': enemy_id,
        'name': name,
        'model_id': model_id,
        'element': element,
        'locations': locations,
        'is_rare': is_rare,
        'is_boss': is_boss,
    }


def main():
    enemies = []
    for fname in sorted(os.listdir(ENEMIES_DIR)):
        if not fname.endswith('.tres'):
            continue
        path = os.path.join(ENEMIES_DIR, fname)
        data = parse_tres(path)
        if data:
            enemies.append(data)

    # Sort by name
    enemies.sort(key=lambda e: e['name'])

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, 'w') as f:
        json.dump(enemies, f, indent=2)

    print(f'Exported {len(enemies)} enemies to {OUTPUT_PATH}')

    # Print summary by area
    area_counts: dict[str, int] = {}
    for e in enemies:
        for loc in e['locations']:
            area_counts[loc] = area_counts.get(loc, 0) + 1
    for area, count in sorted(area_counts.items()):
        print(f'  {area}: {count} enemies')


if __name__ == '__main__':
    main()
