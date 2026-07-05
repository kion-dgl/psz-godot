#!/usr/bin/env python3
"""Seed / refresh data/enemy_attacks.json from data/enemies/*.tres.

Usage:
    python3 scripts/tools/gen_enemy_attacks.py

The output is the per-enemy attack-behavior config consumed by the
#/enemy-room web tool and (next PR) the Godot runtime — see
spec /mechanics/enemy-attacks. The .tres files remain authoritative for
the base stats mirrored into each entry's "stats" block.

Merge-preserving: hand-tuned "attacks" and "fsm" blocks in an existing
enemy_attacks.json are kept verbatim; only missing enemies are added and
each entry's "stats" block is refreshed from its .tres. Output key order
is sorted, so re-running on an unchanged tree is diff-clean.
"""

import json
import os
import re

ENEMIES_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'enemies')
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'enemy_attacks.json')

# Defaults mirror enemy_base.gd constants (FSM) and the spec's default
# attack shape (/mechanics/enemy-attacks). Keep in sync with
# web/src/enemy-room/types.ts DEFAULTS.
DEFAULTS = {
    'fsm': {
        'walk_speed_mult': 0.5,
        'charge_range_mult': 2.0,
        'charge_speed_mult': 1.5,
        'loaf_duration_min': 2.5,
        'loaf_duration_max': 4.0,
        'hurt_duration': 0.3,
        'attack_fallback_duration': 0.8,
    },
    'attack': {
        'windup_frac': 0.35,
        'damage_end_frac': 0.6,
        'hit_half_angle_deg': 45.0,
        'hit_reach': 2.0,
        'damage_mult': 1.0,
        'weight': 1.0,
        'min_range': 0.0,
        'max_range': 999.0,
    },
}

# enemy_data.gd @export defaults — .tres files omit fields left at the
# script default, so absent fields must fall back to these.
TRES_STAT_DEFAULTS = {
    'move_speed': 3.0,
    'attack_range': 2.0,
    'attack_cooldown': 1.5,
    'detection_range': 15.0,
    'attack_base': 10,
}


def parse_tres_stats(path: str) -> tuple[str, dict] | None:
    """Extract (id, stats) from a .tres; None if it has no id field."""
    with open(path, 'r') as f:
        text = f.read()

    def get_field(name: str) -> str | None:
        m = re.search(rf'^{name}\s*=\s*(.+)$', text, re.MULTILINE)
        return m.group(1).strip() if m else None

    raw_id = get_field('id')
    if not raw_id:
        return None
    enemy_id = raw_id.strip('"')

    stats = {}
    for field, default in TRES_STAT_DEFAULTS.items():
        raw = get_field(field)
        if raw is None:
            stats[field] = default
        elif isinstance(default, int):
            stats[field] = int(float(raw))
        else:
            stats[field] = float(raw)
    return enemy_id, stats


def default_attack(attack_range: float) -> dict:
    atk = dict(DEFAULTS['attack'])
    atk['max_range'] = attack_range
    return {'id': 'basic', 'clip': 'atk', **atk}


def main() -> None:
    existing = {'enemies': {}}
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'r') as f:
            existing = json.load(f)

    enemies = {}
    count_new = 0
    for fname in sorted(os.listdir(ENEMIES_DIR)):
        if not fname.endswith('.tres'):
            continue
        parsed = parse_tres_stats(os.path.join(ENEMIES_DIR, fname))
        if not parsed:
            continue
        enemy_id, stats = parsed
        prev = existing.get('enemies', {}).get(enemy_id)
        if prev:
            entry = {
                'stats': stats,  # always refreshed from .tres (authoritative)
                'fsm': prev.get('fsm', {}),
                'attacks': prev.get('attacks') or [default_attack(stats['attack_range'])],
            }
        else:
            entry = {
                'stats': stats,
                'fsm': {},
                'attacks': [default_attack(stats['attack_range'])],
            }
            count_new += 1
        enemies[enemy_id] = entry

    out = {
        'schema_version': 1,
        'defaults': DEFAULTS,
        'enemies': {k: enemies[k] for k in sorted(enemies)},
    }
    with open(OUTPUT_PATH, 'w') as f:
        json.dump(out, f, indent=2)
        f.write('\n')

    print(f'Wrote {len(enemies)} enemies ({count_new} new) to {OUTPUT_PATH}')


if __name__ == '__main__':
    main()
