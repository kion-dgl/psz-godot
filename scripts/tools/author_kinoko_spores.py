#!/usr/bin/env python3
"""Author pink kinoko spore effects from stage art (#659 walk pass).

Where the red mushrooms stand (any mesh on the 1_kinoko material — the
texture s03_1_kinoko), a slow pink spore drift rises from the cluster: the
`spores` placed-effect type (the #646 particle path). Unlike the anchor
LIGHT pass, every cluster counts — the wall-edge growth the lights skipped
as scenic is exactly what the spores dust.

Idempotent: existing kinoko_spore_* entries for a stage are replaced.

Usage:
  python3 scripts/tools/author_kinoko_spores.py            # author all stages
  python3 scripts/tools/author_kinoko_spores.py --dry-run  # report only
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from detect_s03b_anchors import STAGE_ROOT, detect  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "data/stage_configs/unified-stage-configs.json"

SPORE_COLOR = [1.0, 0.5, 0.72]  # PSO spore pink


def build_entries(anchors):
    return [
        {
            "type": "spores",
            "category": "placed",
            "color": SPORE_COLOR,
            "count": 14,
            "radius": 1.6,
            "height": 3.5,
            "speed": 0.3,
            "position": a["centroid"],
            "id": f"kinoko_spore_{i}",
        }
        for i, a in enumerate(anchors)
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--min-verts", type=int, default=2)
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text())
    for d in sorted(STAGE_ROOT.iterdir()):
        if not d.is_dir() or not d.name.startswith("s03b"):
            continue
        try:
            # No band: floor clusters and wall-edge growth both get dusted.
            anchors = detect(d.name, args.min_verts, None, materials=("1_kinoko",))
        except Exception as e:  # noqa: BLE001 — keep authoring other stages
            print(f"{d.name}: ERROR {e}")
            continue
        if not anchors:
            continue
        effects = build_entries(anchors)
        print(f"{d.name}: {len(effects)} kinoko spores ("
              + ", ".join(str(a["centroid"]) for a in anchors) + ")")
        if args.dry_run:
            continue
        entry = cfg.setdefault(d.name, {})
        old = [e for e in entry.get("effects", [])
               if not str(e.get("id", "")).startswith("kinoko_spore_")]
        entry["effects"] = old + effects

    if args.dry_run:
        return 0
    CONFIG.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {CONFIG}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
