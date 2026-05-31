// Manhattan grid emit — same shape of output as emit_recast (a graph of
// waypoints + edges in unified-stage-configs.json's format), but the
// per-pair pathfinding is the 4-connected Manhattan A* in manhattan.ts.
// Produces axis-aligned waypoint chains (paths bend at 90° corners), which
// the autopilot's camera-relative input can drive without drift.

import type { NavGrid } from "./grid.ts";
import { solveManhattan } from "./manhattan.ts";
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

const MERGE_DIST = 2.5;
const MAX_LEG = 6.0;

export function solveStageGraphManhattan(
	stageId: string,
	grid: NavGrid,
	points: StagePoint[],
	opts: { mergeDist?: number; maxLeg?: number } = {},
): EmittedGraph {
	const mergeDist = opts.mergeDist ?? MERGE_DIST;
	const maxLeg = opts.maxLeg ?? MAX_LEG;
	const mergeDistSq = mergeDist * mergeDist;

	const waypoints: EmittedWaypoint[] = [];
	const edges = new Set<string>();
	let nextAutoId = 0;

	for (const p of points) {
		waypoints.push({ id: p.id, position: [p.x, 0, p.z], kind: p.kind, label: p.label });
	}

	const addEdge = (a: string, b: string) => {
		if (a === b) return;
		const k = a < b ? `${a}|${b}` : `${b}|${a}`;
		edges.add(k);
	};

	const addOrMerge = (x: number, z: number): string => {
		for (const w of waypoints) {
			const dx = w.position[0] - x;
			const dz = w.position[2] - z;
			if (dx * dx + dz * dz < mergeDistSq) return w.id;
		}
		const id = `wp_auto_${nextAutoId++}_${stageId}`;
		waypoints.push({ id, position: [x, 0, z], kind: "point" });
		return id;
	};

	// Manhattan paths are already axis-aligned. Re-split any leg longer
	// than maxLeg so the autopilot has frequent direction-correction
	// waypoints even on long straight corridors.
	const splitLong = (path: { x: number; z: number }[]): { x: number; z: number }[] => {
		if (path.length < 2) return path;
		const out: { x: number; z: number }[] = [path[0]];
		for (let i = 1; i < path.length; i++) {
			const a = path[i - 1];
			const b = path[i];
			const dist = Math.hypot(b.x - a.x, b.z - a.z);
			if (dist <= maxLeg) {
				out.push(b);
				continue;
			}
			const n = Math.ceil(dist / maxLeg);
			for (let k = 1; k <= n; k++) {
				const t = k / n;
				out.push({ x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t });
			}
		}
		return out;
	};

	const spawns = points.filter((p) => p.kind === "spawn");
	const exits = points.filter((p) => p.kind === "exit");
	const objectives = points.filter((p) => p.kind === "key_drop" || p.kind === "switch" || p.kind === "telepipe");
	const vias = points.filter((p) => p.kind === "via");

	let attempted = 0;
	let failed = 0;
	let solved = 0;

	const trySolve = (a: StagePoint, b: StagePoint) => {
		attempted++;
		const path = solveManhattan(grid, { x: a.x, z: a.z }, { x: b.x, z: b.z });
		if (!path || path.length < 2) {
			failed++;
			return;
		}
		solved++;
		const split = splitLong(path);
		const ids: string[] = [a.id];
		for (let i = 1; i < split.length - 1; i++) {
			ids.push(addOrMerge(split[i].x, split[i].z));
		}
		ids.push(b.id);
		for (let i = 0; i < ids.length - 1; i++) addEdge(ids[i], ids[i + 1]);
	};

	// spawn ↔ exit through the same portal.
	for (let i = 0; i < spawns.length; i++) {
		for (let j = 0; j < exits.length; j++) {
			if (spawns[i].label.replace("spawn ", "") === exits[j].label.replace("load ", "")) {
				trySolve(spawns[i], exits[j]);
			}
		}
	}
	// spawn → spawn via junction center if hinted.
	for (let i = 0; i < spawns.length; i++) {
		for (let j = i + 1; j < spawns.length; j++) {
			if (vias.length > 0) {
				for (const v of vias) {
					trySolve(spawns[i], v);
					trySolve(v, spawns[j]);
				}
			} else {
				trySolve(spawns[i], spawns[j]);
			}
		}
	}
	// spawn → objective via junction.
	for (const s of spawns) {
		for (const o of objectives) {
			if (vias.length > 0) {
				for (const v of vias) {
					trySolve(s, v);
					trySolve(v, o);
				}
			} else {
				trySolve(s, o);
			}
		}
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

export function applyToStageConfigManhattan(existing: any, graph: EmittedGraph): any {
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
