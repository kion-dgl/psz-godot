#!/usr/bin/env python3
"""Read-only re-derivation of the progression evidence; no invented class mapping."""
import json
from pathlib import Path
import struct
import subprocess
import sys

source = Path(sys.argv[1])
table = json.loads((source / 'data/player_level_table.json').read_text())
raw = (source / 'build/fs/player/player_lv_param.zarc').read_bytes()
assert raw[:4] == b'ZARC'
anchors = 0
for entry in table['classes']:
    index = entry['index']
    offset, size = struct.unpack_from('<II', raw, 0x20 + 64 * index)
    assert size == 2480
    for level in (1, 50, 100):
        row = struct.unpack_from('<7H', raw, offset + 0x18 + level * 24)
        assert list(row) == entry[f'lv{level}'], (index, level)
        anchors += 7
    # NEXT-level cumulative thresholds, not per-kill awards.
    thresholds = [struct.unpack_from('<I', raw, offset + 0x18 + level * 24 + 0x14)[0]
                  for level in range(1, 100)]
    assert thresholds[:2] == [70, 160]
    assert all(a < b for a, b in zip(thresholds, thresholds[1:]))
assert len(table['classes']) == 14
revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
print(f'psz-re {revision}: {anchors} stat anchors across 14 members; 99 monotonic next-level thresholds each.')
print('Class-to-member identities are not inferred. Godot interpolated class curves and authored enemy levels remain remake choices.')
