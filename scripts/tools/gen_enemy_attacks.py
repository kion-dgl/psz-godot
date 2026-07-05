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
        'standoff_range': 6.0,  # kiter archetypes (quad_machine); flyers reuse as orbit radius
        'hover_height': 0.0,  # flyer archetypes: airborne height while engaged
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

# model_id → behavior archetype (spec /mechanics/enemy-attacks "Rig groups
# & behavior archetypes"; derived from the enemy_anim_groups.py scan — run
# it to audit when rigs change). Every roster model MUST be classified; the
# data test fails on 'unclassified' so new rigs force a decision here.
MODEL_ARCHETYPES = {
    'simple_melee': [
        'bat', 'bat_blue', 'circle', 'circle_black', 'vulture', 'lizard',
        'rabbit', 'rabbit_rare', 'lion', 'lion_rare',
    ],
    'quadruped': ['wolf', 'hyena', 'hyena_rare', 'deer', 'tiger'],
    'quad_machine': ['quad', 'quad_rare'],
    'bruiser': ['booma', 'jigobooma'],
    'bigrig_combo': ['gorilla', 'gorilla_female', 'gorilla_rare'],
    'flyer_combo': ['roc', 'roc_rare'],
    'two_attack': ['seal', 'seal_rare'],
    'stance_riser': ['snake', 'snake_rare'],
    'transformer': [
        'armadillo', 'armadillo_rare', 'shrimp', 'shrimp_rare',
        'orangutan', 'orangutan_rare',
    ],
    'trickster': ['frog', 'frog_bomb', 'frog_rare', 'rappy', 'rappy_blue', 'rappy_red'],
    'machine_soldier': [
        'leg', 'leg_black', 'lower', 'lower_black',
        'swordman', 'swordman_b', 'swordman_rare', 'swordman_rare_b',
        'board', 'board_blue', 'board_green',
        'tank', 'tank_rare', 'shooter', 'shooter_leader',
    ],
    'mother_caster': ['mother', 'mother_sword', 'mother_gun', 'mother_tech'],
    'unique': ['mole', 'shinowa', 'poison_lily'],
    'boss': ['boss_dragon', 'boss_octopus', 'boss_mother', 'boss_darkfalz', 'boss_robot'],
}
ARCHETYPE_BY_MODEL = {m: a for a, ms in MODEL_ARCHETYPES.items() for m in ms}


def parse_tres_stats(path: str) -> tuple[str, str, dict] | None:
    """Extract (id, model_id, stats) from a .tres; None if it has no id field."""
    with open(path, 'r') as f:
        text = f.read()

    def get_field(name: str) -> str | None:
        m = re.search(rf'^{name}\s*=\s*(.+)$', text, re.MULTILINE)
        return m.group(1).strip() if m else None

    raw_id = get_field('id')
    if not raw_id:
        return None
    enemy_id = raw_id.strip('"')
    model_id = (get_field('model_id') or '').strip('"')

    stats = {}
    for field, default in TRES_STAT_DEFAULTS.items():
        raw = get_field(field)
        if raw is None:
            stats[field] = default
        elif isinstance(default, int):
            stats[field] = int(float(raw))
        else:
            stats[field] = float(raw)
    return enemy_id, model_id, stats


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
        enemy_id, model_id, stats = parsed
        # Always re-derived from model_id — classification lives in
        # MODEL_ARCHETYPES, not in hand edits of the output file.
        archetype = ARCHETYPE_BY_MODEL.get(model_id, 'unclassified')
        prev = existing.get('enemies', {}).get(enemy_id)
        if prev:
            entry = {
                'archetype': archetype,
                'stats': stats,  # always refreshed from .tres (authoritative)
                'fsm': prev.get('fsm', {}),
                'attacks': prev.get('attacks') or [default_attack(stats['attack_range'])],
            }
            if prev.get('clip_notes'):
                entry['clip_notes'] = prev['clip_notes']
        else:
            entry = {
                'archetype': archetype,
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
