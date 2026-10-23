#!/usr/bin/env python3
"""Derive godot-side attack timing from the frame-exact original decode.

Input: data/re_reference/player_combo_windows.json — psz-re's emulator-
validated decode of the per-weapon-type attack records (22 x 152-byte records
in each pa00 DSIF): per attack step, the animation length in frames, the
chain-accept window (chain_opens..chain_closes) and the HIT FRAMES — the
instants the swing's damage event fires. Ten boundaries were verified
frame-exact on hardware traces.

Output: data/re_reference/original_attack_timing.json keyed by psz-godot's
WeaponType enum, with everything as FRACTIONS of the swing so the runtime
pipeline can consume it alongside its tuned defaults:
  hit_fracs        [f1, f2, ...] per step (multi-hit swings keep every frame)
  chain_open_frac  when a follow-up press starts chaining
  chain_close_frac when it stops (godot previously had no closing boundary)
  length_frames    the original clip length, for reference

The male ('m') build is canonical; 'w' is the fallback where a type has no
male rows. Types with no corpus entry are omitted and keep their tuned
defaults. Regenerate after psz-re refreshes the decode.
"""
import json
from pathlib import Path

ROOT = pathlib = Path(__file__).resolve().parents[2]

# corpus file_name -> psz-godot WeaponType (see WeaponData.WeaponType)
TYPE_FOR_FILE = {
    "saver": 0,       # SABER
    "sword": 1,       # SWORD
    "dagger": 2,      # DAGGERS
    "claw": 3,        # CLAW
    "d_saver": 4,     # DOUBLE_SABER
    "spear": 5,       # SPEAR
    "slicer": 6,      # SLICER
    "shield": 8,      # SHIELD
    "handgun": 9,     # HANDGUN
    "machinegun": 10,  # MECH_GUN
    "a_rifle": 11,    # RIFLE
    "grenade": 12,    # BAZOOKA (the launcher family)
    "l_cannon": 13,   # LASER_CANNON
    "rod": 14,        # ROD
    "wand": 15,       # WAND
}


def main():
    doc = json.loads((ROOT / "data/re_reference/player_combo_windows.json").read_text())
    rows = {}
    for weapon in doc["weapons"]:
        name = weapon["file_name"]
        if name not in TYPE_FOR_FILE:
            continue  # common (bare hands) and shotgun have no godot type
        build = weapon["build"]
        if build not in ("m", "w"):
            continue  # child builds sm/sw; the adult timings are canonical
        gtype = TYPE_FOR_FILE[name]
        existing = rows.get(str(gtype))
        if existing and build != "m":
            continue  # keep the male row when both builds exist
        steps = []
        for step in ("atk1", "atk2", "atk3"):
            attack = weapon["attacks"].get(step)
            if not attack:
                steps.append({})
                continue
            length = float(attack["length"])
            steps.append({
                "hit_fracs": [round(float(f) / length, 4) for f in attack.get("hit_frames", [])],
                "chain_open_frac": round(float(attack["chain_opens"]) / length, 4) if attack.get("chain_opens") is not None else None,
                "chain_close_frac": round(float(attack["chain_closes"]) / length, 4) if attack.get("chain_closes") is not None else None,
                "length_frames": attack["length"],
            })
        rows[str(gtype)] = {"file": name, "build": build, "steps": steps}

    out = {
        "source": "derived from data/re_reference/player_combo_windows.json (psz-re emulator-validated decode of the pa00 attack records; hit frames, chain windows, clip lengths)",
        "units": "fractions of the swing animation; hit_fracs fire damage at each crossing, chain_open/close_frac bound follow-up presses; atk3 never carries a chain window (no fourth hit)",
        "types": rows,
    }
    path = ROOT / "data/re_reference/original_attack_timing.json"
    path.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {path}: {len(rows)} weapon types")
    for gtype in sorted(rows, key=int):
        r = rows[gtype]
        brief = []
        for s in r["steps"]:
            if s:
                brief.append(f"hit@{s['hit_fracs']} chain {s['chain_open_frac']}..{s['chain_close_frac']}")
            else:
                brief.append("-")
        print(f"  type {gtype:>2} {r['file']:10s} ({r['build']}): " + " | ".join(brief))


if __name__ == "__main__":
    main()
