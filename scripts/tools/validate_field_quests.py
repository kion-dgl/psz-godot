#!/usr/bin/env python3
"""Validate field quest JSON files conform to the expected schema.

Checks:
  1. Required top-level fields: version, last_updated, id, name, description, area_id, sections
  2. Each section has: type, area, start_pos, end_pos, cells
  3. Each cell has required fields (pos, stage_id, rotation, connections, portals, etc.)
  4. Portal connection bidirectionality (A->south->B implies B->north->A)
  5. All connection targets exist as cells in the same section
  6. Stage portal directions (after rotation) match the cell's connections and portals
"""

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(SCRIPT_DIR, '..', '..')
FIELD_QUEST_DIR = os.path.join(PROJECT_ROOT, 'data', 'field_quests')
STAGE_CONFIG_PATH = os.path.join(PROJECT_ROOT, 'data', 'stage_configs', 'unified-stage-configs.json')

REQUIRED_QUEST_FIELDS = {'version', 'last_updated', 'id', 'name', 'description', 'area_id', 'sections'}
REQUIRED_SECTION_FIELDS = {'type', 'area', 'start_pos', 'end_pos', 'cells'}
REQUIRED_CELL_FIELDS = {
    'pos', 'stage_id', 'rotation', 'connections', 'portals',
    'is_start', 'is_end', 'is_branch', 'has_key', 'key_for_cell',
    'is_key_gate', 'key_gate_direction', 'key_drop', 'required_keys',
    'warp_edge', 'path_order', 'objects',
}

OPPOSITE_DIR = {
    'north': 'south',
    'south': 'north',
    'east': 'west',
    'west': 'east',
}

# Rotation maps: given a base direction, what does it become after rotation?
ROTATION_MAPS = {
    0: {'north': 'north', 'south': 'south', 'east': 'east', 'west': 'west'},
    90: {'north': 'east', 'east': 'south', 'south': 'west', 'west': 'north'},
    180: {'north': 'south', 'south': 'north', 'east': 'west', 'west': 'east'},
    270: {'north': 'west', 'west': 'south', 'south': 'east', 'east': 'north'},
}


def load_stage_configs() -> dict:
    """Load unified stage configs and return a dict of stage_id -> list of portal directions."""
    if not os.path.exists(STAGE_CONFIG_PATH):
        print(f'ERROR: Stage config not found: {STAGE_CONFIG_PATH}', file=sys.stderr)
        sys.exit(1)
    with open(STAGE_CONFIG_PATH) as f:
        configs = json.load(f)
    return configs


def get_stage_portal_directions(stage_configs: dict, stage_id: str) -> list[str] | None:
    """Get the list of portal directions for a stage from the config.

    Returns None if the stage is not found.
    """
    config = stage_configs.get(stage_id)
    if config is None:
        return None
    portals = config.get('portals', [])
    return [p['direction'] for p in portals if 'direction' in p]


def rotate_directions(base_directions: list[str], rotation: int) -> set[str]:
    """Apply rotation to a list of base directions, returning the rotated set."""
    rot_map = ROTATION_MAPS.get(rotation)
    if rot_map is None:
        return set()  # Will be caught as an error elsewhere
    return {rot_map[d] for d in base_directions if d in rot_map}


def validate_quest(filepath: str, stage_configs: dict) -> list[str]:
    """Validate a single field quest JSON file. Returns a list of error strings."""
    errors = []
    quest_id = os.path.basename(filepath)

    with open(filepath) as f:
        quest = json.load(f)

    # 1. Required top-level fields
    missing = REQUIRED_QUEST_FIELDS - set(quest.keys())
    if missing:
        errors.append(f'[{quest_id}] missing top-level fields: {sorted(missing)}')

    if quest.get('version') != 1:
        errors.append(f'[{quest_id}] version must be 1, got {quest.get("version")}')

    qid = quest.get('id', quest_id)

    for si, section in enumerate(quest.get('sections', [])):
        sec_label = f'[{qid}] section[{si}]'

        # 2. Required section fields
        sec_missing = REQUIRED_SECTION_FIELDS - set(section.keys())
        if sec_missing:
            errors.append(f'{sec_label}: missing fields: {sorted(sec_missing)}')

        cells = section.get('cells', [])
        cell_by_pos: dict[str, dict] = {}
        for cell in cells:
            pos = cell.get('pos', '?')
            if pos in cell_by_pos:
                errors.append(f'{sec_label} cell [{pos}]: duplicate cell position')
            cell_by_pos[pos] = cell

        cell_positions = set(cell_by_pos.keys())

        # Validate start_pos/end_pos reference existing cells
        start = section.get('start_pos', '')
        end = section.get('end_pos', '')
        if start and start not in cell_positions:
            errors.append(f'{sec_label}: start_pos "{start}" not in cells')
        if end and end not in cell_positions:
            errors.append(f'{sec_label}: end_pos "{end}" not in cells')

        for cell in cells:
            pos = cell.get('pos', '?')
            cell_label = f'{sec_label} cell [{pos}]'

            # 3. Required cell fields
            cell_missing = REQUIRED_CELL_FIELDS - set(cell.keys())
            if cell_missing:
                errors.append(f'{cell_label}: missing fields: {sorted(cell_missing)}')

            # Portal format: all values must be strings (v1)
            portals = cell.get('portals', {})
            for dir_key, value in portals.items():
                if not isinstance(value, str):
                    errors.append(
                        f'{cell_label}: portal "{dir_key}" must be a string (v1 format), '
                        f'got {type(value).__name__}'
                    )

            connections = cell.get('connections', {})

            # 5. All connection targets must exist as cells in the same section
            for dir_key, target_pos in connections.items():
                if target_pos not in cell_positions:
                    errors.append(
                        f'{cell_label}: connection "{dir_key}" -> "{target_pos}" '
                        f'target not found in section cells'
                    )

            # 4. Bidirectional connection check
            for dir_key, target_pos in connections.items():
                if target_pos not in cell_by_pos:
                    continue  # Already reported as missing above
                target_cell = cell_by_pos[target_pos]
                target_connections = target_cell.get('connections', {})
                reverse_dir = OPPOSITE_DIR.get(dir_key)
                if reverse_dir is None:
                    errors.append(
                        f'{cell_label}: connection has unknown direction "{dir_key}"'
                    )
                    continue
                if reverse_dir not in target_connections:
                    errors.append(
                        f'{cell_label}: connection "{dir_key}" -> "{target_pos}", '
                        f'but cell [{target_pos}] has no "{reverse_dir}" connection back'
                    )
                elif target_connections[reverse_dir] != pos:
                    errors.append(
                        f'{cell_label}: connection "{dir_key}" -> "{target_pos}", '
                        f'but cell [{target_pos}] "{reverse_dir}" connects to '
                        f'"{target_connections[reverse_dir]}" instead of "{pos}"'
                    )

            # 6. Stage portal directions (after rotation) must match cell connections/portals
            stage_id = cell.get('stage_id', '')
            rotation = cell.get('rotation', 0)

            if rotation not in ROTATION_MAPS:
                errors.append(
                    f'{cell_label}: invalid rotation {rotation}, '
                    f'must be one of {sorted(ROTATION_MAPS.keys())}'
                )
                continue

            base_directions = get_stage_portal_directions(stage_configs, stage_id)
            if base_directions is None:
                errors.append(
                    f'{cell_label}: stage_id "{stage_id}" not found in '
                    f'unified-stage-configs.json'
                )
                continue

            rotated_directions = rotate_directions(base_directions, rotation)

            # The cell's connection directions (excluding "default") should match
            # the rotated portal directions from the stage config.
            # warp_edge uses a portal direction that is NOT a connection to another cell.
            cell_connection_dirs = set(connections.keys())
            cell_portal_dirs = {d for d in portals.keys() if d != 'default'}
            warp_edge = cell.get('warp_edge', '')
            warp_edge_dirs = {warp_edge} if warp_edge else set()

            section_type = section.get('type', 'grid')

            # For grid sections, connections should be a subset of portals (extra portals
            # may serve as warp_edge or section entry/exit points)
            if section_type == 'grid':
                missing_portals = cell_connection_dirs - cell_portal_dirs
                if missing_portals:
                    errors.append(
                        f'{cell_label}: connections {sorted(missing_portals)} '
                        f'have no matching portal entry'
                    )

            # For transition/boss sections, portals serve as cross-section entry/exit
            # points or the stage may have no portals (boss arenas). Skip strict
            # portal-to-connection matching for these section types.
            # For grid start cells, an extra portal may serve as section entry point.
            if section_type == 'grid':
                expected_dirs = cell_connection_dirs | warp_edge_dirs
                is_start = cell.get('is_start', False)
                if is_start and rotated_directions - expected_dirs:
                    # Start cell may have an extra portal for section entry — allow it
                    extra = rotated_directions - expected_dirs
                    if len(extra) <= 1:
                        expected_dirs = expected_dirs | extra
                if rotated_directions != expected_dirs:
                    errors.append(
                        f'{cell_label}: stage "{stage_id}" at rotation {rotation} has '
                        f'portal directions {sorted(rotated_directions)}, but cell declares '
                        f'connections{" + warp_edge" if warp_edge_dirs else ""} '
                        f'{sorted(expected_dirs)}'
                    )

    return errors


def main():
    stage_configs = load_stage_configs()

    manifest_path = os.path.join(FIELD_QUEST_DIR, 'manifest.json')
    if not os.path.exists(manifest_path):
        print('WARNING: manifest.json not found, scanning directory', file=sys.stderr)
        quest_files = [
            f for f in os.listdir(FIELD_QUEST_DIR)
            if f.endswith('.json') and f != 'manifest.json'
        ]
    else:
        with open(manifest_path) as f:
            quest_files = json.load(f)

    all_errors: list[str] = []

    for raw_name in sorted(quest_files):
        fname = raw_name if raw_name.endswith('.json') else raw_name + '.json'
        fpath = os.path.join(FIELD_QUEST_DIR, fname)
        if not os.path.exists(fpath):
            all_errors.append(f'{fname}: file not found (listed in manifest)')
            continue
        quest_errors = validate_quest(fpath, stage_configs)
        if quest_errors:
            all_errors.extend(quest_errors)
        else:
            print(f'  OK: {fname}')

    if all_errors:
        print(f'\n{len(all_errors)} error(s):', file=sys.stderr)
        for e in all_errors:
            print(f'  ERROR: {e}', file=sys.stderr)
        sys.exit(1)
    else:
        print(f'\nAll {len(quest_files)} field quest file(s) valid.')


if __name__ == '__main__':
    main()
