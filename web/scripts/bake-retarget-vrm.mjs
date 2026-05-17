// Bake retargeted PSO animations into a VRM-targeted GLB so the
// item-shop NPC (which uses a VRM rig with J_Bip_* bone names) can
// play them in-game via the existing CityNPC animation pipeline.
//
// Usage: cd web && node scripts/bake-retarget-vrm.mjs
//
// Output is written to assets/player/animations/npc_idles_vrm.glb —
// CityNPC's NPC_ANIM_SOURCES list is extended to include this file,
// so when the ShopNPC's idle_anim ("pso_f_sh_stand") is looked up
// across the source GLBs it finds the VRM-targeted version and binds
// correctly to the item-shop's J_Bip_* skeleton.

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

// PSO bone → VRM bone (from web/src/retarget/retarget-utils.ts).
const BONE_MAPPINGS_VRM = {
  bone_000: 'Root',
  bone_002: 'J_Bip_C_Hips',
  bone_024: 'J_Bip_C_Chest',
  bone_025: 'J_Bip_C_UpperChest',
  bone_028: 'J_Bip_L_UpperArm',
  bone_029: 'J_Bip_L_LowerArm',
  bone_041: 'J_Bip_R_UpperArm',
  bone_042: 'J_Bip_R_LowerArm',
  bone_056: 'J_Bip_C_Head',
  bone_004: 'J_Bip_L_UpperLeg',
  bone_005: 'J_Bip_L_LowerLeg',
  bone_013: 'J_Bip_R_UpperLeg',
  bone_014: 'J_Bip_R_LowerLeg',
};

// Baked offsets from the VRM tuner (RetargetTunerVrm.tsx
// BAKED_OPTIMAL_OFFSETS) — direction-match output plus three manual
// corrections discovered visually: L forearm X+90, R upper arm Z+180,
// R forearm X-90.
const BAKED_OFFSETS = {
  Root: { x: -0.2, y: 0, z: 0 },
  J_Bip_C_Hips: { x: -13.5, y: 0.2, z: -1 },
  J_Bip_C_UpperChest: { x: 14.7, y: 0, z: -0.4 },
  J_Bip_L_UpperLeg: { x: -5.3, y: -0.2, z: 4.6 },
  J_Bip_L_LowerLeg: { x: 1.4, y: 0.1, z: 4.6 },
  J_Bip_R_UpperLeg: { x: -5.3, y: 0.2, z: -4.5 },
  J_Bip_R_LowerLeg: { x: 1.4, y: -0.1, z: -4.5 },
  J_Bip_L_LowerArm: { x: 90, y: 0, z: 0 },
  J_Bip_R_UpperArm: { x: 0, y: 0, z: 180 },
  J_Bip_R_LowerArm: { x: -90, y: 0, z: 0 },
};

// Animations to bake. Format: { index: <PSO anim number>, name: <output clip name> }.
// Start with just the item-shop NPC's idle pose; can extend later
// (greeting, browse, leave) for richer interaction.
// All clip names are suffixed _vrm so they don't collide with the
// PSZ-targeted versions of the same animations in npc_idles.glb.
// CityNPC searches NPC_ANIM_SOURCES by name; if a VRM clip shared the
// PSZ name, PSZ NPCs would get a clip that targets J_Bip_* bones they
// don't have (and vice-versa). The _vrm suffix keeps the two parallel
// libraries cleanly separated.
const ANIMS = [
  { index: 279, name: 'pso_f_sh_stand_vrm' },     // female shop NPC idle
  { index: 278, name: 'pso_f_emote_bow_vrm' },    // greet/bow — for interaction response
];

const PSO_PATH = path.join(REPO_ROOT, 'data/retarget/Humar_body.glb');
const VRM_PATH = path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop.glb');
// Ships in-tree with the item_shop NPC's other assets — assets/player/*
// is excluded from the APK by export_presets.cfg (those ship via the
// Arweave asset pack), so putting the VRM anim library there would
// strip it from the binary and the in-game NPC would T-pose at load.
const OUT_PATH = path.join(REPO_ROOT, 'assets/npcs/item_shop/npc_idles_vrm.glb');

// ── three.js retargeting math (mirrors web/src/retarget/retarget-utils.ts) ──

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

// Skeleton-agnostic retargeting — keyed by bone-map entries so the
// same routine handles any target skeleton (PSZ, VRM, etc.).
function buildRetargetedClip(clip, psoRest, targetRest, boneMap, posScale, outputName, boneOffsets) {
  if (Object.keys(boneMap).length === 0) return null;
  const adjustedTargetRest = {
    localQuats: { ...targetRest.localQuats },
    worldQuats: { ...targetRest.worldQuats },
    parentMap: targetRest.parentMap,
  };

  // Arm rest-pose correction: align each target upper-arm/forearm
  // world rest orientation with PSO's so the retargeting math F
  // factor stays clean. Keyed off PSO bone names; the target bone is
  // resolved through boneMap so this works for any target rig.
  const armPsoBones = ['bone_028', 'bone_041', 'bone_029', 'bone_042'];
  for (const psoBone of armPsoBones) {
    const targetBone = boneMap[psoBone];
    if (!targetBone) continue;
    const targetParent = adjustedTargetRest.parentMap[targetBone];
    const targetParentWorld = targetParent
      ? getWorldRestQuat(targetParent, adjustedTargetRest)
      : new THREE.Quaternion();
    const psoArmWorld = getWorldRestQuat(psoBone, psoRest);
    adjustedTargetRest.localQuats[targetBone] = targetParentWorld
      .clone()
      .invert()
      .multiply(psoArmWorld);
  }

  // Apply offsets AFTER arm correction (deliberately, so the user-
  // tuned offsets layer on top of the arm-correction's idealised rest).
  if (boneOffsets) {
    const deg2rad = Math.PI / 180;
    for (const [boneName, offset] of Object.entries(boneOffsets)) {
      if (offset.x === 0 && offset.y === 0 && offset.z === 0) continue;
      const base = adjustedTargetRest.localQuats[boneName];
      if (!base) continue;
      const euler = new THREE.Euler(
        offset.x * deg2rad,
        offset.y * deg2rad,
        offset.z * deg2rad,
        'XYZ',
      );
      const offsetQuat = new THREE.Quaternion().setFromEuler(euler);
      adjustedTargetRest.localQuats[boneName] = base.clone().multiply(offsetQuat);
    }
  }

  const tracks = [];
  const identity = new THREE.Quaternion();
  for (const track of clip.tracks) {
    const dotIdx = track.name.indexOf('.');
    if (dotIdx < 0) continue;
    const boneName = track.name.substring(0, dotIdx);
    const prop = track.name.substring(dotIdx);
    const targetBoneName = boneMap[boneName];
    if (!targetBoneName) continue;

    if (prop === '.quaternion') {
      const psoLocalRest = psoRest.localQuats[boneName] || identity;
      const targetLocalRest = adjustedTargetRest.localQuats[targetBoneName] || identity;
      const psoWorldRest = getWorldRestQuat(boneName, psoRest);
      const targetWorldRest = getWorldRestQuat(targetBoneName, adjustedTargetRest);
      const F = targetWorldRest.clone().invert().multiply(psoWorldRest);
      const Finv = F.clone().invert();
      const prefix = targetLocalRest.clone().multiply(F).multiply(psoLocalRest.clone().invert());
      const suffix = Finv;
      const srcValues = track.values;
      const dstValues = new Float32Array(srcValues.length);
      const psoLocalAnim = new THREE.Quaternion();
      for (let i = 0; i < srcValues.length; i += 4) {
        psoLocalAnim.set(srcValues[i], srcValues[i + 1], srcValues[i + 2], srcValues[i + 3]);
        const out = prefix.clone().multiply(psoLocalAnim).multiply(suffix);
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
    } else if (prop === '.position' && boneName === 'bone_000') {
      // Root position needs to rotate with the retargeted root orientation
      // so the character moves in the correct facing direction.
      const psoWorldRest = getWorldRestQuat(boneName, psoRest);
      const targetWorldRest = getWorldRestQuat(targetBoneName, adjustedTargetRest);
      const F = targetWorldRest.clone().invert().multiply(psoWorldRest);
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
  return new THREE.AnimationClip(outputName || clip.name + '_vrm', clip.duration, tracks);
}

// ── Main ──

async function main() {
  console.log('Loading source models…');
  const [psoGltf, vrmGltf] = await Promise.all([loadGLB(PSO_PATH), loadGLB(VRM_PATH)]);

  console.log('Capturing rest poses…');
  const psoModel = psoGltf.scene;
  psoModel.updateMatrixWorld(true);
  resetToBindPose(psoModel);
  psoModel.updateMatrixWorld(true);
  const psoRest = captureRestPose(psoModel);

  const vrmModel = vrmGltf.scene;
  vrmModel.updateMatrixWorld(true);
  resetToBindPose(vrmModel);
  vrmModel.updateMatrixWorld(true);
  const vrmRest = captureRestPose(vrmModel);

  // Same height-normalisation as the runtime tuner does — keeps
  // bake-time math in sync with the in-editor preview.
  const psoBox = new THREE.Box3().setFromObject(psoModel);
  const vrmBox = new THREE.Box3().setFromObject(vrmModel);
  const psoH = psoBox.max.y - psoBox.min.y;
  const vrmH = vrmBox.max.y - vrmBox.min.y;
  const posScale = psoH > 0 ? vrmH / psoH : 1;
  console.log(`  PSO height ${psoH.toFixed(3)}m, VRM height ${vrmH.toFixed(3)}m, posScale ${posScale.toFixed(4)}`);

  console.log('\nRetargeting animations:');
  const newClips = [];
  for (const { index, name } of ANIMS) {
    const clipName = `plymotiondata_${String(index).padStart(3, '0')}`;
    const srcClip = psoGltf.animations.find((c) => c.name === clipName);
    if (!srcClip) {
      console.warn(`  ${clipName} not found — skipping ${name}`);
      continue;
    }
    const retargeted = buildRetargetedClip(
      srcClip, psoRest, vrmRest, BONE_MAPPINGS_VRM, posScale, name, BAKED_OFFSETS,
    );
    if (retargeted) {
      newClips.push(retargeted);
      console.log(`  ${clipName} → ${name} (${retargeted.duration.toFixed(2)}s, ${retargeted.tracks.length} tracks)`);
    }
  }

  if (newClips.length === 0) {
    console.error('No clips retargeted — aborting.');
    process.exit(1);
  }

  // Strip materials/textures from the VRM scene before export — the
  // in-game CityNPC only needs the AnimationPlayer's clips out of this
  // file (the actual mesh comes from item_shop.glb on the NPC model
  // itself), and the VRM's textured materials would inflate the
  // output GLB to 8MB+ for no runtime benefit.
  vrmGltf.scene.traverse((child) => {
    if (child.isMesh) child.material = new THREE.MeshBasicMaterial();
  });

  console.log('\nExporting…');
  const exporter = new GLTFExporter();
  const glb = await exporter.parseAsync(vrmGltf.scene, {
    binary: true,
    animations: newClips,
  });
  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, Buffer.from(glb));
  console.log(`  Wrote ${path.relative(REPO_ROOT, OUT_PATH)} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
