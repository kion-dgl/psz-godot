#!/usr/bin/env python3
"""Run #684's unit and real-rig difficulty matrix in a disposable save project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from verify_melee_contact import ROOT, prepare_project

MODES = {'hit', 'dodge', 'sidestep', 'retreat', 'wall', 'thin_wall', 'edge',
         'hurt', 'hurt_travel', 'lost', 'death_st', 'death_lp'}
ENEMIES = ('booma_origin', 'gigobooma_origin')
TIERS = ('normal', 'hard', 'super-hard')


def run(godot, project, output, name, env, unit=False):
    log = output / (name + '.log')
    scene = 'test_runner' if unit else 'coliseum_probe'
    command = [godot, '--headless', '--fixed-fps', '60', '--path', str(project),
               f'res://scripts/tools/{scene}.tscn']
    with log.open('w') as stream:
        try:
            code = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=180).returncode
        except subprocess.TimeoutExpired:
            code = -1
    text = log.read_text(errors='replace')
    rows = [json.loads(line.split('RESULT ', 1)[1]) for line in text.splitlines()
            if line.startswith('[booma-live] RESULT ')]
    rigs = [json.loads(line.split('RIG ', 1)[1]) for line in text.splitlines()
            if line.startswith('[booma-live] RIG ')]
    errors = 'SCRIPT ERROR' in text or 'Parse Error' in text or 'Warning treated as error' in text
    if unit:
        match = re.search(r'RESULTS: (\d+) passed, (\d+) failed', text)
        complete = bool(match and int(match[2]) == 0)
    else:
        complete = (len(rigs) == 1 and rigs[0]['complete'] and len(rows) == len(MODES) and {r['mode'] for r in rows} == MODES
                    and all(r['passed'] for r in rows)
                    and all(r['enemy'] == env['PSZ_COLISEUM_ENEMY'] and
                            r['difficulty'] == env['PSZ_COLISEUM_DIFFICULTY'] for r in rows)
                    and '[coliseum] DONE ok' in text and 'PASS=false' not in text)
    return {'passed': code == 0 and complete and not errors, 'exit_code': code,
            'script_errors': errors, 'log': str(log), 'cases': rows, 'rigs': rigs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--calibrate', action='store_true')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'issue': 684, 'seed': 684, 'decision_seed': 7007, 'fixed_fps': 60,
              'scope': 'Godot contract; original-game parity and visual feel remain unverified',
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'godot_version': subprocess.check_output([args.godot, '--version'], text=True).strip(),
              'input_sha256': {}, 'checks': {}}
    for name in ('scripts/3d/enemies/enemy_base.gd', 'scripts/tools/booma_validation_tests.gd',
                 'scripts/tools/coliseum_booma_check.gd', 'scripts/tools/enemy_decision_scenarios.gd',
                 'scripts/tools/coliseum_entrance_check.gd', 'scripts/tools/coliseum_probe.gd',
                 'scripts/tools/test_runner.gd', 'scripts/tools/verify_booma.py',
                 'data/combat_scenarios.json', 'data/enemy_attacks.json',
                 'data/re_reference/booma_evidence.json'):
        report['input_sha256'][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    env = {k: v for k, v in os.environ.items() if not k.startswith('PSZ_')}
    with tempfile.TemporaryDirectory(prefix='psz-booma-') as directory:
        project = Path(directory)
        prepare_project(project)
        report['checks']['unit'] = run(args.godot, project, args.output, 'unit', env, True)
        print('unit:', report['checks']['unit']['passed'], flush=True)
        for enemy in ENEMIES:
            for tier in TIERS:
                name = enemy + '-' + tier
                env.update(PSZ_COLISEUM_ENEMY=enemy, PSZ_COLISEUM_DIFFICULTY=tier,
                           PSZ_BOOMA_CHECK='1', PSZ_COMBAT_SCENARIOS='1')
                report['checks'][name] = run(args.godot, project, args.output, name, env)
                print(name + ':', report['checks'][name]['passed'], flush=True)
        if args.calibrate:
            source = project / 'scripts/3d/enemies/enemy_base.gd'
            original = source.read_text()
            mutant = original.replace('var end_charge := _charge_path_blocked(_attack_facing * speed * delta)',
                                      'var end_charge := false').replace(' and _charge_contact_clear():', ':')
            if mutant == original:
                raise RuntimeError('Mutation did not apply')
            source.write_text(mutant)
            env.update(PSZ_COLISEUM_ENEMY='booma_origin', PSZ_COLISEUM_DIFFICULTY='normal')
            result = run(args.godot, project, args.output, 'unsafe-charge-mutant', env)
            reproduced = {r['mode'] for r in result['cases'] if not r['passed'] and r.get('hits', 0) > 0}
            result['rejected_as_expected'] = (not result['passed'] and not result['script_errors']
                                               and result['exit_code'] != -1
                                               and {'thin_wall', 'edge'} <= reproduced)
            report['calibration'] = result
            print('calibration:', result['rejected_as_expected'], flush=True)
    report['passed'] = all(r['passed'] for r in report['checks'].values()) and report.get('calibration', {}).get('rejected_as_expected', True)
    (args.output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
