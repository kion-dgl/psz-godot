// derive_bake_lights.mjs — seed a city-lights sidecar from the DS bake.
//
// The GLBs ship KHR_materials_unlit with COLOR_0 = the console's baked
// vertex lighting. The game renders some interiors with vertex colors
// OFF (city_counter_controller's "baked too dark" override) and the
// authored sidecar ON — so the rig's job (#656) is to recreate the bake's
// style with real OmniLight3Ds. This script mines COLOR_0 directly:
//
//   ambient  ← the bake's overall mean color (the between-pools fill)
//   omnis    ← luminance-weighted clusters of bright verts (lum ≥
//              THRESHOLD): position at the brightness centroid, color from
//              the cluster's mean COLOR_0, energy/range from its brightness
//              mass and extent.
//
// Output is a starting draft, not a final rig — tune in web #/city-lab
// (lighting mode) and save; the lab's save overwrites the sidecar.
// Idempotent per GLB: reads only the GLB, writes the sidecar path given.
//
// Run: node scripts/tools/derive_bake_lights.mjs \
//        assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb s00e_sa2

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const [,, glbArg, stageArg] = process.argv;
if (!glbArg || !stageArg) throw new Error('usage: derive_bake_lights.mjs <model.glb> <stage_id>');
const OUT = path.resolve('data/stage_configs/city-lights', `${stageArg}.json`);

const THRESHOLD = 0.85; // bright-vert cutoff (bake lum p90 ≈ 1.0)
const CLUSTER_RADIUS = 6.0; // meters — verts within this join a cluster
const MAX_LIGHTS = 20;
const MIN_CLUSTER_VERTS = 6;

const buf = readFileSync(path.resolve(glbArg));
if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error('not a GLB');
const jsonLen = buf.readUInt32LE(12);
const gltf = JSON.parse(buf.slice(20, 20 + jsonLen).toString());
const bin = buf.subarray(20 + jsonLen + 8);
const view = (acc) => {
  const bv = gltf.bufferViews[acc.bufferView];
  return bin.subarray((bv.byteOffset || 0) + (acc.byteOffset || 0));
};

const lum = (c) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
const d3 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

// Collect verts (position, color) from every COLOR_0-carrying primitive.
const verts = [];
for (const mesh of gltf.meshes) {
  for (const prim of mesh.primitives) {
    if (prim.attributes.COLOR_0 == null || prim.attributes.POSITION == null) continue;
    const cAcc = gltf.accessors[prim.attributes.COLOR_0];
    const pAcc = gltf.accessors[prim.attributes.POSITION];
    const cv = view(cAcc), pv = view(pAcc);
    const size = cAcc.type === 'VEC4' ? 4 : 3;
    for (let i = 0; i < cAcc.count; i++) {
      const rgb = cAcc.componentType === 5123
        ? [0, 1, 2].map((k) => cv.readUInt16LE(i * size * 2 + k * 2) / 65535)
        : [0, 1, 2].map((k) => cv.readFloatLE(i * size * 4 + k * 4));
      verts.push({
        p: [0, 1, 2].map((k) => pv.readFloatLE(i * 12 + k * 4)),
        c: rgb,
        l: lum(rgb),
      });
    }
  }
}
if (verts.length === 0) throw new Error('no COLOR_0 in ' + glbArg);

// Ambient: the bake's overall mean tint, but only a trace of it as energy —
// the fill must sit far under the omni pools or the base stays readable
// with every light deleted ("see everything with no lights"). ~0.1 reads
// as near-black floors between pools; nudge in-tool per stage taste.
let mr = 0, mg = 0, mb = 0;
for (const v of verts) { mr += v.c[0]; mg += v.c[1]; mb += v.c[2]; }
const meanLum = verts.reduce((s, v) => s + v.l, 0) / verts.length;
const ambient = {
  color: [mr / verts.length, mg / verts.length, mb / verts.length].map((n) => +n.toFixed(3)),
  energy: +(0.05 + meanLum * 0.16).toFixed(2),
};

// Greedy luminance-weighted clustering of the bright tail.
const bright = verts.filter((v) => v.l >= THRESHOLD);
const clusters = [];
for (const v of bright) {
  let best = null, bestD = CLUSTER_RADIUS;
  for (const cl of clusters) {
    const d = d3(v.p, cl.centroid);
    if (d < bestD) { best = cl; bestD = d; }
  }
  if (best) {
    best.mass += v.l;
    best.wsum = best.wsum.map((s, k) => s + v.l * v.p[k]);
    best.csum = best.csum.map((s, k) => s + v.c[k]);
    best.n += 1;
    best.centroid = best.wsum.map((s) => s / best.mass);
  } else {
    clusters.push({ mass: v.l, wsum: v.p.map((n) => v.l * n), csum: [...v.c], n: 1, centroid: [...v.p] });
  }
}

// Rank by brightness mass, keep the strongest, and shape them into lights.
clusters.sort((a, b) => b.mass - a.mass);
const kept = clusters.filter((c) => c.n >= MIN_CLUSTER_VERTS).slice(0, MAX_LIGHTS);
const maxMass = kept[0]?.mass ?? 1;
const lights = kept.map((cl, i) => {
  const meanColor = cl.csum.map((s) => s / cl.n);
  // Light color: the cluster's mean bake tint, brightened toward white so
  // the omni reads as a source, not a surface.
  const src = meanColor.map((c, k) => Math.min(1, c * 0.4 + 0.6)) ;
  // Extent: RMS distance of member verts — cheap stand-in computed from
  // the running centroid drift; use cluster vert count as density proxy.
  const extent = Math.sqrt(cl.mass / Math.max(1, cl.n)); // lum concentration
  const strength = cl.mass / maxMass;
  return {
    name: `Bake${String(i + 1).padStart(2, '0')}`,
    pos: cl.centroid.map((n) => +n.toFixed(2)),
    color: src.map((n) => +n.toFixed(3)),
    energy: +(1.6 + 2.0 * strength).toFixed(2),
    range: +(10 + 8 * extent).toFixed(1),
    attenuation: 1.0,
    shadows: false,
  };
});

const doc = { stage: stageArg, ambient, lights };
writeFileSync(OUT, JSON.stringify(doc, null, 2) + '\n');
console.log(`${OUT}: ambient ${ambient.color.join(',')} @ ${ambient.energy}`);
for (const l of lights) {
  console.log(`  ${l.name}  pos ${l.pos.join(',')}  color ${l.color.join(',')}  energy ${l.energy}  range ${l.range}`);
}
console.log(`(${bright.length} bright verts of ${verts.length} → ${lights.length} lights)`);
