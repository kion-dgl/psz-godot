#!/usr/bin/env python3
"""Snap each stage portal to the DEPTH the game's own doorway sits at.

kion, from play: "we have the original gate positions from the game, can we make
sure those are actually being used? a lot of the gate positions are slightly off
from me trying to hand place them."

Measuring `data/stage_configs/unified-stage-configs.json` against psz-re's
measured doorway segments in `data/re_reference/room_doorways.json` says the
hand-placed portals are in better shape than that suggests, and that exactly one
axis is wrong:

    along the wall   median error 0.11 units  -- already right
    into the room    median error 1.88 units  -- every gate sits inside the wall
                     with a tail: p10 -5.2, worst -20.8

So this rewrites ONLY the depth component and leaves the along-wall coordinate,
the `id`, the `label` and the `direction` untouched. Ids stay stable, which is
what the stage editor and every consumer key on, and the config remains the
single source of truth rather than the runtime reading two tables.

    python3 scripts/tools/refield/fix_portal_depth.py           # write
    python3 scripts/tools/refield/fix_portal_depth.py --check   # report only

THE DIRECTION CONVENTION DIFFERS BETWEEN THE TWO TABLES, and getting it wrong
looks like a placement disaster rather than a mapping bug. psz-re names the -z
wall `south`; psz-godot names it `north`. East and west agree. Measured over 553
portals:

    flip N/S only        553 matched, 0 portals beyond 2 units along the wall
    flip N/S and E/W     491 matched, 85 phantom outliers of +/-32 units

The +/-32 outliers arrived in symmetric east/west pairs (s01b_xb2 west +31.9,
east -31.2), which is the signature of a bad mapping rather than bad authoring.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent.parent
CONFIGS = ROOT / "data" / "stage_configs" / "unified-stage-configs.json"
DOORWAYS = ROOT / "data" / "re_reference" / "room_doorways.json"

# psz-re wall name -> psz-godot portal direction. Only the z axis is renamed.
WALL_FOR_DIRECTION = {
    "north": "south",
    "south": "north",
    "east": "east",
    "west": "west",
}

# A portal further than this from its measured doorway along the wall is not a
# depth problem -- it is a different bug, and this script refuses to touch it.
ALONG_WALL_TOLERANCE = 2.0


def segments_by_wall(entry: dict) -> dict:
    """{wall_name: [[x1, z1], [x2, z2]]} for one room."""
    out: dict = {}
    for seg, wall in zip(entry.get("segments", []), entry.get("walls", [])):
        out.setdefault(str(wall.get("wall", "")), []).append(seg)
    return out


def measured_depth(seg: list, direction: str) -> float:
    """The doorway's INNER end -- the room wall, where a door belongs.

    psz-re measures a doorway as a segment running |22| -> |25|: the wall plane
    and then the stub projecting out of it. The gate goes at the wall, not out
    in the stub, and not 1.9 units back inside the room where it is today.
    """
    (x1, z1), (x2, z2) = seg
    a, b = (abs(z1), abs(z2)) if direction in ("north", "south") else (abs(x1), abs(x2))
    return min(a, b)


# The nav graph hangs off the gate: `scripts/tools/waypoints/validate_graph.mjs`
# requires a `spawn` node exactly SPAWN_OUTSET (3m) outward from each portal and
# an `exit` node at EXIT_OUTSET (7m), joined by an edge. The engine derives the
# player spawn and the scene-change trigger from the same offsets.
#
# So moving a gate without moving its two nodes silently orphans the graph — the
# autopilot would keep navigating to where the door used to be. The web test
# `waypoint-coverage.test.ts` catches it, which is how this was found.
SPAWN_OUTSET = 3.0
EXIT_OUTSET = 7.0
OFFSET_TOL = 1.5  # matches validate_graph.mjs


def shift_portal_waypoints(stage: dict, portal: dict, axis: int, delta: float) -> int:
    """Move this portal's spawn/exit nodes by the same delta. Returns how many."""
    if abs(delta) < 0.005:
        return 0
    pos = portal["position"]
    # Outward is away from the room centre along the axis we just moved.
    sign = 1.0 if pos[axis] >= 0 else -1.0
    moved = 0
    for kind, outset in (("spawn", SPAWN_OUTSET), ("exit", EXIT_OUTSET)):
        # Find the node that WAS at the old offset — i.e. is now off by `delta`.
        want = pos[axis] - delta + sign * outset
        best, best_d = None, OFFSET_TOL
        for wp in stage.get("waypoints", []):
            if str(wp.get("kind")) != kind:
                continue
            wpos = wp.get("position")
            if not wpos:
                continue
            # Same doorway: the along-wall coordinate must match too, or a room
            # with two doors on parallel walls would drag the wrong node.
            other = 0 if axis == 2 else 2
            if abs(wpos[other] - pos[other]) > OFFSET_TOL:
                continue
            d = abs(wpos[axis] - want)
            if d < best_d:
                best, best_d = wp, d
        if best is not None:
            best["position"][axis] = round(best["position"][axis] + delta, 4)
            moved += 1
    return moved


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report the deltas without writing")
    args = ap.parse_args()

    configs = json.loads(CONFIGS.read_text())
    doorways = json.loads(DOORWAYS.read_text()).get("rooms", {})

    moved, skipped_far, no_data = [], [], 0
    waypoints_shifted = 0
    for stage_id, stage in configs.items():
        room = doorways.get(stage_id)
        if room is None:
            no_data += 1
            continue
        walls = segments_by_wall(room)
        for portal in stage.get("portals", []):
            direction = str(portal.get("direction", ""))
            pos = portal.get("position")
            wall = WALL_FOR_DIRECTION.get(direction)
            if not pos or wall not in walls:
                continue
            seg = walls[wall][0]
            (x1, z1), (x2, z2) = seg

            # Guard: only correct depth, and only where the along-wall position
            # already agrees. Anything else is a different problem.
            if direction in ("north", "south"):
                along_err = abs(pos[0] - (x1 + x2) / 2.0)
                axis, current = 2, pos[2]
            else:
                along_err = abs(pos[2] - (z1 + z2) / 2.0)
                axis, current = 0, pos[0]
            if along_err > ALONG_WALL_TOLERANCE:
                skipped_far.append((stage_id, direction, round(along_err, 2)))
                continue

            target = measured_depth(seg, direction)
            wanted = target if current >= 0 else -target
            if abs(wanted - current) < 0.005:
                continue
            moved.append((stage_id, direction, round(current, 2), round(wanted, 2)))
            if not args.check:
                delta = round(wanted, 4) - pos[axis]
                pos[axis] = round(wanted, 4)
                waypoints_shifted += shift_portal_waypoints(stage, portal, axis, delta)

    deltas = [abs(w - c) for _, _, c, w in moved]
    print("stages with measured doorways: %d (no data for %d)"
          % (len(configs) - no_data, no_data))
    print("portals moved: %d (waypoint nodes carried along: %d)"
          % (len(moved), waypoints_shifted))
    if deltas:
        deltas.sort()
        print("  depth shift: median %.2f  p90 %.2f  max %.2f"
              % (statistics.median(deltas), deltas[int(0.9 * len(deltas))], deltas[-1]))
    if skipped_far:
        print("  SKIPPED %d portal(s) more than %.1f units off ALONG the wall — "
              "those are a placement problem, not a depth one:"
              % (len(skipped_far), ALONG_WALL_TOLERANCE))
        for s in skipped_far[:5]:
            print("    %-14s %-6s off by %.2f" % s)

    if args.check:
        print("--check: nothing written")
        return 0

    # ensure_ascii=False, because the file carries literal em dashes in its
    # `reason` strings; escaping them would put 55k lines of noise in the diff
    # and bury the 552 positions this actually changes.
    CONFIGS.write_text(json.dumps(configs, indent=2, ensure_ascii=False) + "\n")
    print("wrote %s" % CONFIGS.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
