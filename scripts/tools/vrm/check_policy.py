#!/usr/bin/env python3
"""Asset-free CI guard for the VRM character policy; --assets checks local coverage."""
import argparse
import json
import os
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[3]


def source_files(directory):
    for parent, directories, files in os.walk(directory):
        directories[:] = [name for name in directories if name not in ('node_modules', '__pycache__', '.git')]
        for name in files:
            yield Path(parent) / name


def check(assets=False):
    errors = []
    legacy = set(json.loads((Path(__file__).with_name('legacy_npc_glbs.json')).read_text())['paths'])
    for directory in ('scripts', 'scenes', 'data'):
        for path in source_files(ROOT / directory):
            if path.suffix not in ('.gd', '.tscn', '.tres', '.json') or 'scripts/tools' in str(path):
                continue
            for ref in re.findall(r'res://assets/(?:player|npcs)/[^"\s]+\.glb', path.read_text()):
                if '/player/animations/' not in ref and ref not in legacy:
                    errors.append(f'{path.relative_to(ROOT)}: humanoid model must be VRM: {ref}')
    config = (ROOT / 'scripts/autoloads/player_config.gd').read_text()
    if '"res://assets/player/%s/%s.vrm"' not in config:
        errors.append('PlayerConfig must resolve VRM avatars')
    presets = (ROOT / 'export_presets.cfg').read_text().split('[preset.')
    pack = next(section for section in presets if 'name="Asset Pack"' in section)
    if 'assets/player/*.vrm' not in pack:
        errors.append('Asset Pack must explicitly include raw VRM files')
    if assets:
        for class_index in range(14):
            for variant in range(4):
                model = f'pc_{class_index:02}{variant}'
                path = ROOT / f'assets/player/{model}/{model}.vrm'
                if not path.is_file():
                    errors.append(f'Missing playable avatar: {path.relative_to(ROOT)}')
                    continue
                data = path.read_bytes()
                try:
                    size = struct.unpack_from('<I', data, 12)[0]
                    doc = json.loads(data[20:20 + size])
                    assert doc['extensions']['VRMC_vrm']['specVersion'] == '1.0'
                    assert doc['extras']['pszLegacyRig']['model'] == model
                    assert doc['extras']['pszLegacyRig']['version'] == 1
                except (ValueError, KeyError, AssertionError, struct.error) as error:
                    errors.append(f'{path}: invalid avatar profile ({error})')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', action='store_true')
    errors = check(parser.parse_args().assets)
    for error in errors:
        print(error)
    print(f'VRM character policy: {len(errors)} errors')
    raise SystemExit(bool(errors))
