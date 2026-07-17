// Manhattan grid emit — same shape of output as emit_recast (a graph of
// waypoints + edges in unified-stage-configs.json's format), but the
// per-pair pathfinding is the 4-connected Manhattan A* in manhattan.ts.
// Produces axis-aligned waypoint chains (paths bend at 90° corners), which
// the autopilot's camera-relative input can drive without drift.

import type { NavGrid } from "./grid.ts";
import { solveManhattan } from "./manhattan.ts";
import type { StagePoint } from "./quest_walk.ts";
import type { Tri2D } from "./floor.ts";
import { pointInTriangle } from "./floor.ts";
import { GraphBuilder } from "./emit_common.ts";
import type { EmittedGraph } from "./emit_common.ts";

export type { EmittedWaypoint, EmittedGraph } from "./emit_common.ts";
export { applyGraphToStageConfig as applyToStageConfigManhattan } from "./emit_common.ts";

// MERGE_DIST collapses path corners onto existing waypoints if they're
// closer than this. Keep it BELOW the grid resolution so we don't eat
// real axis-aligned bend corners (e.g. an L-bend that lands 2m from a
// spawn waypoint — losing the corner turns a Manhattan path into a
// diagonal one, which the autopilot's camera-relative input can't walk
// without drifting into walls).
const MERGE_DIST = 0.9;
const MAX_LEG = 6.0;

export function solveStageGraphManhattan(
	stageId: string,
	grid: NavGrid,
	points: StagePoint[],
	opts: {
		mergeDist?: number;
		maxLeg?: number;
		preSwitchGrid?: NavGrid;
		/** Real floor triangles. When set, every solved path is sampled at
		 *  `floorSampleStep` meters and any sample that lands off-floor causes
		 *  the path to be rejected. This catches the "grid said walkable, but
		 *  the actual floor mesh has a hole" case — the solver was emitting
		 *  edges that cut through floor voids the grid clearance missed. */
		floorTriangles?: Tri2D[];
		floorSampleStep?: number;
	} = {},
): EmittedGraph {
	const mergeDist = opts.mergeDist ?? MERGE_DIST;
	const maxLeg = opts.maxLeg ?? MAX_LEG;
	// preSwitchGrid is the variant with closed fences stamped as obstacles.
	// If absent we just route everything against the open grid (stages with
	// no fences have nothing to vary). Spawn→switch and spawn↔spawn run on
	// preSwitchGrid (conservative — assume the fence is still up); spawn↔exit
	// and switch→exit run on the open grid (semantically, you only leave a
	// fenced cell after activating the switch).
	const preGrid = opts.preSwitchGrid ?? grid;
	const floor = opts.floorTriangles;
	const floorStep = opts.floorSampleStep ?? 0.25;

	/** Walk a polyline at floorStep and verify every sample sits on a floor
	 *  triangle. Returns the first off-floor sample, or null if the whole
	 *  polyline is on floor. */
	const validateFloorCoverage = (corners: { x: number; z: number }[]): { x: number; z: number } | null => {
		if (!floor || floor.length === 0) return null;
		for (let i = 0; i < corners.length - 1; i++) {
			const a = corners[i];
			const b = corners[i + 1];
			const len = Math.hypot(b.x - a.x, b.z - a.z);
			const steps = Math.max(1, Math.ceil(len / floorStep));
			for (let s = 0; s <= steps; s++) {
				const t = s / steps;
				const sx = a.x + (b.x - a.x) * t;
				const sz = a.z + (b.z - a.z) * t;
				let on = false;
				for (let ti = 0; ti < floor.length; ti++) {
					if (pointInTriangle(sx, sz, floor[ti])) { on = true; break; }
				}
				if (!on) return { x: sx, z: sz };
			}
		}
		return null;
	};

	const builder = new GraphBuilder(stageId, mergeDist);
	builder.seed(points);
	const { addEdge, addOrMerge } = builder;

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

	const trySolve = (a: StagePoint, b: StagePoint, g: NavGrid) => {
		attempted++;
		const path = solveManhattan(g, { x: a.x, z: a.z }, { x: b.x, z: b.z });
		if (!path || path.length < 2) {
			failed++;
			return;
		}
		const split = splitLong(path);
		// Floor-coverage validation: the grid said this path is walkable, but
		// clearance erosion at 1m+ resolutions can miss floor voids smaller
		// than the grid cell. Sample the polyline against actual floor
		// triangles and reject if any sample is off-floor. Rejected paths
		// don't get an edge — the autopilot's BFS will find a longer route
		// (e.g. backtrack via the spawn-side waypoints).
		const offFloor = validateFloorCoverage(split);
		if (offFloor) {
			failed++;
			return;
		}
		solved++;
		const ids: string[] = [a.id];
		for (let i = 1; i < split.length - 1; i++) {
			ids.push(addOrMerge(split[i].x, split[i].z));
		}
		ids.push(b.id);
		for (let i = 0; i < ids.length - 1; i++) addEdge(ids[i], ids[i + 1]);
	};

	// spawn ↔ exit through the same portal. Open grid: this is the natural
	// in/out of a cell; if the fence happens to sit on this portal the
	// solver will still find a route once the switch is hit.
	for (let i = 0; i < spawns.length; i++) {
		for (let j = 0; j < exits.length; j++) {
			if (spawns[i].label.replace("spawn ", "") === exits[j].label.replace("load ", "")) {
				trySolve(spawns[i], exits[j], grid);
			}
		}
	}
	// spawn → spawn via junction center if hinted. Pre-switch grid: when
	// you walk from one portal to another within the cell, the fence is
	// still closed (you haven't hit the switch yet).
	for (let i = 0; i < spawns.length; i++) {
		for (let j = i + 1; j < spawns.length; j++) {
			if (vias.length > 0) {
				for (const v of vias) {
					trySolve(spawns[i], v, preGrid);
					trySolve(v, spawns[j], preGrid);
				}
			} else {
				trySolve(spawns[i], spawns[j], preGrid);
			}
		}
	}
	// spawn → objective via junction. Pre-switch grid: you walk to the
	// switch BEFORE the fence opens, so closed-fence cells are obstacles.
	for (const s of spawns) {
		for (const o of objectives) {
			if (vias.length > 0) {
				for (const v of vias) {
					trySolve(s, v, preGrid);
					trySolve(v, o, preGrid);
				}
			} else {
				trySolve(s, o, preGrid);
			}
		}
	}
	// switch → exit (open grid). After the switch is hit the fence opens,
	// so the post-switch leg uses the open grid. We only need this edge
	// when the spawn↔exit and spawn→switch routes don't already chain
	// through the same waypoints — but emitting it is cheap and covers
	// the case where the switch and the natural spawn→exit route diverge.
	const switches = objectives.filter((p) => p.kind === "switch");
	for (const sw of switches) {
		for (const ex of exits) {
			trySolve(sw, ex, grid);
		}
	}

	return builder.finish({
		stagePoints: points.length,
		pathsAttempted: attempted,
		pathsFailed: failed,
		pathsSolved: solved,
	});
}
