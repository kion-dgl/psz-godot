// Graph emitter — solve A* paths between all useful (StagePoint) pairs in a
// stage, union the resulting waypoint sets, then write back to the format
// unified-stage-configs.json expects:
//   stage.waypoints      = [{id, position: [x,0,z], kind, label}]
//   stage.waypointEdges  = [[idA, idB], ...]
//
// Dedup strategy: any new path waypoint within `mergeDist` of an existing one
// is replaced by a reference to the existing one. Without this, every A*
// path adds 5-10 new nodes and the graph explodes.

import type { NavGrid } from "./grid.ts";
import { solvePath } from "./pathfinder.ts";
import type { StagePoint } from "./quest_walk.ts";
import { GraphBuilder } from "./emit_common.ts";
import type { EmittedGraph } from "./emit_common.ts";

export type { EmittedWaypoint, EmittedGraph } from "./emit_common.ts";
export { applyGraphToStageConfig as applyToStageConfig } from "./emit_common.ts";

// Larger than the autopilot's 1.5m arrive radius so waypoints from different
// A* runs (e.g. spawn→spawn and spawn→objective) snap into shared nodes.
// Without sharing, BFS detours through far spawn waypoints to bridge between
// two nearby-but-not-merged interior nodes.
const MERGE_DIST = 2.5;

export function solveStageGraph(
	stageId: string,
	grid: NavGrid,
	points: StagePoint[],
	opts: { mergeDist?: number; decimate?: boolean } = {},
): EmittedGraph {
	const mergeDist = opts.mergeDist ?? MERGE_DIST;
	const decimate = opts.decimate ?? true;

	const builder = new GraphBuilder(stageId, mergeDist);
	// Seed the graph with the StagePoints themselves — the "anchored"
	// waypoints (spawn/exit/objective) that must keep their stable IDs
	// because the autopilot looks them up by kind.
	builder.seed(points);
	const { addEdge, addOrMerge } = builder;

	// Pair every spawn with every other useful point (spawn, exit, objective).
	// Exit-to-exit pairs aren't useful (you don't walk between scene-change
	// triggers). Objective-to-objective is rare but cheap.
	const spawns = points.filter((p) => p.kind === "spawn");
	const exits = points.filter((p) => p.kind === "exit");
	const objectives = points.filter((p) => p.kind === "key_drop" || p.kind === "switch" || p.kind === "telepipe");

	let attempted = 0;
	let failed = 0;
	let solved = 0;

	const trySolve = (a: StagePoint, b: StagePoint) => {
		attempted++;
		const path = solvePath(grid, { x: a.x, z: a.z }, { x: b.x, z: b.z }, { decimate });
		if (!path || path.length < 2) {
			failed++;
			return;
		}
		solved++;
		// Snap first and last waypoints to the anchored StagePoint IDs.
		const ids: string[] = [a.id];
		for (let i = 1; i < path.length - 1; i++) {
			ids.push(addOrMerge(path[i].x, path[i].z));
		}
		ids.push(b.id);
		for (let i = 0; i < ids.length - 1; i++) addEdge(ids[i], ids[i + 1]);
	};

	// spawn ↔ exit through this same portal (gate-into-load straight line).
	// This is the ONLY pair that connects load waypoints into the graph —
	// load is a terminal for "exit the cell" walks, NOT an interior routing
	// point. Routing post-objective back to spawn should use spawn↔objective
	// (which we add below) and then the existing spawn↔exit edge to leave.
	for (let i = 0; i < spawns.length; i++) {
		for (let j = 0; j < exits.length; j++) {
			if (spawns[i].label.replace("spawn ", "") === exits[j].label.replace("load ", "")) {
				trySolve(spawns[i], exits[j]);
			}
		}
	}
	// spawn → other spawn (through-traversal)
	for (let i = 0; i < spawns.length; i++) {
		for (let j = i + 1; j < spawns.length; j++) trySolve(spawns[i], spawns[j]);
	}
	// spawn → objective (and back, same edges) — covers both the pre-objective
	// walk in and the post-objective walk back to any spawn.
	for (const s of spawns) {
		for (const o of objectives) trySolve(s, o);
	}

	return builder.finish({
		stagePoints: points.length,
		pathsAttempted: attempted,
		pathsFailed: failed,
		pathsSolved: solved,
	});
}
