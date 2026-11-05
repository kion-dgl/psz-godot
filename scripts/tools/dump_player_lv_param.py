#!/usr/bin/env python3
"""Dump player_lv_param.zarc into data/re_reference/player_lv_param.json.

Row layout follows the decomp's banked reader (pszm-decomp src/arm9/FUN_020412d8.c)
and matches scripts/tools/check_progression_reference.py: per member, 100 rows of
24 bytes starting at +0x30 — seven u16 stats (hp, pp, attack, defense, accuracy,
evasion, technique; names verified against data/classes/*.tres level anchors),
reserved bytes at +0x0E/+0x10, and a u32 cumulative XP threshold at +0x14
(XP needed to reach the NEXT level; see check_progression_reference.py).

ZARC parsing is a Python transcription of the MIT-licensed ArchiveUnpacker
(https://github.com/DashGL/ArchiveUnpacker, src/zarc.ts).

Class-to-member candidates are derived by curve-matching data/classes/*.tres
breakpoints against the decoded rows; only exact stat matches are reported.
"""
import argparse
import json
import re
import struct
from pathlib import Path

STAT_NAMES = ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]


def zarc_files(raw: bytes):
    assert raw[:4] == b"ZARC", raw[:4]
    header_size, file_count, def_size = struct.unpack_from("<III", raw, 0x0C)
    for i in range(file_count):
        base = header_size + i * def_size
        offset, size = struct.unpack_from("<II", raw, base)
        name = raw[base + 16:base + 16 + 0x30].split(b"\0")[0].decode("ascii")
        yield name, raw[offset:offset + size]


def parse_param(blob: bytes):
    assert blob[:4] == b"DSIF", blob[:4]
    ndr = 0x20
    assert blob[ndr:ndr + 4] == b"NDR\0", blob[ndr:ndr + 4]
    stats = {name: [] for name in STAT_NAMES}
    xp_to_reach = []  # cumulative XP to reach the NEXT level, per level 1..100
    reserved_e = set()
    reserved_10 = set()
    for lv in range(100):
        row = 0x30 + lv * 24
        values = struct.unpack_from("<7H", blob, row)
        for name, value in zip(STAT_NAMES, values):
            stats[name].append(value)
        reserved_e.add(struct.unpack_from("<H", blob, row + 0x0E)[0])
        reserved_10.add(blob[row + 0x10])
        xp_to_reach.append(struct.unpack_from("<I", blob, row + 0x14)[0])
    tail = blob[0x30 + 100 * 24:]
    reserved = {
        "u16_at_0e_distinct": sorted(reserved_e),
        "u8_at_10_distinct": sorted(reserved_10),
        "tail_hex": tail.hex(),
    }
    return stats, xp_to_reach, reserved


def parse_type_param(blob: bytes):
    # player_type_param.rel: DSIF/NDR with repeated 16-byte rows whose second
    # u32 is 100 or 80 shifted left by 8. Field meaning unconfirmed (candidate
    # per-type caps); stored raw for future decode.
    body = blob[0x30:]
    rows = []
    for off in range(0, len(body) - 15, 16):
        a, b = struct.unpack_from("<II", body, off)
        rows.append([a, b, b >> 8])
    return {"row_hex": body.hex(), "u32_pairs_shifted": rows}


def load_class_curves(classes_dir: Path):
    curves = {}
    for tres in sorted(classes_dir.glob("*.tres")):
        text = tres.read_text()
        stats = {}
        for name in STAT_NAMES:
            block = re.search(rf'"{name}"\s*:\s*\{{([^}}]+)\}}', text)
            stats[name] = {int(lv): int(v) for lv, v in re.findall(r'"(\d+)":\s*(\d+)', block.group(1))}
        curves[tres.stem] = stats
    return curves


def match_classes(members, curves):
    mapping = {}
    for key, member in members.items():
        best = []
        for class_name, stats in curves.items():
            levels = sorted(stats["hp"])
            diffs = [(name, lv, values[lv], member["stats"][name][lv - 1])
                     for name, values in stats.items() for lv in levels
                     if member["stats"][name][lv - 1] != values[lv]]
            best.append((len(diffs), class_name, diffs))
        best.sort()
        exact = [c for n, c, _ in best if n == 0]
        entry = {"exact": exact}
        if not exact and best and best[0][0] <= 4:
            n, class_name, diffs = best[0]
            entry["near"] = {"class": class_name, "breakpoint_diffs": diffs}
        mapping[key] = entry
    return mapping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zarc", required=True, help="player_lv_param.zarc (psz-re retail build/fs or pszm-decomp extracted copy)")
    ap.add_argument("--out", default="data/re_reference/player_lv_param.json")
    ap.add_argument("--classes", default="data/classes")
    ap.add_argument("--source-note", default="")
    args = ap.parse_args()

    raw = Path(args.zarc).read_bytes()
    members = {}
    type_param = None
    for name, blob in zarc_files(raw):
        if name.startswith("player_param_"):
            stats, xp, reserved = parse_param(blob)
            members[name] = {
                "stats": stats,
                "xp_cumulative_to_next": xp,
                "reserved": reserved,
            }
        elif name == "player_type_param.rel":
            type_param = parse_type_param(blob)
    assert len(members) == 14, sorted(members)

    curves = load_class_curves(Path(args.classes))
    mapping = match_classes(members, curves)

    for key, member in sorted(members.items()):
        member["class_match"] = mapping[key]

    unresolved = [k for k, v in mapping.items() if not v["exact"]]
    ambiguous = [k for k, v in mapping.items() if len(v["exact"]) > 1]

    out = {
        "source": args.source_note or args.zarc,
        "row_format": "per member: 100 rows x 24 bytes @ +0x30; 7 u16 stats (hp,pp,attack,defense,accuracy,evasion,technique); u32 cumulative XP to reach next level @ +0x14; follows FUN_020412d8 / check_progression_reference.py",
        "column_names_evidence": "member player_param_00 L1 (82,67,56,10,110,13,33) == data/classes/humar.tres L1 hp/pp/attack/defense/accuracy/evasion/technique; L100 also matches",
        "class_match_note": "class_match.exact = data/classes/*.tres breakpoint curve (L1/20/40/60/80/100 x 7 stats) identical to ROM rows. All 14 members matched uniquely; hucaseal accuracy L20 was corrected from tres 172 to the ROM value 178 when these rows were hooked up (see git history).",
        "xp_note": "xp_cumulative_to_next[L] is total XP to reach level L+1 (godot totalExp[L]). Mini ROM diverges from retail at L5-L9 and L45; retail psz-re stays authoritative.",
        "members": dict(sorted(members.items())),
        "player_type_param": type_param,
    }
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {args.out}: {len(members)} members x 100 levels x 7 stats")
    for key in sorted(members):
        m = mapping[key]
        if m["exact"]:
            label = m["exact"][0]
        elif "near" in m:
            label = f"{m['near']['class']} (near, {len(m['near']['breakpoint_diffs'])} breakpoint diffs)"
        else:
            label = "<none>"
        print(f"  {key}: {label}")
    if unresolved:
        print(f"unresolved members (no tres curve match): {unresolved}")
    if ambiguous:
        print(f"ambiguous members (multiple matches): {ambiguous}")


if __name__ == "__main__":
    main()
