#!/usr/bin/env python3
"""Extract the per-weapon-type player action parameter table.

Inside every raw/player/XX_type_[m|w]_paNN.narc, alongside the BCA0
animations, rides a DSIF rel whose NDR data block carries the per-type
ACTION rows: about 25-35 bytes differ between weapon types, clustered in
five field groups at fixed offsets (0x850, 0x8e8, 0x980, 0xa18, 0xa38 in the
male-frame files) inside otherwise-shared 152-byte rows.

These are the gameplay timing windows around the attack chain (per step:
a total/window value, hit-window pairs, extra event bytes, kind tag 3, 0xFF
terminators) - NOT the animation clip lengths (see
data/re_reference/player_anim_timings.json for those). Which field is the
hit frame, the combo-continue window, or the heavy/PA branch is pending
recovery of the consumer function in the player action driver; values are
exported raw with layout notes so the mapping can be filled in without
re-dumping.
"""
import argparse
import json
import struct
from pathlib import Path

# (offset, length) of each per-type field cluster inside the NDR data block
CLUSTERS = [
    (0x850, 12, "action row 1 (combo step 1 window)"),
    (0x8e8, 12, "action row 2 (combo step 2 window)"),
    (0x980, 12, "action row 3 (combo step 3 / finisher window)"),
    (0xa18, 16, "action row 4 (heavy/PA event list)"),
    (0xa38, 4, "row 5 flag pair"),
]


def narc_entries(raw: bytes):
    out = raw
    if out[:4] == b"ZPR\x00":
        # ZPR: 16-byte header, payload XOR 0x95, PRS stream (ArchiveUnpacker zpr.ts)
        raise RuntimeError("use the shared parser; pass decompressed narc")
    assert out[:4] == b"NARC"
    btaf = 0x10
    size, n = struct.unpack_from("<II", out, btaf + 4)
    entries = [struct.unpack_from("<II", out, btaf + 12 + i * 8) for i in range(n)]
    btnf = btaf + size
    gmif = btnf + struct.unpack_from("<I", out, btnf + 4)[0]
    return [(out[gmif + 8 + s:gmif + 8 + e]) for s, e in entries]


def zpr(buf: bytes) -> bytes:
    assert buf[:4] == b"ZPR\x00"
    (size,) = struct.unpack_from("<I", buf, 0x08)
    data = bytes(b ^ 0x95 for b in buf[0x10:])
    # PRS decompression (ArchiveUnpacker prs.ts transcription)
    out = bytearray(size)
    ip = op = 0
    ctrl = counter = 0
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


def action_blob(narc_path: Path):
    raw = narc_path.read_bytes()
    out = zpr(raw) if raw[:4] == b"ZPR\x00" else raw
    for entry in narc_entries(out):
        if entry[:4] == b"DSIF":
            size = struct.unpack_from("<I", entry, 0x24)[0]
            return entry[0x30:0x20 + size]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True, help="retail raw/player extraction (psz-asset-viewer)")
    ap.add_argument("--out", default="data/re_reference/player_action_params.json")
    args = ap.parse_args()
    player = Path(args.raw) / "player"

    types = {}
    for narc in sorted(player.glob("*_pa00.narc")):
        stem = narc.stem  # e.g. 01_saver_m_pa00
        parts = stem.split("_")
        category = "_".join(parts[1:-2])
        frame = parts[-2]
        blob = action_blob(narc)
        if blob is None:
            continue
        fields = {}
        for off, length, label in CLUSTERS:
            seg = blob[off:off + length]
            fields[label] = list(seg)
        types.setdefault(category, {})[frame] = {
            "narc": narc.name,
            "fields": fields,
        }

    out = {
        "source": f"retail raw/player/*_pa00.narc DSIF payload (psz-asset-viewer); per-type action parameter rows at fixed NDR offsets, extracted raw",
        "layout": "each cluster holds: window total byte, kind tag (3), 0xFF separators, hit/window byte pairs, and per-action extra event bytes. Row 4 carries the heavy/PA event list. Values are gameplay ticks against the 30fps action clock; they are NOT animation clip lengths.",
        "semantics": "UNCONFIRMED: which byte is the hit frame vs combo-continue window vs heavy branch needs the consumer function in the player action driver (decomp ask). Cross-reference data/re_reference/player_anim_timings.json clip lengths when mapping: saber windows 20/22/23 vs clips 17/18/16; sword 44/43/48 vs clips 23/23/25.",
        "types": types,
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.out}: {len(types)} categories")
    for category, frames in sorted(types.items()):
        if "m" in frames:
            rows = frames["m"]["fields"]
            r1 = rows["action row 1 (combo step 1 window)"]
            print(f'  {category:11s} step1={r1[:8]}')


if __name__ == "__main__":
    main()
