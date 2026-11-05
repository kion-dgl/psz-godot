#!/usr/bin/env python3
"""Convert all 14 playable classes x four variants. Never uploads assets."""
import json
from convert_humar import ROOT, convert


def main():
    entries = []
    for class_index in range(14):
        for variation in range(4):
            model = f"pc_{class_index:02}{variation}"
            directory = ROOT / 'assets/player' / model
            _, _, report = convert(directory / f'{model}.vrm',
                                   directory / f'{model}_000.glb',
                                   directory / 'textures' / f'{model}_000.png')
            report['output'] = f'assets/player/{model}/{model}.vrm'
            entries.append(report)
    destination = ROOT / 'assets/player/vrm_conversion_report.json'
    destination.write_text(json.dumps({'profile': 'pszLegacyRig/1', 'models': entries}, indent=2) + '\n')
    print(f'Converted {len(entries)} playable models; report: {destination}')


if __name__ == '__main__':
    main()
