#!/usr/bin/env python3
"""Extract per-weapon-type animation frame counts from psz-asset-viewer GLBs.

The viewer's processPlayerAnimations.ts converts the original per-type
animation NARCs (raw/player/XX_category_[m|w]_paNN.narc) into GLBs under
public/player/animations. Each GLB's animation samplers carry the original
clip durations; at the game's 30 fps tick they give the original combo/PA/
technique/hit-reaction timing per weapon type and player frame (m/w).

Frames are rounded from the sampler input max (duration * 30). Clip role is
parsed from the original naming: pm<pw><clip> (male/female frame, weapon
code: sa=saver bn=bare-body, etc).
"""
import argparse
import json
import struct
from pathlib import Path

CLIP_ROLES = {
    "atk": "combo attack step (atk1..atkN)",
    "pa1": "photon art 1", "pa2": "photon art 2", "pa3": "photon art 3",
    "tec": "technique cast",
    "dam_n": "light damage reaction", "dam_h": "heavy damage reaction",
    "dam_d": "knockdown reaction", "dam_d_lp": "knockdown loop",
    "dam_d_wa": "knockdown get-up",
    "wait": "idle", "run": "run cycle", "chg": "charge",
    "esc_f": "escape/dash", "stp_fb": "step forward/back", "stp_lr": "step left/right",
    "slp": "sleep/downed", "pb": "photon blast", "pb_lp": "photon blast loop",
}


def glb_animation_frames(path: Path):
    data = path.read_bytes()
    magic, _ver, _len = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path
    clen, ctype = struct.unpack_from("<II", data, 12)
    assert ctype == 0x4E4F534A, path
    gltf = json.loads(data[20:20 + clen])
    out = {}
    for anim in gltf.get("animations", []):
        dur = 0.0
        for s in anim.get("samplers", []):
            acc = gltf["accessors"][s["input"]]
            dur = max(dur, acc.get("max", [0])[0])
        out[anim["name"]] = round(dur * 30)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--viewer", required=True, help="psz-asset-viewer checkout (needs public/player/animations)")
    ap.add_argument("--out", default="data/re_reference/player_anim_timings.json")
    args = ap.parse_args()

    sets_path = Path(args.viewer) / "public/player/animations/animation_sets.json"
    sets = json.loads(sets_path.read_text())
    by_type = {}
    for entry in sets:
        glb = Path(args.viewer) / "public/player/animations" / entry["glbFile"]
        if not glb.exists():
            continue
        frames = glb_animation_frames(glb)
        # clip names: p<frame><weapon-code>_<clip>; weapon code sa (saber), bn (body)
        clips = {}
        for name, count in frames.items():
            if not name.startswith("p") or "_" not in name:
                continue
            clip = name.split("_", 1)[1]
            clips[clip] = count
        by_type.setdefault(entry["category"], {})[entry["weaponType"]] = {
            "set": entry["id"],
            "frames": clips,
        }

    out = {
        "source": f"psz-asset-viewer public/player/animations GLBs (converted from raw/player/XX_category_[m|w]_paNN.narc via processPlayerAnimations.ts + apicula); frame counts = animation duration x 30fps, rounded from glTF sampler input max",
        "naming": "clips are p<frame m|w...><weapon code bn|sa|sw|da|sp|ds|sl|gb|hg|mc|ri|bz|lc|ro|wa>_<role>; common/bn clips are weapon-independent body animations shared by all types",
        "roles": CLIP_ROLES,
        "types": by_type,
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.out}: {len(by_type)} weapon categories")
    for category in sorted(by_type):
        frames = next(iter(by_type[category].values()))["frames"]
        combo = [frames.get(f"atk{i}") for i in (1, 2, 3)]
        pa = [frames.get(f"pa{i}") for i in (1, 2, 3)]
        print(f"  {category:10s} combo atk1..3={combo} pa1..3={pa} tec={frames.get('tec')}")


if __name__ == "__main__":
    main()
