#!/usr/bin/env python3
"""Launch #790 in an isolated save: --check for automated live checks, --group for three enemies."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--group', action='store_true')
    parser.add_argument('--weapon', choices=['saber', 'sword', 'daggers', 'claw', 'double-saber', 'spear'], default='saber')
    parser.add_argument('--gender', choices=['male', 'female'], default='male', help='HUmar or HUmarl saber reference')
    parser.add_argument('--rendered', action='store_true', help='Render automated checks for visual capture')
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot'))
    args = parser.parse_args()
    if not args.godot:
        parser.error('Godot is required')
    library = ('pso_female_sword.glb' if args.gender == 'female' else 'pso_male_sword.glb') if args.weapon == 'sword' else 'pso_female_saber.glb' if args.gender == 'female' else 'pso_humar_saber.glb'
    bake_flag = ('--female-sword' if args.gender == 'female' else '--male-sword') if args.weapon == 'sword' else '--female-saber' if args.gender == 'female' else '--humar-saber'
    if args.weapon == 'daggers':
        library = 'pso_female_dagger.glb' if args.gender == 'female' else 'pso_male_dagger.glb'
        bake_flag = '--female-daggers' if args.gender == 'female' else '--male-daggers'
    if args.weapon == 'claw':
        library = 'pso_female_claw.glb' if args.gender == 'female' else 'pso_male_claw.glb'
        bake_flag = '--female-claw' if args.gender == 'female' else '--male-claw'
    if args.weapon == 'double-saber':
        library = 'pso_female_double_saber.glb' if args.gender == 'female' else 'pso_male_double_saber.glb'
        bake_flag = '--female-double-saber' if args.gender == 'female' else '--male-double-saber'
    if args.weapon == 'spear':
        if args.gender == 'female':
            parser.error('Female spear is not adapted yet')
        library, bake_flag = 'pso_male_spear.glb', '--male-spear'
    if not (ROOT / 'assets/player/animations' / library).exists():
        parser.error('Bake first: cd web && node scripts/bake-retarget.mjs ' + bake_flag)
    with tempfile.TemporaryDirectory(prefix='psz-saber-') as temporary:
        project = Path(temporary)
        for item in ROOT.iterdir():
            if item.name not in ('.git', 'project.godot'):
                (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
        settings = (ROOT / 'project.godot').read_text().replace(
            'config/name="PSZ Godot"',
            'config/name="PSZ Saber Prototype"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="psz-saber-prototype"')
        (project / 'project.godot').write_text(settings)
        env = dict(os.environ, PSZ_HUMAR_SABER='1', PSZ_SABER_GENDER=args.gender, PSZ_MELEE_WEAPON=args.weapon, PSZ_SABER_CHECK='1' if args.check else '0',
                   PSZ_SABER_GROUP='1' if args.group else '0', XDG_DATA_HOME=str(project / 'save'))
        env["PSZ_DAGGER_GRIP_PATH"] = str(ROOT / ".godot" / ("dagger-female-left-grip.json" if args.gender == "female" else "dagger-left-grip.json"))
        env["PSZ_DOUBLE_SABER_GRIP_PATH"] = str(ROOT / ".godot" / ("double-saber-female-grip.json" if args.gender == "female" else "double-saber-grip.json"))
        env["PSZ_SPEAR_GRIP_PATH"] = str(ROOT / ".godot" / "spear-male-grips.json")
        command = [args.godot, '--path', str(project), '--max-fps', '60']
        if args.check and not args.rendered:
            command += ['--headless']
        command += ['res://scripts/tools/humar_saber_probe.tscn']
        if args.check:
            result = subprocess.run(command, env=env, timeout=180, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end='')
            return result.returncode or int('SCRIPT ERROR:' in result.stdout or '[humar-saber] DONE ok' not in result.stdout)
        return subprocess.call(command, env=env)


if __name__ == '__main__':
    raise SystemExit(main())
