// Bake retargeted PSO walk/run animations into saber_m.glb
// Usage: cd web && node scripts/bake-retarget.mjs
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

// ── Bone mapping: PSO → PSZ ──────────────────────────────────────

const BONE_MAPPINGS = {
  bone_000: '000_Root',
  bone_002: '010_Hip',
  bone_024: '020_Spine',
  bone_028: '030_LArm01',
  bone_029: '040_LArm02',
  bone_041: '060_RArm01',
  bone_042: '070_RArm02',
  bone_056: '090_Head',
  bone_004: '100_LLeg01',
  bone_005: '110_LLeg02',
  bone_013: '120_RLeg01',
  bone_014: '130_RLeg02',
};

// ── Tuned bone offsets (from PlayerAnimationStorybook) ────────────

const WALK_OFFSETS = {
  '020_Spine': { x: 0, y: 8, z: 0 },
  '090_Head': { x: 0, y: 10, z: 0 },
  '030_LArm01': { x: 0, y: -15, z: 0 },
  '040_LArm02': { x: 90, y: 0, z: 0 },
  '060_RArm01': { x: 0, y: 15, z: 0 },
  '070_RArm02': { x: 90, y: 0, z: 0 },
};

const RUN_OFFSETS = {
  '020_Spine': { x: 0, y: 8, z: 0 },
  '090_Head': { x: 0, y: 3, z: 0 },
  '030_LArm01': { x: 0, y: -10, z: 0 },
  '040_LArm02': { x: 90, y: 0, z: 0 },
  '060_RArm01': { x: 0, y: 10, z: 0 },
  '070_RArm02': { x: 90, y: 0, z: 0 },
};

const RETARGET_ANIMS = [
  { index: 200, name: 'pmsa_walk', offsets: WALK_OFFSETS },
  { index: 207, name: 'pmsa_run_pso', offsets: RUN_OFFSETS },
];

// ── Retarget utilities (inlined from retarget-utils.ts) ──────────

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
    if (child.isSkinnedMesh && child.skeleton) {
      child.skeleton.pose();
    }
  });
  model.updateMatrixWorld(true);
}

function buildRetargetedClip(clip, psoRest, pszRest, boneMap, posScale, outputName, boneOffsets) {
  if (Object.keys(boneMap).length === 0) return null;

  const adjustedPszRest = {
    localQuats: { ...pszRest.localQuats },
    worldQuats: { ...pszRest.worldQuats },
    parentMap: pszRest.parentMap,
  };

  // Correct arm rest poses so PSZ bone world orientations match PSO's
  const armCorrectionBones = [
    ['bone_028', '030_LArm01'],
    ['bone_041', '060_RArm01'],
    ['bone_029', '040_LArm02'],
    ['bone_042', '070_RArm02'],
  ];
  for (const [psoBone, pszBone] of armCorrectionBones) {
    if (!(psoBone in boneMap) || boneMap[psoBone] !== pszBone) continue;
    const pszParent = adjustedPszRest.parentMap[pszBone];
    const pszParentWorld = pszParent ? getWorldRestQuat(pszParent, adjustedPszRest) : new THREE.Quaternion();
    const psoArmWorld = getWorldRestQuat(psoBone, psoRest);
    adjustedPszRest.localQuats[pszBone] = pszParentWorld.clone().invert().multiply(psoArmWorld);
  }

  // Apply bone offsets after arm correction
  if (boneOffsets) {
    const deg2rad = Math.PI / 180;
    for (const [boneName, offset] of Object.entries(boneOffsets)) {
      if (offset.x === 0 && offset.y === 0 && offset.z === 0) continue;
      const base = adjustedPszRest.localQuats[boneName];
      if (!base) continue;
      const euler = new THREE.Euler(offset.x * deg2rad, offset.y * deg2rad, offset.z * deg2rad, 'XYZ');
      const offsetQuat = new THREE.Quaternion().setFromEuler(euler);
      adjustedPszRest.localQuats[boneName] = base.clone().multiply(offsetQuat);
    }
  }

  const tracks = [];
  const identity = new THREE.Quaternion();

  for (const track of clip.tracks) {
    const dotIdx = track.name.indexOf('.');
    if (dotIdx < 0) continue;
    const boneName = track.name.substring(0, dotIdx);
    const prop = track.name.substring(dotIdx);
    const pszBoneName = boneMap[boneName];
    if (!pszBoneName) continue;

    if (prop === '.quaternion') {
      const psoLocalRest = psoRest.localQuats[boneName] || identity;
      const pszLocalRest = adjustedPszRest.localQuats[pszBoneName] || identity;
      const psoWorldRest = getWorldRestQuat(boneName, psoRest);
      const pszWorldRest = getWorldRestQuat(pszBoneName, adjustedPszRest);

      const F = pszWorldRest.clone().invert().multiply(psoWorldRest);
      const Finv = F.clone().invert();
      const prefix = pszLocalRest.clone().multiply(F).multiply(psoLocalRest.clone().invert());
      const suffix = Finv;

      const srcValues = track.values;
      const dstValues = new Float32Array(srcValues.length);
      const psoLocalAnim = new THREE.Quaternion();

      for (let i = 0; i < srcValues.length; i += 4) {
        psoLocalAnim.set(srcValues[i], srcValues[i + 1], srcValues[i + 2], srcValues[i + 3]);
        const pszLocalResult = prefix.clone().multiply(psoLocalAnim).multiply(suffix);
        dstValues[i] = pszLocalResult.x;
        dstValues[i + 1] = pszLocalResult.y;
        dstValues[i + 2] = pszLocalResult.z;
        dstValues[i + 3] = pszLocalResult.w;
      }

      tracks.push(new THREE.QuaternionKeyframeTrack(
        pszBoneName + '.quaternion',
        Array.from(track.times),
        Array.from(dstValues),
      ));
    } else if (prop === '.position' && boneName === 'bone_000') {
      const psoWorldRest = getWorldRestQuat(boneName, psoRest);
      const pszWorldRest = getWorldRestQuat(pszBoneName, adjustedPszRest);
      const F = pszWorldRest.clone().invert().multiply(psoWorldRest);
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
        pszBoneName + '.position',
        Array.from(track.times),
        Array.from(dstValues),
      ));
    }
  }

  if (tracks.length === 0) return null;
  return new THREE.AnimationClip(outputName || clip.name + '_retargeted', clip.duration, tracks);
}

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  const psoPath = path.resolve('../data/retarget/Humar_body.glb');
  const pszPath = path.resolve('public/player/pc_000/pc_000/pc_000_000.glb');
  const saberPath = path.resolve('../assets/player/animations/saber_m.glb');

  console.log('Loading models...');
  const [psoGltf, pszGltf, saberGltf] = await Promise.all([
    loadGLB(psoPath),
    loadGLB(pszPath),
    loadGLB(saberPath),
  ]);

  // Compute position scale from height ratio
  const psoModel = psoGltf.scene;
  psoModel.updateMatrixWorld(true);
  const psoBox = new THREE.Box3().setFromObject(psoModel);
  const psoHeight = psoBox.max.y - psoBox.min.y;
  const pszHeight = 1.5;
  const posScale = pszHeight / psoHeight;
  console.log(`PSO height: ${psoHeight.toFixed(3)}, scale: ${posScale.toFixed(4)}`);

  // Capture rest poses
  resetToBindPose(psoModel);
  psoModel.updateMatrixWorld(true);
  const psoRest = captureRestPose(psoModel);

  const pszModel = pszGltf.scene;
  resetToBindPose(pszModel);
  pszModel.updateMatrixWorld(true);
  const pszRest = captureRestPose(pszModel);

  // Retarget walk/run animations
  const newClips = [];
  for (const { index, name, offsets } of RETARGET_ANIMS) {
    const clipName = `plymotiondata_${String(index).padStart(3, '0')}`;
    const srcClip = psoGltf.animations.find((c) => c.name === clipName);
    if (!srcClip) {
      console.warn(`Animation ${clipName} not found, skipping ${name}`);
      continue;
    }
    const retargeted = buildRetargetedClip(srcClip, psoRest, pszRest, BONE_MAPPINGS, posScale, name, offsets);
    if (retargeted) {
      newClips.push(retargeted);
      console.log(`Retargeted: ${clipName} -> ${name} (${retargeted.duration.toFixed(2)}s, ${retargeted.tracks.length} tracks)`);
    }
  }

  if (newClips.length === 0) {
    console.error('No clips were retargeted!');
    process.exit(1);
  }

  // Merge with existing saber_m animations (deduplicate by name)
  const newNames = new Set(newClips.map((c) => c.name));
  const existing = saberGltf.animations.filter((a) => !newNames.has(a.name));
  const allAnims = [...existing, ...newClips];
  console.log(`Existing: ${saberGltf.animations.length}, adding: ${newClips.length}, total: ${allAnims.length}`);

  // Strip materials/textures to avoid export issues in Node.js
  saberGltf.scene.traverse((child) => {
    if (child.isMesh) {
      child.material = new THREE.MeshBasicMaterial();
    }
  });

  // Export as GLB
  const exporter = new GLTFExporter();
  const glb = await exporter.parseAsync(saberGltf.scene, {
    binary: true,
    animations: allAnims,
  });

  fs.writeFileSync(saberPath, Buffer.from(glb));
  console.log(`Written: ${saberPath} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
