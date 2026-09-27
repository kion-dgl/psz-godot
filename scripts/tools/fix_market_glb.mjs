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
//   3. uv-degenerate faces (dup UV pair + span > 0.05, the tool's audit
//                    predicate) whose verts had a neighbour's UVs copied
//                    onto them, mapping the whole face onto one texel
//                    line — stripes. Auto-detected across every UV-carrying
//                    primitive (set02 is 200+ faces), repaired by extending
//                    the adjacent healthy face's world→UV affine (linear
//                    part only, offset re-fit to each face's known-good
//                    verts so the tiling stays continuous). Passes chain:
//                    faces repaired in pass N become anchors in pass N+1,
//                    so vert islands repair without hand-authored lists.
//
// Output: assets/stages/city_e/market/dairon3.glb (dairon2 stays the
// rollback). Idempotent by construction: reads dairon2, writes dairon3.
// Run: node scripts/tools/fix_market_glb.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..', '..');
const SRC = path.join(ROOT, 'assets/stages/city_e/market/dairon2.glb');
const OUT = path.join(ROOT, 'assets/stages/city_e/market/dairon3.glb');

// Class 3 thresholds — mirror web/src/city-lab/triangleAudit.ts so the
// surgery fixes exactly what the audit flags (deliberate flat-color fills
// with span ≤ UV_SPAN_MIN are left alone).
const UV_DUP_EPS = 1e-4;
const UV_SPAN_MIN = 0.05;

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

// --- 3. uv-degenerate faces: auto-detect, repair via adjacent healthy anchor
const UV_MAX_PASSES = 6;
for (const mesh of gltf.meshes) {
  for (const prim of mesh.primitives) {
    if (prim.attributes.TEXCOORD_0 == null || prim.indices == null || prim.attributes.POSITION == null) continue;
    const pos = new Reader(gltf.accessors[prim.attributes.POSITION]);
    const uv = new Reader(gltf.accessors[prim.attributes.TEXCOORD_0]);
    const idx = new Reader(gltf.accessors[prim.indices]);
    const faceCount = idx.count() / 3;
    const P = (v) => pos.vec3(v);
    const U = (v) => uv.vec2(v);
    const F = (f) => [idx.scalar(f * 3), idx.scalar(f * 3 + 1), idx.scalar(f * 3 + 2)];

    const d2 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
    const isDegenerate = (vs) => {
      const us = vs.map(U);
      const duvs = [d2(us[0], us[1]), d2(us[1], us[2]), d2(us[0], us[2])];
      return duvs.some((x) => x < UV_DUP_EPS) && Math.max(...duvs) > UV_SPAN_MIN;
    };
    const isHealthy = (vs) => {
      const us = vs.map(U);
      return d2(us[0], us[1]) > 1e-4 && d2(us[1], us[2]) > 1e-4 && d2(us[0], us[2]) > 1e-4;
    };

    let repairedTotal = 0;
    for (let pass = 1; pass <= UV_MAX_PASSES; pass++) {
      const bad = [];
      for (let f = 0; f < faceCount; f++) {
        if (isDegenerate(F(f))) bad.push(f);
      }
      if (bad.length === 0) break;

      // position → UV candidates from healthy faces (3 distinct UVs)
      const cand = new Map();
      for (let f = 0; f < faceCount; f++) {
        const vs = F(f);
        if (!isHealthy(vs)) continue;
        vs.forEach((v, i) => {
          const k = qpos(P(v));
          if (!cand.has(k)) cand.set(k, []);
          cand.get(k).push(U(v));
        });
      }
      const badSet = new Set(bad);

      let repairedThisPass = 0;
      for (const f of bad) {
        const vs = F(f);
        // anchor: healthy face sharing the most verts with this one;
        // the bad faces often carry unwelded (duplicated) verts, so fall
        // back to the nearest healthy face by centroid distance. Multiple
        // candidates are tried in order — the affine must reproduce the
        // face's known-good verts (below) before it is trusted, which
        // rejects non-coplanar neighbours.
        const cx = (fs) => fs.reduce((s, v) => s + P(v)[0], 0) / fs.length;
        const cy = (fs) => fs.reduce((s, v) => s + P(v)[1], 0) / fs.length;
        const cz = (fs) => fs.reduce((s, v) => s + P(v)[2], 0) / fs.length;
        const cands = [];
        for (let g = 0; g < faceCount; g++) {
          if (badSet.has(g)) continue;
          const gs = F(g);
          if (!isHealthy(gs)) continue;
          const shared = vs.filter((v) => gs.includes(v)).length;
          const cd = Math.hypot(cx(vs) - cx(gs), cy(vs) - cy(gs), cz(vs) - cz(gs));
          cands.push({ g, score: shared * 1e6 - cd });
        }
        cands.sort((a, b) => b.score - a.score);

        // known-good verts (position-confirmed UVs) are anchor-independent
        const good = [];
        for (const v of vs) {
          const c = cand.get(qpos(P(v)));
          if (c && c.some((cu) => d2(cu, U(v)) < 1e-3)) good.push(v);
        }
        if (good.length === 0) {
          console.warn(`  ${matName(prim)} face ${f}: no known-good vert — left as-is`);
          continue;
        }

        let repaired = false;
        for (const { g: anchor } of cands.slice(0, 8)) {
          const av = F(anchor);
          const p0 = P(av[0]), e1 = P(av[1]).map((n, k) => n - p0[k]), e2 = P(av[2]).map((n, k) => n - p0[k]);
          const u0 = U(av[0]), d1 = U(av[1]).map((n, k) => n - u0[k]), d2v = U(av[2]).map((n, k) => n - u0[k]);
          // world→UV linear map: coordinates in the anchor's edge basis
          const gram = [
            [e1.reduce((s, n) => s + n * n, 0), e1.reduce((s, n, k) => s + n * e2[k], 0)],
            [e1.reduce((s, n, k) => s + n * e2[k], 0), e2.reduce((s, n) => s + n * n, 0)],
          ];
          const det = gram[0][0] * gram[1][1] - gram[0][1] * gram[1][0];
          if (Math.abs(det) < 1e-12) continue;
          const lin = (p) => {
            const c1 = (p.reduce((s, n, k) => s + n * e1[k], 0) * gram[1][1] - p.reduce((s, n, k) => s + n * e2[k], 0) * gram[0][1]) / det;
            const c2 = (p.reduce((s, n, k) => s + n * e2[k], 0) * gram[0][0] - p.reduce((s, n, k) => s + n * e1[k], 0) * gram[1][0]) / det;
            return [u0[0] + c1 * d1[0] + c2 * d2v[0], u0[1] + c1 * d1[1] + c2 * d2v[1]];
          };

          // offset correction + coplanarity guard: the affine must
          // reproduce the known-good verts (residual < 0.05 UV units)
          // before it is trusted to extrapolate the bad verts
          let ox = 0, oy = 0, maxRes = 0;
          for (const v of good) {
            const m = lin(P(v));
            ox += U(v)[0] - m[0];
            oy += U(v)[1] - m[1];
          }
          ox /= good.length; oy /= good.length;
          for (const v of good) {
            const m = lin(P(v));
            maxRes = Math.max(maxRes, Math.abs(U(v)[0] - m[0] - ox), Math.abs(U(v)[1] - m[1] - oy));
          }
          if (maxRes > 0.05) continue;

          for (const v of vs) {
            const c = cand.get(qpos(P(v)));
            const known = c && c.some((cu) => d2(cu, U(v)) < 1e-3);
            if (known) continue;
            const m = lin(P(v));
            writeVec2(gltf.accessors[prim.attributes.TEXCOORD_0], v, [m[0] + ox, m[1] + oy]);
            report.repairedUvs++;
            repairedThisPass++;
          }
          repaired = true;
          break;
        }
        if (!repaired) {
          console.warn(`  ${matName(prim)} face ${f}: no coplanar anchor — left as-is`);
        }
      }
      repairedTotal += repairedThisPass;
      if (repairedThisPass === 0) {
        console.warn(`  ${matName(prim)}: ${bad.length} faces unrepairable (no anchors/known-good verts)`);
        break;
      }
    }
    if (repairedTotal > 0) console.log(`uv: ${matName(prim)} — repaired ${repairedTotal} faces`);
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
