#!/usr/bin/env python3
"""Re-anchor load triggers that do not overlap their own doorway.

#617. The gate mesh was moved onto psz-re's measured doorway (#612) while the
load trigger kept deriving from the authored `position` -- deliberately, because
moving `position` itself put the trigger past the end of the doorway stub and
the autopilot walked to the edge and stopped (s01b_tb3, see fix_portal_depth.py).

That protected navigation, but it left the trigger free to sit anywhere relative
to the door it belongs to. Measured across 552 portals with a measured doorway:

    429  trigger reaches the doorway stub          -- fine
    109  trigger past the stub end                 -- unreachable
     14  trigger entirely inside the room          -- fires early

s01b_xb2's north trigger spans 5.2..11.2 while its doorway is at 22.0: the cell
load fires halfway across the room.

WHAT THIS WRITES. A `triggerPosition` per broken portal, the same way
`gatePosition` is a separate measured field rather than a change to `position`.
The engine and validate_graph.mjs both read it, so the geometry lives in the
DATA and is not reimplemented in GDScript, JS and Python -- which is how the
+3/+7 contract came to be stated in three places to begin with.

ONLY BROKEN PORTALS ARE TOUCHED. The 429 that already reach their stub keep the
navigation that was tuned around them; this is the same restraint that split
gatePosition from position rather than moving everything at once.

The matching `exit` waypoint moves with the trigger, or the autopilot would keep
walking to where the trigger used to be -- an orphan the graph validator cannot
see, because it would still be a well-formed pair at the wrong place.
"""
import argparse, json, pathlib

CONFIGS = pathlib.Path(__file__).resolve().parents[3] / "data/stage_configs/unified-stage-configs.json"
DOORWAYS = pathlib.Path(__file__).resolve().parents[3] / "data/re_reference/room_doorways.json"

OUTWARD = {"north": (0, -1), "south": (0, 1), "east": (1, 0), "west": (-1, 0)}
AXIS = {"north": 2, "south": 2, "east": 0, "west": 0}

# The engine's box is Vector3(6, 3, 6), so the trigger reaches 3 either side of
# its centre. A doorway stub runs from the wall out to +3.
TRIGGER_HALF = 3.0
STUB_DEPTH = 3.0
EXIT_OUTSET = 7.0
SPAWN_OUTSET = 3.0
OFFSET_TOL = 1.5


def overlaps_stub(centre_d: float, gate_d: float) -> bool:
    """Does the trigger box reach the doorway stub at all?

    Distances are along the door axis, measured from the room centre, so both
    are positive and 'outward' is increasing.
    """
    near, far = centre_d - TRIGGER_HALF, centre_d + TRIGGER_HALF
    return near <= gate_d + STUB_DEPTH and far >= gate_d


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report, write nothing")
    args = ap.parse_args()

    cfgs = json.loads(CONFIGS.read_text())
    fixed, moved_wp, skipped_no_gate, already_ok = [], 0, 0, 0

    for stage_id, st in cfgs.items():
        if not isinstance(st, dict):
            continue
        for portal in st.get("portals", []):
            direction = str(portal.get("direction", ""))
            pos, gate = portal.get("position"), portal.get("gatePosition")
            if direction not in OUTWARD or not pos:
                continue
            if not gate:
                skipped_no_gate += 1
                continue

            axis = AXIS[direction]
            out = OUTWARD[direction]
            sign = 1.0 if float(gate[axis]) >= 0 else -1.0
            gate_d = abs(float(gate[axis]))

            # Where the trigger IS, which is not always position+7: a portal
            # already re-anchored carries triggerPosition, and reading past it
            # would re-flag it every run and then fail to find the exit node it
            # had itself already moved. Caught by --check being non-idempotent.
            existing = portal.get("triggerPosition")
            centre_d = (abs(float(existing[axis])) if existing
                        else abs(float(pos[axis])) + EXIT_OUTSET)

            if overlaps_stub(centre_d, gate_d):
                already_ok += 1
                continue

            # Centre the trigger in the stub: the box then spans the wall face
            # to 1.5 beyond the stub, so it is entered walking either way
            # through the door and never fires in open floor.
            new_d = gate_d + STUB_DEPTH / 2.0
            trigger = list(pos)
            trigger[axis] = round(sign * new_d, 4)
            trigger[1] = 0.0

            if not args.check:
                portal["triggerPosition"] = trigger

            # The exit waypoint has to follow. It is matched the way
            # validate_graph.mjs matches it -- nearest 'exit' node within
            # OFFSET_TOL of the OLD contract position -- so a hand-nudged node
            # is still found rather than duplicated.
            old = [float(pos[0]) + out[0] * EXIT_OUTSET, 0.0,
                   float(pos[2]) + out[1] * EXIT_OUTSET]
            best, best_d = None, OFFSET_TOL
            for w in st.get("waypoints", []):
                if w.get("kind") != "exit":
                    continue
                wp = w.get("position", [0, 0, 0])
                d = ((wp[0] - old[0]) ** 2 + (wp[2] - old[2]) ** 2) ** 0.5
                if d <= best_d:
                    best, best_d = w, d
            if best is not None:
                if not args.check:
                    best["position"] = [trigger[0], best["position"][1], trigger[2]]
                moved_wp += 1

            fixed.append((stage_id, direction, round(centre_d, 2), round(new_d, 2),
                          best is not None))

    print("portals already reaching their stub: %d" % already_ok)
    print("portals with no measured doorway (left alone): %d" % skipped_no_gate)
    print("portals re-anchored: %d  (exit waypoint moved for %d)" % (len(fixed), moved_wp))
    without = [f for f in fixed if not f[4]]
    if without:
        print("!! %d re-anchored portals had no matching exit node:" % len(without))
        for s, d, _, _, _ in without[:10]:
            print("     %s %s" % (s, d))
    for s, d, was, now, _ in sorted(fixed, key=lambda r: -abs(r[2] - r[3]))[:8]:
        print("   %-12s %-6s trigger %6.2f -> %6.2f" % (s, d, was, now))

    if args.check:
        print("\n--check: nothing written")
        return 1 if fixed else 0

    CONFIGS.write_text(json.dumps(cfgs, indent=2) + "\n")
    print("\nwrote %s" % CONFIGS.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
