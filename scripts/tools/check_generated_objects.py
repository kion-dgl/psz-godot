#!/usr/bin/env python3
"""Assert that generated free fields carry AUTHORED objects, in the room.

The seeded unit tests in `test_runner` check the selection rule in isolation.
This is the other half: it reads the committed dump that
`scripts/tools/dump_generated_fields.gd` produces by running the REAL generator
across every area and seed, and asserts the objects actually came out the far
end and landed somewhere a room can hold them.

    godot --headless --path . --script res://scripts/tools/dump_generated_fields.gd
    python3 scripts/tools/check_generated_objects.py

Why a separate check rather than more unit tests: the unit tests call
`FieldPopulation.authored_objects` directly, so they cannot catch the generator
forgetting to call it, passing the wrong room code, or dropping the result on
the floor. The dump is the generator's own output.
"""
from __future__ import annotations

import collections
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
DUMP = ROOT / "web" / "public" / "field-dumps" / "generated-fields.json"

# A room is a 44x44 cell centred on the origin, with door stubs projecting 3
# units past the wall — psz-re measures every doorway as a segment running
# +/-22 -> +/-25. So 25 is the room's true outer extent and anything past it is
# in the void.
#
# This bound is not arbitrary and it is worth stating what it caught: 34 of the
# 2,726 imported objects (1.2%) sit past +/-22, the furthest at 24.29 — they are
# in the doorway mouths — and ZERO sit past 25. An independent agreement with
# psz-re's door geometry, from a file that knows nothing about it.
HALF_CELL = 25.0

TRAP_TYPES = {
    "heal_trap", "heat_trap", "light_trap", "ice_trap",
    "gun_trap", "burn_trap", "needler_trap", "capture_trap",
}
CONTAINER_TYPES = {"box", "rare_box"}


def main() -> int:
    if not DUMP.exists():
        print("FAIL: %s is missing — run dump_generated_fields.gd first" % DUMP)
        return 1
    doc = json.loads(DUMP.read_text())

    census: collections.Counter = collections.Counter()
    out_of_cell: list[str] = []
    walls: list[str] = []
    cells = 0
    cells_with_objects = 0

    for area in doc.get("areas", []):
        for roll in area.get("rolls", []):
            for section in roll.get("sections", []):
                for cell in section.get("cells", []):
                    cells += 1
                    objects = cell.get("objects", [])
                    if objects:
                        cells_with_objects += 1
                    for obj in objects:
                        kind = str(obj.get("type", ""))
                        census[kind] += 1
                        if kind == "wall":
                            walls.append("%s/%s" % (area.get("area_id"), cell.get("pos")))
                        # Enemies are ring-placed by us and deliberately not
                        # held to this; authored positions must be in the room.
                        if not obj.get("authored", False):
                            continue
                        pos = obj.get("position", [0, 0, 0])
                        if abs(float(pos[0])) > HALF_CELL or abs(float(pos[2])) > HALF_CELL:
                            out_of_cell.append("%s %s %s at %s"
                                               % (area.get("area_id"), cell.get("pos"), kind, pos))

    failures = []
    if cells == 0:
        failures.append("the dump has no cells at all")
    if not census:
        failures.append("no objects in any generated field")

    traps = sum(census[t] for t in TRAP_TYPES)
    containers = sum(census[t] for t in CONTAINER_TYPES)
    if traps == 0:
        failures.append("no traps in any generated field — group 5 is not being rolled")
    if containers == 0:
        failures.append("no containers in any generated field")

    # The point of the change: several distinct trap families reach the field,
    # not just whichever one happens to sit in group 0.
    families = sorted(t for t in TRAP_TYPES if census[t])
    if len(families) < 4:
        failures.append("only %d trap families reach a field (%s)" % (len(families), families))

    if out_of_cell:
        failures.append("%d authored objects outside the room + its door stubs: %s"
                        % (len(out_of_cell), out_of_cell[:5]))
    if walls:
        failures.append("%d walls placed while FieldPopulation.PLACE_WALLS is false: %s"
                        % (len(walls), walls[:5]))

    if failures:
        print("FAIL:")
        for f in failures:
            print("  - %s" % f)
        return 1

    print("ok: %d cells over %d areas, %d with objects"
          % (cells, len(doc.get("areas", [])), cells_with_objects))
    print("    containers %d, traps %d over %d families (%s)"
          % (containers, traps, len(families), ", ".join(families)))
    print("    every authored position is inside its room (44x44 + 3-unit door stubs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
