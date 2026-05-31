// Browser-side Manhattan grid solver for the stage editor.
//
// Mirrors scripts/tools/quest_solver/lib/{grid,manhattan,floor}.ts but
// uses three.js's GLTFLoader rather than `node:fs` so it can run in the
// editor's react-three-fiber canvas. The point isn't to compute
// production waypoints here — it's to visualize the SAME algorithm the
// CLI solver runs so the user can iterate on tuning (resolution,
// clearance, via-point placement) at editor speed instead of waiting
// 10 minutes per autopilot run.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

export interface Tri3D {
  x1: number; y1: number; z1: number;
  x2: number; y2: number; z2: number;
  x3: number; y3: number; z3: number;
}

export interface Tri2D {
  x1: number; z1: number;
  x2: number; z2: number;
  x3: number; z3: number;
}

export interface NavGrid {
  walkable: Uint8Array;   // row-major; 1 = walkable, 0 = blocked
  rows: number;
  cols: number;
  minX: number;
  minZ: number;
  resolution: number;
}

const loader = new GLTFLoader();

/** Load + parse a GLB URL into 3D triangle list. Cached by URL. */
const glbCache = new Map<string, Promise<Tri3D[]>>();
export function loadGlbTriangles(url: string): Promise<Tri3D[]> {
  const cached = glbCache.get(url);
  if (cached) return cached;
  const p = new Promise<Tri3D[]>((resolve, reject) => {
    loader.load(
      url,
      (gltf) => {
        const out: Tri3D[] = [];
        gltf.scene.updateMatrixWorld(true);
        gltf.scene.traverse((node) => {
          const mesh = node as THREE.Mesh;
          if (!mesh.isMesh) return;
          const geom = mesh.geometry;
          const pos = geom.attributes.position;
          if (!pos) return;
          const idx = geom.index;
          const mat = mesh.matrixWorld;
          const v = new THREE.Vector3();
          const triCount = idx ? idx.count / 3 : pos.count / 3;
          for (let i = 0; i < triCount; i++) {
            const i0 = idx ? idx.getX(i * 3 + 0) : i * 3 + 0;
            const i1 = idx ? idx.getX(i * 3 + 1) : i * 3 + 1;
            const i2 = idx ? idx.getX(i * 3 + 2) : i * 3 + 2;
            const a = v.fromBufferAttribute(pos, i0).applyMatrix4(mat).clone();
            const b = v.fromBufferAttribute(pos, i1).applyMatrix4(mat).clone();
            const c = v.fromBufferAttribute(pos, i2).applyMatrix4(mat).clone();
            out.push({
              x1: a.x, y1: a.y, z1: a.z,
              x2: b.x, y2: b.y, z2: b.z,
              x3: c.x, y3: c.y, z3: c.z,
            });
          }
        });
        resolve(out);
      },
      undefined,
      reject,
    );
  });
  glbCache.set(url, p);
  return p;
}

/** Apply the floorCollision.triangles per-tri filter from the stage config. */
export function filterFloorTriangles(
  tris: Tri3D[],
  overrides: Record<string, boolean> = {},
): Tri3D[] {
  const out: Tri3D[] = [];
  for (let i = 0; i < tris.length; i++) {
    if (overrides[`tri_${i}`] === false) continue;
    out.push(tris[i]);
  }
  return out;
}

/** Project to XZ. */
export function tri3dToTri2d(t: Tri3D): Tri2D {
  return { x1: t.x1, z1: t.z1, x2: t.x2, z2: t.z2, x3: t.x3, z3: t.z3 };
}

/** Standard same-sign-of-cross-products point-in-triangle (XZ). */
export function pointInTriangle(px: number, pz: number, t: Tri2D): boolean {
  const d1 = (px - t.x2) * (t.z1 - t.z2) - (t.x1 - t.x2) * (pz - t.z2);
  const d2 = (px - t.x3) * (t.z2 - t.z3) - (t.x2 - t.x3) * (pz - t.z3);
  const d3 = (px - t.x1) * (t.z3 - t.z1) - (t.x3 - t.x1) * (pz - t.z1);
  const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

export interface FloorBounds {
  minX: number; maxX: number;
  minZ: number; maxZ: number;
}

export function floorBounds(triangles: Tri2D[]): FloorBounds {
  let minX = Infinity, maxX = -Infinity;
  let minZ = Infinity, maxZ = -Infinity;
  for (const t of triangles) {
    minX = Math.min(minX, t.x1, t.x2, t.x3);
    maxX = Math.max(maxX, t.x1, t.x2, t.x3);
    minZ = Math.min(minZ, t.z1, t.z2, t.z3);
    maxZ = Math.max(maxZ, t.z1, t.z2, t.z3);
  }
  return { minX, maxX, minZ, maxZ };
}

export interface BuildGridOpts {
  resolution: number;
  padding?: number;
  /** Erode the walkable region away from real walls (cells that border the
   *  floor edge) by `clearance` meters. Matches the CLI grid.ts behaviour:
   *  only dilate from non-walkable cells that have a walkable 4-neighbor
   *  (the actual floor boundary), not from the off-floor void surrounding
   *  the bounding box — otherwise a corridor right at the AABB edge would
   *  get eroded into nothing. */
  clearance?: number;
}

export function buildNavGrid(triangles: Tri2D[], opts: BuildGridOpts): NavGrid {
  const { resolution } = opts;
  const padding = opts.padding ?? 1.0;
  const clearance = opts.clearance ?? 0;
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

  // Pass 1: raw walkability — center-of-cell on a floor triangle.
  const raw = new Uint8Array(rows * cols);
  for (let r = 0; r < rows; r++) {
    const wz = minZ + r * resolution;
    for (let c = 0; c < cols; c++) {
      const wx = minX + c * resolution;
      for (let i = 0; i < triangles.length; i++) {
        if (pointInTriangle(wx, wz, triangles[i])) {
          raw[r * cols + c] = 1;
          break;
        }
      }
    }
  }

  const k = Math.max(0, Math.ceil(clearance / resolution));
  if (k === 0) {
    return { walkable: raw, rows, cols, minX, minZ, resolution };
  }

  // Pass 2: find boundary cells (non-walkable, but adjacent to walkable).
  // These are the actual floor edges. Dilate them KxK to push the walkable
  // region inward by `clearance` meters.
  const wallCells: number[] = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (raw[r * cols + c] === 1) continue;
      let hasWalkable = false;
      if (r > 0 && raw[(r - 1) * cols + c] === 1) hasWalkable = true;
      else if (r < rows - 1 && raw[(r + 1) * cols + c] === 1) hasWalkable = true;
      else if (c > 0 && raw[r * cols + (c - 1)] === 1) hasWalkable = true;
      else if (c < cols - 1 && raw[r * cols + (c + 1)] === 1) hasWalkable = true;
      if (hasWalkable) wallCells.push(r * cols + c);
    }
  }

  const walkable = new Uint8Array(raw);
  for (const wi of wallCells) {
    const wr = Math.floor(wi / cols);
    const wc = wi % cols;
    const r0 = Math.max(0, wr - k);
    const r1 = Math.min(rows - 1, wr + k);
    const c0 = Math.max(0, wc - k);
    const c1 = Math.min(cols - 1, wc + k);
    for (let rr = r0; rr <= r1; rr++) {
      for (let cc = c0; cc <= c1; cc++) walkable[rr * cols + cc] = 0;
    }
  }
  return { walkable, rows, cols, minX, minZ, resolution };
}

export function worldToGrid(g: NavGrid, wx: number, wz: number): { r: number; c: number } {
  const c = Math.max(0, Math.min(g.cols - 1, Math.round((wx - g.minX) / g.resolution)));
  const r = Math.max(0, Math.min(g.rows - 1, Math.round((wz - g.minZ) / g.resolution)));
  return { r, c };
}

export function gridToWorld(g: NavGrid, r: number, c: number): { x: number; z: number } {
  return { x: g.minX + c * g.resolution, z: g.minZ + r * g.resolution };
}

export function isWalkable(g: NavGrid, r: number, c: number): boolean {
  if (r < 0 || r >= g.rows || c < 0 || c >= g.cols) return false;
  return g.walkable[r * g.cols + c] === 1;
}

export function findNearestWalkable(g: NavGrid, r: number, c: number, maxRadius: number): { r: number; c: number } | null {
  if (isWalkable(g, r, c)) return { r, c };
  for (let rad = 1; rad <= maxRadius; rad++) {
    for (let d = -rad; d <= rad; d++) {
      if (isWalkable(g, r - rad, c + d)) return { r: r - rad, c: c + d };
      if (isWalkable(g, r + rad, c + d)) return { r: r + rad, c: c + d };
      if (isWalkable(g, r + d, c - rad)) return { r: r + d, c: c - rad };
      if (isWalkable(g, r + d, c + rad)) return { r: r + d, c: c + rad };
    }
  }
  return null;
}

// ── Manhattan A* (4-conn primary, 8-conn fallback for Z-rooms) ──

interface AstarNode { r: number; c: number; g: number; f: number; }

class MinHeap {
  private heap: AstarNode[] = [];
  push(n: AstarNode) {
    this.heap.push(n);
    let i = this.heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this.heap[p].f <= this.heap[i].f) break;
      [this.heap[p], this.heap[i]] = [this.heap[i], this.heap[p]];
      i = p;
    }
  }
  pop(): AstarNode | undefined {
    const n = this.heap.length;
    if (n === 0) return undefined;
    const top = this.heap[0];
    const last = this.heap.pop()!;
    if (n > 1) {
      this.heap[0] = last;
      let i = 0;
      for (;;) {
        const l = i * 2 + 1, r = i * 2 + 2;
        let s = i;
        if (l < this.heap.length && this.heap[l].f < this.heap[s].f) s = l;
        if (r < this.heap.length && this.heap[r].f < this.heap[s].f) s = r;
        if (s === i) break;
        [this.heap[i], this.heap[s]] = [this.heap[s], this.heap[i]];
        i = s;
      }
    }
    return top;
  }
  size() { return this.heap.length; }
}

const NEIGHBORS_4: [number, number, number][] = [
  [-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0],
];
const NEIGHBORS_8: [number, number, number][] = [
  [-1, 0, 1.0], [1, 0, 1.0], [0, -1, 1.0], [0, 1, 1.0],
  [-1, -1, 1.41421356], [-1, 1, 1.41421356], [1, -1, 1.41421356], [1, 1, 1.41421356],
];

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
  open.push({ r: startRC.r, c: startRC.c, g: 0, f: heuristic(startRC, endRC, !!opts.eightConn) });

  while (open.size() > 0) {
    const cur = open.pop()!;
    const ci = cur.r * cols + cur.c;
    if (closed[ci]) continue;
    closed[ci] = 1;
    if (cur.r === endRC.r && cur.c === endRC.c) {
      const cells = reconstruct(parent, cols, startRC, endRC);
      return { cells };
    }
    for (const [dr, dc, cost] of neighbors) {
      const nr = cur.r + dr, nc = cur.c + dc;
      if (!isWalkable(grid, nr, nc)) continue;
      if (dr !== 0 && dc !== 0) {
        if (!isWalkable(grid, cur.r + dr, cur.c) || !isWalkable(grid, cur.r, cur.c + dc)) continue;
      }
      const ni = nr * cols + nc;
      if (closed[ni]) continue;
      const tg = cur.g + cost;
      if (tg < gScore[ni]) {
        gScore[ni] = tg;
        parent[ni] = ci;
        const h = heuristic({ r: nr, c: nc }, endRC, !!opts.eightConn);
        open.push({ r: nr, c: nc, g: tg, f: tg + h });
      }
    }
  }
  return null;
}

function heuristic(a: { r: number; c: number }, b: { r: number; c: number }, eightConn: boolean): number {
  const dr = Math.abs(a.r - b.r);
  const dc = Math.abs(a.c - b.c);
  if (eightConn) return Math.min(dr, dc) * 1.41421356 + Math.abs(dr - dc);
  return dr + dc;
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

export function decimateToCorners(cells: { r: number; c: number }[]): { r: number; c: number }[] {
  if (cells.length <= 2) return cells;
  const out: { r: number; c: number }[] = [cells[0]];
  let prevDr = cells[1].r - cells[0].r;
  let prevDc = cells[1].c - cells[0].c;
  for (let i = 2; i < cells.length; i++) {
    const dr = cells[i].r - cells[i - 1].r;
    const dc = cells[i].c - cells[i - 1].c;
    if (dr !== prevDr || dc !== prevDc) {
      out.push(cells[i - 1]);
      prevDr = dr;
      prevDc = dc;
    }
  }
  out.push(cells[cells.length - 1]);
  return out;
}

export interface ManhattanPath {
  cellsAll: { r: number; c: number }[]; // full A* output
  corners: { r: number; c: number }[];  // direction-change waypoints
  worldCorners: { x: number; z: number }[]; // corner in world coords
  usedDiagonal: boolean;
}

export function solveManhattan(
  g: NavGrid,
  worldStart: { x: number; z: number },
  worldEnd: { x: number; z: number },
  opts: { snapRadius?: number; allowDiagonalFallback?: boolean } = {},
): ManhattanPath | null {
  const snapRadius = opts.snapRadius ?? Math.max(4, Math.ceil(2.0 / g.resolution));
  const allow = opts.allowDiagonalFallback ?? true;
  const s0 = worldToGrid(g, worldStart.x, worldStart.z);
  const e0 = worldToGrid(g, worldEnd.x, worldEnd.z);
  const s = isWalkable(g, s0.r, s0.c) ? s0 : findNearestWalkable(g, s0.r, s0.c, snapRadius);
  const e = isWalkable(g, e0.r, e0.c) ? e0 : findNearestWalkable(g, e0.r, e0.c, snapRadius);
  if (!s || !e) return null;
  let usedDiagonal = false;
  let result = astar(g, s, e, { eightConn: false });
  if (!result && allow) {
    result = astar(g, s, e, { eightConn: true });
    usedDiagonal = !!result;
  }
  if (!result) return null;
  const corners = decimateToCorners(result.cells);
  const worldCorners = corners.map((rc) => gridToWorld(g, rc.r, rc.c));
  return { cellsAll: result.cells, corners, worldCorners, usedDiagonal };
}
