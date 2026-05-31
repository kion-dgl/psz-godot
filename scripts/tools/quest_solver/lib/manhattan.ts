// Manhattan grid solver — emits axis-aligned paths.
//
// Why: most paru stages are small arenas with simple shapes (E, C, T, Z).
// Recast's funnel algorithm gives optimal *diagonal* paths through them,
// but the autopilot's camera-relative input drifts ~20% off-axis per meter
// on diagonals — by the time the player walks 30m diagonal across an
// E-shape they're 6m off course and snag on geometry.
//
// Strategy: build a grid, mark cells walkable iff their center sits on a
// floor triangle, then run 4-connected A* (no diagonals). The Manhattan
// shortest path naturally follows corridors: through an E-room from east
// to north spawn it walks west along the top corridor then drops south
// down the spine — the same route a human would take, with all pure
// cardinal segments the autopilot can drive without drift.
//
// Diagonals only enter the picture for Z-shape rooms where the only
// connecting floor is at a diagonal. That case is handled by falling
// back to 8-conn for the relevant leg.

import type { NavGrid } from "./grid.ts";
import { findNearestWalkable, gridToWorld, isWalkable, worldToGrid } from "./grid.ts";

interface Node {
	r: number;
	c: number;
	g: number;
	f: number;
}

// Min-heap on f. Inlined; bun's V8 doesn't ship one.
class MinHeap {
	private heap: Node[] = [];
	push(n: Node) {
		this.heap.push(n);
		let i = this.heap.length - 1;
		while (i > 0) {
			const p = (i - 1) >> 1;
			if (this.heap[p].f <= this.heap[i].f) break;
			[this.heap[p], this.heap[i]] = [this.heap[i], this.heap[p]];
			i = p;
		}
	}
	pop(): Node | undefined {
		const n = this.heap.length;
		if (n === 0) return undefined;
		const top = this.heap[0];
		const last = this.heap.pop()!;
		if (n > 1) {
			this.heap[0] = last;
			let i = 0;
			for (;;) {
				const l = i * 2 + 1;
				const r = i * 2 + 2;
				let smallest = i;
				if (l < this.heap.length && this.heap[l].f < this.heap[smallest].f) smallest = l;
				if (r < this.heap.length && this.heap[r].f < this.heap[smallest].f) smallest = r;
				if (smallest === i) break;
				[this.heap[i], this.heap[smallest]] = [this.heap[smallest], this.heap[i]];
				i = smallest;
			}
		}
		return top;
	}
	size() {
		return this.heap.length;
	}
}

// 4-connected (Manhattan): cardinal only.
const NEIGHBORS_4: [number, number, number][] = [
	[-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0],
];
// 8-connected fallback: cardinal + diagonal (Z-room compatibility).
const NEIGHBORS_8: [number, number, number][] = [
	[-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0],
	[-1, -1, 1.41421356], [-1, 1, 1.41421356], [1, -1, 1.41421356], [1, 1, 1.41421356],
];

/** A* on the grid with selectable neighborhood (4 or 8). */
export function astar(
	grid: NavGrid,
	startRC: { r: number; c: number },
	endRC: { r: number; c: number },
	opts: { eightConn?: boolean } = {},
): { cells: { r: number; c: number }[] } | null {
	const neighbors = opts.eightConn ? NEIGHBORS_8 : NEIGHBORS_4;
	const { rows, cols } = grid;
	if (!isWalkable(grid, startRC.r, startRC.c) || !isWalkable(grid, endRC.r, endRC.c)) return null;
	if (startRC.r === endRC.r && startRC.c === endRC.c) return { cells: [startRC] };

	const gScore = new Float64Array(rows * cols).fill(Infinity);
	const parent = new Int32Array(rows * cols).fill(-1);
	const closed = new Uint8Array(rows * cols);
	gScore[startRC.r * cols + startRC.c] = 0;
	const open = new MinHeap();
	open.push({ r: startRC.r, c: startRC.c, g: 0, f: heuristic(startRC, endRC, opts.eightConn ?? false) });

	while (open.size() > 0) {
		const cur = open.pop()!;
		const ci = cur.r * cols + cur.c;
		if (closed[ci]) continue;
		closed[ci] = 1;
		if (cur.r === endRC.r && cur.c === endRC.c) {
			return { cells: reconstruct(parent, cols, startRC, endRC) };
		}
		for (const [dr, dc, cost] of neighbors) {
			const nr = cur.r + dr;
			const nc = cur.c + dc;
			if (!isWalkable(grid, nr, nc)) continue;
			// Diagonal moves require both orthogonal neighbors walkable —
			// prevents cutting through wall corners.
			if (dr !== 0 && dc !== 0) {
				if (!isWalkable(grid, cur.r + dr, cur.c) || !isWalkable(grid, cur.r, cur.c + dc)) continue;
			}
			const ni = nr * cols + nc;
			if (closed[ni]) continue;
			const tentativeG = cur.g + cost;
			if (tentativeG < gScore[ni]) {
				gScore[ni] = tentativeG;
				parent[ni] = ci;
				const h = heuristic({ r: nr, c: nc }, endRC, opts.eightConn ?? false);
				open.push({ r: nr, c: nc, g: tentativeG, f: tentativeG + h });
			}
		}
	}
	return null;
}

function heuristic(a: { r: number; c: number }, b: { r: number; c: number }, eightConn: boolean): number {
	const dr = Math.abs(a.r - b.r);
	const dc = Math.abs(a.c - b.c);
	if (eightConn) {
		// Octile (optimal 8-conn admissible heuristic).
		return Math.min(dr, dc) * 1.41421356 + Math.abs(dr - dc);
	}
	return dr + dc; // Manhattan
}

function reconstruct(parent: Int32Array, cols: number, start: { r: number; c: number }, end: { r: number; c: number }): { r: number; c: number }[] {
	const cells: { r: number; c: number }[] = [];
	let idx = end.r * cols + end.c;
	const startIdx = start.r * cols + start.c;
	while (idx !== -1) {
		cells.push({ r: Math.floor(idx / cols), c: idx % cols });
		if (idx === startIdx) break;
		idx = parent[idx];
	}
	cells.reverse();
	return cells;
}

/**
 * Decimate a cell-by-cell A* path to corner-only waypoints. Only emit a
 * point when direction changes. The autopilot then walks pure straight
 * legs between waypoints, with zero drift because each leg is purely
 * cardinal (4-conn) or pure 45° (8-conn fallback).
 */
export function decimateToCorners(cells: { r: number; c: number }[]): { r: number; c: number }[] {
	if (cells.length <= 2) return cells;
	const out: { r: number; c: number }[] = [cells[0]];
	let prevDr = cells[1].r - cells[0].r;
	let prevDc = cells[1].c - cells[0].c;
	for (let i = 2; i < cells.length; i++) {
		const dr = cells[i].r - cells[i - 1].r;
		const dc = cells[i].c - cells[i - 1].c;
		if (dr !== prevDr || dc !== prevDc) {
			out.push(cells[i - 1]); // direction change: keep the corner
			prevDr = dr;
			prevDc = dc;
		}
	}
	out.push(cells[cells.length - 1]);
	return out;
}

/**
 * High-level: solve a Manhattan path from worldStart to worldEnd, returning
 * a list of world-XZ waypoints at corners only. Falls back to 8-conn for
 * Z-rooms where 4-conn can't connect (the diagonal floor case).
 */
export function solveManhattan(
	g: NavGrid,
	worldStart: { x: number; z: number },
	worldEnd: { x: number; z: number },
	opts: { allowDiagonalFallback?: boolean; snapRadius?: number } = {},
): { x: number; z: number }[] | null {
	const allowDiagonalFallback = opts.allowDiagonalFallback ?? true;
	const snapRadius = opts.snapRadius ?? Math.max(4, Math.ceil(2.0 / g.resolution));

	const s0 = worldToGrid(g, worldStart.x, worldStart.z);
	const e0 = worldToGrid(g, worldEnd.x, worldEnd.z);
	const s = isWalkable(g, s0.r, s0.c) ? s0 : findNearestWalkable(g, s0.r, s0.c, snapRadius);
	const e = isWalkable(g, e0.r, e0.c) ? e0 : findNearestWalkable(g, e0.r, e0.c, snapRadius);
	if (!s || !e) return null;

	// 4-conn first.
	let result = astar(g, s, e, { eightConn: false });
	if (!result && allowDiagonalFallback) {
		// Fall back to 8-conn for Z-shape connectivity.
		result = astar(g, s, e, { eightConn: true });
	}
	if (!result) return null;

	const corners = decimateToCorners(result.cells);
	return corners.map((rc) => {
		const w = gridToWorld(g, rc.r, rc.c);
		return { x: w.x, z: w.z };
	});
}
