// Walls — extract non-floor-like triangles from a stage's visual mesh and
// treat them as XZ obstacles for the nav grid.
//
// The visual mesh `_m.glb` contains floor + walls + decorations all in one.
// The floor loader strips wall/decoration triangles by Y-band + Y-span, but
// the *grid* then loses any concept that walls exist — so a corridor with
// floor on both sides can have the autopilot diagonal-cut straight across.
//
// Definition of a wall used here: any triangle whose surface normal has
// |normal.y| < 0.5 — i.e., steep enough that the player can't stand on it.
// (For reference: a perfectly flat floor has |normal.y| = 1, a 30° slope
// has |normal.y| ≈ 0.87, a 60° slope ≈ 0.5, vertical wall = 0.)
//
// We don't need the wall's Y range to block movement; only its XZ shadow.

import { loadGlb } from "./glb.ts";
import type { Tri2D } from "./floor.ts";

const FLOOR_NORMAL_Y_THRESHOLD = 0.5;
// Player body roughly spans floor (y≈0) up to ~1.5m. A wall has to overlap
// this range to actually block movement — eaves at y=3, railings at y=2,
// skybox ceilings, etc. don't.
const PLAYER_BODY_Y_MIN = 0.0;
const PLAYER_BODY_Y_MAX = 1.5;

/**
 * Extract wall triangles (projected to XZ) from a GLB. A triangle is a wall
 * iff its surface normal has |normal.y| < threshold (steep, can't stand on)
 * AND its vertical extent overlaps the player's body height range (low
 * eaves and high railings are filtered out — they don't physically block).
 */
export function loadWalls(glbPath: string, opts: { minSlopeY?: number; yMin?: number; yMax?: number } = {}): Tri2D[] {
	const cutoff = opts.minSlopeY ?? FLOOR_NORMAL_Y_THRESHOLD;
	const yMin = opts.yMin ?? PLAYER_BODY_Y_MIN;
	const yMax = opts.yMax ?? PLAYER_BODY_Y_MAX;
	const prims = loadGlb(glbPath);
	const walls: Tri2D[] = [];

	for (const prim of prims) {
		const { positions, indices } = prim;
		const triCount = indices ? indices.length / 3 : positions.length / 9;

		for (let i = 0; i < triCount; i++) {
			const i0 = indices ? indices[i * 3 + 0] : i * 3 + 0;
			const i1 = indices ? indices[i * 3 + 1] : i * 3 + 1;
			const i2 = indices ? indices[i * 3 + 2] : i * 3 + 2;

			const ax = positions[i0 * 3 + 0], ay = positions[i0 * 3 + 1], az = positions[i0 * 3 + 2];
			const bx = positions[i1 * 3 + 0], by = positions[i1 * 3 + 1], bz = positions[i1 * 3 + 2];
			const cx = positions[i2 * 3 + 0], cy = positions[i2 * 3 + 1], cz = positions[i2 * 3 + 2];

			// Y-extent overlap with player body? If the triangle entirely sits
			// above the player's head or entirely below their feet, skip it.
			const triYMin = Math.min(ay, by, cy);
			const triYMax = Math.max(ay, by, cy);
			if (triYMax < yMin || triYMin > yMax) continue;

			// Normal = (b-a) × (c-a). We only need normal.y here.
			const ux = bx - ax, uy = by - ay, uz = bz - az;
			const vx = cx - ax, vy = cy - ay, vz = cz - az;
			const nx = uy * vz - uz * vy;
			const ny = uz * vx - ux * vz;
			const nz = ux * vy - uy * vx;
			const len = Math.hypot(nx, ny, nz);
			if (len < 1e-6) continue; // degenerate
			const nyNorm = Math.abs(ny / len);

			if (nyNorm < cutoff) {
				walls.push({ x1: ax, z1: az, x2: bx, z2: bz, x3: cx, z3: cz });
			}
		}
	}

	return walls;
}

/** Load walls from a stage's visual mesh. Empty array on missing file. */
export function loadStageWalls(
	stageId: string,
	areaSubfolder: string,
	stageConfigsRoot: string,
	opts: { minSlopeY?: number } = {},
): Tri2D[] {
	const mainPath = `${stageConfigsRoot}/${areaSubfolder}/${stageId}/lndmd/${stageId}_m.glb`;
	try {
		return loadWalls(mainPath, opts);
	} catch (_e) {
		return [];
	}
}
