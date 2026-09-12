import * as THREE from 'three';

/**
 * Lantern detection over a loaded stage GLB scene.
 *
 * Lanterns are the mesh whose material is NAMED `…lamp…` — snowfield's
 * 1_lamp1. Name only, never the texture: the `0_fire` material shares the
 * very same sheet (the flame frames live on s03_1_lamp1.png) and matches by
 * filename, which would drag the authored fire billboards — treetops
 * included — into the anchor set.
 *
 * The exporter wrote fully flat vertices (no shared verts between
 * triangles), and the geometry chains lamps together along a path — so
 * neither triangle connectivity nor naive XZ clustering separates
 * instances. What DOES: lantern heads are where the lamp geometry reaches
 * high. Grid the verts 2×2 in XZ, keep cells whose maxY clears MIN_HEIGHT
 * (chains sag below it), merge adjacent cells, and each surviving region is
 * one lantern.
 *
 * Trees are separated by REGION VERTEX COUNT, not height: real lanterns
 * are chunky (42–53 verts whether short 5.1u posts or tall 29.5u posts —
 * lc2/na1/nc2 carry ONLY the tall variant), while tree clusters run
 * 12–23 verts. minVerts=40 keeps the lanterns and loses the forest.
 * Measured against the original: lc2→4, nc2→4, na1→2 (tall), ic1→2,
 * sa1→1, ga1→4 (short), most short-post rooms 2–5, snowfield B 0.
 *
 * Positions are mesh-local on purpose: the node transform is identity and
 * the "skeleton" is one bone with out-of-range joint indices (a degenerate
 * no-op), so matrixWorld alone is the correct world placement.
 */

export interface LanternDetectParams {
  cell: number;
  minHeight: number;
  maxTop: number;
  minVerts: number;
}

export const DEFAULT_LANTERN_PARAMS: LanternDetectParams = {
  cell: 2,
  minHeight: 2.2,
  maxTop: 1e9,
  minVerts: 40,
};

export function detectLanterns(
  root: THREE.Object3D,
  params: LanternDetectParams = DEFAULT_LANTERN_PARAMS,
): THREE.Vector3[] {
  const { cell, minHeight, maxTop, minVerts } = params;

  const pts: THREE.Vector3[] = [];
  const v = new THREE.Vector3();
  root.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (!mesh.isMesh) return;
    const mat = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
    if (!(mat?.name ?? '').toLowerCase().includes('lamp')) return;
    const pos = mesh.geometry.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      v.fromBufferAttribute(pos, i);
      pts.push(v.clone().applyMatrix4(mesh.matrixWorld));
    }
  });
  if (!pts.length) return [];

  const cells = new Map<string, { ix: number; iz: number; n: number; maxY: number }>();
  for (const p of pts) {
    const ix = Math.floor(p.x / cell);
    const iz = Math.floor(p.z / cell);
    const k = `${ix},${iz}`;
    let c = cells.get(k);
    if (!c) {
      c = { ix, iz, n: 0, maxY: -Infinity };
      cells.set(k, c);
    }
    c.n += 1;
    c.maxY = Math.max(c.maxY, p.y);
  }

  const cand = [...cells.values()].filter((c) => c.maxY >= minHeight);
  const parent = new Map<string, string>();
  const find = (k: string): string => {
    let a = k;
    while (parent.get(a) !== a) a = parent.get(a) as string;
    return a;
  };
  for (const c of cand) parent.set(`${c.ix},${c.iz}`, `${c.ix},${c.iz}`);
  for (const c of cand) {
    const ck = `${c.ix},${c.iz}`;
    for (let dx = -1; dx <= 1; dx++) {
      for (let dz = -1; dz <= 1; dz++) {
        const nk = `${c.ix + dx},${c.iz + dz}`;
        if (parent.has(nk)) parent.set(find(nk), find(ck));
      }
    }
  }

  const regions = new Map<string, { sx: number; sz: number; n: number; top: number; cells: number }>();
  for (const c of cand) {
    const rk = find(`${c.ix},${c.iz}`);
    let r = regions.get(rk);
    if (!r) {
      r = { sx: 0, sz: 0, n: 0, top: -Infinity, cells: 0 };
      regions.set(rk, r);
    }
    r.sx += c.ix + 0.5;
    r.sz += c.iz + 0.5;
    r.n += c.n;
    r.top = Math.max(r.top, c.maxY);
    r.cells += 1;
  }

  return [...regions.values()]
    .filter((r) => r.n >= minVerts)
    .map((r) => new THREE.Vector3(
      (r.sx / r.cells) * cell,
      r.top - 1.0, // the flame sits below the lantern's top cap — 4.1 on the 5.1-tall posts
      (r.sz / r.cells) * cell,
    ));
}
