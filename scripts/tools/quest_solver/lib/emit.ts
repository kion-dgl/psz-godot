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
import type { Tri2D } from "./floor.ts";
import { solvePath } from "./pathfinder.ts";
import type { StagePoint } from "./quest_walk.ts";

export interface EmittedWaypoint {
	id: string;
	position: [number, number, number];
	kind: string;
	label?: string;
}

export interface EmittedGraph {
	waypoints: EmittedWaypoint[];
	waypointEdges: [string, string][];
	stats: {
		stagePoints: number;
		pathsAttempted: number;
		pathsFailed: number;
		pathsSolved: number;
		uniqueWaypoints: number;
		edges: number;
	};
}

const MERGE_DIST = 1.5;

export function solveStageGraph(
	stageId: string,
	grid: NavGrid,
	points: StagePoint[],
	opts: { mergeDist?: number; decimate?: boolean } = {},
): EmittedGraph {
	const mergeDist = opts.mergeDist ?? MERGE_DIST;
	const decimate = opts.decimate ?? true;
	const mergeDistSq = mergeDist * mergeDist;

	const waypoints: EmittedWaypoint[] = [];
	const edges = new Set<string>();
	let nextAutoId = 0;

	// First pass: seed the graph with the StagePoints themselves. These are
	// the "anchored" waypoints (spawn/exit/objective) that must keep their
	// stable IDs because the autopilot looks them up by kind.
	for (const p of points) {
		waypoints.push({ id: p.id, position: [p.x, 0, p.z], kind: p.kind, label: p.label });
	}

	const addEdge = (a: string, b: string) => {
		if (a === b) return;
		const k = a < b ? `${a}|${b}` : `${b}|${a}`;
		edges.add(k);
	};

	const addOrMerge = (x: number, z: number): string => {
		// Find any existing waypoint within mergeDist; if so, snap to it.
		for (const w of waypoints) {
			const dx = w.position[0] - x;
			const dz = w.position[2] - z;
			if (dx * dx + dz * dz < mergeDistSq) return w.id;
		}
		const id = `wp_auto_${nextAutoId++}_${stageId}`;
		waypoints.push({ id, position: [x, 0, z], kind: "point" });
		return id;
	};

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

	return {
		waypoints,
		waypointEdges: [...edges].map((k) => k.split("|") as [string, string]),
		stats: {
			stagePoints: points.length,
			pathsAttempted: attempted,
			pathsFailed: failed,
			pathsSolved: solved,
			uniqueWaypoints: waypoints.length,
			edges: edges.size,
		},
	};
}

/**
 * Merge an emitted graph into the existing unified-stage-configs entry.
 * Returns the new config block (caller writes it back to disk).
 */
export function applyToStageConfig(
	existing: any,
	graph: EmittedGraph,
): any {
	const next = { ...existing };
	next.waypoints = graph.waypoints.map((w) => ({
		id: w.id,
		position: w.position,
		kind: w.kind,
		...(w.label ? { label: w.label } : {}),
	}));
	next.waypointEdges = graph.waypointEdges;
	return next;
}
