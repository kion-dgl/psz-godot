#!/usr/bin/env python3
"""Merge authoritative SE_* names from the PSO:BB reverse-engineering TSV
into data/sfx_labels.json.

Source TSV (columns: pac, wav_file, entry_idx, se_id, se_name):
  http://174.138.36.4/logic-findings/se-to-wav-exact.tsv
Browsable rendering:
  http://174.138.36.4/findings/sounds/se-to-wav/

Behavior:
- For every row in the TSV, upsert an entry keyed by wav_file.
- `label` is set to se_name (the authoritative PSO:BB symbol).
- Existing `notes` / `starred` are preserved if present.
- Entries already in the JSON that are NOT in the TSV are kept as-is
  (no destructive drops — the labeler may have been enriched with custom
  buckets).

Usage:
  python3 scripts/tools/merge_sfx_labels.py <path-to-tsv>
"""

from __future__ import annotations
import csv
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LABELS_PATH = REPO_ROOT / "data" / "sfx_labels.json"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <tsv>", file=sys.stderr)
        return 2
    tsv_path = Path(sys.argv[1])
    if not tsv_path.exists():
        print(f"missing: {tsv_path}", file=sys.stderr)
        return 2

    existing: dict[str, dict] = (
        json.loads(LABELS_PATH.read_text()) if LABELS_PATH.exists() else {}
    )

    upserted = 0
    added = 0
    with tsv_path.open() as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            wav = row["wav_file"].strip()
            pac = row["pac"].strip()
            se_name = row["se_name"].strip()
            if not wav or not se_name:
                continue
            existed = wav in existing
            prev = existing.get(wav, {})
            existing[wav] = {
                "file": wav.split("/", 1)[1] if "/" in wav else wav,
                "category": pac,
                "label": se_name,
                "notes": prev.get("notes", ""),
                "starred": bool(prev.get("starred", False)),
            }
            if existed:
                upserted += 1
            else:
                added += 1

    LABELS_PATH.write_text(json.dumps(existing, indent=2) + "\n")
    print(f"total entries now: {len(existing)}")
    print(f"  upserted (already existed): {upserted}")
    print(f"  added (new from TSV): {added}")
    print(f"→ wrote {LABELS_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
