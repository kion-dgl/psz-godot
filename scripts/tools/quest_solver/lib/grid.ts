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
	/** Wall obstacles. Cells whose centers fall inside any wall's XZ shadow are
	 *  marked blocked, then `wallClearance` dilates only from those wall cells
	 *  (not from off-floor void) so the path stays a margin away from walls
	 *  even though corridor edges retain full width. */
	walls?: Tri2D[];
	/** Extra dilation specifically from wall-rasterized cells, in meters. */
	wallClearance?: number;
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

	// Step 1b: punch walls back out. Walls extracted from the visual mesh's
	// steep surfaces often project to *degenerate* XZ triangles (a vertical
	// wall is a line in plan view), so a plain point-in-triangle test misses
	// them. Instead, rasterize each wall's three edges as line segments and
	// also test point-in-triangle for the non-degenerate case (ramps, steep
	// slopes). Both pass: any cell within rasterRadius of a wall edge OR
	// inside a wall's XZ shadow gets blocked.
	const walls = opts.walls ?? [];
	// Track which blocked cells came from walls (vs floor void) so we can
	// dilate from walls only later.
	const wallStamp = new Uint8Array(rows * cols);
	if (walls.length > 0) {
		const stampHalfCells = 1;
		const stampLine = (ax: number, az: number, bx: number, bz: number) => {
			const dist = Math.hypot(bx - ax, bz - az);
			if (dist < 1e-6) return;
			const steps = Math.ceil(dist / (resolution * 0.5)) + 1;
			for (let s = 0; s <= steps; s++) {
				const t = s / steps;
				const x = ax + (bx - ax) * t;
				const z = az + (bz - az) * t;
				const c = Math.round((x - minX) / resolution);
				const r = Math.round((z - minZ) / resolution);
				const r0 = Math.max(0, r - stampHalfCells);
				const r1 = Math.min(rows - 1, r + stampHalfCells);
				const c0 = Math.max(0, c - stampHalfCells);
				const c1 = Math.min(cols - 1, c + stampHalfCells);
				for (let rr = r0; rr <= r1; rr++) {
					for (let cc = c0; cc <= c1; cc++) {
						raw[rr * cols + cc] = 0;
						wallStamp[rr * cols + cc] = 1;
					}
				}
			}
		};
		for (const w of walls) {
			stampLine(w.x1, w.z1, w.x2, w.z2);
			stampLine(w.x2, w.z2, w.x3, w.z3);
			stampLine(w.x3, w.z3, w.x1, w.z1);
		}
	}

	// Step 1c: wall-only clearance dilation. Push the walkable region away
	// from real walls (so the autopilot's diagonal-drift has buffer) without
	// also eroding floor edges (which would close corridors that are narrow
	// but actually traversable).
	const wallClearance = opts.wallClearance ?? 0;
	const kWall = Math.max(0, Math.ceil(wallClearance / resolution));
	if (kWall > 0) {
		for (let r = 0; r < rows; r++) {
			for (let c = 0; c < cols; c++) {
				if (wallStamp[r * cols + c] !== 1) continue;
				const r0 = Math.max(0, r - kWall);
				const r1 = Math.min(rows - 1, r + kWall);
				const c0 = Math.max(0, c - kWall);
				const c1 = Math.min(cols - 1, c + kWall);
				for (let rr = r0; rr <= r1; rr++) {
					for (let cc = c0; cc <= c1; cc++) raw[rr * cols + cc] = 0;
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
