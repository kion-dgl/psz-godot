#!/usr/bin/env python3
"""Author the valley toro-lantern anchor lights + glow materials (#648).

Runs detect_valley_anchors over the valley stages and merges authored data
into data/stage_configs/unified-stage-configs.json, following the #657 s03b
pattern:

- `effects[]` plain `light` entries (#636): one warm pool per stone-lantern
  (1_toro) cluster — td1/td2 are the only toro stages. Intensities are day
  rig values: the pools punch against sun 0.9 + ambient 0.8, unlike the
  night-calibrated s03b anchors.
- No `glowMaterials[]`: toro's texture carries a mirror-wrap fix
  (s01_1_toro.png#1), so its surface renders through the texture-fix shader
  by glow time — an emissive StandardMaterial3D swap would drop the wrap.
  The warm pool light carries the anchor alone.

The boss arena's 2_kemu smoke stays un-authored on purpose: detection puts
every cluster on the distant backdrop ring (|coord| ≥ 20, mostly below-floor
copies) — scenery, not sources.

Idempotent: existing placed_anchor_* entries and glowMaterials for a stage
are replaced, everything else preserved. Re-run after stage art changes.

Usage: python3 scripts/tools/author_valley_anchors.py [--dry]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from detect_valley_anchors import detect  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "data/stage_configs/unified-stage-configs.json"

# The stone lanterns stand ~2 m tall; the light rides just above the housing.
TORO_BAND = (1.0, 3.0)

ANCHOR_KINDS = {
    "1_toro": {
        "light": {"color": [1.0, 0.72, 0.42], "intensity": 6.0, "radius": 7.0, "y_offset": 0.3},
    },
}


def anchors_for(stage_id):
    out = []
    for a in detect(stage_id, min_verts=2, band=TORO_BAND):
        kind = ANCHOR_KINDS.get(a["material"])
        if not kind:
            continue
        cx, cy, cz = a["centroid"]
        y = a["top"] + kind["light"]["y_offset"]
        out.append({"material": a["material"], "position": [cx, y, cz]})
    return out


def build_entries(anchors):
    effects = []
    glow = {}
    for i, a in enumerate(anchors):
        kind = ANCHOR_KINDS[a["material"]]
        spec = kind["light"]
        effects.append(
            {
                "type": "light",
                "category": "placed",
                "color": spec["color"],
                "intensity": spec["intensity"],
                "radius": spec["radius"],
                "position": [round(v, 2) for v in a["position"]],
                "id": f"placed_anchor_{i}_{a['material'].lstrip('1_')}",
            }
        )
        if "glow" in kind:
            glow[a["material"]] = kind["glow"]
    glow_list = [
        {"material": m, **glow[m]} for m in sorted(glow)
    ]
    return effects, glow_list


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text())
    stage_dirs = []
    for folder in ("valley_a", "valley_b", "valley_e", "valley_z"):
        root = REPO / "assets/stages" / folder
        if root.is_dir():
            stage_dirs += sorted(d.name for d in root.iterdir() if d.name.startswith("s01"))
    changed = 0
    for stage in stage_dirs:
        anchors = anchors_for(stage)
        if not anchors:
            continue
        effects, glow_list = build_entries(anchors)
        glow_names = sorted({g["material"] for g in glow_list})
        entry = cfg.setdefault(stage, {})
        old = [
            e for e in entry.get("effects", []) if not str(e.get("id", "")).startswith("placed_anchor_")
        ]
        entry["effects"] = old + effects
        if glow_list:
            entry["glowMaterials"] = glow_list
        else:
            entry.pop("glowMaterials", None)
        changed += 1
        print(f"{stage}: {len(effects)} anchor lights, glow on {glow_names or ['—']}")
    print(f"\n{changed} stages authored")
    if args.dry:
        return 0
    CONFIG.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
