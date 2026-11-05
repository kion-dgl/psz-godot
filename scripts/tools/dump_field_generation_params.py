#!/usr/bin/env python3
"""Consolidate the original field-generation parameters into one reference file.

Sources (semantics from data/re_reference/level_generation_algorithm.json,
which solved the algorithm against retail savestates and live melonDS reads):

- quest/single/dive/quest_001SS00.rel (SS = stage 01..07): the per-area sparse
  override record - pass 3 of FUN_02031ce8's three-pass parameter merge.
  Record located by the params[4..8] signature 32 19 32 1e 55; picker index
  bytes at SOURCE+0x23 (not the merged block's +0x0e); no weights here.
- quest/random_dungeon.rel: pass-2 overlay - supplies the u16@0x0c corridor
  chance and the five u16 weights; its room bounds are SUPERSEDED per-area.
- The merged block only ever exists as a DTCM stack local at generation time.

Also encodes the rare-room eligibility masks (0x020f5798) and the
FUN_0206d4bc slot->room switch, cross-validated against the visual IDs.
"""
import argparse
import json
import struct
from pathlib import Path

SIG = bytes.fromhex("3219321e55")

RARE_ROOM_SLOTS = {
    "0": {"room": "nr1", "mask": "0x000e", "stages": [1, 2, 3], "note": "cake shop"},
    "1": {"room": "nr3", "mask": "0x0020", "stages": [5], "note": "paru room"},
    "2": {"room": "nr4", "mask": "0x0010", "stages": [4], "note": "pumpkins (makara)"},
    "3": {"room": "nr5", "mask": "0x0008", "stages": [3], "note": "snowfield room"},
    "4": {"room": "nr6", "mask": "0x00c0", "stages": [6, 7], "note": "pizza shop (arca plant)"},
    "5": {"room": "nr2", "mask": "0x0000", "stages": [], "note": "COLISEUM - never via the picker; placed by the E-transition builder at 8% (weights[4]=800/10000)"},
    "6": {"room": "na1", "mask": "0xfffe", "stages": "all", "note": "ordinary dead end"},
    "7": {"room": "nc2", "mask": "0xfffe", "stages": "all", "note": "ordinary dead end"},
}


def zpr(buf: bytes) -> bytes:
    assert buf[:4] == b"ZPR\x00"
    (size,) = struct.unpack_from("<I", buf, 0x08)
    data = bytes(b ^ 0x95 for b in buf[0x10:])
    out = bytearray(size)
    ip = op = 0
    state = {"c": 1, "b": 0}

    def bit():
        nonlocal ip
        state["c"] -= 1
        if state["c"] == 0:
            state["b"] = data[ip]; ip += 1
            state["c"] = 8
        v = state["b"] & 1
        state["b"] >>= 1
        return v

    while op < size and ip < len(data):
        while bit():
            if ip >= len(data) or op >= size:
                break
            out[op] = data[ip]; op += 1; ip += 1
        if op >= size or ip >= len(data):
            break
        if bit():
            b1 = data[ip]; b2 = data[ip + 1]; ip += 2
            if b1 == 0 and b2 == 0:
                break
            offset = ((b2 << 5) + (b1 >> 3)) - 8192
            lp = b1 & 7
            length = lp + 2 if lp else data[ip] + 10; ip += 0 if lp else 1
        else:
            length = 2
            if bit(): length += 2
            if bit(): length += 1
            offset = data[ip] - 256; ip += 1
        cp = offset + op
        for i in range(length):
            if op >= size:
                break
            out[op] = out[cp + i] if 0 <= cp + i < op else 0
            op += 1
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True, help="retail raw/ extraction (psz-asset-viewer)")
    ap.add_argument("--out", default="data/re_reference/field_generation_params.json")
    args = ap.parse_args()
    raw = Path(args.raw)

    areas = {}
    for stage in range(1, 8):
        blob = zpr((raw / f"quest/single/dive/quest_0010{stage}00.rel").read_bytes())
        i = blob.find(SIG)
        assert i >= 0, stage
        rec = blob[i - 4:]  # record starts at params[0]; signature = params[4..8]
        picker = list(rec[0x0B:0x0B + 8])  # verified: valley = 02 ff ff ff ff 04 03 03, snowfield slot 3, paru slot 1
        live = [k for k, v in enumerate(picker[:5]) if v != 0xFF]
        areas[str(stage)] = {
            "min_rooms": rec[0], "max_rooms": rec[1],
            "branch_pair": [rec[2], rec[3]],
            "gate_params_4_to_8": list(rec[4:9]),
            "start_y_param": rec[9], "goal_mode": rec[10],
            "picker_index_bytes": picker,
            "live_rare_slots": live,
            "note": "branch pair (2,2) skips the branch draw entirely (max==min); (2,3) draws rand(1)=0 - branches are ALWAYS 2",
        }

    rd = zpr((raw / "quest/random_dungeon.rel").read_bytes())
    cfg = rd[0x30:0x30 + 32]
    weights = [struct.unpack_from("<H", cfg, o)[0] for o in range(0x16, 0x20, 2)]

    out = {
        "source": f"retail raw/ quest/single/dive/quest_0010S00.rel + quest/random_dungeon.rel; semantics from data/re_reference/level_generation_algorithm.json (FUN_02031ce8 three-pass merge, resolved live via DTCM breakpoint)",
        "merge_rule": "arm9 default 0x020ec2d8 <- random_dungeon.rel overlay (pass 2) <- per-area sparse diff (pass 3, sentinel = inherit: negative for bytes 0..8/0x0a, 0xFE for byte 9 and the picker loop). The merged block exists only as a DTCM stack local at generation time.",
        "target_rule": "target = min + rand(max-min); branches = pair[0] + rand(pair[1]-pair[0]); budget identity target = 2*branches + spine + 1 (FUN_02083378); growth stops at placed >= target, one extension pass when short",
        "areas": areas,
        "random_dungeon_overlay": {
            "room_bounds_superseded": [cfg[0], cfg[1]],
            "params_4_to_6": list(cfg[4:7]),
            "corridor_chance_u16_0x0c": struct.unpack_from("<H", cfg, 0x0C)[0],
            "weights_per_10000": weights,
            "weights_note": "weight index i is selected by a picker byte; value is the per-10000 chance. weights[4]=800 is the coliseum rate read by the E-transition builder (8%)",
        },
        "rare_room_slots": RARE_ROOM_SLOTS,
        "rare_room_odds_stage1": {"nr1": "2.0%", "na1": "4.0%", "nc2": "4.0%", "nothing": "90.0%", "coliseum_e_transition": "8.0% (separate roll)"},
        "wave_count_rule": "FUN_02057794 (banked, pszm-decomp): count = ctx_min + game_rng(ctx_max - ctx_min + 1) - INCLUSIVE range on the combat RNG (PszRng). ctx min/max are the [w3, w4] fields of the per-room wave records in enemy_room_assignment.json",
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.out}")
    for stage, a in sorted(areas.items()):
        print(f'  stage {stage}: rooms {a["min_rooms"]}..{a["max_rooms"]} branches {a["branch_pair"]} rare slots {a["live_rare_slots"]}')


if __name__ == "__main__":
    main()
