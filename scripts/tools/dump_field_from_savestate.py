#!/usr/bin/env python3
"""Dump a PSZ free field's per-room traps + enemies from a melonDS savestate.

The point: save a state anywhere in a field and get the WHOLE field's expected
contents at once, so a play-test verifies a printed sheet instead of
transcribing every room by hand.

How it works -- three joins, all keyed on the room code:

  1. The savestate's room table (the field the game actually rolled) gives every
     room's CODE. MainRAM is located by validation (same trick as
     scripts, ../psz-melonmix read-savestate.py): *(0x02108C64) -> root,
     *(root) -> table base, count at base+0x410 must be 1..20. Each 0x34-byte
     record's first five words ARE {stage, variantId, shapeId, classId, digit}
     (psz-re level_room_naming FUN_02041A08), rebuilt as s%02d%c_%c%c%1d.

  2. Enemies: data/re_reference/enemy_room_assignment.json maps a room code to a
     WEIGHTED POOL of wave templates; enemy_wave_templates.json['d'] resolves
     each template id to its exact enemy composition (ids + names). A room rolls
     its waves from this pool, so the pool is what a run is verified against.

  3. Traps: data/re_reference/room_objects.json (key = code + '_d') carries the
     authored objects; the trap kinds among them are listed. Which group-5 traps
     actually spawn is rolled per visit, so treat the trap list as the pool too.

    python3 scripts/tools/dump_field_from_savestate.py <state.mln>
    python3 scripts/tools/dump_field_from_savestate.py <state.mln> --json out.json
    python3 scripts/tools/dump_field_from_savestate.py --selftest
"""
from __future__ import annotations
import json, pathlib, struct, sys, zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
REF = ROOT / "data" / "re_reference"
RAM_BASE, RAM_SIZE = 0x02000000, 0x400000
DIRS = "NESW"

# psz-re data/level_room_naming.json, tables at 0x020F24B4 / shape / class.
VARIANT, SHAPE, CLASS = "aebz01234567", "iltxnsg", "abcdr"

TRAP_KINDS = {"heal_trap", "heat_trap", "light_trap", "ice_trap", "gun_trap",
              "burn_trap", "needler_trap", "capture_trap", "poison_trap"}


def _u32(b, o): return struct.unpack_from("<I", b, o)[0]


def find_ram(buf):
    """File offset where main RAM begins, plus root/table/count, or None."""
    for base in range(0, min(len(buf) - RAM_SIZE + 1, 0x100000), 4):
        try:
            root = _u32(buf, base + 0x108C64)
            if not (RAM_BASE <= root < RAM_BASE + RAM_SIZE):
                continue
            tbl = _u32(buf, base + (root - RAM_BASE))
            if not (RAM_BASE <= tbl < RAM_BASE + RAM_SIZE):
                continue
            n = _u32(buf, base + (tbl - RAM_BASE) + 0x410)
            if 1 <= n <= 20:
                return base, root, tbl, n
        except struct.error:
            continue
    return None


def room_code(rec: bytes) -> str | None:
    """Build s%02d%c_%c%c%1d from the record's five-word descriptor."""
    stage, var, shp, cls, digit = (rec[0], rec[4], rec[8], rec[0x0C], rec[0x10])
    if var >= len(VARIANT) or shp >= len(SHAPE) or cls >= len(CLASS):
        return None
    return f"s{stage:02d}{VARIANT[var]}_{SHAPE[shp]}{CLASS[cls]}{digit}"


def load_ref():
    assign = json.loads((REF / "enemy_room_assignment.json").read_text())["assignment"]
    waves = json.loads((REF / "enemy_wave_templates.json").read_text())["d"]["waves"]
    rooms = json.loads((REF / "room_objects.json").read_text())["rooms"]
    return assign, waves, rooms


def model_names():
    """model_id -> display name, so the dump speaks the game's own names
    (frog_bomb -> Pobomma) instead of psz-godot's internal model ids."""
    try:
        enemies = json.loads((ROOT / "data" / "enemies.json").read_text())
    except FileNotFoundError:
        return {}
    return {e["model_id"]: e["name"] for e in enemies if e.get("model_id")}


NAMES = model_names()


def enemy_pool(code, assign, waves):
    """Resolved weighted wave pool for a room code: [(weight, [names]), ...]."""
    out = []
    for entry in assign.get(code, []):
        t = entry.get("template")
        w = waves[t] if isinstance(t, int) and 0 <= t < len(waves) else None
        names = w.get("names", []) if isinstance(w, dict) else []
        out.append((entry.get("weight", 0), names))
    return out


def trap_pool(code, rooms):
    """Authored trap kinds in a room, as {kind: count}."""
    entry = rooms.get(code + "_d")
    pool = {}
    if entry:
        for o in entry.get("objects", []):
            k = o.get("k", "")
            if k in TRAP_KINDS:
                pool[k] = pool.get(k, 0) + 1
    return pool


def fold_names(names):
    """['pobomma','pobomma','bolix'] -> 'pobomma x2, bolix'."""
    order, counts = [], {}
    for raw in names:
        n = NAMES.get(raw, raw)
        if n not in counts:
            order.append(n)
        counts[n] = counts.get(n, 0) + 1
    return ", ".join(f"{n} x{counts[n]}" if counts[n] > 1 else n for n in order)


def build(raw):
    hit = find_ram(raw)
    if hit is None:
        try:
            raw = zlib.decompress(raw); hit = find_ram(raw)
        except zlib.error:
            pass
    if hit is None:
        return None
    off, root, tbl, n = hit
    ram = lambda a: off + (a - RAM_BASE)
    assign, waves, rooms = load_ref()

    field = []
    for i in range(n):
        rec = raw[ram(tbl) + i * 0x34: ram(tbl) + (i + 1) * 0x34]
        code = room_code(rec)
        cx, cy = rec[0x2E], rec[0x2F]
        ex = [rec[0x18 + k] for k in range(4)]
        ga = [rec[0x1C + k] for k in range(4)]
        field.append({
            "index": i,
            "code": code,
            "cell": f"{chr(ord('A') + cx)}{cy + 1}",
            "doors": {DIRS[k]: ga[k] for k in range(4) if ex[k] != 0xFF},
            "keys": rec[0x2C],
            "enemy_pool": enemy_pool(code, assign, waves) if code else [],
            "traps": trap_pool(code, rooms) if code else {},
        })
    cur = raw[ram(root + 0x16)]
    return {"rooms": field, "current_room": cur if cur < n else None}


def render(doc):
    lines = []
    for r in doc["rooms"]:
        here = " <- you are here" if r["index"] == doc["current_room"] else ""
        doors = ", ".join(f"{d}={g}" for d, g in r["doors"].items()) or "-"
        traps = ", ".join(f"{k} x{v}" for k, v in r["traps"].items()) or "none"
        lines.append(f"[{r['index']:2d}] {r['code'] or '??':10} cell {r['cell']:>3}  "
                     f"doors {doors}  keys {r['keys']}{here}")
        # Authored pool, not the spawned count: traps are the group-5 roll, so
        # only 0-3 of them actually appear on a given visit.
        lines.append(f"       trap pool (0-3 spawn): {traps}")
        if r["enemy_pool"]:
            lines.append("       enemy wave pool (weighted; a run rolls 1-2 waves from these):")
            for wt, names in sorted(r["enemy_pool"], key=lambda x: -x[0]):
                lines.append(f"         w{wt:>3}: {fold_names(names) or '(empty)'}")
        else:
            lines.append("       enemy wave pool: (no assignment for this code)")
    return "\n".join(lines)


def selftest():
    # descriptor words at +0x00 stage, +0x04 variant, +0x08 shape, +0x0C class, +0x10 digit
    rec = bytearray(0x34)
    rec[0], rec[4], rec[8], rec[0x0C], rec[0x10] = 5, 0, 1, 1, 3  # s05 a l b 3
    assert room_code(bytes(rec)) == "s05a_lb3", "code build"
    assert fold_names(["shrimp", "shrimp", "frog_bomb"]).startswith(
        NAMES.get("shrimp", "shrimp") + " x2"), "fold+name-map"
    rec[4] = 99  # variant out of range
    assert room_code(bytes(rec)) is None, "bad variant guarded"
    print("selftest ok")


def main(argv):
    if "--selftest" in argv:
        selftest(); return 0
    if len(argv) < 2:
        print(__doc__); return 2
    doc = build(pathlib.Path(argv[1]).read_bytes())
    if doc is None:
        print("could not locate a field room table in this savestate", file=sys.stderr)
        return 1
    print(render(doc))
    if "--json" in argv:
        out = argv[argv.index("--json") + 1]
        pathlib.Path(out).write_text(json.dumps(doc, indent=2))
        print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
