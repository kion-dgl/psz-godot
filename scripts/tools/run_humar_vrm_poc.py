#!/usr/bin/env python3
"""Launch playable-character VRM comparison or the game using isolated save data.

python3 scripts/tools/run_humar_vrm_poc.py [--headless] [--game] [--screenshot PATH]
Generate all VRMs with scripts/tools/vrm/convert_players.py first.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot') or str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--gallery', action='store_true')
    parser.add_argument('--all', action='store_true', help='Run all-character animation checks')
    parser.add_argument('--class-id', default='humar', choices=['humar', 'humarl', 'ramar', 'ramarl', 'fomar', 'fomarl', 'hunewm', 'hunewearl', 'fonewm', 'fonewearl', 'hucast', 'hucaseal', 'racast', 'racaseal'])
    parser.add_argument('--variation', type=int, choices=range(4), default=0)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--portable', action='store_true', help='Show the unmodified portable VRM T-pose')
    parser.add_argument('--game', action='store_true')
    parser.add_argument('--screenshot', type=Path)
    args = parser.parse_args()
    if not (ROOT / 'assets/player/pc_000/pc_000.vrm').exists():
        parser.error('Generate assets/player/pc_000/pc_000.vrm with convert_players.py first.')
    with tempfile.TemporaryDirectory(prefix='psz-humar-vrm-') as temporary:
        project = Path(temporary)
        for item in ROOT.iterdir():
            if item.name not in ('.git', 'project.godot'):
                (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
        settings = (ROOT / 'project.godot').read_text().replace('config/name="PSZ Godot"', 'config/name="PSZ HUmar VRM PoC"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="psz-humar-vrm-poc"')
        (project / 'project.godot').write_text(settings)
        env = dict(os.environ, PSZ_VRM_CLASS=args.class_id, PSZ_VRM_VARIATION=str(args.variation))
        if args.portable:
            env['PSZ_VRM_PORTABLE'] = '1'
        if args.screenshot:
            env['PSZ_VRM_SCREENSHOT'] = str(args.screenshot.resolve())
        command = [args.godot, '--path', str(project), '--max-fps', '60']
        if args.headless: command += ['--headless', '--quit-after', '3600']
        if not args.game:
            scene = 'vrm/player_vrm_gallery' if args.gallery else ('vrm/player_vrm_probe' if args.all else 'humar_vrm_probe')
            command += ['res://scripts/tools/' + scene + '.tscn']
        return subprocess.call(command, env=env)

if __name__ == '__main__':
    raise SystemExit(main())
