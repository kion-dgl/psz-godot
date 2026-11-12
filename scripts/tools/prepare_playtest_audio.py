#!/usr/bin/env python3
"""Copy labelled PSO feedback cues into the asset-pack tree (no publication)."""
from pathlib import Path
import shutil
import argparse

ROOT = Path(__file__).resolve().parents[2]
CUES = (
    "common/common_132.wav",  # Owner technique/box cue
    "common/common_133.wav",  # Owner technique/box cue
    "common/common_141.wav",  # Owner technique/box cue
    "common/common_143.wav",  # Owner technique/box cue
    "common/common_131.wav",  # Owner technique/box cue
    "common/common_160.wav",  # Owner technique/box cue

    "common/common_130.wav",  # Razonde: SE_W27_HEY
    "common/common_126.wav",  # Rabarta: SE_EP4ITEM_S52
    "common/common_122.wav",  # Rafoie cast: SE_EP4ITEM_WH02
    "common/common_123.wav",  # Rafoie explosion: SE_EP4ITEM_WH11
    "common/common_011.wav",  # Owner-auditioned technique/status cue
    "common/common_012.wav",  # Owner-auditioned technique/status cue
    "common/common_013.wav",  # Owner-auditioned technique/status cue
    "common/common_120.wav",  # Owner-auditioned technique/status cue
    "common/common_124.wav",  # Owner-auditioned technique/status cue
    "common/common_128.wav",  # Owner-auditioned technique/status cue
    "common/common_134.wav",  # Owner-auditioned technique/status cue
    "common/common_135.wav",  # Owner-auditioned technique/status cue
    "common/common_140.wav",  # Owner-auditioned technique/status cue
    "common/common_142.wav",  # Owner-auditioned technique/status cue
    'common/common_186.wav',  # SE_SYS_WINCLOSE
    'forest/forest_007.wav',  # SE_MOJA_DEAD
    'cave/cave_015.wav',     # SE_POIZ_DEAD
    'machine/machine_022.wav',  # SE_SINO_DEAD
    'ancient/ancient_022.wav',  # SE_CHSR_DEAD
)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'web/public/assets/psobb_sfx')
    args = parser.parse_args()
    for cue in CUES:
        source = args.source / cue
        target = ROOT / 'assets/sfx' / cue
        if not source.is_file():
            raise SystemExit(f'Missing labelled source cue: {source}')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        print(target.relative_to(ROOT))
