#!/usr/bin/env python3
"""Re-derive systems fixtures from a local psz-re checkout (read-only).

Run: python3 scripts/tools/check_systems_reference.py [path/to/psz-re]
CI uses committed numeric fixtures; this evidence check additionally requires ROM inputs.
"""
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "psz-re"
sys.path.insert(0, str(SOURCE / "tools"))
from zpr import unzpr
import wpnprm

raw = unzpr((SOURCE / "build/fs/player/pb_param_data.rel").read_bytes())
record = raw[0x30:]
charge = json.loads((ROOT / "data/re_reference/photon_blast_charge.json").read_text())
assert hashlib.sha256(raw).hexdigest() == charge["sha256_uncompressed"]
for key, offset, count in [("selector_multipliers", 0, 4), ("six_thresholds", 8, 6),
                           ("six_awards", 0x14, 6), ("ten_thresholds", 0x20, 10),
                           ("ten_awards", 0x34, 10)]:
    assert charge[key] == list(struct.unpack_from(f"<{count}H", record, offset)), key
assert charge["charge_multiplier"] == record[0x81]
source = json.loads((SOURCE / "data/enemy_stat_table.json").read_text())["enemies"]
export = json.loads((ROOT / "data/re_reference/enemy_combat_stats.json").read_text())["enemies"]
for enemy_id, rows in export.items():
    resource = (ROOT / f"data/enemies/{enemy_id}.tres").read_text()
    model = re.search(r'model_id = "([^"]+)"', resource)[1]
    assert rows == source[f"enemy/{model}.narc"]["rows"], enemy_id
for weapon_id, index in [("saber", 0), ("handgun", 152)]:
    row = wpnprm.decode(index)
    resource = (ROOT / f"data/weapons/{weapon_id}.tres").read_text()
    for field, original in [("attack_base", "atp"), ("attack_max", "attack_max"),
                            ("max_grind", "max_grind"), ("accuracy_base", "ata")]:
        value = int(re.search(rf'^{field} = (\d+)', resource, re.M)[1])
        assert value == row[original], (weapon_id, field)
assert all(row["agree"] == row["weapons"] for row in wpnprm.wiki_agreement().values())
print(f"Verified PB parameter bytes, {len(export)} enemy row mappings, two starter baselines and 16 original grind anchors.")
