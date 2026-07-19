// Shared emit scaffolding for the three graph emitters (emit.ts,
// emit_manhattan.ts, emit_recast.ts). They differ only in the per-pair
// pathfinder and the file-specific path post-processing; the waypoint/edge
// bookkeeping and the unified-stage-configs.json write-back are identical.

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

/**
 * Accumulates the waypoint set + edge set for one stage graph.
 *
 * Seeds with the anchored StagePoints (kept by stable ID), then interior path
 * waypoints are folded in via `addOrMerge` (snap to any existing node within
 * mergeDist) and connected with `addEdge`. `finish` produces the EmittedGraph.
 */
export class GraphBuilder {
	readonly waypoints: EmittedWaypoint[] = [];
	private readonly edges = new Set<string>();
	private nextAutoId = 0;
	private readonly mergeDistSq: number;

	constructor(
		private readonly stageId: string,
		mergeDist: number,
	) {
		this.mergeDistSq = mergeDist * mergeDist;
	}

	/** Seed the graph with the anchored StagePoints (stable IDs). */
	seed(points: StagePoint[]): void {
		for (const p of points) {
			this.waypoints.push({ id: p.id, position: [p.x, 0, p.z], kind: p.kind, label: p.label });
		}
	}

	// Arrow properties so destructured `const { addEdge, addOrMerge } = builder`
	// keeps its binding when passed around the emitter's inner closures.
	addEdge = (a: string, b: string): void => {
		if (a === b) return;
		const k = a < b ? `${a}|${b}` : `${b}|${a}`;
		this.edges.add(k);
	};

	addOrMerge = (x: number, z: number): string => {
		// Find any existing waypoint within mergeDist; if so, snap to it.
		for (const w of this.waypoints) {
			const dx = w.position[0] - x;
			const dz = w.position[2] - z;
			if (dx * dx + dz * dz < this.mergeDistSq) return w.id;
		}
		const id = `wp_auto_${this.nextAutoId++}_${this.stageId}`;
		this.waypoints.push({ id, position: [x, 0, z], kind: "point" });
		return id;
	};

	finish(counts: {
		stagePoints: number;
		pathsAttempted: number;
		pathsFailed: number;
		pathsSolved: number;
	}): EmittedGraph {
		return {
			waypoints: this.waypoints,
			waypointEdges: [...this.edges].map((k) => k.split("|") as [string, string]),
			stats: {
				stagePoints: counts.stagePoints,
				pathsAttempted: counts.pathsAttempted,
				pathsFailed: counts.pathsFailed,
				pathsSolved: counts.pathsSolved,
				uniqueWaypoints: this.waypoints.length,
				edges: this.edges.size,
			},
		};
	}
}

/**
 * Merge an emitted graph into the existing unified-stage-configs entry.
 * Returns the new config block (caller writes it back to disk).
 */
export function applyGraphToStageConfig(existing: any, graph: EmittedGraph): any {
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
