// Convert the 7 pixiv VRoid VRMA motion-pack files into a single
// VRM-targeted GLB that the existing CityNPC animation pipeline can
// load. VRMA is structurally a glTF binary with a VRMC_vrm_animation
// extension, but the trick that makes this conversion trivial is that
// pixiv's VRMAs already name their animated nodes with the standard
// VRoid bone names (J_Bip_C_Hips, J_Bip_L_UpperArm, etc.) — exactly
// what the item-shop VRM skeleton uses. So we don't need to walk the
// extension's humanoid-bone map; we can just rewrite the animation
// track paths to bone-name form and bundle into a multi-anim GLB.
//
// Usage: cd web && node scripts/convert-vrma.mjs
//
// Output: assets/npcs/item_shop/vrma_anims.glb with animations
//   vrma_show_full_body, vrma_greeting, vrma_peace_sign, vrma_shoot,
//   vrma_spin, vrma_model_pose, vrma_squat

import { Blob } from 'buffer';
globalThis.self = globalThis;
globalThis.Blob = Blob;
globalThis.document = { createElementNS: () => ({}) };
globalThis.FileReader = class FileReader {
  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then((ab) => {
      this.result = ab;
      if (this.onload) this.onload({ target: this });
      if (this.onloadend) this.onloadend({ target: this });
    });
  }
  readAsDataURL(blob) {
    blob.arrayBuffer().then((ab) => {
      const base64 = Buffer.from(ab).toString('base64');
      this.result = `data:${blob.type || 'application/octet-stream'};base64,${base64}`;
      if (this.onload) this.onload({ target: this });
      if (this.onloadend) this.onloadend({ target: this });
    });
  }
};

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '../..');

const VRMA_DIR = path.join(REPO_ROOT, 'assets/npcs/item_shop/vrma');
const VRM_PATH = path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop.glb');
const OUT_PATH = path.join(REPO_ROOT, 'assets/npcs/item_shop/vrma_anims.glb');

// pixiv VRMA pack file index → output animation name. Names are
// snake_cased per the existing pso_* clip-name convention so future
// CityNPC consumers can request them via `idle_anim`/`interact_anim`.
const CLIPS = [
  { file: 'VRMA_01.vrma', name: 'vrma_show_full_body' },
  { file: 'VRMA_02.vrma', name: 'vrma_greeting' },
  { file: 'VRMA_03.vrma', name: 'vrma_peace_sign' },
  { file: 'VRMA_04.vrma', name: 'vrma_shoot' },
  { file: 'VRMA_05.vrma', name: 'vrma_spin' },
  { file: 'VRMA_06.vrma', name: 'vrma_model_pose' },
  { file: 'VRMA_07.vrma', name: 'vrma_squat' },
];

function loadGLB(filePath) {
  return new Promise((resolve, reject) => {
    const data = fs.readFileSync(filePath);
    const loader = new GLTFLoader();
    loader.parse(data.buffer, '', (gltf) => resolve(gltf), reject);
  });
}

/** Rewrite track names so each track targets just the bone's name,
 *  not the hierarchical node path the VRMA originally used. CityNPC's
 *  remap step will then prepend the actual Skeleton3D path at
 *  runtime, the same way it does for the PSO-retargeted clips. */
function remapClip(srcClip, newName) {
  const tracks = [];
  for (const tr of srcClip.tracks) {
    const dotIdx = tr.name.lastIndexOf('.');
    if (dotIdx < 0) continue;
    const fullNodePath = tr.name.substring(0, dotIdx); // e.g. "J_Bip_C_Hips/J_Bip_C_Spine/J_Bip_C_Chest"
    const prop = tr.name.substring(dotIdx);            // e.g. ".quaternion"
    // Bone name = last path segment. Three.js GLTFLoader builds these
    // path-style track names from the node hierarchy when there's no
    // skeleton wrapping the animated nodes, which is exactly the case
    // for a VRMA (it's a skeleton-only glTF with no skinned mesh).
    const boneName = fullNodePath.split('/').pop();
    const cloned = tr.clone();
    cloned.name = `${boneName}${prop}`;
    tracks.push(cloned);
  }
  return new THREE.AnimationClip(newName, srcClip.duration, tracks);
}

async function main() {
  console.log('Loading VRM target for scene context…');
  const vrmGltf = await loadGLB(VRM_PATH);

  const clips = [];
  for (const { file, name } of CLIPS) {
    const fp = path.join(VRMA_DIR, file);
    if (!fs.existsSync(fp)) {
      console.warn(`  ${file} missing — skipping`);
      continue;
    }
    const gltf = await loadGLB(fp);
    if (gltf.animations.length === 0) {
      console.warn(`  ${file} has no animations — skipping`);
      continue;
    }
    const remapped = remapClip(gltf.animations[0], name);
    clips.push(remapped);
    console.log(`  ${file} → ${name} (${remapped.duration.toFixed(2)}s, ${remapped.tracks.length} tracks)`);
  }
  if (clips.length === 0) {
    console.error('No clips produced.');
    process.exit(1);
  }

  // Strip materials from the VRM mesh to avoid headless texture load
  // issues during export — CityNPC pulls the mesh from item_shop.glb
  // itself, so this anim source GLB only needs the skeleton + clips.
  vrmGltf.scene.traverse((child) => {
    if (child.isMesh) child.material = new THREE.MeshBasicMaterial();
  });

  const exporter = new GLTFExporter();
  const glb = await exporter.parseAsync(vrmGltf.scene, {
    binary: true,
    animations: clips,
  });
  fs.writeFileSync(OUT_PATH, Buffer.from(glb));
  console.log(`\nWrote ${path.relative(REPO_ROOT, OUT_PATH)} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
