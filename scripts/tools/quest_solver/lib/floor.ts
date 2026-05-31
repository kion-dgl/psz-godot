// Floor triangles — extract 2D (XZ-plane) triangles from a stage's -floor.glb,
// apply the floorCollision config from unified-stage-configs.json, provide a
// point-in-triangle test.
//
// Matches simulate_field_quest.py:filter_floor_triangles and is_on_floor.

import { loadGlb } from "./glb.ts";

/** 3D triangle (preserves Y) — used by the recast solver, which needs the
 *  actual surface geometry to compute slopes and floor heights. */
export interface Tri3D {
	x1: number; y1: number; z1: number;
	x2: number; y2: number; z2: number;
	x3: number; y3: number; z3: number;
}

/** Load all triangles from a GLB as 3D triangles. Recast wants the actual
 *  mesh, not Y-flattened. */
export function loadGlb3D(path: string): Tri3D[] {
	const prims = loadGlb(path);
	const out: Tri3D[] = [];
	for (const prim of prims) {
		const { positions, indices } = prim;
		const triCount = indices ? indices.length / 3 : positions.length / 9;
		for (let i = 0; i < triCount; i++) {
			const i0 = indices ? indices[i * 3 + 0] : i * 3 + 0;
			const i1 = indices ? indices[i * 3 + 1] : i * 3 + 1;
			const i2 = indices ? indices[i * 3 + 2] : i * 3 + 2;
			out.push({
				x1: positions[i0 * 3 + 0], y1: positions[i0 * 3 + 1], z1: positions[i0 * 3 + 2],
				x2: positions[i1 * 3 + 0], y2: positions[i1 * 3 + 1], z2: positions[i1 * 3 + 2],
				x3: positions[i2 * 3 + 0], y3: positions[i2 * 3 + 1], z3: positions[i2 * 3 + 2],
			});
		}
	}
	return out;
}

/**
 * Weld triangle vertices that lie within `tolerance` meters of each other.
 *
 * Why: some stages (e.g. `s05a_tb3`'s south-tube ↔ arena junction) have small
 * gaps between adjacent triangles — sub-meter holes the player capsule can
 * snag on. recast-navigation-js inherits those gaps as navmesh holes. Welding
 * collapses near-coincident vertices to a single canonical position, sealing
 * the cracks before they reach recast.
 *
 * Algorithm:
 *   1. Spatial-hash every vertex into a `tolerance`-sized 3D grid.
 *   2. Union-find: for each vertex, scan its own cell + the 26 neighbour cells
 *      and merge into the same cluster if within `tolerance`. The 27-cell
 *      probe avoids the cell-boundary aliasing you'd get from a naive
 *      cell-bucket dedupe (two vertices 1cm apart but straddling a cell wall
 *      would otherwise miss each other).
 *   3. Average each cluster's vertices to get the canonical snapped position.
 *   4. Rewrite the triangle list with snapped coordinates; triangle count is
 *      preserved (we move vertices, never drop tris).
 *
 * O(N · k) where k is the average vertex density per 3³-cell neighbourhood
 * (≈ small constant for a properly-chosen tolerance).
 */
export function weldTriangles(tris: Tri3D[], tolerance: number = 0.3): Tri3D[] {
	if (tris.length === 0) return tris;

	// Flatten every triangle's 3 vertices into a single array so we can refer
	// to them by global index. verts[i] = [x, y, z] for vertex i.
	const N = tris.length * 3;
	const verts: Float64Array = new Float64Array(N * 3);
	for (let t = 0; t < tris.length; t++) {
		const tri = tris[t];
		const base = t * 9;
		verts[base + 0] = tri.x1; verts[base + 1] = tri.y1; verts[base + 2] = tri.z1;
		verts[base + 3] = tri.x2; verts[base + 4] = tri.y2; verts[base + 5] = tri.z2;
		verts[base + 6] = tri.x3; verts[base + 7] = tri.y3; verts[base + 8] = tri.z3;
	}

	// Spatial hash: cell-key → list of vertex indices in that cell.
	const cellKey = (ix: number, iy: number, iz: number) => `${ix},${iy},${iz}`;
	const cellOf = (x: number, y: number, z: number): [number, number, number] => [
		Math.floor(x / tolerance),
		Math.floor(y / tolerance),
		Math.floor(z / tolerance),
	];
	const cells = new Map<string, number[]>();
	for (let i = 0; i < N; i++) {
		const [ix, iy, iz] = cellOf(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2]);
		const k = cellKey(ix, iy, iz);
		let bucket = cells.get(k);
		if (!bucket) { bucket = []; cells.set(k, bucket); }
		bucket.push(i);
	}

	// Union-find over vertex indices.
	const parent = new Int32Array(N);
	for (let i = 0; i < N; i++) parent[i] = i;
	const find = (i: number): number => {
		let r = i;
		while (parent[r] !== r) r = parent[r];
		// Path-compress.
		let cur = i;
		while (parent[cur] !== r) { const next = parent[cur]; parent[cur] = r; cur = next; }
		return r;
	};
	const union = (a: number, b: number) => {
		const ra = find(a);
		const rb = find(b);
		if (ra !== rb) parent[ra] = rb;
	};

	const tolSq = tolerance * tolerance;

	// For each vertex, probe its 3×3×3 neighbourhood and union with any vertex
	// within tolerance. We only need to scan each cell-pair once: union is
	// symmetric, so checking every vertex's own neighbourhood covers all pairs.
	for (let i = 0; i < N; i++) {
		const xi = verts[i * 3];
		const yi = verts[i * 3 + 1];
		const zi = verts[i * 3 + 2];
		const [cx, cy, cz] = cellOf(xi, yi, zi);
		for (let dx = -1; dx <= 1; dx++) {
			for (let dy = -1; dy <= 1; dy++) {
				for (let dz = -1; dz <= 1; dz++) {
					const bucket = cells.get(cellKey(cx + dx, cy + dy, cz + dz));
					if (!bucket) continue;
					for (const j of bucket) {
						if (j <= i) continue; // each unordered pair handled once
						const dxv = verts[j * 3] - xi;
						const dyv = verts[j * 3 + 1] - yi;
						const dzv = verts[j * 3 + 2] - zi;
						if (dxv * dxv + dyv * dyv + dzv * dzv <= tolSq) {
							union(i, j);
						}
					}
				}
			}
		}
	}

	// Average each cluster's vertices to get the canonical position.
	const sumX = new Map<number, number>();
	const sumY = new Map<number, number>();
	const sumZ = new Map<number, number>();
	const count = new Map<number, number>();
	for (let i = 0; i < N; i++) {
		const r = find(i);
		sumX.set(r, (sumX.get(r) ?? 0) + verts[i * 3]);
		sumY.set(r, (sumY.get(r) ?? 0) + verts[i * 3 + 1]);
		sumZ.set(r, (sumZ.get(r) ?? 0) + verts[i * 3 + 2]);
		count.set(r, (count.get(r) ?? 0) + 1);
	}
	const canonX = new Map<number, number>();
	const canonY = new Map<number, number>();
	const canonZ = new Map<number, number>();
	for (const [r, c] of count) {
		canonX.set(r, (sumX.get(r) ?? 0) / c);
		canonY.set(r, (sumY.get(r) ?? 0) / c);
		canonZ.set(r, (sumZ.get(r) ?? 0) / c);
	}

	// Rewrite triangles using snapped vertices.
	const out: Tri3D[] = new Array(tris.length);
	for (let t = 0; t < tris.length; t++) {
		const v0 = find(t * 3 + 0);
		const v1 = find(t * 3 + 1);
		const v2 = find(t * 3 + 2);
		out[t] = {
			x1: canonX.get(v0)!, y1: canonY.get(v0)!, z1: canonZ.get(v0)!,
			x2: canonX.get(v1)!, y2: canonY.get(v1)!, z2: canonZ.get(v1)!,
			x3: canonX.get(v2)!, y3: canonY.get(v2)!, z3: canonZ.get(v2)!,
		};
	}
	return out;
}

/** Count how many distinct canonical vertices a triangle list contains. Used
 *  by tests/diagnostics to measure the effect of `weldTriangles`. */
export function countUniqueVertices(tris: Tri3D[]): number {
	const seen = new Set<string>();
	for (const t of tris) {
		seen.add(`${t.x1},${t.y1},${t.z1}`);
		seen.add(`${t.x2},${t.y2},${t.z2}`);
		seen.add(`${t.x3},${t.y3},${t.z3}`);
	}
	return seen.size;
}

/** Load a stage's 3D triangles from both -floor.glb (if present, applies the
 *  per-tri filter from floorCollision) and _m.glb (visual mesh; covers
 *  surfaces the curated floor.glb doesn't). Recast classifies floors vs
 *  walls itself based on triangle normals so we feed it everything. */
export function loadStage3D(
	stageId: string,
	areaSubfolder: string,
	stageConfigsRoot: string,
	config: FloorCollisionConfig = {},
): Tri3D[] {
	const out: Tri3D[] = [];
	const floorPath = `${stageConfigsRoot}/${areaSubfolder}/${stageId}/lndmd/${stageId}-floor.glb`;
	const mainPath = `${stageConfigsRoot}/${areaSubfolder}/${stageId}/lndmd/${stageId}_m.glb`;
	try {
		const floorTris = loadGlb3D(floorPath);
		const overrides = config.triangles ?? {};
		for (let i = 0; i < floorTris.length; i++) {
			if (overrides[`tri_${i}`] === false) continue;
			out.push(floorTris[i]);
		}
	} catch (_e) {}
	try {
		out.push(...loadGlb3D(mainPath));
	} catch (_e) {}
	return out;
}

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
