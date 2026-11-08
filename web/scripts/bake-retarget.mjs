// Bake retargeted PSO animations into weapon animation GLBs.
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

// Female walk/run offsets — same corrections as male (arms need 90° forearm fix)
const F_WALK_OFFSETS = {
  '020_Spine': { x: 0, y: 8, z: 0 },
  '090_Head': { x: 0, y: 10, z: 0 },
  '030_LArm01': { x: 0, y: -15, z: 0 },
  '040_LArm02': { x: 90, y: 0, z: 0 },
  '060_RArm01': { x: 0, y: 15, z: 0 },
  '070_RArm02': { x: 90, y: 0, z: 0 },
};

const F_RUN_OFFSETS = {
  '020_Spine': { x: 0, y: 8, z: 0 },
  '090_Head': { x: 0, y: 3, z: 0 },
  '030_LArm01': { x: 0, y: -10, z: 0 },
  '040_LArm02': { x: 90, y: 0, z: 0 },
  '060_RArm01': { x: 0, y: 10, z: 0 },
  '070_RArm02': { x: 90, y: 0, z: 0 },
};

// Stand idle offsets — arms at rest, spine/head fixes
const STAND_OFFSETS = {
  '020_Spine': { x: 0, y: 8, z: 0 },
  '090_Head': { x: 0, y: 10, z: 0 },
  '030_LArm01': { x: 0, y: -15, z: 0 },
  '040_LArm02': { x: 90, y: 0, z: 0 },
  '060_RArm01': { x: 0, y: 15, z: 0 },
  '070_RArm02': { x: 90, y: 0, z: 0 },
};

// Each target GLB gets its own list of retarget animations.
// To add a new retargeted animation: add an entry with { index, name, offsets }.
const BAKE_TARGETS = [
  {
    targetGlb: '../assets/player/animations/saber_m.glb',
    anims: [
      { index: 200, name: 'pmsa_walk', offsets: WALK_OFFSETS },
      { index: 207, name: 'pmsa_run_pso', offsets: RUN_OFFSETS },
    ],
  },
  {
    targetGlb: '../assets/player/animations/saver_w.glb',
    anims: [
      { index: 412, name: 'pwsa_walk', offsets: F_WALK_OFFSETS },
      { index: 416, name: 'pwsa_run_pso', offsets: F_RUN_OFFSETS },
    ],
  },
  {
    // Mechgun (male) — missing walk/run
    targetGlb: '../assets/player/animations/machinegun_m.glb',
    anims: [
      { index: 28, name: 'pmmg_walk', offsets: WALK_OFFSETS },
      { index: 35, name: 'pmmg_run', offsets: RUN_OFFSETS },
    ],
  },
  {
    // Mechgun (female) — missing walk/run
    targetGlb: '../assets/player/animations/machinegun_w.glb',
    anims: [
      { index: 267, name: 'pwmgs_walk', offsets: F_WALK_OFFSETS },
      { index: 272, name: 'pwmgs_run', offsets: F_RUN_OFFSETS },
    ],
  },
  {
    // Rifle (male) — PSO rifle animations baked into shotgun GLB
    targetGlb: '../assets/player/animations/shotgun_m.glb',
    anims: [
      { index: 12, name: 'pmri_atk1', offsets: WALK_OFFSETS },
      { index: 13, name: 'pmri_wait', offsets: WALK_OFFSETS },
      { index: 15, name: 'pmri_walk', offsets: WALK_OFFSETS },
      { index: 19, name: 'pmri_dam_n', offsets: WALK_OFFSETS },
      { index: 22, name: 'pmri_run', offsets: RUN_OFFSETS },
    ],
  },
  {
    // Rifle (female) — PSO rifle animations
    targetGlb: '../assets/player/animations/shotgun_w.glb',
    anims: [
      { index: 252, name: 'pwri_atk1', offsets: F_WALK_OFFSETS },
      { index: 253, name: 'pwri_wait', offsets: F_WALK_OFFSETS },
      { index: 255, name: 'pwri_walk', offsets: F_WALK_OFFSETS },
      { index: 258, name: 'pwri_dam_n', offsets: F_WALK_OFFSETS },
      { index: 262, name: 'pwri_run', offsets: F_RUN_OFFSETS },
    ],
  },
  {
    // NPC idle animations — baked into a copy of the PSZ player skeleton
    targetGlb: '../assets/player/animations/npc_idles.glb',
    anims: [
      { index: 70, name: 'pso_ro_stand', offsets: STAND_OFFSETS },
      { index: 279, name: 'pso_f_sh_stand', offsets: STAND_OFFSETS },
      { index: 307, name: 'pso_f_ro_stand', offsets: STAND_OFFSETS },
      { index: 335, name: 'pso_f_sa_stand', offsets: STAND_OFFSETS },
      { index: 421, name: 'plymotiondata_421', offsets: STAND_OFFSETS },
      { index: 429, name: 'pso_f_emote_bow', offsets: STAND_OFFSETS },
    ],
  },
  {
    // Slicer (male) — PSZ native anims + PSO walk/run
    targetGlb: '../assets/player/animations/slicer_m.glb',
    anims: [
      { index: 200, name: 'pmsl_walk', offsets: WALK_OFFSETS },
      { index: 207, name: 'pmsl_run_pso', offsets: RUN_OFFSETS },
    ],
  },
  {
    // Slicer (female) — PSZ native anims + PSO walk/run
    targetGlb: '../assets/player/animations/slicer_w.glb',
    anims: [
      { index: 412, name: 'pwsls_walk', offsets: F_WALK_OFFSETS },
      { index: 416, name: 'pwsls_run_pso', offsets: F_RUN_OFFSETS },
    ],
  },
  {
    // Claw (male) — PSZ native anims + PSO walk/run
    targetGlb: '../assets/player/animations/claw_m.glb',
    anims: [
      { index: 200, name: 'pmcl_walk', offsets: WALK_OFFSETS },
      { index: 207, name: 'pmcl_run_pso', offsets: RUN_OFFSETS },
    ],
  },
  {
    // Claw (female) — PSZ native anims + PSO walk/run
    targetGlb: '../assets/player/animations/claw_w.glb',
    anims: [
      { index: 412, name: 'pwcl_walk', offsets: F_WALK_OFFSETS },
      { index: 416, name: 'pwcl_run_pso', offsets: F_RUN_OFFSETS },
    ],
  },
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
  const femaleSaber = process.argv.includes('--female-saber');
  const maleSaber = process.argv.includes('--humar-saber');
  const femaleDouble = process.argv.includes('--female-double-saber');
  const femaleSpear = process.argv.includes('--female-spear');
  const femaleSlicer = process.argv.includes('--female-slicer');
  const maleBazooka = process.argv.includes('--male-bazooka');
  const femaleRifle = process.argv.includes('--female-rifle');
  const maleRifle = process.argv.includes('--male-rifle');
  const femaleMechgun = process.argv.includes('--female-mechgun');
  const maleMechgun = process.argv.includes('--male-mechgun');
  const femaleHandgun = process.argv.includes('--female-handgun');
  const maleHandgun = process.argv.includes('--male-handgun');
  const femaleGunblade = process.argv.includes('--female-gunblade');
  const maleGunblade = process.argv.includes('--male-gunblade');
  const maleSlicer = process.argv.includes('--male-slicer');
  const maleSpear = process.argv.includes('--male-spear');
  const maleDouble = process.argv.includes('--male-double-saber');
  const femaleClaw = process.argv.includes('--female-claw');
  const maleClaw = process.argv.includes('--male-claw');
  const femaleDagger = process.argv.includes('--female-daggers');
  const maleDagger = process.argv.includes('--male-daggers');
  const femaleSword = process.argv.includes('--female-sword');
  const female = femaleSaber || femaleSword || femaleDagger || femaleClaw || femaleDouble || femaleSpear || femaleSlicer || femaleGunblade || femaleHandgun || femaleMechgun || femaleRifle;
  const maleSword = process.argv.includes('--male-sword');
  if ([femaleSaber, maleSaber, maleSword, femaleSword, maleDagger, femaleDagger, maleClaw, femaleClaw, maleDouble, femaleDouble, maleSpear, femaleSpear, maleSlicer, femaleSlicer, maleGunblade, femaleGunblade, maleHandgun, femaleHandgun, maleMechgun, femaleMechgun, maleRifle, femaleRifle, maleBazooka].filter(Boolean).length > 1) throw new Error('Choose one profile per bake');
  const psoPath = path.resolve('../data/retarget/Humar_body.glb');
  // The source archive includes both motion sets on its common PSO skeleton.
  const pszPath = path.resolve(female ? '../assets/player/pc_010/pc_010_000.glb' : '../assets/player/pc_000/pc_000_000.glb');

  console.log('Loading PSO and PSZ models...');
  const [psoGltf, pszGltf] = await Promise.all([
    loadGLB(psoPath),
    loadGLB(pszPath),
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

  // Isolated complete saber library for the Coliseum prototype (#790).
  const saberPrototype = maleSaber || femaleSaber || maleSword || femaleSword || maleDagger || femaleDagger || maleClaw || femaleClaw || maleDouble || femaleDouble || maleSpear || femaleSpear || maleSlicer || femaleSlicer || maleGunblade || femaleGunblade || maleHandgun || femaleHandgun || maleMechgun || femaleMechgun || maleRifle || femaleRifle || maleBazooka;
  const mapping = JSON.parse(fs.readFileSync('../data/retarget/pso_animation_map.json')).mappings;
  const targets = saberPrototype ? [{
    targetGlb: maleBazooka ? '../assets/player/animations/pso_male_bazooka.glb' : femaleRifle ? '../assets/player/animations/pso_female_rifle.glb' : maleRifle ? '../assets/player/animations/pso_male_rifle.glb' : femaleMechgun ? '../assets/player/animations/pso_female_mechgun.glb' : maleMechgun ? '../assets/player/animations/pso_male_mechgun.glb' : femaleHandgun ? '../assets/player/animations/pso_female_handgun.glb' : maleHandgun ? '../assets/player/animations/pso_male_handgun.glb' : femaleGunblade ? '../assets/player/animations/pso_female_gunblade.glb' : maleGunblade ? '../assets/player/animations/pso_male_gunblade.glb' : femaleSlicer ? '../assets/player/animations/pso_female_slicer.glb' : maleSlicer ? '../assets/player/animations/pso_male_slicer.glb' : femaleSpear ? '../assets/player/animations/pso_female_spear.glb' : maleSpear ? '../assets/player/animations/pso_male_spear.glb' : femaleDouble ? '../assets/player/animations/pso_female_double_saber.glb' : maleDouble ? '../assets/player/animations/pso_male_double_saber.glb' : femaleClaw ? '../assets/player/animations/pso_female_claw.glb' : maleClaw ? '../assets/player/animations/pso_male_claw.glb' : femaleDagger ? '../assets/player/animations/pso_female_dagger.glb' : maleDagger ? '../assets/player/animations/pso_male_dagger.glb' : femaleSword ? '../assets/player/animations/pso_female_sword.glb' : maleSword ? '../assets/player/animations/pso_male_sword.glb' : femaleSaber ? '../assets/player/animations/pso_female_saber.glb' : '../assets/player/animations/pso_humar_saber.glb',
    anims: Object.entries(mapping).filter(([, name]) => name.startsWith(maleBazooka ? 'pso_la_' : femaleRifle ? 'pso_f_ri_' : maleRifle ? 'pso_ri_' : femaleMechgun ? 'pso_f_mg_' : maleMechgun ? 'pso_mg_' : femaleHandgun ? 'pso_f_hg_' : maleHandgun ? 'pso_hg_' : femaleGunblade ? 'pso_f_sa_' : maleGunblade ? 'pso_sa_' : maleSlicer || femaleSlicer ? 'pso_sl_' : maleSpear || femaleSpear ? 'pso_pa_' : femaleDouble ? 'pso_f_ds_' : maleDouble ? 'pso_ds_' : femaleClaw ? 'pso_f_cl_' : maleClaw ? 'pso_cl_' : femaleDagger ? 'pso_f_da_' : maleDagger ? 'pso_da_' : femaleSword ? 'pso_f_sw_' : maleSword ? 'pso_sw_' : femaleSaber ? 'pso_f_sa_' : 'pso_sa_'))
      .map(([index, name]) => ({ index: Number(index), name: femaleGunblade ? name.replace('pso_f_sa_', 'pso_f_gb_') : maleGunblade ? name.replace('pso_sa_', 'pso_gb_') : femaleSlicer ? name.replace('pso_sl_', 'pso_f_sl_') : femaleSpear ? name.replace('pso_pa_', 'pso_f_pa_') : name,
        offsets: name.endsWith('_run') ? (female ? F_RUN_OFFSETS : RUN_OFFSETS) : (female ? F_WALK_OFFSETS : WALK_OFFSETS) })),
  }] : BAKE_TARGETS;
  if (saberPrototype && targets[0].anims.length !== (maleBazooka || femaleRifle || maleRifle ? 13 : femaleMechgun ? 10 : maleMechgun ? 11 : femaleHandgun ? 11 : maleHandgun ? 8 : femaleGunblade ? 16 : maleGunblade ? 15 : maleSlicer || femaleSlicer ? 12 : maleSpear || femaleSpear ? 14 : maleClaw || femaleClaw || maleDouble || femaleDouble ? 5 : femaleDagger ? 8 : maleSword || femaleSword || maleDagger ? 13 : femaleSaber ? 16 : 15)) throw new Error('Incomplete saber source inventory');
  // Sword shares the saber run; keep the donor ID explicit.
  if (maleSword) targets[0].anims.push({ index: 111, name: 'pso_sw_run', offsets: RUN_OFFSETS });
  if (femaleSword) targets[0].anims.push({ index: 342, name: 'pso_f_sw_run', offsets: F_RUN_OFFSETS });
  if (maleDagger) targets[0].anims.push({ index: 111, name: 'pso_da_run', offsets: RUN_OFFSETS });
  if (femaleDagger) targets[0].anims.push({ index: 342, name: 'pso_f_da_run', offsets: F_RUN_OFFSETS });
  if (maleClaw) targets[0].anims.push(...[[98, 'tec'], [103, 'block'], [105, 'dam_h'], [106, 'dam_d_wa'], [107, 'dam_n'], [108, 'dam_d'], [110, 'pb'], [111, 'run']].map(([index, role]) => ({ index, name: 'pso_cl_' + role, offsets: role === 'run' ? RUN_OFFSETS : WALK_OFFSETS })));
  if (femaleClaw) targets[0].anims.push(...[[328, 'tec'], [333, 'block'], [336, 'dam_h'], [337, 'dam_d_wa'], [338, 'dam_n'], [339, 'dam_d'], [341, 'pb'], [342, 'run']].map(([index, role]) => ({ index, name: 'pso_f_cl_' + role, offsets: role === 'run' ? F_RUN_OFFSETS : F_WALK_OFFSETS })));
  if (maleDouble) targets[0].anims.push(...[[113, 'tec'], [118, 'block'], [120, 'dam_h'], [121, 'dam_d_wa'], [122, 'dam_n'], [123, 'dam_d'], [124, 'pb'], [111, 'run']].map(([index, role]) => ({ index, name: 'pso_ds_' + role, offsets: role === 'run' ? RUN_OFFSETS : WALK_OFFSETS })));
  if (femaleDouble) targets[0].anims.push(...[[344, 'tec'], [349, 'block'], [351, 'dam_h'], [352, 'dam_d_wa'], [353, 'dam_n'], [354, 'dam_d'], [355, 'pb'], [342, 'run']].map(([index, role]) => ({ index, name: 'pso_f_ds_' + role, offsets: role === 'run' ? F_RUN_OFFSETS : F_WALK_OFFSETS })));
  if (maleSlicer) targets[0].anims.push(...[[98, 'tec'], [103, 'block'], [111, 'run']].map(([index, role]) => ({ index, name: 'pso_sl_' + role, offsets: role === 'run' ? RUN_OFFSETS : WALK_OFFSETS })));
  if (femaleSlicer) targets[0].anims.push(...[[328, 'tec'], [333, 'block'], [342, 'run']].map(([index, role]) => ({ index, name: 'pso_f_sl_' + role, offsets: role === 'run' ? F_RUN_OFFSETS : F_WALK_OFFSETS })));
  if (maleBazooka) targets[0].anims.push({ index: 108, name: 'pso_la_dam_d', offsets: WALK_OFFSETS });
  if (maleRifle) targets[0].anims.push({ index: 110, name: 'pso_ri_pb', offsets: WALK_OFFSETS });
  if (femaleMechgun) targets[0].anims.push(...[[328, 'tec'], [341, 'pb']].map(([index, role]) => ({ index, name: 'pso_f_mg_' + role, offsets: F_WALK_OFFSETS })));
  if (maleMechgun) targets[0].anims.push(...[[105, 'dam_h'], [106, 'dam_d_wa']].map(([index, role]) => ({ index, name: 'pso_mg_' + role, offsets: WALK_OFFSETS })));
  if (femaleHandgun) targets[0].anims.push({ index: 342, name: 'pso_f_hg_run', offsets: F_RUN_OFFSETS });
  if (maleHandgun) targets[0].anims.push(...[[107, 'dam_n'], [108, 'dam_d'], [111, 'run']].map(([index, role]) => ({ index, name: 'pso_hg_' + role, offsets: role === 'run' ? RUN_OFFSETS : WALK_OFFSETS })));
  if (femaleGunblade) targets[0].anims.push(...[[250, 'walk_ready'], [253, 'wait'], [262, 'run']].map(([index, role]) => ({ index, name: 'pso_f_gb_gun_' + role, offsets: role === 'run' ? F_RUN_OFFSETS : F_WALK_OFFSETS })));
  if (maleGunblade) targets[0].anims.push(...[[10, 'walk_ready'], [13, 'wait'], [22, 'run']].map(([index, role]) => ({ index, name: 'pso_gb_gun_' + role, offsets: role === 'run' ? RUN_OFFSETS : WALK_OFFSETS })));
  for (const { targetGlb, anims } of targets) {
    const targetPath = path.resolve(targetGlb);
    console.log(`\n── Baking into: ${targetGlb} ──`);

    const targetGltf = saberPrototype ? pszGltf : await loadGLB(targetPath);

    // Retarget animations
    const newClips = [];
    for (const { index, name, offsets } of anims) {
      const clipName = `plymotiondata_${String(index).padStart(3, '0')}`;
      const srcClip = psoGltf.animations.find((c) => c.name === clipName);
      if (!srcClip) {
        if (saberPrototype) throw new Error(`Missing source clip: ${clipName}`);
        console.warn(`Animation ${clipName} not found, skipping ${name}`);
        continue;
      }
      const retargeted = buildRetargetedClip(srcClip, psoRest, pszRest, BONE_MAPPINGS, posScale, name, offsets);
      if (retargeted) {
        // PSO chains contain cumulative travel (atk3 starts ~2.65m forward).
        // The gameplay body owns movement; retain vertical pose, never let the
        // visible rig walk away from its collider or drift on loop boundaries.
        if (saberPrototype) {
          for (const track of retargeted.tracks) {
            if (track.name !== '000_Root.position') continue;
            for (let i = 0; i < track.values.length; i += 3) {
              track.values[i] = 0;
              track.values[i + 2] = 0;
            }
          }
        }
        newClips.push(retargeted);
        console.log(`  Retargeted: ${clipName} -> ${name} (${retargeted.duration.toFixed(2)}s, ${retargeted.tracks.length} tracks)`);
      }
    }

    if (newClips.length === 0) {
      console.warn(`  No clips retargeted for ${targetGlb}, skipping`);
      continue;
    }

    // Merge with existing animations (deduplicate by name)
    const newNames = new Set(newClips.map((c) => c.name));
    const existing = saberPrototype ? [] : targetGltf.animations.filter((a) => !newNames.has(a.name));
    const allAnims = [...existing, ...newClips];
    console.log(`  Existing: ${targetGltf.animations.length}, adding: ${newClips.length}, total: ${allAnims.length}`);

    // Strip materials/textures to avoid export issues in Node.js
    targetGltf.scene.traverse((child) => {
      if (child.isMesh) {
        child.material = new THREE.MeshBasicMaterial();
      }
    });

    // Export as GLB
    const exporter = new GLTFExporter();
    const glb = await exporter.parseAsync(targetGltf.scene, {
      binary: true,
      animations: allAnims,
    });

    fs.writeFileSync(targetPath, Buffer.from(glb));
    console.log(`  Written: ${targetPath} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
