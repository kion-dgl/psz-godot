// Floor triangles — extract 2D (XZ-plane) triangles from a stage's -floor.glb,
// apply the floorCollision config from unified-stage-configs.json, provide a
// point-in-triangle test.
//
// Matches simulate_field_quest.py:filter_floor_triangles and is_on_floor.

import { loadGlb } from "./glb.ts";

export interface Tri2D {
	x1: number;
	z1: number;
	x2: number;
	z2: number;
	x3: number;
	z3: number;
}

export interface FloorCollisionConfig {
	excludedMeshPatterns?: string[];
	triangles?: Record<string, boolean>;
	yTolerance?: number;
}

export interface LoadFloorOpts {
	/** Y range to consider "floor-like" — drops walls, roofs, railings. */
	yMin?: number;
	yMax?: number;
	/** Max Y-span within a single triangle. Walls have huge Y-span; floors don't. */
	maxYSpan?: number;
}

/**
 * Extract triangles (projected to XZ plane) from a GLB whose Y coords sit in
 * the "floor-like" range. The -floor.glb is the authoritative collision when
 * it exists; for stages whose -floor.glb is incomplete (e.g. s01b_ic1's
 * bridge), we fall back to the visual mesh _m.glb with the same Y filter to
 * pick up the surfaces the player actually walks on.
 *
 * Apply the floorCollision per-triangle filter from unified-stage-configs
 * (`tri_N: false` excludes the Nth triangle in global mesh-declaration order).
 */
export function loadFloorTriangles(
	glbPath: string,
	config: FloorCollisionConfig = {},
	loadOpts: LoadFloorOpts = {},
): Tri2D[] {
	const yMin = loadOpts.yMin ?? -2.5;
	const yMax = loadOpts.yMax ?? 2.5;
	const maxYSpan = loadOpts.maxYSpan ?? 2.0;

	const prims = loadGlb(glbPath);
	const all: Tri2D[] = [];
	const excludedPatterns = config.excludedMeshPatterns ?? [];

	for (const prim of prims) {
		if (excludedPatterns.some((p) => prim.meshName.includes(p))) continue;

		const { positions, indices } = prim;
		const triCount = indices ? indices.length / 3 : positions.length / 9;

		for (let i = 0; i < triCount; i++) {
			const i0 = indices ? indices[i * 3 + 0] : i * 3 + 0;
			const i1 = indices ? indices[i * 3 + 1] : i * 3 + 1;
			const i2 = indices ? indices[i * 3 + 2] : i * 3 + 2;
			const y0 = positions[i0 * 3 + 1];
			const y1 = positions[i1 * 3 + 1];
			const y2 = positions[i2 * 3 + 1];
			// Drop walls/roofs: any vertex outside the band, or large Y-span.
			if (y0 < yMin || y0 > yMax || y1 < yMin || y1 > yMax || y2 < yMin || y2 > yMax) continue;
			if (Math.max(y0, y1, y2) - Math.min(y0, y1, y2) > maxYSpan) continue;
			all.push({
				x1: positions[i0 * 3 + 0],
				z1: positions[i0 * 3 + 2],
				x2: positions[i1 * 3 + 0],
				z2: positions[i1 * 3 + 2],
				x3: positions[i2 * 3 + 0],
				z3: positions[i2 * 3 + 2],
			});
		}
	}

	const overrides = config.triangles ?? {};
	const filtered: Tri2D[] = [];
	for (let i = 0; i < all.length; i++) {
		if (overrides[`tri_${i}`] === false) continue;
		filtered.push(all[i]);
	}
	return filtered;
}

/**
 * Load a stage's walkable triangles. The -floor.glb is the in-game collision
 * mesh — when it's complete, use it alone. Some stages (like s01b_ic1) have
 * a -floor.glb that explicitly excludes terrain the player still walks on
 * (the bridge); for those, the visual mesh _m.glb is the only source.
 *
 * Strategy: load floor.glb first. Caller can additionally call `loadMainMesh`
 * and merge if floor.glb's connectivity is insufficient. The per-triangle
 * floorCollision filter only applies to the -floor.glb half because the
 * indices are local to that file.
 */
export function loadStageFloor(
	stageId: string,
	areaSubfolder: string,
	stageConfigsRoot: string,
	config: FloorCollisionConfig = {},
	loadOpts: LoadFloorOpts = {},
): Tri2D[] {
	const floorPath = `${stageConfigsRoot}/${areaSubfolder}/${stageId}/lndmd/${stageId}-floor.glb`;
	try {
		return loadFloorTriangles(floorPath, config, loadOpts);
	} catch (_e) {
		return [];
	}
}

/** Load the visual mesh as additional walkable triangles (Y-filtered). Used
 *  when the -floor.glb alone leaves the stage disconnected. */
export function loadStageMainMesh(
	stageId: string,
	areaSubfolder: string,
	stageConfigsRoot: string,
	loadOpts: LoadFloorOpts = {},
): Tri2D[] {
	const mainPath = `${stageConfigsRoot}/${areaSubfolder}/${stageId}/lndmd/${stageId}_m.glb`;
	try {
		return loadFloorTriangles(mainPath, {}, loadOpts);
	} catch (_e) {
		return [];
	}
}

/** Standard same-sign-of-cross-products point-in-triangle test (2D). */
export function pointInTriangle(px: number, pz: number, t: Tri2D): boolean {
	const d1 = (px - t.x2) * (t.z1 - t.z2) - (t.x1 - t.x2) * (pz - t.z2);
	const d2 = (px - t.x3) * (t.z2 - t.z3) - (t.x2 - t.x3) * (pz - t.z3);
	const d3 = (px - t.x1) * (t.z3 - t.z1) - (t.x3 - t.x1) * (pz - t.z1);
	const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
	const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
	return !(hasNeg && hasPos);
}

export interface FloorBounds {
	minX: number;
	maxX: number;
	minZ: number;
	maxZ: number;
}

export function floorBounds(triangles: Tri2D[]): FloorBounds {
	let minX = Infinity;
	let maxX = -Infinity;
	let minZ = Infinity;
	let maxZ = -Infinity;
	for (const t of triangles) {
		minX = Math.min(minX, t.x1, t.x2, t.x3);
		maxX = Math.max(maxX, t.x1, t.x2, t.x3);
		minZ = Math.min(minZ, t.z1, t.z2, t.z3);
		maxZ = Math.max(maxZ, t.z1, t.z2, t.z3);
	}
	return { minX, maxX, minZ, maxZ };
}

/** True if any floor triangle contains (x, z). */
export function isOnFloor(x: number, z: number, triangles: Tri2D[]): boolean {
	for (const t of triangles) {
		if (pointInTriangle(x, z, t)) return true;
	}
	return false;
}
