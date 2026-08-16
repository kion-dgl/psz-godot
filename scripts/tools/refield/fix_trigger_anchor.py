#!/usr/bin/env python3
"""Align every portal's spawn and trigger to its measured gate.

#617, following #612. The three points of a portal -- gate, spawn, trigger --
are one line: same lateral position, same axis, fixed distances apart, in that
order going outward. kion authored them that way by hand. #612 moved the gate
onto psz-re's measured doorway and left the other two on the old `position`, so
the line broke wherever the gate moved.

THE SPACING IS NOT INVENTED, it is what the existing portals already are. Over
all 552 portals with a measured doorway:

    gate -> spawn     median 1.12   p25 0.43   p75 1.79
    gate -> trigger   median 5.12   p25 4.43   p75 5.79

An interquartile spread of ~1.4 units across 552 hand-placed portals is a
pattern, not a coincidence -- the outliers (as far as -17.8) are the ones the
gate move stranded. So the rule is the median, applied to everything, and most
portals barely move because their gate barely moved.

WHY UNIFORM RATHER THAN ONLY-THE-BROKEN-ONES. Two earlier attempts tried to fix
just the portals that looked wrong, using the doorway stub to decide which those
were. Both were refuted: a trigger past the stub is NOT necessarily unreachable
(s05b_nc2 worked for years at 3 units past it), and a trigger inside the room is
not necessarily wrong. The stub cannot tell a good portal from a bad one. One
line with fixed spacing can, because it is the thing that was true before the
gate moved.

WHAT THIS CANNOT FIX. 25 portals had their gate move more than 8 units, which
means psz-godot's floor and psz-re's measured doorway disagree about where the
door is. Aligning the line there just puts all three points in the same wrong
place -- s02a_sa1 moved 16.3 units and the autopilot walks into a wall at the
gate. Those are a geometry question, and this prints them rather than pretending
the spacing fixed them.
"""
import argparse, json, pathlib

CONFIGS = pathlib.Path(__file__).resolve().parents[3] / "data/stage_configs/unified-stage-configs.json"

OUTWARD = {"north": (0, -1), "south": (0, 1), "east": (1, 0), "west": (-1, 0)}
AXIS = {"north": 2, "south": 2, "east": 0, "west": 0}

# The measured medians above. Distances outward from the gate, along the door
# axis. Spawn first, then trigger, so a player leaving a room crosses the spawn
# and then fires the trigger, and a player arriving lands short of the trigger
# rather than inside it (which is what stranded the_paru_pact).
SPAWN_FROM_GATE = 1.1
TRIGGER_FROM_GATE = 5.1

# Engine offsets the nodes were authored at, used only to FIND the existing
# waypoint so a hand-nudged one is moved rather than duplicated.
SPAWN_OUTSET = 3.0
EXIT_OUTSET = 7.0
OFFSET_TOL = 1.5

# A gate that moved further than this means the stage geometry and the measured
# doorway disagree about where the door is. Aligning the line cannot help.
GEOMETRY_SUSPECT = 8.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report, write nothing")
    args = ap.parse_args()

    cfgs = json.loads(CONFIGS.read_text())
    aligned, unchanged, no_gate, suspect, nodes_moved = 0, 0, 0, [], 0
    biggest = []

    for stage_id, st in cfgs.items():
        if not isinstance(st, dict):
            continue
        for portal in st.get("portals", []):
            direction = str(portal.get("direction", ""))
            pos, gate = portal.get("position"), portal.get("gatePosition")
            if direction not in OUTWARD or not pos:
                continue
            if not gate:
                no_gate += 1
                continue

            axis = AXIS[direction]
            out = OUTWARD[direction]
            gate_v = float(gate[axis])
            sign = 1.0 if gate_v >= 0 else -1.0

            # ONE LINE. Lateral coordinates come from the GATE, not from the old
            # position, so all three points sit on the doorway's own axis rather
            # than being merely parallel to it.
            def point_at(dist):
                p = list(gate)
                p[axis] = round(gate_v + sign * dist, 4)
                p[1] = 0.0
                return p

            spawn_pt = point_at(SPAWN_FROM_GATE)
            trigger = point_at(TRIGGER_FROM_GATE)

            # `out` is (x, z); the door axis is 0 or 2 in a 3-vector, so map it.
            oi = 0 if axis == 0 else 1
            moved = max(
                abs(float(pos[axis]) + SPAWN_OUTSET * out[oi] - spawn_pt[axis]),
                abs(float(pos[axis]) + EXIT_OUTSET * out[oi] - trigger[axis]),
            )

            gate_move = abs(gate_v - float(pos[axis]))
            if gate_move > GEOMETRY_SUSPECT:
                suspect.append((stage_id, direction, round(gate_move, 1)))

            if not args.check:
                portal["spawnPosition"] = spawn_pt
                portal["triggerPosition"] = trigger

            if moved < 0.5:
                unchanged += 1
            else:
                aligned += 1
                biggest.append((moved, stage_id, direction))

            def move_node(kind, outset, dest):
                old = [float(pos[0]) + out[0] * outset, 0.0,
                       float(pos[2]) + out[1] * outset]
                best, best_d = None, OFFSET_TOL
                for w in st.get("waypoints", []):
                    if w.get("kind") != kind:
                        continue
                    wp = w.get("position", [0, 0, 0])
                    d = ((wp[0] - old[0]) ** 2 + (wp[2] - old[2]) ** 2) ** 0.5
                    if d <= best_d:
                        best, best_d = w, d
                if best is not None and not args.check:
                    best["position"] = [dest[0], best["position"][1], dest[2]]
                return best is not None

            if move_node("exit", EXIT_OUTSET, trigger):
                nodes_moved += 1
            move_node("spawn", SPAWN_OUTSET, spawn_pt)

    print("portals aligned to their gate:      %d" % (aligned + unchanged))
    print("  of those, moved < 0.5 units:      %d  (already on the line)" % unchanged)
    print("  meaningfully repositioned:        %d" % aligned)
    print("portals with no measured doorway:   %d  (left alone)" % no_gate)
    print("waypoint pairs moved:               %d" % nodes_moved)

    biggest.sort(reverse=True)
    print("\nlargest repositions:")
    for d, s, dr in biggest[:8]:
        print("   %-12s %-6s %5.1f units" % (s, dr, d))

    if suspect:
        print("\nGEOMETRY SUSPECTS -- gate moved > %.0f units, so psz-godot's floor and" % GEOMETRY_SUSPECT)
        print("psz-re's doorway disagree. Aligning the line cannot fix these:")
        for s, dr, m in sorted(suspect, key=lambda r: -r[2])[:12]:
            print("   %-12s %-6s gate moved %5.1f" % (s, dr, m))
        print("   (%d total)" % len(suspect))

    if args.check:
        print("\n--check: nothing written")
        return 0

    CONFIGS.write_text(json.dumps(cfgs, indent=2) + "\n")
    print("\nwrote %s" % CONFIGS.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
