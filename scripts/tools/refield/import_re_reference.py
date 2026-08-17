#!/usr/bin/env python3
"""Import what the original has in a room that psz-godot does NOT place yet.

`room_objects.json` is the gameplay table — the importer only takes kinds the
spawner handles, because an unhandled record still eats a slot against the
20-object room cap and would silently displace a box. This is the other half: a
REFERENCE layer for the stage editor's Authored tab, so the gap between what the
original puts in a room and what we build is visible instead of theoretical.

    python3 scripts/tools/refield/import_re_reference.py           # write
    python3 scripts/tools/refield/import_re_reference.py --check   # drift guard

THE OBJECTS HERE DO NOT REACH THE GAME. It is deliberately a separate file from
room_objects.json so that adding a kind to this list can never accidentally
start spawning it — the two have different consumers and different risks.

The ENEMY SLOTS are the exception and ARE consumed: FieldPopulation stands each
wave on them instead of a ring (spec /mechanics/enemy-placement). They are
positions rather than objects, so they cost nothing against the room cap.

What it carries, per room:

  keys        o0c_key, 836 records over 224 rooms in set d. The original
              AUTHORS where a key sits. psz-godot instead scatters keys by the
              measured rule (BFS depth < 2 from the gated room, max 2 per room),
              because which ROOMS hold keys is a per-field decision. Both can be
              true — the room table saying where a key may sit, the generator
              choosing which rooms use it — and seeing the authored positions is
              how we find out.

  enemies     Spawn slots from enemy_deploy_positions.json: 257 rooms in set d,
              8 or 9 slots each. CONSUMED by FieldPopulation since #616 — before
              that psz-godot ringed enemies at radius 5.0 (#604), which is why
              they stood on rocks and why a wave straddled a void.

              SLOT ORDER IS (x, z, elevation), NOT (x, y, z) — psz-re's
              THE_COLUMNS_ARE_X_THEN_Z: col0/col1 are the ground plane and col2
              is elevation. Written here as Godot's (x, y, z) so consumers do
              not have to know that.

              `blocks` and `flags` come along because they are unexplained and
              interesting: 254 of 257 rooms have exactly ONE block, so a block
              is not a wave, but the per-block flag is only ever 0 or 1 and
              splits 159/95. With ~8.4 slots per block against 4-enemy wave
              templates, a room's slots plausibly cover more than one wave.

  other       Kinds the original authors that psz-godot does not place:
              o0c_trebox, the TREASURE BOX that appears once a room is cleared
              (653 records over 251 rooms — long carried as psz-re's largest
              unknown until it was identified in play, #613); o0c_mspack, the
              MESSAGE PACK that spawns beside it; warps and healing pads.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent.parent
OUT = ROOT / "data" / "re_reference" / "room_reference.json"

DEFAULT_SETS = ("d",)

# Kinds the gameplay importer already maps; excluded so the two files do not
# disagree about the same record.
PLACED_KINDS = {
    "box", "rare_box", "wall",
    "o0c_fence", "o0c_shfence", "o0c_dgfance", "o0c_fence4",
    "o0c_remswitch", "o0c_switchf", "o0c_switchs",
    "o0c_poisonm",
}

# Model name -> the label the editor shows. Anything unlisted keeps its model
# name, which is the honest default for a thing nobody has identified.
REFERENCE_LABELS = {
    "o0c_key": "key",
    # IDENTIFIED IN PLAY, not guessed. Both were wrong in ways that cost time:
    # "trebox (unidentified)" read as an open question and was re-investigated
    # every session, and "meseta" was simply the wrong object.
    #
    # o0c_trebox is the TREASURE BOX -- it spawns in a room after every enemy in
    # that room is defeated, and it is the treasure box model in the storybook.
    # Confirmed across four rooms of a Rioh run, counts matching the reference
    # each time (kion-dgl/psz-godot#613).
    #
    # o0c_mspack is the MESSAGE PACK, which psz-godot already models --
    # web/src/elements/MessagePack.tsx and scripts/3d/elements/message_pack.gd,
    # the latter reading its own o0c_1_mspack scroll texture. It spawns
    # post-clear alongside the treasure box. Nothing about it is meseta.
    "o0c_trebox": "treasure box",
    "o0c_mspack": "message pack",
    "o0c_healhp": "heal pad",
    "o0s_warpm": "warp",
    "o0s_warps": "warp",
    "o0s_warpb": "warp",
    "o0c_return": "return warp",
}


def psz_re_root(explicit: str | None) -> pathlib.Path | None:
    for candidate in (explicit, os.environ.get("PSZ_RE"),
                      str(ROOT.parent.parent / "psz-re"),
                      str(ROOT.parent / "psz-re")):
        if not candidate:
            continue
        p = pathlib.Path(candidate).expanduser()
        if (p / "data" / "object_placement_per_room.json").exists():
            return p
    return None


def _round(v: float) -> float:
    return round(float(v), 3)


def build(re_root: pathlib.Path, sets: tuple[str, ...]) -> dict:
    objects_doc = json.loads(
        (re_root / "data" / "object_placement_per_room.json").read_text())
    rooms: dict[str, dict] = {}

    for key, rec in objects_doc.get("per_room", {}).items():
        if str(rec.get("set", "")) not in sets:
            continue
        for box in rec.get("boxes", []):
            kind = str(box.get("kind", ""))
            if kind in PLACED_KINDS:
                continue
            entry = rooms.setdefault(key, {"objects": [], "enemies": []})
            entry["objects"].append({
                "k": REFERENCE_LABELS.get(kind, kind),
                "m": kind,
                "g": box.get("group"),
                "x": _round(box.get("x", 0.0)),
                "y": _round(box.get("y", 0.0)),
                "z": _round(box.get("z", 0.0)),
            })

    deploy_path = re_root / "data" / "enemy_deploy_positions.json"
    if deploy_path.exists():
        deploy = json.loads(deploy_path.read_text())
        for state in deploy.get("states", []):
            if str(state.get("set", "")) not in sets:
                continue
            slots = state.get("slots") or []
            if not slots:
                continue
            key = "%s_%s_%s" % (state.get("stage"), state.get("room"), state.get("set"))
            entry = rooms.setdefault(key, {"objects": [], "enemies": []})
            entry["blocks"] = int(state.get("blocks", 0))
            entry["flags"] = state.get("flags", [])
            for slot in slots:
                # (x, z, elevation) -> (x, y, z)
                entry["enemies"].append({
                    "x": _round(slot[0]),
                    "y": _round(slot[2]) if len(slot) > 2 else 0.0,
                    "z": _round(slot[1]),
                })

    return {
        "_": ("What the ORIGINAL has in a room. OBJECTS are reference only and "
              "never reach the game — an unhandled kind would still eat a slot "
              "against the 20-object room cap, so the gameplay table stays "
              "room_objects.json. ENEMIES are DIFFERENT and ARE consumed: "
              "FieldPopulation stands each wave on these authored slots instead "
              "of a ring, because they are positions rather than objects and "
              "cost nothing against that cap (spec /mechanics/enemy-placement). "
              "Regenerate with scripts/tools/refield/import_re_reference.py."),
        "source": "psz-re data/object_placement_per_room.json + enemy_deploy_positions.json",
        "sets": list(sets),
        "rooms": dict(sorted(rooms.items())),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--psz-re")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    re_root = psz_re_root(args.psz_re)
    if re_root is None:
        print("psz-re not found (pass --psz-re or set $PSZ_RE) -- skipping")
        return 0

    doc = build(re_root, DEFAULT_SETS)
    text = json.dumps(doc, indent=1, ensure_ascii=False) + "\n"

    keys = sum(1 for r in doc["rooms"].values() for o in r["objects"] if o["k"] == "key")
    spawns = sum(len(r.get("enemies", [])) for r in doc["rooms"].values())

    if args.check:
        if not OUT.exists() or OUT.read_text() != text:
            print("FAIL: %s is missing or stale against psz-re" % OUT.relative_to(ROOT))
            return 1
        print("ok: %s matches psz-re" % OUT.relative_to(ROOT))
        return 0

    OUT.write_text(text)
    print("wrote %s" % OUT.relative_to(ROOT))
    print("  rooms: %d | authored keys: %d | enemy spawn slots: %d"
          % (len(doc["rooms"]), keys, spawns))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
