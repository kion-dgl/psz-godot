#!/usr/bin/env python3
"""Copy labelled PSO feedback cues into the asset-pack tree (no publication)."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
CUES = (
    'common/common_146.wav',  # SE_TECH_RESTA
    'forest/forest_007.wav',  # SE_MOJA_DEAD
    'cave/cave_015.wav',     # SE_POIZ_DEAD
    'machine/machine_022.wav',  # SE_SINO_DEAD
    'ancient/ancient_022.wav',  # SE_CHSR_DEAD
)

if __name__ == '__main__':
    for cue in CUES:
        source = ROOT / 'web/public/assets/psobb_sfx' / cue
        target = ROOT / 'assets/sfx' / cue
        if not source.is_file():
            raise SystemExit(f'Missing labelled source cue: {source}')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        print(target.relative_to(ROOT))
