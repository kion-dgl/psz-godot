# Authoring waypoint graphs for the autopilot

**tl;dr** — `npm run wp:todo` for the worklist, author in the stage editor,
hit **Save to Disk**, `npm run wp:baseline` when you've done a batch.

The autopilot walks each field stage through a hand-authored nav graph stored
in `data/stage_configs/unified-stage-configs.json` under the stage's
`waypoints` / `waypointEdges`. Rooms without one are why the autopilot fails:
it prints

```
[sanity] FAIL: walk stuck at dist=… in cell … — author waypoints for this stage
```

Free-roam generates fields per run (#582), so the autopilot can land in *any*
room of an area rather than the fixed set a static field used. A room with no
graph is a coin-flip failure, not a latent gap — hence the coverage push in
issue #583.

## The loop

Start the dev server (`npm --prefix web run dev`) and get the worklist:

```bash
npm run wp:todo                    # what's left, with editor URLs
```

Then for each room:

1. Open its URL — `http://localhost:5173/psz-godot/#/stage-editor?stage=<id>`.
   Note the `/psz-godot/` base path; without it the SPA serves a blank page.
   Give the stage GLB a moment — the Floor tab reads 0 triangles until it lands.
2. **Waypoints tab → "Seed from gates + spawn."** This drops the per-portal
   `spawn` (3m outward from the gate) and `exit` (7m outward, on the
   scene-change trigger) nodes and joins each pair. Don't hand-place these —
   the offsets are an engine contract and `wp:check` enforces them.
3. **"+ Place waypoints"** and click the floor to lay interior points along
   the walkable backbone — corridor centers, the corner of an L-bend, the
   middle of a T/X junction. Corners matter more than density: an edge means
   "the player can walk this straight line," so a graph that only cuts
   diagonals across a room will wedge on walls.
4. **"Auto-connect (raycast floor)"** links every pair whose straight segment
   stays over included floor, up to 45m apart. Click a node then another to
   add or remove an edge by hand where the raycast is too permissive or too
   strict. Seeding alone is never enough: on a room whose two gates are more
   than 45m apart, auto-connect leaves the spawns in separate components.
5. **Capsule sim** — pick a From/To and run it to watch a sphere walk the BFS
   path, checking floor presence each step. Cheaper than an autopilot run.
6. **"Save to Disk."** This writes straight into
   `data/stage_configs/unified-stage-configs.json` via the dev server, and the
   confirmation reports what the validator makes of the graph:

   ```
   Saved to disk: s02b_ib1

   Waypoint graph:
   ✗ unreachable from spawn south: spawn north, load north
   ```

   The save always lands — a half-authored room is a fine thing to persist —
   so treat an `✗` as "come back to this one," not as a failed save.

Editing against GitHub Pages, or on a machine that isn't the repo checkout,
means there's no dev server to save through. Use **"Copy JSON"** in the
Waypoints tab and merge from the terminal instead:

```bash
npm run wp:paste                   # reads the clipboard
npm run wp:apply -- ~/Downloads/s02b_ib1-config.json
```

Unlike Save to Disk, these *refuse* to write a graph that fails validation
(`--force` overrides), and print the next room's URL when they're done.

### Gates that are meant to be unreachable

`s02b_lb3`'s south gate sits across a broken bridge — visible from the room,
deliberately not crossable. Its spawn/exit pair exists so the gate reads
correctly, but nothing routes to it, which the all-gates-reachable rule would
otherwise call a bug. Declare it on the stage:

```json
"waypointExceptions": {
  "unreachable": ["south"],
  "reason": "Broken bridge — visible across the gap but intentionally not traversable."
}
```

The excused gate still has to carry a spawn and exit at the contract offsets,
joined to each other; it is only exempt from being reachable from the other
gates. Naming a direction the stage has no portal for is an error, so a typo
can't quietly excuse a real gap.

### Room shapes don't transplant between areas

Tempting shortcut, doesn't work. `s02b_xb2` and `s04a_xb2` share a room *type*
(the four-way junction) but not a footprint — their portals sit at different
offsets along each wall, and the meshes differ. A graph copied from another
area lands off the floor. Every room is its own authoring job.

### Boss arenas

The eight `*z_na1` / `s087_na1` rooms have **no portals** — "Seed from gates"
only drops a node on `defaultSpawn`. Author them like `s03z_na1`, the one that
already works: a ring of ~15 interior points around the arena floor plus the
default spawn, auto-connected into a near-complete graph so the autopilot can
reach the boss from anywhere it gets knocked back to.

## Checking coverage

```bash
npm run wp:check                   # validate every committed graph
npm run wp:check -- --stage s02b_ib1
npm run wp:baseline                # record progress after a batch
```

`wp:check` enforces the conventions every one of the already-authored stages
satisfies:

- each portal has its `spawn` (3m out) and `exit` (7m out) node, joined by an edge
- no isolated nodes; no edges referencing nodes that don't exist
- every spawn and exit is reachable from every other one, except gates the
  stage declares unreachable on purpose (see above)
- portal-less arenas carry a spawn on `defaultSpawn`

One thing it cannot catch: a portal whose `direction` is wrong is
*self-consistently* wrong, because the expected spawn/exit offsets are derived
from that same direction. `s02b_lb3` shipped with its east gate labelled
`west`, which put both nodes inside the room, and every graph check passed.
Only the floor geometry gives it away — probe outward from the gate and a
correct direction stays on floor at +3m and +7m then leaves it, while a
reversed one re-enters the room body further out.

`data/stage_configs/waypoint_coverage_baseline.json` records the outstanding
debt — rooms not yet authored, plus graphs that exist but violate the
contract. `web/src/__tests__/waypoint-coverage.test.ts` fails CI if either
list grows, or if the baseline still lists a room that has since been fixed.
Run `npm run wp:baseline` after each batch to shrink it; that diff *is* the
progress report.

## Verifying for real

Coverage is a precondition, not a pass. Once an area is fully authored, run
the autopilot through it (see CLAUDE.md, "Run autopilot") and confirm
`[sanity] DONE ok` — `wp:check` proves the graph is well-formed and connected,
not that the geometry it describes is walkable in-engine.
