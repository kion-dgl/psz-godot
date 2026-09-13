import * as THREE from 'three';
import { textureFilename } from '../elements/materials';

/**
 * Lantern detection over a loaded stage GLB scene — by TEXTURE, the way the
 * art itself identifies a lantern (#646).
 *
 * The lamp sheet s03_1_lamp1.png carries the flame animation frames in a
 * distinct UV column (u ∈ [0.5, 0.875], located by scanning the texture's
 * pixels for the orange flame). Geometry that samples that column IS flame
 * geometry — both the 1_lamp1 material (lamps) and the 0_fire material
 * (the authored flame overlays) use the sheet, so both are scanned.
 *
 * The flame clusters then separate by HEIGHT:
 *   - lantern heads: top 4.5–6.5 (short posts at 5.1, the lowered off-path
 *     variant at 5.9) — lc2→4, na1→2, nc2→4, ga1→4, matching the original;
 *   - treetop fire billboards: top 28–30 (do not light as lanterns);
 *   - ground scatter and view-wall torches: ≤1.3 or 12+ — out of band.
 *
 * The anchor is the centroid of the head-band vertices (the flame quad
 * itself), y = top − 1.0 — the flame sits just below the lantern cap.
 * Validated against the hand-tuned ga1 set: all four within ~1 unit.
 */

export interface LanternDetectParams {
  cell: number;
  flameU: [number, number];
  flameV: [number, number];
  headTopBand: [number, number];
  minVerts: number;
}

export const DEFAULT_LANTERN_PARAMS: LanternDetectParams = {
  cell: 2,
  flameU: [0.5, 0.875],
  flameV: [0.0, 0.85],
  headTopBand: [4.5, 6.5],
  minVerts: 4,
};

function fold(u: number): number {
  const m = ((u % 2) + 2) % 2;
  return m <= 1 ? m : 2 - m;
}

export function detectLanterns(
  root: THREE.Object3D,
  params: LanternDetectParams = DEFAULT_LANTERN_PARAMS,
): THREE.Vector3[] {
  const { cell, flameU, flameV, headTopBand, minVerts } = params;

  const cells = new Map<string, { ix: number; iz: number; pts: THREE.Vector3[] }>();
  const v = new THREE.Vector3();
  root.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (!mesh.isMesh) return;
    const mat = (Array.isArray(mesh.material) ? mesh.material[0] : mesh.material) as
      | (THREE.Material & { map?: THREE.Texture | null })
      | undefined;
    if (!mat?.map || !textureFilename(mat.map).includes('lamp')) return;
    const pos = mesh.geometry.attributes.position;
    const uv = mesh.geometry.attributes.uv;
    if (!uv) return;
    for (let i = 0; i < pos.count; i++) {
      const u = fold(uv.getX(i));
      const t = fold(uv.getY(i));
      if (u < flameU[0] || u > flameU[1] || t < flameV[0] || t > flameV[1]) continue;
      v.fromBufferAttribute(pos, i);
      const p = v.clone().applyMatrix4(mesh.matrixWorld);
      const ix = Math.floor(p.x / cell);
      const iz = Math.floor(p.z / cell);
      const k = `${ix},${iz}`;
      let c = cells.get(k);
      if (!c) {
        c = { ix, iz, pts: [] };
        cells.set(k, c);
      }
      c.pts.push(p);
    }
  });
  if (!cells.size) return [];

  const cand = [...cells.values()];
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

  const regions = new Map<string, THREE.Vector3[]>();
  for (const c of cand) {
    const rk = find(`${c.ix},${c.iz}`);
    let r = regions.get(rk);
    if (!r) {
      r = [];
      regions.set(rk, r);
    }
    r.push(...c.pts);
  }

  const anchors: THREE.Vector3[] = [];
  for (const pts of regions.values()) {
    if (pts.length < minVerts) continue;
    const top = Math.max(...pts.map((p) => p.y));
    if (top < headTopBand[0] || top > headTopBand[1]) continue;
    const head = pts.filter((p) => p.y >= top - 1.5);
    anchors.push(new THREE.Vector3(
      head.reduce((s, p) => s + p.x, 0) / head.length,
      top - 1.0,
      head.reduce((s, p) => s + p.z, 0) / head.length,
    ));
  }
  return anchors;
}
