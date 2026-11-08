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
    parser.add_argument('--no-grip-controls', action='store_true', help='Play with committed grip defaults and no adjustment panel')
    parser.add_argument('--weapon', choices=['saber', 'sword', 'daggers', 'claw', 'double-saber', 'spear', 'slicer', 'gunblade', 'handgun', 'mechgun', 'rifle', 'bazooka'], default='saber')
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
        library = 'pso_female_spear.glb' if args.gender == 'female' else 'pso_male_spear.glb'
        bake_flag = '--female-spear' if args.gender == 'female' else '--male-spear'
    if args.weapon == 'slicer':
        library = 'pso_female_slicer.glb' if args.gender == 'female' else 'pso_male_slicer.glb'
        bake_flag = '--female-slicer' if args.gender == 'female' else '--male-slicer'
        if not (ROOT / 'assets/weapons/wslc01/wslc01/wslc01_3_o/wslc01_3_o.glb').exists():
            parser.error('Fetch projectile asset: sh scripts/tools/fetch_slicer_projectile.sh, then import with Godot')
    if args.weapon == 'bazooka':
        library = 'pso_female_bazooka.glb' if args.gender == 'female' else 'pso_male_bazooka.glb'
        bake_flag = '--female-bazooka' if args.gender == 'female' else '--male-bazooka'
    if args.weapon == 'rifle':
        library, bake_flag = 'pso_' + args.gender + '_rifle.glb', '--' + args.gender + '-rifle'
    if args.weapon == 'mechgun':
        library, bake_flag = 'pso_' + args.gender + '_mechgun.glb', '--' + args.gender + '-mechgun'
    if args.weapon == 'handgun':
        library, bake_flag = 'pso_' + args.gender + '_handgun.glb', '--' + args.gender + '-handgun'
    if args.weapon == 'gunblade':
        library, bake_flag = 'pso_' + args.gender + '_gunblade.glb', '--' + args.gender + '-gunblade'
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
                   PSZ_SABER_GROUP='1' if args.group else '0', PSZ_NO_GRIP_CONTROLS='1' if args.no_grip_controls else '0', XDG_DATA_HOME=str(project / 'save'))
        env["PSZ_DAGGER_GRIP_PATH"] = str(ROOT / ".godot" / ("dagger-female-left-grip.json" if args.gender == "female" else "dagger-left-grip.json"))
        env["PSZ_DOUBLE_SABER_GRIP_PATH"] = str(ROOT / ".godot" / ("double-saber-female-grip.json" if args.gender == "female" else "double-saber-grip.json"))
        env["PSZ_SPEAR_GRIP_PATH"] = str(ROOT / ".godot" / ("spear-female-grips.json" if args.gender == "female" else "spear-male-grips.json"))
        env["PSZ_SLICER_GRIP_PATH"] = str(ROOT / ".godot" / ("slicer-female-grips.json" if args.gender == "female" else "slicer-male-grips.json"))
        env["PSZ_GUNBLADE_GRIP_PATH"] = str(ROOT / ".godot" / ("gunblade-" + args.gender + "-grips.json"))
        env["PSZ_RIFLE_GRIP_PATH"] = str(ROOT / ".godot" / ("rifle-" + args.gender + "-grips.json"))
        env["PSZ_BAZOOKA_GRIP_PATH"] = str(ROOT / ".godot" / ("bazooka-" + args.gender + "-grips.json"))
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
