#!/usr/bin/env python3
"""Preview scorecard label definitions; use --apply to write to GitHub.

Additive only: never removes labels, closes issues, or changes milestones.
Issue membership is managed directly with labels in GitHub.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPO = 'kion-dgl/psz-godot'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    areas = json.loads((ROOT / 'spec/src/data/fidelity-grades.json').read_text())['areas']
    labels = [area['label'] for area in areas]
    if len(set(labels)) != len(labels):
        parser.error('Scorecard labels must be unique')

    def run(command):
        print(' '.join(command), flush=True)
        if args.apply:
            subprocess.run(command, check=True)

    for area in areas:
        run(['gh', 'label', 'create', area['label'], '--repo', REPO,
             '--color', '5375B9', '--description',
             f"Scorecard area: {area['area']}. Concrete work that improves this score.", '--force'])


if __name__ == '__main__':
    main()
