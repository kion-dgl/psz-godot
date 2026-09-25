// fix_market_glb.mjs — dairon2 → dairon3 data surgery (stdlib only).
//
// The market's malformed triangles come in three classes, all authored
// from the city-lab investigation (web #/city-lab triangles mode):
//
//   1. spike faces   six verts shot to y = −1e9 (six needle triangles in
//                    the set02 strip) — deleted.
//   2. bake seam     the cent5 quad at z = 5 carries near-black COLOR_0
//                    (0.07–0.09) on its bottom corners while the adjacent
//                    triangle of the same quad is pure white at the same
//                    positions — reconciled to the healthy twin values.
//   3. uv-degenerate seven faces (set01 318–321, gr01 161–164) whose
//                    bottom-edge verts had the top-edge UVs copied onto
//                    them, mapping the whole face onto one texel line —
//                    stripes. Repaired by extending the adjacent healthy
//                    quad's world→UV affine (linear part only, offset
//                    re-fit to each face's known-good verts so the tiling
//                    stays continuous).
//
// Output: assets/stages/city_e/market/dairon3.glb (dairon2 stays the
// rollback). Idempotent by construction: reads dairon2, writes dairon3.
// Run: node scripts/tools/fix_market_glb.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const SRC = path.join(ROOT, 'assets/stages/city_e/market/dairon2.glb');
const OUT = path.join(ROOT, 'assets/stages/city_e/market/dairon3.glb');

// Authored repair list for class 3: [material, faces..., anchorFace].
// The anchor is the adjacent healthy quad whose world→UV affine defines
// the strip's texel direction and density.
const UV_REPAIRS = [
  { material: 'set01_COLOR_0', faces: [318, 319, 320, 321], anchor: 317 },
  { material: 'gr01_COLOR_0', faces: [161, 162, 163, 164], anchor: 160 },
];

// Class 2: cent5 quad corners to reconcile, by quantised position.
const CENT5_FIX_VERTS = [
  [-3.084, 1.285, 5.0],
  [3.010, 1.285, 5.0],
];
const CENT5_TARGET_COLOR = [1.0, 1.0, 1.0];

/* ------------------------------------------------------------------ */
/* GLB plumbing                                                        */
/* ------------------------------------------------------------------ */

const buf = readFileSync(SRC);
if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error('not a GLB');
const jsonLen = buf.readUInt32LE(12);
const gltf = JSON.parse(buf.slice(20, 20 + jsonLen).toString());
const binStart = 20 + jsonLen + 8;
const bin = buf.subarray(binStart);

const view = (acc) => {
  const bv = gltf.bufferViews[acc.bufferView];
  return bin.subarray((bv.byteOffset || 0) + (acc.byteOffset || 0));
};
const matName = (prim) => gltf.materials[prim.material]?.name ?? '?';

class Reader {
  constructor(acc) { this.acc = acc; this.view = view(acc); }
  count() { return this.acc.count; }
  scalar(i) {
    const t = this.acc.componentType;
    return t === 5123 ? this.view.readUInt16LE(i * 2) : this.view.readUInt32LE(i * 4);
  }
  vec2(i) { return [this.view.readFloatLE(i * 8), this.view.readFloatLE(i * 8 + 4)]; }
  vec3(i) { return [this.view.readFloatLE(i * 12), this.view.readFloatLE(i * 12 + 4), this.view.readFloatLE(i * 12 + 8)]; }
}

function writeVec3(acc, i, v) {
  const view2 = view(acc);
  if (acc.componentType === 5123) {
    // normalized uint16
    for (let k = 0; k < 3; k++) view2.writeUInt16LE(Math.round(Math.min(1, Math.max(0, v[k])) * 65535), i * 6 + k * 2);
  } else {
    for (let k = 0; k < 3; k++) view2.writeFloatLE(v[k], i * 12 + k * 4);
  }
}

function writeVec2(acc, i, v) {
  const view2 = view(acc);
  view2.writeFloatLE(v[0], i * 8);
  view2.writeFloatLE(v[1], i * 8 + 4);
}

const qpos = (p) => p.map((n) => Math.round(n * 1000)).join(',');
const dist2 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

/* ------------------------------------------------------------------ */
/* Repairs                                                             */
/* ------------------------------------------------------------------ */

const report = { deletedFaces: 0, recoloredVerts: 0, repairedUvs: 0 };

// --- 1. spike faces: delete any face referencing a vertex beyond |y| 1e6
for (const mesh of gltf.meshes) {
  for (const prim of mesh.primitives) {
    if (prim.indices == null || prim.attributes.POSITION == null) continue;
    const pos = new Reader(gltf.accessors[prim.attributes.POSITION]);
    const idx = new Reader(gltf.accessors[prim.indices]);
    const spikes = new Set();
    for (let v = 0; v < pos.count(); v++) {
      if (Math.abs(pos.vec3(v)[1]) > 1e6) spikes.add(v);
    }
    if (spikes.size === 0) continue;
    const keep = [];
    for (let f = 0; f < idx.count() / 3; f++) {
      const tri = [idx.scalar(f * 3), idx.scalar(f * 3 + 1), idx.scalar(f * 3 + 2)];
      if (tri.some((v) => spikes.has(v))) continue;
      keep.push(...tri);
    }
    const dropped = idx.count() / 3 - keep.length / 3;
    report.deletedFaces += dropped;
    const view2 = view(gltf.accessors[prim.indices]);
    const acc = gltf.accessors[prim.indices];
    for (let i = 0; i < keep.length; i++) {
      if (acc.componentType === 5123) view2.writeUInt16LE(keep[i], i * 2);
      else view2.writeUInt32LE(keep[i], i * 4);
    }
    acc.count = keep.length;
    // the index bufferView keeps its original span; the compacted indices
    // simply leave trailing bytes unused
    console.log(`spikes: ${matName(prim)} — dropped ${dropped} faces`);
  }
}

// --- 2. cent5 bake seam: reconcile the dark quad corners to the twin color
outer:
for (const mesh of gltf.meshes) {
  for (const prim of mesh.primitives) {
    if (matName(prim) !== 'cent5_COLOR_0' || prim.attributes.COLOR_0 == null) continue;
    const pos = new Reader(gltf.accessors[prim.attributes.POSITION]);
    const col = gltf.accessors[prim.attributes.COLOR_0];
    const wanted = new Set(CENT5_FIX_VERTS.map(qpos));
    for (let v = 0; v < pos.count(); v++) {
      if (!wanted.has(qpos(pos.vec3(v)))) continue;
      writeVec3(col, v, CENT5_TARGET_COLOR);
      report.recoloredVerts++;
    }
    break outer;
  }
}

// --- 3. uv-degenerate faces: repair via the anchor affine, offset-fit per face
for (const spec of UV_REPAIRS) {
  let done = false;
  for (const mesh of gltf.meshes) {
    for (const prim of mesh.primitives) {
      if (matName(prim) !== spec.material || prim.attributes.TEXCOORD_0 == null) continue;
      const pos = new Reader(gltf.accessors[prim.attributes.POSITION]);
      const uv = new Reader(gltf.accessors[prim.attributes.TEXCOORD_0]);
      const idx = new Reader(gltf.accessors[prim.indices]);
      const P = (v) => pos.vec3(v);
      const U = (v) => uv.vec2(v);

      // position → UV candidates from healthy faces (3 distinct UVs)
      const cand = new Map();
      for (let f = 0; f < idx.count() / 3; f++) {
        const vs = [idx.scalar(f * 3), idx.scalar(f * 3 + 1), idx.scalar(f * 3 + 2)];
        const us = vs.map(U);
        if (dist2(us[0], us[1]) < 1e-4 || dist2(us[1], us[2]) < 1e-4 || dist2(us[0], us[2]) < 1e-4) continue;
        vs.forEach((v, i) => {
          const k = qpos(P(v));
          if (!cand.has(k)) cand.set(k, []);
          cand.get(k).push(us[i]);
        });
      }

      // anchor affine: linear part via two edge vectors of the anchor face
      const av = [idx.scalar(spec.anchor * 3), idx.scalar(spec.anchor * 3 + 1), idx.scalar(spec.anchor * 3 + 2)];
      const p0 = P(av[0]), e1 = P(av[1]).map((n, k) => n - p0[k]), e2 = P(av[2]).map((n, k) => n - p0[k]);
      const u0 = U(av[0]), d1 = U(av[1]).map((n, k) => n - u0[k]), d2 = U(av[2]).map((n, k) => n - u0[k]);
      // solve the 2x2 [e1 e2] [a b; c d] = [d1 d2] per uv component via
      // least squares on the 3D edges: uv(M·p) with M = pinhole of the
      // two edges — approximate linear map from world to uv.
      const gram = [
        [e1.reduce((s, n) => s + n * n, 0), e1.reduce((s, n, k) => s + n * e2[k], 0)],
        [e1.reduce((s, n, k) => s + n * e2[k], 0), e2.reduce((s, n) => s + n * n, 0)],
      ];
      const det = gram[0][0] * gram[1][1] - gram[0][1] * gram[1][0];
      const lin = (p) => {
        // coordinates of p in the anchor's edge basis
        const c1 = (p.reduce((s, n, k) => s + n * e1[k], 0) * gram[1][1] - p.reduce((s, n, k) => s + n * e2[k], 0) * gram[0][1]) / det;
        const c2 = (p.reduce((s, n, k) => s + n * e2[k], 0) * gram[0][0] - p.reduce((s, n, k) => s + n * e1[k], 0) * gram[1][0]) / det;
        return [u0[0] + c1 * d1[0] + c2 * d2[0], u0[1] + c1 * d1[1] + c2 * d2[1]];
      };

      for (const f of spec.faces) {
        const vs = [idx.scalar(f * 3), idx.scalar(f * 3 + 1), idx.scalar(f * 3 + 2)];
        // offset correction: anchor the linear map onto this face's
        // known-good verts (position-confirmed UVs)
        const good = [];
        for (const v of vs) {
          const c = cand.get(qpos(P(v)));
          if (c && c.some((cu) => dist2(cu, U(v)) < 1e-3)) good.push(v);
        }
        if (good.length === 0) {
          console.warn(`  face ${f}: no known-good vert — left as-is`);
          continue;
        }
        let ox = 0, oy = 0;
        for (const v of good) {
          const m = lin(P(v));
          ox += U(v)[0] - m[0];
          oy += U(v)[1] - m[1];
        }
        ox /= good.length; oy /= good.length;
        for (const v of vs) {
          const c = cand.get(qpos(P(v)));
          const known = c && c.some((cu) => dist2(cu, U(v)) < 1e-3);
          if (known) continue;
          const m = lin(P(v));
          writeVec2(gltf.accessors[prim.attributes.TEXCOORD_0], v, [m[0] + ox, m[1] + oy]);
          report.repairedUvs++;
        }
      }
      done = true;
      break;
    }
    if (done) break;
  }
}

/* ------------------------------------------------------------------ */
/* Serialize                                                           */
/* ------------------------------------------------------------------ */

const jsonOut = Buffer.from(JSON.stringify(gltf), 'utf8');
const jsonPad = (4 - (jsonOut.length % 4)) % 4;
const jsonChunk = Buffer.concat([jsonOut, Buffer.alloc(jsonPad, 0x20)]);
const binPad = (4 - (bin.length % 4)) % 4;
const binChunk = Buffer.concat([bin, Buffer.alloc(binPad, 0)]);
const total = 12 + 8 + jsonChunk.length + 8 + binChunk.length;
const out = Buffer.alloc(total);
out.write('glTF', 0, 'ascii');
out.writeUInt32LE(2, 4);
out.writeUInt32LE(total, 8);
out.writeUInt32LE(jsonChunk.length, 12);
out.write('JSON', 16, 'ascii');
jsonChunk.copy(out, 20);
out.writeUInt32LE(binChunk.length, 20 + jsonChunk.length);
out.write('BIN\0', 24 + jsonChunk.length, 'ascii');
binChunk.copy(out, 28 + jsonChunk.length);
writeFileSync(OUT, out);

console.log(
  `dairon3.glb written (${out.length} B): ${report.deletedFaces} spike faces deleted, ` +
    `${report.recoloredVerts} bake-seam verts recolored, ${report.repairedUvs} UVs repaired`,
);
