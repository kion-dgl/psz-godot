#!/usr/bin/env python3
"""Author the s03b cave anchor lights + glow materials (#657).

Runs detect_s03b_anchors over the snowfield B stages and merges two kinds of
authored data into data/stage_configs/unified-stage-configs.json:

- `effects[]` entries of the new plain `light` type (#636): one per detected
  anchor cluster — cool blue over the mizu2 water pools, warm over the
  kinoko mushroom clusters (the art ships no crystals; the pools are the
  blue reflective anchors, the red caps read as warm accents).
- `glowMaterials[]`: per-stage material passes that make the anchor meshes
  read as sources — emissive tint + low roughness (reflectivity) where the
  art supports it.

Idempotent: existing placed_anchor_* entries and glowMaterials for a stage
are replaced, everything else preserved. Re-run after stage art changes.

Usage: python3 scripts/tools/author_s03b_anchors.py [--dry]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from detect_s03b_anchors import detect  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "data/stage_configs/unified-stage-configs.json"

# What each anchor material becomes. Water: the blue story — cool omni above
# the surface, faint blue emission, mirror-smooth. Mushrooms: warm accents
# matching their caps, matte-bright.
ANCHOR_KINDS = {
    "1_mizu2": {
        "light": {"color": [0.45, 0.65, 0.95], "intensity": 0.8, "radius": 7.0, "y_offset": 1.5},
        "glow": {"emission": [0.30, 0.50, 0.80], "energy": 0.45, "roughness": 0.12},
    },
    "1_0mizu": {
        "light": {"color": [0.45, 0.65, 0.95], "intensity": 0.8, "radius": 7.0, "y_offset": 1.5},
        "glow": {"emission": [0.30, 0.50, 0.80], "energy": 0.45, "roughness": 0.12},
    },
    "1_kinoko": {
        "light": {"color": [1.0, 0.55, 0.30], "intensity": 0.55, "radius": 6.0, "y_offset": -0.8},
        "glow": {"emission": [1.0, 0.45, 0.25], "energy": 0.6, "roughness": 0.7},
    },
}

# Cluster acceptance: the #646 lantern band — ground-standing props only.
# Tall kinoko clusters (8–12) are scenic wall-growth; ga1's star sits at
# y −32.5 in the backdrop and is skipped by the band.
KINOKO_BAND = (4.5, 6.5)
# Pool surfaces live in basins below walk height (−2.0 in the mizu2 stages);
# anything deeper than −4 is backdrop/void, and far-edge strips (|x|/|z| > 40,
# ga1's perimeter moat at ±59) light nothing the player walks past.
MIZU_TOP_BAND = (-4.0, 1.0)


def anchors_for(stage_id):
    out = []
    # kinoko: lantern-band clustering
    for a in detect(stage_id, min_verts=2, band=KINOKO_BAND):
        kind = ANCHOR_KINDS.get(a["material"])
        if not kind:
            continue
        cx, cy, cz = a["centroid"]
        y = a["top"] + kind["light"]["y_offset"]
        out.append({"material": a["material"], "position": [cx, y, cz]})
    # water: no band, filter by |y| (pools at walk height; ga1's −2.5 moat
    # strips and backdrop copies drop out)
    for a in detect(stage_id, min_verts=1, band=None, materials=("1_mizu2", "1_0mizu")):
        kind = ANCHOR_KINDS.get(a["material"])
        if not kind:
            continue
        cx, cy, cz = a["centroid"]
        if not (MIZU_TOP_BAND[0] <= a["top"] <= MIZU_TOP_BAND[1]) or abs(cz) > 40 or abs(cx) > 40:
            continue
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
        glow[a["material"]] = kind["glow"]
    # glowMaterials: keep stable ordering
    glow_list = [
        {"material": m, **glow[m]} for m in sorted(glow)
    ]
    return effects, glow_list


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text())
    stage_dirs = sorted(
        d.name for d in (REPO / "assets/stages/snowfield_b").iterdir() if d.name.startswith("s03b")
    )
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
        entry["glowMaterials"] = glow_list
        changed += 1
        print(f"{stage}: {len(effects)} anchor lights, glow on {glow_names}")
    print(f"\n{changed} stages authored")
    if args.dry:
        return 0
    CONFIG.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
