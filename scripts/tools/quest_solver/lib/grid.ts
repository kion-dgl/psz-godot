// Walkability grid. Samples the stage's XZ AABB at `resolution` meters,
// marks each cell walkable iff its center sits on a floor triangle, then
// dilates the non-walkable region by `clearance` meters so the autopilot
// stays away from walls. Mirrors simulate_field_quest.py:build_nav_grid
// with the added clearance-erosion step.

import type { Tri2D } from "./floor.ts";
import { floorBounds, pointInTriangle } from "./floor.ts";

export interface NavGrid {
	walkable: Uint8Array; // row-major; 1 = walkable, 0 = blocked
	rows: number;
	cols: number;
	minX: number;
	minZ: number;
	resolution: number;
}

export interface BuildGridOpts {
	resolution: number;
	clearance: number;
	/** Padding around AABB so the player has room near portals just outside the floor. */
	padding?: number;
}

export function buildNavGrid(triangles: Tri2D[], opts: BuildGridOpts): NavGrid {
	const { resolution, clearance } = opts;
	const padding = opts.padding ?? 1.0;

	if (triangles.length === 0) {
		return { walkable: new Uint8Array(0), rows: 0, cols: 0, minX: 0, minZ: 0, resolution };
	}

	const b = floorBounds(triangles);
	const minX = b.minX - padding;
	const minZ = b.minZ - padding;
	const maxX = b.maxX + padding;
	const maxZ = b.maxZ + padding;
	const cols = Math.ceil((maxX - minX) / resolution) + 1;
	const rows = Math.ceil((maxZ - minZ) / resolution) + 1;

	// Step 1: mark raw walkable cells (cell center on floor).
	const raw = new Uint8Array(rows * cols);
	for (let r = 0; r < rows; r++) {
		const wz = minZ + r * resolution;
		for (let c = 0; c < cols; c++) {
			const wx = minX + c * resolution;
			// pointInTriangle is the inner loop hotspot; bail on the first hit.
			for (let i = 0; i < triangles.length; i++) {
				if (pointInTriangle(wx, wz, triangles[i])) {
					raw[r * cols + c] = 1;
					break;
				}
			}
		}
	}

	// Step 2: identify "wall" cells — non-walkable cells with at least one
	// walkable 4-neighbor. We only dilate FROM walls, not from the great void
	// surrounding the floor mesh. Otherwise a corridor 1 cell from the map's
	// AABB edge would get its single row eroded into nothing.
	const wallCells: number[] = [];
	for (let r = 0; r < rows; r++) {
		for (let c = 0; c < cols; c++) {
			if (raw[r * cols + c] === 1) continue;
			let hasWalkNeighbor = false;
			if (r > 0 && raw[(r - 1) * cols + c] === 1) hasWalkNeighbor = true;
			else if (r < rows - 1 && raw[(r + 1) * cols + c] === 1) hasWalkNeighbor = true;
			else if (c > 0 && raw[r * cols + (c - 1)] === 1) hasWalkNeighbor = true;
			else if (c < cols - 1 && raw[r * cols + (c + 1)] === 1) hasWalkNeighbor = true;
			if (hasWalkNeighbor) wallCells.push(r * cols + c);
		}
	}

	const k = Math.max(0, Math.ceil(clearance / resolution));
	if (k === 0) {
		return { walkable: raw, rows, cols, minX, minZ, resolution };
	}

	// Start from raw (so the void stays non-walkable) and additionally taint
	// walkable cells within K of any wall cell.
	const walkable = new Uint8Array(raw);
	for (const wi of wallCells) {
		const wr = Math.floor(wi / cols);
		const wc = wi % cols;
		const r0 = Math.max(0, wr - k);
		const r1 = Math.min(rows - 1, wr + k);
		const c0 = Math.max(0, wc - k);
		const c1 = Math.min(cols - 1, wc + k);
		for (let rr = r0; rr <= r1; rr++) {
			for (let cc = c0; cc <= c1; cc++) {
				walkable[rr * cols + cc] = 0;
			}
		}
	}
	return { walkable, rows, cols, minX, minZ, resolution };
}

/** Convert world XZ to grid (row, col). Clamps to grid bounds. */
export function worldToGrid(g: NavGrid, wx: number, wz: number): { r: number; c: number } {
	const c = Math.max(0, Math.min(g.cols - 1, Math.round((wx - g.minX) / g.resolution)));
	const r = Math.max(0, Math.min(g.rows - 1, Math.round((wz - g.minZ) / g.resolution)));
	return { r, c };
}

/** Convert grid (row, col) to world XZ at the cell center. */
export function gridToWorld(g: NavGrid, r: number, c: number): { x: number; z: number } {
	return { x: g.minX + c * g.resolution, z: g.minZ + r * g.resolution };
}

/** True if cell is walkable. */
export function isWalkable(g: NavGrid, r: number, c: number): boolean {
	if (r < 0 || r >= g.rows || c < 0 || c >= g.cols) return false;
	return g.walkable[r * g.cols + c] === 1;
}

/**
 * Walk outward in concentric rings to find the nearest walkable cell to
 * (r, c). Used when a target XZ (a portal or objective) lands just off-floor
 * after clearance erosion — we'd rather route to the closest walkable cell
 * than fail the path.
 */
export function findNearestWalkable(g: NavGrid, r: number, c: number, maxRadius: number): { r: number; c: number } | null {
	if (isWalkable(g, r, c)) return { r, c };
	for (let rad = 1; rad <= maxRadius; rad++) {
		// Scan the perimeter of the square at distance `rad`.
		for (let d = -rad; d <= rad; d++) {
			if (isWalkable(g, r - rad, c + d)) return { r: r - rad, c: c + d };
			if (isWalkable(g, r + rad, c + d)) return { r: r + rad, c: c + d };
			if (isWalkable(g, r + d, c - rad)) return { r: r + d, c: c - rad };
			if (isWalkable(g, r + d, c + rad)) return { r: r + d, c: c + rad };
		}
	}
	return null;
}
