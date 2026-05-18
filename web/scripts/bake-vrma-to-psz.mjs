// Bake VRMA / VRM-source animations into a PSZ-targeted GLB so player
// characters (130+ PSZ variants all sharing 12 named bones) can play
// VRoid Hub / BOOTH / community VRMA motions.
//
// Mirror of bake-retarget-vrm.mjs but with the source and target
// flipped: VRM rig as source, PSZ player rig as target. Uses the
// generalized buildRetargetedClip (RetargetDirection config) so the
// arm-correction step works with VRM J_Bip_* arm names as the source.
//
// Usage: cd web && node scripts/bake-vrma-to-psz.mjs
//
// Output: assets/animations/vrma_psz.glb with PSZ-targeted clips
//   built from up to seven pixiv VRMA inputs (VRMA_01..07). The actual
//   clip count depends on which inputs survive the three.js
//   GLTFLoader/Exporter round-trip; current run produces four
//   (greeting, peace_sign, shoot, show_full_body — VRMA_05/06/07
//   lose their animation tracks during export, same limitation as
//   bake-retarget-vrm.mjs).
//
// Pixiv VRMA attribution required when shipped: "Animation credits to
// pixiv Inc.'s VRoid Project" (assets/npcs/item_shop/vrma/LICENSE.txt).

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

// Reverse bone map: VRM J_Bip_* → PSZ named bones (010_Hip etc.). Inline
// to avoid a circular import dance with retarget-utils.ts and to keep the
// script self-contained.
const BONE_MAPPINGS_VRM_TO_PSZ = {
  Root: '000_Root',
  J_Bip_C_Hips: '010_Hip',
  J_Bip_C_UpperChest: '020_Spine',
  J_Bip_C_Head: '090_Head',
  J_Bip_L_UpperArm: '030_LArm01',
  J_Bip_L_LowerArm: '040_LArm02',
  J_Bip_R_UpperArm: '060_RArm01',
  J_Bip_R_LowerArm: '070_RArm02',
  J_Bip_L_UpperLeg: '100_LLeg01',
  J_Bip_L_LowerLeg: '110_LLeg02',
  J_Bip_R_UpperLeg: '120_RLeg01',
  J_Bip_R_LowerLeg: '130_RLeg02',
};

const VRM_TO_PSZ_DIRECTION = {
  armSourceBones: [
    'J_Bip_L_UpperArm', 'J_Bip_R_UpperArm',
    'J_Bip_L_LowerArm', 'J_Bip_R_LowerArm',
  ],
  rootSourceBone: 'Root',
};

// Reference VRM (any VRoid-authored model works; we use the item-shop
// NPC's since it's already in-tree) to capture the source rest pose.
// The VRMA file itself contains a bone hierarchy but no skinned mesh,
// so its rest is functionally equivalent — using the item-shop rig
// keeps us symmetrical with bake-retarget-vrm.mjs.
const VRM_REF_PATH = path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop.glb');
// PSZ player rig that defines our target skeleton.
const PSZ_REF_PATH = path.join(REPO_ROOT, 'assets/player/pc_000/pc_000_000.glb');
const VRMA_DIR = path.join(REPO_ROOT, 'assets/npcs/item_shop/vrma');
const OUT_PATH = path.join(REPO_ROOT, 'assets/animations/vrma_psz.glb');

const CLIPS = [
  { file: 'VRMA_01.vrma', name: 'vrma_show_full_body_psz' },
  { file: 'VRMA_02.vrma', name: 'vrma_greeting_psz' },
  { file: 'VRMA_03.vrma', name: 'vrma_peace_sign_psz' },
  { file: 'VRMA_04.vrma', name: 'vrma_shoot_psz' },
  { file: 'VRMA_05.vrma', name: 'vrma_spin_psz' },
  { file: 'VRMA_06.vrma', name: 'vrma_model_pose_psz' },
  { file: 'VRMA_07.vrma', name: 'vrma_squat_psz' },
];

// ── Helpers (mirror retarget-utils.ts) ──────────────────────────────

function loadGLB(filePath) {
  return new Promise((resolve, reject) => {
    const data = fs.readFileSync(filePath);
    const loader = new GLTFLoader();
    loader.parse(data.buffer, '', (gltf) => resolve(gltf), reject);
  });
}

function captureRestPose(model) {
  const localQuats = {};
  const worldQuats = {};
  const parentMap = {};
  model.traverse((child) => {
    if (child.isBone) {
      localQuats[child.name] = child.quaternion.clone();
      const wq = new THREE.Quaternion();
      child.getWorldQuaternion(wq);
      worldQuats[child.name] = wq;
      parentMap[child.name] = child.parent?.isBone ? child.parent.name : null;
    }
  });
  return { localQuats, worldQuats, parentMap };
}

function getWorldRestQuat(boneName, restData) {
  const result = new THREE.Quaternion();
  const chain = [];
  let cur = boneName;
  while (cur) {
    chain.unshift(cur);
    cur = restData.parentMap[cur] || null;
  }
  for (const name of chain) {
    const local = restData.localQuats[name];
    if (local) result.multiply(local);
  }
  return result;
}

function resetToBindPose(model) {
  model.traverse((child) => {
    if (child.isSkinnedMesh && child.skeleton) child.skeleton.pose();
  });
  model.updateMatrixWorld(true);
}

// Same skeleton-agnostic retarget math as retarget-utils.buildRetargetedClip,
// but with the direction config inlined for the VRM→PSZ direction.
function buildRetargetedClip(clip, sourceRest, targetRest, boneMap, posScale, outputName) {
  if (Object.keys(boneMap).length === 0) return null;
  const adjustedTargetRest = {
    localQuats: { ...targetRest.localQuats },
    worldQuats: { ...targetRest.worldQuats },
    parentMap: targetRest.parentMap,
  };

  // Arm correction — keyed by VRM source arm bones.
  for (const sourceArm of VRM_TO_PSZ_DIRECTION.armSourceBones) {
    const targetArm = boneMap[sourceArm];
    if (!targetArm) continue;
    const targetParent = adjustedTargetRest.parentMap[targetArm];
    const targetParentWorld = targetParent
      ? getWorldRestQuat(targetParent, adjustedTargetRest)
      : new THREE.Quaternion();
    const sourceArmWorld = getWorldRestQuat(sourceArm, sourceRest);
    adjustedTargetRest.localQuats[targetArm] = targetParentWorld
      .clone()
      .invert()
      .multiply(sourceArmWorld);
  }

  const tracks = [];
  const identity = new THREE.Quaternion();
  const rootSourceBone = VRM_TO_PSZ_DIRECTION.rootSourceBone;

  for (const track of clip.tracks) {
    const dotIdx = track.name.lastIndexOf('.');
    if (dotIdx < 0) continue;
    // VRMA tracks come out of three.js GLTFLoader as hierarchical paths
    // like "J_Bip_C_Hips/J_Bip_C_Spine/J_Bip_C_Chest.quaternion" — the
    // bone name is the last "/" segment. Plain "J_Bip_C_Hips.quaternion"
    // also works for sources that aren't hierarchically nested.
    const fullPath = track.name.substring(0, dotIdx);
    const boneName = fullPath.split('/').pop();
    const prop = track.name.substring(dotIdx);

    const targetBoneName = boneMap[boneName];
    if (!targetBoneName) continue;

    if (prop === '.quaternion') {
      const srcLocalRest = sourceRest.localQuats[boneName] || identity;
      const tgtLocalRest = adjustedTargetRest.localQuats[targetBoneName] || identity;
      const srcWorldRest = getWorldRestQuat(boneName, sourceRest);
      const tgtWorldRest = getWorldRestQuat(targetBoneName, adjustedTargetRest);
      const F = tgtWorldRest.clone().invert().multiply(srcWorldRest);
      const Finv = F.clone().invert();
      const prefix = tgtLocalRest.clone().multiply(F).multiply(srcLocalRest.clone().invert());
      const suffix = Finv;

      const srcValues = track.values;
      const dstValues = new Float32Array(srcValues.length);
      const localAnim = new THREE.Quaternion();
      for (let i = 0; i < srcValues.length; i += 4) {
        localAnim.set(srcValues[i], srcValues[i + 1], srcValues[i + 2], srcValues[i + 3]);
        const out = prefix.clone().multiply(localAnim).multiply(suffix);
        dstValues[i] = out.x;
        dstValues[i + 1] = out.y;
        dstValues[i + 2] = out.z;
        dstValues[i + 3] = out.w;
      }
      tracks.push(new THREE.QuaternionKeyframeTrack(
        targetBoneName + '.quaternion',
        Array.from(track.times),
        Array.from(dstValues),
      ));
    } else if (prop === '.position' && boneName === rootSourceBone) {
      const srcWorldRest = getWorldRestQuat(boneName, sourceRest);
      const tgtWorldRest = getWorldRestQuat(targetBoneName, adjustedTargetRest);
      const F = tgtWorldRest.clone().invert().multiply(srcWorldRest);
      const posRotation = F.clone().invert();

      const srcValues = track.values;
      const dstValues = new Float32Array(srcValues.length);
      const pos = new THREE.Vector3();
      for (let i = 0; i < srcValues.length; i += 3) {
        pos.set(srcValues[i], srcValues[i + 1], srcValues[i + 2]);
        pos.applyQuaternion(posRotation);
        dstValues[i] = pos.x * posScale;
        dstValues[i + 1] = pos.y * posScale;
        dstValues[i + 2] = pos.z * posScale;
      }
      tracks.push(new THREE.VectorKeyframeTrack(
        targetBoneName + '.position',
        Array.from(track.times),
        Array.from(dstValues),
      ));
    }
  }
  if (tracks.length === 0) return null;
  return new THREE.AnimationClip(outputName || clip.name + '_psz', clip.duration, tracks);
}

// ── Main ─────────────────────────────────────────────────────────────

async function main() {
  console.log('Loading reference rigs…');
  const [vrmRef, pszRef] = await Promise.all([loadGLB(VRM_REF_PATH), loadGLB(PSZ_REF_PATH)]);

  console.log('Capturing source (VRM) rest pose…');
  const vrmModel = vrmRef.scene;
  vrmModel.updateMatrixWorld(true);
  resetToBindPose(vrmModel);
  vrmModel.updateMatrixWorld(true);
  const vrmRest = captureRestPose(vrmModel);

  console.log('Capturing target (PSZ) rest pose…');
  const pszModel = pszRef.scene;
  pszModel.updateMatrixWorld(true);
  resetToBindPose(pszModel);
  pszModel.updateMatrixWorld(true);
  const pszRest = captureRestPose(pszModel);

  // PSZ is ~1.5m tall, VRM ~1.84m — scale root position to compensate
  // so the character doesn't shuffle in place at the wrong stride.
  const vrmBox = new THREE.Box3().setFromObject(vrmModel);
  const pszBox = new THREE.Box3().setFromObject(pszModel);
  const vrmH = vrmBox.max.y - vrmBox.min.y;
  const pszH = pszBox.max.y - pszBox.min.y;
  const posScale = vrmH > 0 ? pszH / vrmH : 1;
  console.log(`  VRM height ${vrmH.toFixed(3)}m, PSZ height ${pszH.toFixed(3)}m, posScale ${posScale.toFixed(4)}`);

  console.log('\nRetargeting clips:');
  const outClips = [];
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
    const retargeted = buildRetargetedClip(
      gltf.animations[0], vrmRest, pszRest, BONE_MAPPINGS_VRM_TO_PSZ, posScale, name,
    );
    if (retargeted) {
      outClips.push(retargeted);
      console.log(`  ${file} → ${name} (${retargeted.duration.toFixed(2)}s, ${retargeted.tracks.length} tracks)`);
    } else {
      console.warn(`  ${file} → no usable tracks (likely VRMA internal node names diverged)`);
    }
  }
  if (outClips.length === 0) {
    console.error('No clips produced — aborting');
    process.exit(1);
  }

  // Strip textures for headless export.
  pszRef.scene.traverse((child) => {
    if (child.isMesh) child.material = new THREE.MeshBasicMaterial();
  });

  const exporter = new GLTFExporter();
  const glb = await exporter.parseAsync(pszRef.scene, {
    binary: true,
    animations: outClips,
  });
  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, Buffer.from(glb));
  console.log(`\nWrote ${path.relative(REPO_ROOT, OUT_PATH)} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
