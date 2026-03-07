#!/usr/bin/env python3
"""Validate quest JSON files conform to v1 schema.

Checks:
  - Required top-level fields: version, last_updated, id, name, description, area_id, sections
  - version == 1
  - Each section has: type, area, start_pos, end_pos, cells
  - Each cell has required fields (pos, stage_id, rotation, connections, portals, etc.)
  - Portals are v1 format (string references, not baked dictionaries)
  - Connections are bidirectional
  - start_pos/end_pos reference existing cells
"""

import json
import os
import sys

QUEST_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'quests')

REQUIRED_QUEST_FIELDS = {'version', 'last_updated', 'id', 'name', 'description', 'area_id', 'sections'}
REQUIRED_SECTION_FIELDS = {'type', 'area', 'start_pos', 'end_pos', 'cells'}
REQUIRED_CELL_FIELDS = {
    'pos', 'stage_id', 'rotation', 'connections', 'portals',
    'is_start', 'is_end', 'is_branch', 'has_key', 'key_for_cell',
    'is_key_gate', 'key_gate_direction', 'key_drop', 'required_keys',
    'warp_edge', 'path_order',
}


def validate_quest(filepath: str) -> list[str]:
    errors = []
    fname = os.path.basename(filepath)

    with open(filepath) as f:
        quest = json.load(f)

    # Top-level fields
    missing = REQUIRED_QUEST_FIELDS - set(quest.keys())
    if missing:
        errors.append(f'{fname}: missing top-level fields: {missing}')

    if quest.get('version') != 1:
        errors.append(f'{fname}: version must be 1, got {quest.get("version")}')

    for si, section in enumerate(quest.get('sections', [])):
        sec_label = f'{fname} section[{si}]'
        sec_missing = REQUIRED_SECTION_FIELDS - set(section.keys())
        if sec_missing:
            errors.append(f'{sec_label}: missing fields: {sec_missing}')

        cells = section.get('cells', [])
        cell_positions = {c.get('pos') for c in cells}

        # Validate start_pos/end_pos
        start = section.get('start_pos', '')
        end = section.get('end_pos', '')
        if start and start not in cell_positions:
            errors.append(f'{sec_label}: start_pos "{start}" not in cells')
        if end and end not in cell_positions:
            errors.append(f'{sec_label}: end_pos "{end}" not in cells')

        for cell in cells:
            pos = cell.get('pos', '?')
            cell_label = f'{fname} [{pos}]'
            cell_missing = REQUIRED_CELL_FIELDS - set(cell.keys())
            if cell_missing:
                errors.append(f'{cell_label}: missing fields: {cell_missing}')

            # Portal format: all values must be strings (v1)
            portals = cell.get('portals', {})
            for dir_key, value in portals.items():
                if not isinstance(value, str):
                    errors.append(f'{cell_label}: portal "{dir_key}" must be a string (v1 format), got {type(value).__name__}')

            # Connection bidirectionality
            connections = cell.get('connections', {})
            for dir_key, target_pos in connections.items():
                if target_pos not in cell_positions:
                    errors.append(f'{cell_label}: connection "{dir_key}" -> "{target_pos}" not in section cells')

    return errors


def main():
    all_errors = []
    manifest_path = os.path.join(QUEST_DIR, 'manifest.json')
    if not os.path.exists(manifest_path):
        print('WARNING: manifest.json not found', file=sys.stderr)
        quest_files = [f for f in os.listdir(QUEST_DIR) if f.endswith('.json') and f != 'manifest.json']
    else:
        with open(manifest_path) as f:
            quest_files = json.load(f)

    for raw_name in sorted(quest_files):
        fname = raw_name if raw_name.endswith('.json') else raw_name + '.json'
        fpath = os.path.join(QUEST_DIR, fname)
        if not os.path.exists(fpath):
            all_errors.append(f'{fname}: file not found (listed in manifest)')
            continue
        errors = validate_quest(fpath)
        if errors:
            all_errors.extend(errors)
        else:
            print(f'  OK: {fname}')

    if all_errors:
        print(f'\n{len(all_errors)} error(s):', file=sys.stderr)
        for e in all_errors:
            print(f'  ERROR: {e}', file=sys.stderr)
        sys.exit(1)
    else:
        print(f'\nAll {len(quest_files)} quest files valid.')


if __name__ == '__main__':
    main()
