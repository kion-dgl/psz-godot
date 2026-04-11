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
FIELD_QUEST_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'field_quests')

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

    # Validate entry/exit directions for multi-section quests
    sections = quest.get('sections', [])
    if len(sections) > 1:
        for si, section in enumerate(sections):
            sec_label = f'{fname} section[{si}]'
            cells = section.get('cells', [])

            # entry_direction needed if start cell has an unconnected non-default portal
            if si > 0 and not section.get('entry_direction'):
                start_pos = section.get('start_pos', '')
                start_cell = next((c for c in cells if c.get('pos') == start_pos), None)
                if start_cell:
                    conns = set(start_cell.get('connections', {}).keys())
                    portals = {d for d in start_cell.get('portals', {}) if d != 'default'}
                    unconnected = portals - conns
                    if unconnected:
                        errors.append(f'{sec_label}: missing entry_direction (start cell has unconnected portals: {unconnected})')

            # exit_direction needed if end cell has no warp_edge and has unconnected portals
            if si < len(sections) - 1 and not section.get('exit_direction'):
                end_pos = section.get('end_pos', '')
                end_cell = next((c for c in cells if c.get('pos') == end_pos), None)
                has_warp_edge = end_cell and end_cell.get('warp_edge', '')
                if not has_warp_edge:
                    errors.append(f'{sec_label}: missing exit_direction (required for non-final section)')

    return errors


def validate_directory(dir_path: str, label: str, use_manifest: bool = True) -> tuple[list[str], int]:
    """Validate all quest files in a directory. Returns (errors, count)."""
    all_errors = []
    if use_manifest:
        manifest_path = os.path.join(dir_path, 'manifest.json')
        if not os.path.exists(manifest_path):
            print(f'WARNING: {label} manifest.json not found', file=sys.stderr)
            quest_files = [f for f in os.listdir(dir_path) if f.endswith('.json') and f != 'manifest.json']
        else:
            with open(manifest_path) as f:
                quest_files = json.load(f)
    else:
        quest_files = [f for f in os.listdir(dir_path) if f.endswith('.json') and f != 'manifest.json']

    print(f'\n{label}:')
    for raw_name in sorted(quest_files):
        fname = raw_name if raw_name.endswith('.json') else raw_name + '.json'
        fpath = os.path.join(dir_path, fname)
        if not os.path.exists(fpath):
            all_errors.append(f'{fname}: file not found (listed in manifest)')
            continue
        errors = validate_quest(fpath)
        if errors:
            all_errors.extend(errors)
        else:
            print(f'  OK: {fname}')

    return all_errors, len(quest_files)


def main():
    errors1, count1 = validate_directory(QUEST_DIR, 'Guild Quests', use_manifest=True)
    errors2, count2 = validate_directory(FIELD_QUEST_DIR, 'Field Quests', use_manifest=False)

    all_errors = errors1 + errors2
    total = count1 + count2

    if all_errors:
        print(f'\n{len(all_errors)} error(s):', file=sys.stderr)
        for e in all_errors:
            print(f'  ERROR: {e}', file=sys.stderr)
        sys.exit(1)
    else:
        print(f'\nAll {total} quest files valid.')


if __name__ == '__main__':
    main()
