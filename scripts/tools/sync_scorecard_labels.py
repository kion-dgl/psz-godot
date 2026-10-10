#!/usr/bin/env python3
"""Preview scorecard labels/initial issue associations; use --apply to write to GitHub.

Additive only: never removes labels, closes issues, or changes milestones.
The mapping is a reviewed initial seed, not an exhaustive assignment policy.
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
    mapping = json.loads((ROOT / '.github/scorecard-issues.json').read_text())
    labels = [area['label'] for area in areas]
    if len(set(labels)) != len(labels) or set(labels) != set(mapping):
        parser.error('Scorecard labels must be unique and match the issue mapping')
    for label, numbers in mapping.items():
        if any(type(number) is not int or number <= 0 for number in numbers):
            parser.error(f'Invalid issue number for {label}')

    def run(command):
        print(' '.join(command), flush=True)
        if args.apply:
            subprocess.run(command, check=True)

    for area in areas:
        run(['gh', 'label', 'create', area['label'], '--repo', REPO,
             '--color', '5375B9', '--description',
             f"Scorecard area: {area['area']}. Concrete work that improves this score.", '--force'])
    assignments = {}
    for label, numbers in mapping.items():
        for number in numbers:
            assignments.setdefault(number, []).append(label)
    for number, issue_labels in sorted(assignments.items()):
        run(['gh', 'issue', 'edit', str(number), '--repo', REPO,
             '--add-label', ','.join(issue_labels)])


if __name__ == '__main__':
    main()
