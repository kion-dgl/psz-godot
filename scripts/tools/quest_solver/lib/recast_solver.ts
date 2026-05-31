// Recast-navigation based solver. Wraps recast-navigation-js (the WASM port
// of the C++ Recast & Detour library used by Godot/Unity/Unreal) to replace
// our hand-rolled grid + A* + clearance code.
//
// What this gives us over the grid solver:
//   • The agent radius is baked into the navmesh construction so paths
//     naturally stay clear of walls without our "wallClearance" hacks.
//   • The walkable-slope cutoff (45°) classifies floors vs walls correctly
//     using actual 3D normals, not our normal.y heuristic on the projected
//     triangles.
//   • Detour's funnel algorithm returns smoothed, near-optimal paths that
//     hug corridors instead of zigzagging across cell-corners.
//   • Y is preserved end-to-end so multi-floor stages, ramps, and steps
//     work without the "all triangles in [0, 1.5]" hacks.

import { init } from "recast-navigation";
import { generateSoloNavMesh } from "recast-navigation/generators";
import type { NavMesh } from "recast-navigation";
import { NavMeshQuery } from "recast-navigation";
import type { Tri2D, Tri3D } from "./floor.ts";

let _recastReady = false;

export async function ensureRecast(): Promise<void> {
	if (_recastReady) return;
	await init();
	_recastReady = true;
}

export type { Tri3D } from "./floor.ts";

/** Bake a navmesh from 3D triangles. */
export function buildRecastNavMesh(triangles: Tri3D[], opts: {
	cellSize?: number;
	cellHeight?: number;
	agentRadius?: number; // meters
	agentHeight?: number; // meters
	agentMaxClimb?: number; // meters — max step height the agent can walk up
	walkableSlopeAngle?: number; // degrees
}): { navMesh: NavMesh; query: NavMeshQuery } | null {
	const cs = opts.cellSize ?? 0.3;
	const ch = opts.cellHeight ?? 0.2;
	const agentRadius = opts.agentRadius ?? 0.5;
	const agentHeight = opts.agentHeight ?? 1.8;
	const agentMaxClimb = opts.agentMaxClimb ?? 0.5;
	const walkableSlopeAngle = opts.walkableSlopeAngle ?? 45;

	// Recast wants raw triangle vertices + indices.
	const positions: number[] = [];
	const indices: number[] = [];
	for (const t of triangles) {
		const base = positions.length / 3;
		positions.push(t.x1, t.y1, t.z1);
		positions.push(t.x2, t.y2, t.z2);
		positions.push(t.x3, t.y3, t.z3);
		indices.push(base, base + 1, base + 2);
	}

	const result = generateSoloNavMesh(new Float32Array(positions), new Uint32Array(indices), {
		cs,
		ch,
		walkableSlopeAngle,
		walkableHeight: Math.ceil(agentHeight / ch),
		walkableClimb: Math.ceil(agentMaxClimb / ch),
		walkableRadius: Math.ceil(agentRadius / cs),
		maxEdgeLen: 12,
		maxSimplificationError: 1.3,
		minRegionArea: 8,
		mergeRegionArea: 20,
		maxVertsPerPoly: 6,
		detailSampleDist: 6,
		detailSampleMaxError: 1,
	});
	if (!result.success || !result.navMesh) return null;
	const query = new NavMeshQuery(result.navMesh);
	return { navMesh: result.navMesh, query };
}

/** Solve a smoothed path between two world XZ positions. Returns array of
 *  {x, y, z} world coords. y comes from the navmesh's actual floor height,
 *  which the autopilot can ignore (XZ is what it walks with). */
export function solvePathRecast(
	query: NavMeshQuery,
	from: { x: number; y?: number; z: number },
	to: { x: number; y?: number; z: number },
	opts: { halfExtents?: { x: number; y: number; z: number } } = {},
): { x: number; y: number; z: number }[] | null {
	const halfExtents = opts.halfExtents ?? { x: 4, y: 4, z: 4 };
	const result = query.computePath(
		{ x: from.x, y: from.y ?? 0, z: from.z },
		{ x: to.x, y: to.y ?? 0, z: to.z },
		{ halfExtents },
	);
	if (!result.success || !result.path || result.path.length === 0) return null;
	return result.path.map((p) => ({ x: p.x, y: p.y, z: p.z }));
}

/** Project XZ-only triangles back to 3D at y=0 (compat with the existing
 *  floor.ts pipeline that flattens Y). */
export function tri2dToTri3d(tris: Tri2D[]): Tri3D[] {
	return tris.map((t) => ({
		x1: t.x1, y1: 0, z1: t.z1,
		x2: t.x2, y2: 0, z2: t.z2,
		x3: t.x3, y3: 0, z3: t.z3,
	}));
}
