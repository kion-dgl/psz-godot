# Quest solver

Generates autopilot waypoint graphs by raycasting against each stage's floor
GLB and running A* between every pair of useful positions (portal spawns,
exits, key drops, switches, telepipe spawn points). The output is a drop-in
replacement for the hand-authored `waypoints` / `waypointEdges` blocks in
`data/stage_configs/unified-stage-configs.json`.

## Why

Hand-authoring per-stage graphs is N stages × ~15 minutes each. Each cell in
a quest plan needs a graph that lets the autopilot reach every spawn and
every objective from every other spawn. The solver replaces the manual work
with a 2-second offline pass.

## Usage

```sh
# Dry run — writes to unified-stage-configs.solver.<quest>.json
bun scripts/tools/quest_solver/solve_quest.ts the_paru_pact

# Single stage debug
bun scripts/tools/quest_solver/solve_quest.ts the_paru_pact --stage s05b_ic1

# Apply to the in-game file
bun scripts/tools/quest_solver/solve_quest.ts the_paru_pact --apply

# Tuning knobs
bun scripts/tools/quest_solver/solve_quest.ts <quest> --resolution 0.5 --clearance 1.0
```

## Pipeline

1. **Quest plan** (`data/quest_plans/<id>.json`) is parsed for the set of stage IDs
   used and the per-cell objectives (key drops, switches, dialog triggers
   with `telepipe` action).
2. **Floor triangles** from `<stage>-floor.glb` are extracted via a built-in
   GLB binary parser (no deps — DataView on the magic-prefixed buffer). The
   per-stage `floorCollision` filter (`tri_N: false`) is applied to match
   in-game collision exactly.
3. **Nav grid** is sampled at 0.5m XZ resolution. A cell is walkable if its
   center sits inside any floor triangle. Walls are dilated by 1.0m
   Chebyshev clearance, but only from "real" walls (non-walkable cells with
   at least one walkable 4-neighbor) — not from the void surrounding the
   stage's AABB.
4. **A\*** runs between every spawn↔spawn, spawn↔objective, and
   objective↔exit pair, with diagonal-cut-corner prevention.
5. **Decimation** is line-of-sight greedy, capped at ~6m per leg. The cap is
   the autopilot's tolerance for camera-relative drift (it drifts ~20%
   off-axis per meter, so longer legs miss the next waypoint).
6. **Emission** unions all path waypoints, dedupes within 1.5m, and writes
   the graph back to the same shape the autopilot already consumes.

## Status (2026-05-31)

Solver structure is complete and runs in ~1s per 20-stage quest. **Path
quality** still under tuning — the autopilot completes more cells than with
no graph but doesn't yet match the hand-authored success rate on
search-and-rescue end-to-end. The two known issues:

1. **`-floor.glb` doesn't fully match in-game collision.** Some stages (e.g.
   `s01b_ic1`) have an intentionally-incomplete floor.glb where the player
   still walks across (the bridge). The solver falls back to `_m.glb` when
   floor-only A\* fails, but the visual mesh includes terrain the player
   can't reach, so the solver sometimes finds diagonal shortcuts that hit
   walls in-game.
2. **Decimation is too aggressive in spots.** Even with the 6m leg cap,
   a 6m diagonal leg through a turn can clip a wall corner. Probably needs
   per-edge midpoint walkability check before accepting a leg.

The next iteration should address (1) by either extracting wall meshes from
`_m.glb` and treating them as obstacles, or by switching to a real navmesh
built from the floor triangle adjacency graph (no XZ projection).

## Files

- `solve_quest.ts` — CLI entry point
- `lib/glb.ts` — binary GLB parser
- `lib/floor.ts` — floor triangle loader + filter + point-in-triangle
- `lib/grid.ts` — XZ nav grid + clearance dilation
- `lib/pathfinder.ts` — A\* + line-of-sight decimation
- `lib/quest_walk.ts` — quest plan parsing + per-stage point enumeration
- `lib/emit.ts` — multi-pair A\* solve + graph emission with dedup
