// Recast-based graph emitter. Same shape of output as emit.ts (unique
// waypoints + edges in the format unified-stage-configs.json wants), but the
// per-pair pathfinding is delegated to recast's Detour query so we get
// optimal, smoothed, agent-radius-aware paths.

import type { NavMeshQuery } from "recast-navigation";
import { solvePathRecast, isPointOnNavMesh } from "./recast_solver.ts";
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
const MAX_LEG = 3.0; // re-split recast paths so no autopilot leg exceeds this

export function solveStageGraphRecast(
	stageId: string,
	query: NavMeshQuery,
	points: StagePoint[],
	opts: { mergeDist?: number; maxLeg?: number; lShape?: boolean } = {},
): EmittedGraph {
	const lShape = opts.lShape ?? false;
	const mergeDist = opts.mergeDist ?? MERGE_DIST;
	const maxLeg = opts.maxLeg ?? MAX_LEG;
	const mergeDistSq = mergeDist * mergeDist;

	const waypoints: EmittedWaypoint[] = [];
	const edges = new Set<string>();
	let nextAutoId = 0;

	// Seed graph with the anchored StagePoints (kept by stable ID).
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

	// Convert each diagonal leg into an L-shape: walk axis-aligned first
	// (longest axis), then the perpendicular axis. The autopilot's camera-
	// relative input drifts on diagonals (forward + right press maps to
	// camera basis, not world basis, and the resulting motion accumulates
	// off-axis error). Cardinal walks have no drift. Then re-split each
	// resulting leg to <= maxLeg meters.
	//
	// L-shape corners are only inserted when both corner candidates pass
	// isPointOnNavMesh — otherwise we fall back to the diagonal (which
	// recast guarantees is walkable).
	const axisAlignAndSplit = (path: { x: number; z: number }[]): { x: number; z: number }[] => {
		if (path.length < 2) return path;
		const lShaped: { x: number; z: number }[] = [path[0]];
		for (let i = 1; i < path.length; i++) {
			const a = lShaped[lShaped.length - 1];
			const b = path[i];
			const dx = Math.abs(b.x - a.x);
			const dz = Math.abs(b.z - a.z);
			if (!lShape || dx < 0.5 || dz < 0.5) {
				lShaped.push(b);
				continue;
			}
			// Try both L-corner candidates; pick one that's on the navmesh.
			const cornerA = { x: b.x, z: a.z }; // x-first then z
			const cornerB = { x: a.x, z: b.z }; // z-first then x
			const aOk = isPointOnNavMesh(query, cornerA.x, cornerA.z, 1.0);
			const bOk = isPointOnNavMesh(query, cornerB.x, cornerB.z, 1.0);
			if (aOk && (!bOk || dx >= dz)) {
				lShaped.push(cornerA);
				lShaped.push(b);
			} else if (bOk) {
				lShaped.push(cornerB);
				lShaped.push(b);
			} else {
				// Neither corner is walkable — keep the diagonal.
				lShaped.push(b);
			}
		}
		// Step 2: split long axis-aligned legs.
		const out: { x: number; z: number }[] = [lShaped[0]];
		for (let i = 1; i < lShaped.length; i++) {
			const a = lShaped[i - 1];
			const b = lShaped[i];
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
		const path = solvePathRecast(query, { x: a.x, z: a.z }, { x: b.x, z: b.z });
		if (!path || path.length < 2) {
			failed++;
			return;
		}
		solved++;
		const split = axisAlignAndSplit(path);
		const ids: string[] = [a.id];
		for (let i = 1; i < split.length - 1; i++) {
			ids.push(addOrMerge(split[i].x, split[i].z));
		}
		ids.push(b.id);
		for (let i = 0; i < ids.length - 1; i++) addEdge(ids[i], ids[i + 1]);
	};

	// spawn ↔ exit through the same portal
	for (let i = 0; i < spawns.length; i++) {
		for (let j = 0; j < exits.length; j++) {
			if (spawns[i].label.replace("spawn ", "") === exits[j].label.replace("load ", "")) {
				trySolve(spawns[i], exits[j]);
			}
		}
	}
	// spawn → spawn: route via the junction center if one exists. Otherwise
	// solve direct (covers L-bend, straight, dead-end, and unknown shapes).
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
	// spawn → objective also routes via the junction if one is present.
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

export function applyToStageConfigRecast(
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
