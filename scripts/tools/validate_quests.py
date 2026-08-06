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

    # Completion-scaled rewards (#190): rewards.scaled.tiers must each carry
    # an int "min" and a non-empty items list of {id, quantity>0}; mins must
    # be unique so the highest-earned-tier pick is unambiguous.
    scaled = quest.get('rewards', {}).get('scaled')
    if scaled is not None:
        tiers = scaled.get('tiers', [])
        if not tiers:
            errors.append(f'{fname}: rewards.scaled has no tiers')
        mins = []
        for ti, tier in enumerate(tiers):
            t_label = f'{fname} rewards.scaled.tiers[{ti}]'
            if not isinstance(tier.get('min'), int):
                errors.append(f'{t_label}: "min" must be an int')
            else:
                mins.append(tier['min'])
            items = tier.get('items', [])
            if not items:
                errors.append(f'{t_label}: no items')
            for item in items:
                if not item.get('id'):
                    errors.append(f'{t_label}: item missing id')
                if not isinstance(item.get('quantity'), int) or item.get('quantity', 0) <= 0:
                    errors.append(f'{t_label}: item quantity must be a positive int')
        if len(mins) != len(set(mins)):
            errors.append(f'{fname}: rewards.scaled tier "min" values must be unique')

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

    # Key-gate routing: every gate needs enough keys pointed AT IT.
    #
    # key_gate.gd opens a gate when the player holds `required_keys` copies of
    # a single key id. Two authoring shapes feed a gate, and a gate is only
    # satisfiable when they supply at least required_keys between them:
    #   * field quests place a pickup cell — `key_for_cell` names the gate and
    #     `key_count` is how many copies that cell holds;
    #   * guild quests drop keys on clear — `key_drop` names the gate, one key
    #     per dropping cell (a gate may also self-drop, e.g. finding_ogi B 3,2).
    #
    # An aggregate keys-vs-gates count is not enough: it balances even when
    # every key is routed to one gate and another gate gets none, which ships a
    # field that cannot be completed (wetlands 2,2 and paru 0,1 both did).
    for si, section in enumerate(quest.get('sections', [])):
        cells = section.get('cells', [])
        supply: dict[str, int] = {}
        for cell in cells:
            target = str(cell.get('key_for_cell', '') or '')
            if target:
                supply[target] = supply.get(target, 0) + max(1, int(cell.get('key_count', 1) or 1))
            drop = str(cell.get('key_drop', '') or '')
            if drop:
                supply[drop] = supply.get(drop, 0) + 1
        for cell in cells:
            if not cell.get('is_key_gate'):
                continue
            pos = str(cell.get('pos', ''))
            need = int(cell.get('required_keys', 0) or 0)
            have = supply.get(pos, 0)
            if have < need:
                errors.append(
                    f'{fname} section[{si}] cell {pos}: key gate needs {need} key(s) '
                    f'but only {have} routed to it (no cell has key_for_cell="{pos}" '
                    f'with enough key_count) — gate would be unopenable'
                )

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
