#!/usr/bin/env python3
"""Verify individual projectile families with imported rigs and isolated saves."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from verify_melee_contact import ROOT, prepare_project

ENEMIES = ('batt', 'bullbatt', 'korse', 'akorse', 'finjer_r', 'finjer_b', 'finjer_g',
           'phobos', 'phobos_dyna', 'blade_mother', 'shot_mother', 'force_mother',
           'mother_trinity', 'hypao', 'vespao', 'arkzein', 'arkzein_r', 'zaphobos', 'zaphobos_dyna')
MODES = {'hit', 'dodge', 'wall', 'muzzle_wall', 'sidestep', 'hurt', 'death', 'lost', 'owner_death', 'aim_lock', 'retreat'}


def run(godot, project, output, name, env, scene='coliseum_probe'):
    log = output / (name + '.log')
    with log.open('w') as stream:
        try:
            code = subprocess.run([godot, '--headless', '--fixed-fps', '60', '--path', str(project),
                                   f'res://scripts/tools/{scene}.tscn'], env=env, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=240).returncode
        except subprocess.TimeoutExpired:
            code = -1
    text = log.read_text(errors='replace')
    rows = [json.loads(line.split('RESULT ', 1)[1]) for line in text.splitlines()
            if line.startswith('[projectile-live] RESULT ')]
    errors = any(s in text for s in ('SCRIPT ERROR', 'Parse Error', 'Warning treated as error'))
    if scene == 'test_runner':
        match = re.search(r'RESULTS: (\d+) passed, (\d+) failed', text)
        complete = bool(match and int(match[2]) == 0)
    elif scene == 'combat_fidelity_probe':
        complete = '[combat-fidelity] DONE ok' in text
    else:
        enemy = env['PSZ_COLISEUM_ENEMY']
        entry = json.loads((ROOT / 'data/enemy_attacks.json').read_text())['enemies'][enemy]
        attacks = entry['attacks']
        expected = {(a['id'], m) for a in attacks if a.get('kind') in {'projectile', 'lob'} and not a.get('missile_waves') for m in MODES}
        complete = (len(rows) == len(expected) and {(r['attack'], r['mode']) for r in rows} == expected
                    and all(r['passed'] and r['enemy'] == enemy for r in rows)
                    and '[coliseum] DONE ok' in text and 'PASS=false' not in text
                    and (not entry['fsm'].get('tank_kit') or text.count('[tank-behavior] ') == 8)
                    and (entry['archetype'] != 'boarder' or text.count('[finjer-behavior] ') == 4))
    return {'passed': code == 0 and complete and not errors, 'exit_code': code,
            'script_errors': errors, 'log': str(log), 'cases': rows,
            'decision_cases': text.count('[combat-scenario] '),
            'attack_execution_cases': text.count('[family-execution] '),
            'tank_behavior_cases': text.count('[tank-behavior] '),
            'finjer_behavior_cases': text.count('[finjer-behavior] ')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--enemies', nargs='+', choices=ENEMIES, default=ENEMIES)
    parser.add_argument('--tiers', nargs='+', choices=('normal', 'hard', 'super-hard'), default=['normal'])
    parser.add_argument('--calibrate', action='store_true')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'scope': 'Individual Godot behavior; original-game fidelity and human feel remain open',
              'seed': 7240, 'decision_seed': 7007, 'fixed_fps': 60,
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'godot_version': subprocess.check_output([args.godot, '--version'], text=True).strip(),
              'checks': {}, 'input_sha256': {}}
    for name in ('data/enemies/zaphobos.tres', 'data/enemies/zaphobos_dyna.tres',
                 'assets/enemies/tank_missiles/b_052m.glb', 'assets/enemies/tank_missiles/b_152m.glb',
                 'data/enemy_attacks.json', 'data/combat_scenarios.json',
                 'scripts/3d/enemies/enemy_base.gd', 'scripts/3d/enemies/enemy_projectile.gd',
                 'scripts/3d/enemies/tank_behavior.gd', 'scripts/3d/enemies/tank_missile.gd',
                 'scripts/tools/tank_behavior_check.gd',
                 'scripts/3d/enemies/finjer_behavior.gd', 'scripts/3d/enemies/shooter_behavior.gd',
                 'scripts/tools/finjer_behavior_check.gd',
                 'scripts/3d/enemies/enemy_lob.gd', 'scripts/3d/combat/projectile_sweep.gd',
                 'scripts/3d/combat/ice_technique.gd', 'scripts/tools/coliseum_projectile_check.gd',
                 'scripts/tools/coliseum_family_check.gd', 'scripts/tools/coliseum_runtime_check.gd',
                 'scripts/tools/combat_fidelity_probe.gd', 'scripts/tools/coliseum_probe.gd',
                 'scripts/tools/verify_projectile_batch.py'):
        report['input_sha256'][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    env = {k: v for k, v in os.environ.items() if not k.startswith('PSZ_')}
    with tempfile.TemporaryDirectory(prefix='psz-projectiles-') as directory:
        project = Path(directory)
        prepare_project(project)
        for name, scene in [('unit', 'test_runner'), ('physics', 'combat_fidelity_probe')]:
            report['checks'][name] = run(args.godot, project, args.output, name, env, scene)
            print(name, report['checks'][name]['passed'], flush=True)
        env.update(PSZ_COMBAT_SCENARIOS='1', PSZ_ENEMY_RUNTIME_CHECK='1', PSZ_PROJECTILE_CHECK='1')
        for enemy in args.enemies:
            for tier in args.tiers:
                env.update(PSZ_COLISEUM_ENEMY=enemy, PSZ_COLISEUM_DIFFICULTY=tier)
                name = enemy + '-' + tier
                report['checks'][name] = run(args.godot, project, args.output, name, env)
                print(name, report['checks'][name]['passed'], flush=True)
        if args.calibrate:
            path = project / 'scripts/3d/combat/projectile_sweep.gd'
            original = path.read_text()
            assert original.count('query.collision_mask = 1\n') == 1
            path.write_text(original.replace('query.collision_mask = 1\n', 'query.collision_mask = 0\n'))
            env.update(PSZ_COLISEUM_ENEMY='batt', PSZ_COLISEUM_DIFFICULTY='normal')
            result = run(args.godot, project, args.output, 'walls-disabled', env)
            failed = {r['mode'] for r in result['cases'] if not r['passed'] and r['hits'] > 0}
            result['rejected_as_expected'] = (not result['passed'] and not result['script_errors']
                                               and result['exit_code'] != -1
                                               and {'wall', 'muzzle_wall'} <= failed)
            report['calibration'] = result
            print('calibration', result['rejected_as_expected'], flush=True)
    report['passed'] = (all(r['passed'] for r in report['checks'].values())
                        and report.get('calibration', {}).get('rejected_as_expected', True))
    (args.output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
