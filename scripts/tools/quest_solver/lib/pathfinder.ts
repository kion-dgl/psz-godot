// A* pathfinder on the nav grid. Returns the actual cell path (not just
// length, unlike simulate_field_quest.py which only needs reachability).
// 8-neighbor expansion with euclidean heuristic.
//
// Includes line-of-sight smoothing: after finding the cell-by-cell path,
// drop intermediate cells when there's a clear walkable line between two
// non-adjacent cells. This turns a 30-cell staircase into a 2-point
// (start, end) line where possible — fewer waypoints for the autopilot
// to follow, but still dense enough on actual corners that the camera-
// drift problem doesn't show up.

import type { NavGrid } from "./grid.ts";
import { findNearestWalkable, gridToWorld, isWalkable, worldToGrid } from "./grid.ts";

interface Node {
	r: number;
	c: number;
	g: number;
	f: number;
}

// Min-heap keyed on `f`. Inlined for speed — bun's V8 doesn't ship one.
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

const NEIGHBORS: [number, number, number][] = [
	[-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0],
	[-1, -1, 1.41421356], [-1, 1, 1.41421356], [1, -1, 1.41421356], [1, 1, 1.41421356],
];

export interface AstarResult {
	cells: { r: number; c: number }[];
	costCells: number;
}

/** A* on the grid. Returns null if unreachable. */
export function astar(grid: NavGrid, startRC: { r: number; c: number }, endRC: { r: number; c: number }): AstarResult | null {
	const { rows, cols } = grid;
	if (!isWalkable(grid, startRC.r, startRC.c) || !isWalkable(grid, endRC.r, endRC.c)) return null;
	if (startRC.r === endRC.r && startRC.c === endRC.c) {
		return { cells: [startRC], costCells: 0 };
	}

	const gScore = new Float64Array(rows * cols).fill(Infinity);
	const parent = new Int32Array(rows * cols).fill(-1);
	const closed = new Uint8Array(rows * cols);
	gScore[startRC.r * cols + startRC.c] = 0;
	const open = new MinHeap();
	open.push({ r: startRC.r, c: startRC.c, g: 0, f: heuristic(startRC, endRC) });

	while (open.size() > 0) {
		const cur = open.pop()!;
		const ci = cur.r * cols + cur.c;
		if (closed[ci]) continue;
		closed[ci] = 1;
		if (cur.r === endRC.r && cur.c === endRC.c) {
			return reconstruct(parent, cols, startRC, endRC, cur.g);
		}
		for (const [dr, dc, cost] of NEIGHBORS) {
			const nr = cur.r + dr;
			const nc = cur.c + dc;
			if (!isWalkable(grid, nr, nc)) continue;
			// For diagonal moves, also require both orthogonal neighbors to be
			// walkable — prevents corner-cutting through a wall meeting at a
			// diagonal seam.
			if (dr !== 0 && dc !== 0) {
				if (!isWalkable(grid, cur.r + dr, cur.c) || !isWalkable(grid, cur.r, cur.c + dc)) continue;
			}
			const ni = nr * cols + nc;
			if (closed[ni]) continue;
			const tentativeG = cur.g + cost;
			if (tentativeG < gScore[ni]) {
				gScore[ni] = tentativeG;
				parent[ni] = ci;
				const h = heuristic({ r: nr, c: nc }, endRC);
				open.push({ r: nr, c: nc, g: tentativeG, f: tentativeG + h });
			}
		}
	}
	return null;
}

function heuristic(a: { r: number; c: number }, b: { r: number; c: number }): number {
	const dr = a.r - b.r;
	const dc = a.c - b.c;
	return Math.sqrt(dr * dr + dc * dc);
}

function reconstruct(parent: Int32Array, cols: number, start: { r: number; c: number }, end: { r: number; c: number }, cost: number): AstarResult {
	const cells: { r: number; c: number }[] = [];
	let idx = end.r * cols + end.c;
	const startIdx = start.r * cols + start.c;
	while (idx !== -1) {
		cells.push({ r: Math.floor(idx / cols), c: idx % cols });
		if (idx === startIdx) break;
		idx = parent[idx];
	}
	cells.reverse();
	return { cells, costCells: cost };
}

/**
 * Line-of-sight test on the grid using Bresenham. True if every cell along the
 * line between (r0,c0) and (r1,c1) is walkable.
 */
export function gridLineWalkable(g: NavGrid, r0: number, c0: number, r1: number, c1: number): boolean {
	let r = r0, c = c0;
	const dr = Math.abs(r1 - r0);
	const dc = Math.abs(c1 - c0);
	const sr = r0 < r1 ? 1 : -1;
	const sc = c0 < c1 ? 1 : -1;
	let err = dc - dr;
	for (;;) {
		if (!isWalkable(g, r, c)) return false;
		if (r === r1 && c === c1) return true;
		const e2 = 2 * err;
		if (e2 > -dr) { err -= dr; c += sc; }
		if (e2 < dc) { err += dc; r += sr; }
	}
}

/**
 * Decimate an A* path to a minimal set of waypoints. Greedy: from the current
 * waypoint, scan forward to the furthest cell that's still line-of-sight
 * walkable, drop everything in between, repeat.
 *
 * Capped at `maxLegCells` — the autopilot's camera-relative keyboard input
 * drifts ~20% off-axis per meter on diagonal walks. At a 6m leg, drift can
 * reach 1.2m — enough to drift into a wall the leg's straight line cleared.
 * 3m max keeps drift within ~0.6m, well under the 1.5m arrive radius.
 */
export function decimatePath(
	g: NavGrid,
	cells: { r: number; c: number }[],
	opts: { maxLegCells?: number } = {},
): { r: number; c: number }[] {
	const maxLeg = opts.maxLegCells ?? Math.max(2, Math.floor(3.0 / g.resolution));
	if (cells.length <= 2) return cells;
	const out: { r: number; c: number }[] = [cells[0]];
	let i = 0;
	while (i < cells.length - 1) {
		let j = Math.min(cells.length - 1, i + maxLeg);
		while (j > i + 1 && !gridLineWalkable(g, cells[i].r, cells[i].c, cells[j].r, cells[j].c)) j--;
		out.push(cells[j]);
		i = j;
	}
	return out;
}

/**
 * High-level: solve a path from worldStart to worldEnd, returning a list of
 * world-XZ waypoints. Snaps off-floor endpoints to the nearest walkable cell.
 * Optionally decimates via line-of-sight smoothing.
 */
export function solvePath(
	g: NavGrid,
	worldStart: { x: number; z: number },
	worldEnd: { x: number; z: number },
	opts: { decimate?: boolean; snapRadius?: number } = {},
): { x: number; z: number }[] | null {
	const decimate = opts.decimate ?? true;
	const snapRadius = opts.snapRadius ?? Math.max(4, Math.ceil(2.0 / g.resolution));

	const s0 = worldToGrid(g, worldStart.x, worldStart.z);
	const e0 = worldToGrid(g, worldEnd.x, worldEnd.z);
	const s = isWalkable(g, s0.r, s0.c) ? s0 : findNearestWalkable(g, s0.r, s0.c, snapRadius);
	const e = isWalkable(g, e0.r, e0.c) ? e0 : findNearestWalkable(g, e0.r, e0.c, snapRadius);
	if (!s || !e) return null;
	const path = astar(g, s, e);
	if (!path) return null;
	const cells = decimate ? decimatePath(g, path.cells) : path.cells;
	return cells.map((rc) => {
		const w = gridToWorld(g, rc.r, rc.c);
		return { x: w.x, z: w.z };
	});
}
