#!/usr/bin/env python3
"""Launch the Ranger aim prototype with a separate save; --check runs live assertions."""
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
    parser.add_argument('--rendered', action='store_true')
    parser.add_argument('--female', action='store_true')
    parser.add_argument('--weapon', choices=['handgun', 'rifle', 'mechgun'], default='handgun')
    parser.add_argument('--scene', default='res://scripts/tools/ranger_aim_probe.tscn', help='Alternate verification scene')
    mac_godot = Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot'
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot') or (str(mac_godot) if mac_godot.exists() else None))
    args = parser.parse_args()
    if not args.godot:
        parser.error('Godot is required; pass --godot /path/to/Godot')
    with tempfile.TemporaryDirectory(prefix='psz-aim-') as temporary:
        project = Path(temporary)
        for item in ROOT.iterdir():
            if item.name not in ('.git', 'project.godot'):
                (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
        settings = (ROOT / 'project.godot').read_text().replace(
            'config/name="PSZ Godot"', 'config/name="PSZ Aim Prototype"')
        (project / 'project.godot').write_text(settings)
        env = dict(os.environ, PSZ_AIM_PROTOTYPE='1', PSZ_AIM_CHECK='1' if args.check else '0',
                   PSZ_AIM_FEMALE='1' if args.female else '0', PSZ_AIM_WEAPON=args.weapon,
                   PSZ_HUMAR_SABER='0')
        command = [args.godot, '--path', str(project), '--max-fps', '60']
        if args.check and not args.rendered:
            command.append('--headless')
        command.append(args.scene)
        if not args.check:
            return subprocess.call(command, env=env)
        try:
            result = subprocess.run(command, env=env, timeout=180, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b''
            print(output.decode(errors='replace') if isinstance(output, bytes) else output)
            print('Ranger check timed out after 180 seconds; rendered checks require a visible window.')
            return 124
        print(result.stdout, end='')
        failed = 'SCRIPT ERROR:' in result.stdout or 'Parse Error:' in result.stdout
        if args.scene.endswith('ranger_aim_probe.tscn'):
            failed |= '[ranger-aim] DONE ok' not in result.stdout
        return result.returncode or int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
