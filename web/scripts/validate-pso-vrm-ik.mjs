// Validate the PSO→VRM retarget pipeline against the PSO source
// across a sample of clips. For each clip, samples N frames and at
// each frame measures the per-segment **aim-direction divergence**
// between PSO's parent→child world vector and the retargeted VRM's
// equivalent. Error is in degrees and is invariant to rest pose and
// proportions — only pose similarity counts. Threshold is the
// per-segment angle (default 5°) that constitutes a "fail".
//
// Usage:
//   cd web && node scripts/validate-pso-vrm-ik.mjs --limit 10
//   cd web && node scripts/validate-pso-vrm-ik.mjs --limit 50 --threshold 5
//   cd web && node scripts/validate-pso-vrm-ik.mjs --limit all --samples 60
//   cd web && node scripts/validate-pso-vrm-ik.mjs --limit all --constraints
//
// Flags:
//   --constraints   apply the anti-hyperextension joint constraint.
//                   When on, the retarget intentionally diverges from
//                   PSO for poses that bend the wrong way, so the
//                   per-segment angle metric will report large errors
//                   on those frames by design. Use the constraint-
//                   firing counts in the summary to gauge frequency.
//   --no-twist      skip the swing-twist blend on lower bones (debug).
//
// Output:
//   - console: PASS/FAIL summary per clip, ranked by max error
//   - JSON:    web/scripts/validate-pso-vrm-ik.report.json (full detail)
//
// Inline copies of the IK + rotation-copy math live alongside the
// /pso-ik-vrm viewer's ik-utils.ts and PsoIkVrmViewer.tsx; if either
// changes meaningfully, mirror the change here too — this script does
// NOT import from the TS sources, by design (avoids a build step).

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
};

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../..');
const PSO_GLB = path.join(REPO_ROOT, 'web/public/data/retarget/Humar_body.glb');
const VRM_GLB = path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop.glb');
const ANIM_MAP = path.join(REPO_ROOT, 'web/public/data/retarget/pso_animation_map.json');
const REPORT_OUT = path.join(__dirname, 'validate-pso-vrm-ik.report.json');

// === CLI ===
const argv = process.argv.slice(2);
function arg(name, def) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : def;
}
const LIMIT = (() => {
  const v = arg('--limit', '10');
  if (v === 'all') return Infinity;
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : 10;
})();
const SAMPLES = parseInt(arg('--samples', '20'), 10);
const THRESHOLD = parseFloat(arg('--threshold', '5'));   // degrees
const DISABLE_TWIST = argv.includes('--no-twist');
const CONSTRAINTS = argv.includes('--constraints');

// === Bone mappings ===
const BONE_MAP_VRM = {
  bone_000: 'Root',
  bone_002: 'J_Bip_C_Hips',
  bone_024: 'J_Bip_C_Chest',
  bone_025: 'J_Bip_C_UpperChest',
  bone_028: 'J_Bip_L_UpperArm',
  bone_029: 'J_Bip_L_LowerArm',
  bone_030: 'J_Bip_L_Hand',
  bone_041: 'J_Bip_R_UpperArm',
  bone_042: 'J_Bip_R_LowerArm',
  bone_043: 'J_Bip_R_Hand',
  bone_056: 'J_Bip_C_Head',
  bone_004: 'J_Bip_L_UpperLeg',
  bone_005: 'J_Bip_L_LowerLeg',
  bone_006: 'J_Bip_L_Foot',
  bone_013: 'J_Bip_R_UpperLeg',
  bone_014: 'J_Bip_R_LowerLeg',
  bone_015: 'J_Bip_R_Foot',
};

// Bones that get straight rotation copy (no aim — they're leaves or
// they're the root). bone_000 (root) needed for damage/knockdown
// clips that rotate the character. Hands+feet are end-of-chain.
// Head is the end of the spine chain but its rotation matters for
// looking around, so we copy.
const ROTATION_COPY_BONES = [
  ['bone_000', 'Root'],
  ['bone_002', 'J_Bip_C_Hips'],
  ['bone_056', 'J_Bip_C_Head'],
  ['bone_030', 'J_Bip_L_Hand'],
  ['bone_043', 'J_Bip_R_Hand'],
  ['bone_006', 'J_Bip_L_Foot'],
  ['bone_015', 'J_Bip_R_Foot'],
];

// Direction-aim spine chain. VRoid VRMs have intermediate bones
// (J_Bip_C_Spine between Hips↔Chest, J_Bip_C_Neck between
// UpperChest↔Head) that PSO doesn't have — PSO is Hips → Chest →
// UpperChest → Head with no intermediates. To keep the per-VRM-bone
// aim correct, we walk every VRM-hierarchy edge and aim each segment
// in the matching PSO direction:
//   Hips→Spine, Spine→Chest both use PSO bone_002→bone_024
//   UpperChest→Neck, Neck→Head both use PSO bone_025→bone_056
// (effectively distributing PSO's coarser spine motion across VRM's
// finer chain).
const SPINE_CHAIN = [
  // [psoParent, psoChild, vrmParent, vrmChild]
  ['bone_002', 'bone_024', 'J_Bip_C_Hips',       'J_Bip_C_Spine'],
  ['bone_002', 'bone_024', 'J_Bip_C_Spine',      'J_Bip_C_Chest'],
  ['bone_024', 'bone_025', 'J_Bip_C_Chest',      'J_Bip_C_UpperChest'],
  ['bone_025', 'bone_056', 'J_Bip_C_UpperChest', 'J_Bip_C_Neck'],
  ['bone_025', 'bone_056', 'J_Bip_C_Neck',       'J_Bip_C_Head'],
];

// bendSign: +1 = joint bends toward body-forward (arms — forearm
//   comes forward to touch chest), -1 = bends away (legs — calf
//   goes back toward butt). bodyForward is hardcoded +Z (VRoid faces
//   +Z in three.js).
const LIMB_CHAINS = [
  { label: 'L arm', psoUpper: 'bone_028', psoLower: 'bone_029', psoEnd: 'bone_030',
    vrmUpper: 'J_Bip_L_UpperArm', vrmLower: 'J_Bip_L_LowerArm', vrmEnd: 'J_Bip_L_Hand',
    poleOffset: new THREE.Vector3(0, -1, -0.6), bendSign: 1 },
  { label: 'R arm', psoUpper: 'bone_041', psoLower: 'bone_042', psoEnd: 'bone_043',
    vrmUpper: 'J_Bip_R_UpperArm', vrmLower: 'J_Bip_R_LowerArm', vrmEnd: 'J_Bip_R_Hand',
    poleOffset: new THREE.Vector3(0, -1, -0.6), bendSign: 1 },
  { label: 'L leg', psoUpper: 'bone_004', psoLower: 'bone_005', psoEnd: 'bone_006',
    vrmUpper: 'J_Bip_L_UpperLeg', vrmLower: 'J_Bip_L_LowerLeg', vrmEnd: 'J_Bip_L_Foot',
    poleOffset: new THREE.Vector3(0, 0, 1), bendSign: -1 },
  { label: 'R leg', psoUpper: 'bone_013', psoLower: 'bone_014', psoEnd: 'bone_015',
    vrmUpper: 'J_Bip_R_UpperLeg', vrmLower: 'J_Bip_R_LowerLeg', vrmEnd: 'J_Bip_R_Foot',
    poleOffset: new THREE.Vector3(0, 0, 1), bendSign: -1 },
];

const BODY_FORWARD = new THREE.Vector3(0, 0, 1);

// Minimum bend (in radians) before the constraint considers a joint
// for correction. Below this, the joint is essentially straight and
// the cross-product direction is dominated by float noise — don't
// fire. ~15° = 0.26 rad means we only correct visibly-bent joints.
const MIN_BEND_RAD = 0.26;

function enforceNaturalBend(vrmUpper, vrmLower, vrmEnd, lowerChildRestLocal, vrmLowerLen, bendSign) {
  const upperW = new THREE.Vector3(); vrmUpper.getWorldPosition(upperW);
  const lowerW = new THREE.Vector3(); vrmLower.getWorldPosition(lowerW);
  const endW = new THREE.Vector3(); vrmEnd.getWorldPosition(endW);
  const upperDir = lowerW.clone().sub(upperW);
  if (upperDir.lengthSq() < 1e-12) return false;
  upperDir.normalize();
  const lowerDir = endW.clone().sub(lowerW);
  if (lowerDir.lengthSq() < 1e-12) return false;
  lowerDir.normalize();
  // Skip near-straight joints — the bend direction is meaningless
  // when the bones are colinear.
  const bendAngle = Math.acos(Math.max(-1, Math.min(1, upperDir.dot(lowerDir))));
  if (bendAngle < MIN_BEND_RAD) return false;
  const bendDir = BODY_FORWARD.clone().multiplyScalar(bendSign);
  const naturalAxis = new THREE.Vector3().crossVectors(upperDir, bendDir);
  if (naturalAxis.lengthSq() < 1e-6) return false;
  naturalAxis.normalize();
  const actualAxis = new THREE.Vector3().crossVectors(upperDir, lowerDir);
  if (actualAxis.dot(naturalAxis) >= 0) return false;
  const reflected = lowerDir.clone().sub(naturalAxis.multiplyScalar(2 * lowerDir.dot(naturalAxis)));
  const newTarget = reflected.multiplyScalar(vrmLowerLen).add(lowerW);
  aimBoneAtTarget(vrmLower, newTarget, lowerChildRestLocal);
  return true;
}

// === Rest pose + retarget math (mirrors ik-utils.ts / retarget-utils.ts) ===

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
      parentMap[child.name] = child.parent && child.parent.isBone ? child.parent.name : null;
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

function measureChain(upperBone, lowerBone, endEffector) {
  const upperWorld = new THREE.Vector3();
  const lowerWorld = new THREE.Vector3();
  const endWorld = new THREE.Vector3();
  upperBone.getWorldPosition(upperWorld);
  lowerBone.getWorldPosition(lowerWorld);
  endEffector.getWorldPosition(endWorld);
  return {
    upperLength: upperWorld.distanceTo(lowerWorld),
    lowerLength: lowerWorld.distanceTo(endWorld),
    upperChildRestLocal: lowerBone.position.clone().normalize(),
    lowerChildRestLocal: endEffector.position.clone().normalize(),
  };
}

// Direction-driven chain retarget. Instead of analytic 2-bone IK with a
// fixed pole vector (which can put the elbow on the wrong side when
// PSO's pose disagrees with the pole bias), aim each VRM bone in the
// world-space direction that PSO has its equivalent bone, then advance
// along the chain using VRM's bone lengths. Result: per-bone aim
// matches PSO direction exactly, modulo twist (which setFromUnitVectors
// doesn't fix — handled separately by the hybrid twist blend).
function aimBoneAtTarget(bone, targetWorld, childRestLocal) {
  if (!bone.parent) return;
  bone.parent.updateMatrixWorld(true);
  const parentInv = new THREE.Matrix4().copy(bone.parent.matrixWorld).invert();
  const targetInParent = targetWorld.clone().applyMatrix4(parentInv);
  const localDir = targetInParent.sub(bone.position).normalize();
  bone.quaternion.setFromUnitVectors(childRestLocal, localDir);
  bone.updateMatrixWorld(true);
}

function retargetChainByDirection(vrmUpper, vrmLower, psoUpper, psoLower, psoEnd, vrmUpperLen, vrmLowerLen, upperChildRestLocal, lowerChildRestLocal) {
  const pU = new THREE.Vector3(); psoUpper.getWorldPosition(pU);
  const pL = new THREE.Vector3(); psoLower.getWorldPosition(pL);
  const pE = new THREE.Vector3(); psoEnd.getWorldPosition(pE);

  // Place VRM elbow at vrm-upper-length from VRM shoulder, in PSO's
  // upper-bone direction (in world space).
  const upperDir = pL.clone().sub(pU);
  if (upperDir.lengthSq() < 1e-12) return;
  upperDir.normalize();
  const vSw = new THREE.Vector3(); vrmUpper.getWorldPosition(vSw);
  const elbowTarget = upperDir.multiplyScalar(vrmUpperLen).add(vSw);
  aimBoneAtTarget(vrmUpper, elbowTarget, upperChildRestLocal);

  // After upper is aimed, the lower bone has carried along — get its
  // new world position, then aim it in PSO's lower-bone direction.
  vrmLower.updateMatrixWorld(true);
  const vEw = new THREE.Vector3(); vrmLower.getWorldPosition(vEw);
  const lowerDir = pE.clone().sub(pL);
  if (lowerDir.lengthSq() < 1e-12) return;
  lowerDir.normalize();
  const handTarget = lowerDir.multiplyScalar(vrmLowerLen).add(vEw);
  aimBoneAtTarget(vrmLower, handTarget, lowerChildRestLocal);
}

// Legacy: analytic 2-bone IK with fixed pole. Kept for reference / A/B
// testing via --legacy-ik. Not used by default — see runRetarget below.
function solveTwoBoneIK(upperBone, lowerBone, targetWorld, poleWorld, rest) {
  if (!upperBone.parent || !lowerBone.parent) return;
  upperBone.parent.updateMatrixWorld(true);
  const shoulderWorld = new THREE.Vector3();
  upperBone.getWorldPosition(shoulderWorld);
  const { upperLength, lowerLength, upperChildRestLocal, lowerChildRestLocal } = rest;
  const totalReach = upperLength + lowerLength;
  const minReach = Math.abs(upperLength - lowerLength);
  let dist = targetWorld.distanceTo(shoulderWorld);
  const dirToTarget = new THREE.Vector3().subVectors(targetWorld, shoulderWorld);
  if (dist < 1e-6) return;
  dirToTarget.divideScalar(dist);
  const reachedTarget =
    dist > totalReach - 1e-4
      ? new THREE.Vector3().copy(shoulderWorld).addScaledVector(dirToTarget, totalReach - 1e-4)
      : targetWorld.clone();
  dist = Math.max(minReach + 1e-4, Math.min(totalReach - 1e-4, dist));
  const a = (upperLength * upperLength - lowerLength * lowerLength + dist * dist) / (2 * dist);
  const h = Math.sqrt(Math.max(0, upperLength * upperLength - a * a));
  const poleRel = new THREE.Vector3().subVectors(poleWorld, shoulderWorld);
  const polePerp = poleRel.sub(dirToTarget.clone().multiplyScalar(poleRel.dot(dirToTarget)));
  if (polePerp.lengthSq() < 1e-6) polePerp.set(0, 0, 1);
  polePerp.normalize();
  const elbowWorld = new THREE.Vector3()
    .copy(shoulderWorld)
    .addScaledVector(dirToTarget, a)
    .addScaledVector(polePerp, h);
  const parentInvUpper = new THREE.Matrix4().copy(upperBone.parent.matrixWorld).invert();
  const elbowInUpperParent = elbowWorld.clone().applyMatrix4(parentInvUpper);
  const upperLocalDir = elbowInUpperParent.sub(upperBone.position).normalize();
  upperBone.quaternion.setFromUnitVectors(upperChildRestLocal, upperLocalDir);
  upperBone.updateMatrixWorld(true);
  const parentInvLower = new THREE.Matrix4().copy(lowerBone.parent.matrixWorld).invert();
  const targetInLowerParent = reachedTarget.clone().applyMatrix4(parentInvLower);
  const lowerLocalDir = targetInLowerParent.sub(lowerBone.position).normalize();
  lowerBone.quaternion.setFromUnitVectors(lowerChildRestLocal, lowerLocalDir);
  lowerBone.updateMatrixWorld(true);
}

function swingTwistDecomposition(q, axis) {
  const dot = q.x * axis.x + q.y * axis.y + q.z * axis.z;
  const px = axis.x * dot, py = axis.y * dot, pz = axis.z * dot;
  let twist = new THREE.Quaternion(px, py, pz, q.w);
  const lenSq = twist.x * twist.x + twist.y * twist.y + twist.z * twist.z + twist.w * twist.w;
  if (lenSq < 1e-12) twist = new THREE.Quaternion();
  else twist.normalize();
  const swing = q.clone().multiply(twist.clone().invert());
  return { swing, twist };
}

function findBone(root, name) {
  let found = null;
  root.traverse((o) => { if (!found && o.isBone && o.name === name) found = o; });
  return found;
}

function resetToBindPose(model) {
  // skeleton.pose() restores bone local transforms from each bone's
  // bind matrix. Without this, the GLB-loaded skeleton may be in a
  // first-frame pose rather than rest, which corrupts captureRestPose.
  model.traverse((child) => {
    if (child.isSkinnedMesh && child.skeleton) {
      child.skeleton.pose();
    }
  });
  model.updateMatrixWorld(true);
}

// === GLB loader ===
async function loadGLB(filePath) {
  const buf = fs.readFileSync(filePath);
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  const loader = new GLTFLoader();
  return new Promise((res, rej) => {
    loader.parse(ab, '', res, rej);
  });
}

// === Main ===
async function main() {
  console.log(`[validate] loading PSO + VRM…`);
  const [psoGltf, vrmGltf] = await Promise.all([loadGLB(PSO_GLB), loadGLB(VRM_GLB)]);
  const animMap = JSON.parse(fs.readFileSync(ANIM_MAP, 'utf-8')).mappings;

  const psoModel = psoGltf.scene;
  const vrmModel = vrmGltf.scene;

  // Crucial: reset bones to the rig's bind pose BEFORE measuring
  // bbox / capturing rest. GLTFLoader may leave bones at "first frame
  // of first animation" position, which would corrupt rest math.
  resetToBindPose(psoModel);
  resetToBindPose(vrmModel);

  // Match PSO bbox height to VRM (purely for the IK/expected math to
  // operate at a sane scale — local-space animation tracks are unaffected).
  const vrmBox = new THREE.Box3().setFromObject(vrmModel);
  const psoBox = new THREE.Box3().setFromObject(psoModel);
  const vrmHeight = vrmBox.max.y - vrmBox.min.y;
  const psoHeight = psoBox.max.y - psoBox.min.y;
  const psoDisplayScale = vrmHeight / psoHeight;
  psoModel.scale.multiplyScalar(psoDisplayScale);
  psoModel.updateMatrixWorld(true);

  // Capture rest poses AFTER bind-pose reset, AFTER scale applied
  // (so world positions of the source rest match scaled space).
  const psoRest = captureRestPose(psoModel);
  const vrmRest = captureRestPose(vrmModel);

  // Resolve chains + measure rest lengths.
  const chains = [];
  for (const spec of LIMB_CHAINS) {
    const vrmUpper = findBone(vrmModel, spec.vrmUpper);
    const vrmLower = findBone(vrmModel, spec.vrmLower);
    const vrmEnd = findBone(vrmModel, spec.vrmEnd);
    const psoUpper = findBone(psoModel, spec.psoUpper);
    const psoLower = findBone(psoModel, spec.psoLower);
    const psoEnd = findBone(psoModel, spec.psoEnd);
    if (!vrmUpper || !vrmLower || !vrmEnd || !psoUpper || !psoLower || !psoEnd) {
      console.warn(`[validate] missing bone in chain ${spec.label}`);
      continue;
    }
    const rest = measureChain(vrmUpper, vrmLower, vrmEnd);
    const psoU = new THREE.Vector3(), psoL = new THREE.Vector3(), psoE = new THREE.Vector3();
    psoUpper.getWorldPosition(psoU); psoLower.getWorldPosition(psoL); psoEnd.getWorldPosition(psoE);
    const psoTotal = psoU.distanceTo(psoL) + psoL.distanceTo(psoE);
    const vrmTotal = rest.upperLength + rest.lowerLength;
    const scale = psoTotal > 1e-6 ? vrmTotal / psoTotal : 1.0;
    // Precompute rotation-copy F-correction for lower bone (for twist blend).
    const psoLowerLocalRest = psoRest.localQuats[spec.psoLower] || new THREE.Quaternion();
    const vrmLowerLocalRest = vrmRest.localQuats[spec.vrmLower] || new THREE.Quaternion();
    const psoLowerWorldRest = getWorldRestQuat(spec.psoLower, psoRest);
    const vrmLowerWorldRest = getWorldRestQuat(spec.vrmLower, vrmRest);
    const F = vrmLowerWorldRest.clone().invert().multiply(psoLowerWorldRest);
    const lowerRotCopyPrefix = vrmLowerLocalRest.clone().multiply(F).multiply(psoLowerLocalRest.clone().invert());
    const lowerRotCopySuffix = F.clone().invert();
    chains.push({ spec, vrmUpper, vrmLower, psoUpper, psoLower, psoEnd, rest, scale,
                  lowerRotCopyPrefix, lowerRotCopySuffix });
  }

  // Precompute rotation-copy prefix/suffix for spine/head/hand/foot.
  const rotCopies = [];
  for (const [psoBone, vrmBoneName] of ROTATION_COPY_BONES) {
    const vrmBone = findBone(vrmModel, vrmBoneName);
    if (!vrmBone) continue;
    const psoLocalRest = psoRest.localQuats[psoBone] || new THREE.Quaternion();
    const vrmLocalRest = vrmRest.localQuats[vrmBoneName] || new THREE.Quaternion();
    const psoWorldRest = getWorldRestQuat(psoBone, psoRest);
    const vrmWorldRest = getWorldRestQuat(vrmBoneName, vrmRest);
    const F = vrmWorldRest.clone().invert().multiply(psoWorldRest);
    const prefix = vrmLocalRest.clone().multiply(F).multiply(psoLocalRest.clone().invert());
    const suffix = F.clone().invert();
    rotCopies.push({ psoBone, vrmBone, prefix, suffix });
  }

  // Resolve spine chain references + measure VRM rest segment lengths.
  const spineSteps = [];
  for (const [psoP, psoC, vrmP, vrmC] of SPINE_CHAIN) {
    const psoParent = findBone(psoModel, psoP);
    const psoChild = findBone(psoModel, psoC);
    const vrmParent = findBone(vrmModel, vrmP);
    const vrmChild = findBone(vrmModel, vrmC);
    if (!psoParent || !psoChild || !vrmParent || !vrmChild) {
      console.warn(`[validate] missing bone in spine step ${vrmP}→${vrmC}`);
      continue;
    }
    const vPw = new THREE.Vector3(); vrmParent.getWorldPosition(vPw);
    const vCw = new THREE.Vector3(); vrmChild.getWorldPosition(vCw);
    const restLen = vPw.distanceTo(vCw);
    const childRestLocal = vrmChild.position.clone().normalize();
    spineSteps.push({ psoParent, psoChild, vrmParent, vrmChild, restLen, childRestLocal });
  }

  // Root bones for position mirroring.
  const psoRootBone = findBone(psoModel, 'bone_000');
  const psoRootRest = psoRootBone ? psoRootBone.position.clone() : new THREE.Vector3();
  const vrmRootBone = findBone(vrmModel, 'Root');
  const vrmRootRest = vrmRootBone ? vrmRootBone.position.clone() : new THREE.Vector3();
  const vrmHipsBone = findBone(vrmModel, 'J_Bip_C_Hips');
  const psoHipsBone = findBone(psoModel, 'bone_002');

  // Bone-cache for the per-frame retarget.
  const psoBoneCache = new Map();
  psoModel.traverse((o) => { if (o.isBone) psoBoneCache.set(o.name, o); });

  // === Per-frame retarget (mirrors PsoIkVrmViewer per-frame loop) ===
  // The current-clip constraint-fire counter. Reset per clip; mutated
  // inside runRetarget when --constraints is on.
  let currentConstraintFires = {};
  function runRetarget() {
    // Root position mirror (full XYZ delta).
    if (psoRootBone && vrmRootBone) {
      const dx = (psoRootBone.position.x - psoRootRest.x) * psoDisplayScale;
      const dy = (psoRootBone.position.y - psoRootRest.y) * psoDisplayScale;
      const dz = (psoRootBone.position.z - psoRootRest.z) * psoDisplayScale;
      vrmRootBone.position.set(vrmRootRest.x + dx, vrmRootRest.y + dy, vrmRootRest.z + dz);
    }
    // Rotation copy (root + hips + head + hands + feet).
    for (const rc of rotCopies) {
      const psoBoneObj = psoBoneCache.get(rc.psoBone);
      if (!psoBoneObj) continue;
      rc.vrmBone.quaternion.copy(rc.prefix).multiply(psoBoneObj.quaternion).multiply(rc.suffix);
    }
    vrmModel.updateMatrixWorld(true);

    // Direction-aim spine chain (Hips→Chest, Chest→UpperChest,
    // UpperChest→Head). Walks the chain top-down so each subsequent
    // step sees its parent's already-aimed matrix.
    const tmpP = new THREE.Vector3(), tmpC = new THREE.Vector3(), tmpV = new THREE.Vector3();
    for (const s of spineSteps) {
      s.psoParent.getWorldPosition(tmpP);
      s.psoChild.getWorldPosition(tmpC);
      const psoDir = tmpC.sub(tmpP);
      if (psoDir.lengthSq() < 1e-12) continue;
      psoDir.normalize();
      s.vrmParent.getWorldPosition(tmpV);
      const target = psoDir.multiplyScalar(s.restLen).add(tmpV);
      aimBoneAtTarget(s.vrmParent, target, s.childRestLocal);
    }
    vrmModel.updateMatrixWorld(true);
    // Limb retarget (direction-driven) + hybrid twist + optional
    // anti-hyperextension constraint.
    for (const chain of chains) {
      retargetChainByDirection(
        chain.vrmUpper, chain.vrmLower,
        chain.psoUpper, chain.psoLower, chain.psoEnd,
        chain.rest.upperLength, chain.rest.lowerLength,
        chain.rest.upperChildRestLocal, chain.rest.lowerChildRestLocal,
      );
      if (!DISABLE_TWIST) {
        const rcQuat = chain.lowerRotCopyPrefix.clone()
          .multiply(chain.psoLower.quaternion)
          .multiply(chain.lowerRotCopySuffix);
        const axis = chain.rest.lowerChildRestLocal;
        const { twist: rcTwist } = swingTwistDecomposition(rcQuat, axis);
        const { swing: ikSwing } = swingTwistDecomposition(chain.vrmLower.quaternion, axis);
        chain.vrmLower.quaternion.copy(ikSwing).multiply(rcTwist);
        chain.vrmLower.updateMatrixWorld(true);
      }
      if (CONSTRAINTS) {
        if (!chain._vrmEndBone) chain._vrmEndBone = findBone(vrmModel, chain.spec.vrmEnd);
        if (chain._vrmEndBone) {
          const fired = enforceNaturalBend(
            chain.vrmUpper, chain.vrmLower, chain._vrmEndBone,
            chain.rest.lowerChildRestLocal, chain.rest.lowerLength,
            chain.spec.bendSign,
          );
          if (fired) {
            currentConstraintFires[chain.spec.label] = (currentConstraintFires[chain.spec.label] ?? 0) + 1;
          }
        }
      }
    }
    vrmModel.updateMatrixWorld(true);
  }

  // === Per-bone-aim angle metric ===
  // Hip-anchored position error compared apples-to-oranges: PSO arms-
  // down rest vs VRM T-pose rest gives a 38% body-height "error"
  // before any animation runs. That's a rest-pose disagreement, not
  // a retarget failure.
  //
  // Better: for each bone segment, measure the world-space direction
  // it points (parent→child). Compare PSO direction vs VRM direction;
  // angle between them is the per-segment retarget error in degrees.
  // Invariant to rest pose and bone-length proportions — only pose
  // similarity matters.
  const AIM_PAIRS = [
    ['hips→chest',     'bone_002', 'bone_024', 'J_Bip_C_Hips',       'J_Bip_C_Chest'],
    ['chest→uchest',   'bone_024', 'bone_025', 'J_Bip_C_Chest',      'J_Bip_C_UpperChest'],
    ['uchest→head',    'bone_025', 'bone_056', 'J_Bip_C_UpperChest', 'J_Bip_C_Head'],
    ['L upper-arm',    'bone_028', 'bone_029', 'J_Bip_L_UpperArm',   'J_Bip_L_LowerArm'],
    ['L lower-arm',    'bone_029', 'bone_030', 'J_Bip_L_LowerArm',   'J_Bip_L_Hand'],
    ['R upper-arm',    'bone_041', 'bone_042', 'J_Bip_R_UpperArm',   'J_Bip_R_LowerArm'],
    ['R lower-arm',    'bone_042', 'bone_043', 'J_Bip_R_LowerArm',   'J_Bip_R_Hand'],
    ['L upper-leg',    'bone_004', 'bone_005', 'J_Bip_L_UpperLeg',   'J_Bip_L_LowerLeg'],
    ['L lower-leg',    'bone_005', 'bone_006', 'J_Bip_L_LowerLeg',   'J_Bip_L_Foot'],
    ['R upper-leg',    'bone_013', 'bone_014', 'J_Bip_R_UpperLeg',   'J_Bip_R_LowerLeg'],
    ['R lower-leg',    'bone_014', 'bone_015', 'J_Bip_R_LowerLeg',   'J_Bip_R_Foot'],
  ];

  // Cache the bone refs once.
  const aimRefs = AIM_PAIRS.map(([label, psoP, psoC, vrmP, vrmC]) => ({
    label,
    psoP: psoBoneCache.get(psoP),
    psoC: psoBoneCache.get(psoC),
    vrmP: findBone(vrmModel, vrmP),
    vrmC: findBone(vrmModel, vrmC),
  })).filter((r) => r.psoP && r.psoC && r.vrmP && r.vrmC);

  function measureFrameErrors() {
    const errs = {};
    const pp = new THREE.Vector3(), pc = new THREE.Vector3();
    const vp = new THREE.Vector3(), vc = new THREE.Vector3();
    for (const r of aimRefs) {
      r.psoP.getWorldPosition(pp);
      r.psoC.getWorldPosition(pc);
      r.vrmP.getWorldPosition(vp);
      r.vrmC.getWorldPosition(vc);
      const psoDir = pc.sub(pp);
      const vrmDir = vc.sub(vp);
      const psoLen = psoDir.length();
      const vrmLen = vrmDir.length();
      if (psoLen < 1e-6 || vrmLen < 1e-6) { errs[r.label] = null; continue; }
      psoDir.divideScalar(psoLen);
      vrmDir.divideScalar(vrmLen);
      const cos = Math.max(-1, Math.min(1, psoDir.dot(vrmDir)));
      errs[r.label] = Math.acos(cos) * 180 / Math.PI;   // degrees
    }
    return errs;
  }

  // === Drive PSO via AnimationMixer + sample frames ===
  const mixer = new THREE.AnimationMixer(psoModel);
  const allClips = psoGltf.animations;
  const clipsToTest = allClips.slice(0, Number.isFinite(LIMIT) ? LIMIT : allClips.length);
  console.log(`[validate] testing ${clipsToTest.length} of ${allClips.length} clips, ${SAMPLES} samples each, threshold=${THRESHOLD}`);

  const report = {
    threshold: THRESHOLD,
    samples_per_clip: SAMPLES,
    total_clips: clipsToTest.length,
    vrm_height: vrmHeight,
    pso_display_scale: psoDisplayScale,
    clips: [],
  };

  for (const clip of clipsToTest) {
    const idx = clip.name.match(/(\d+)/)?.[1] ?? '???';
    const friendly = animMap[idx.padStart(3, '0')] || `plymotiondata_${idx}`;
    const action = mixer.clipAction(clip);
    action.reset();
    action.setLoop(THREE.LoopOnce);
    action.play();

    const perJointMax = {};
    const perJointMean = {};
    const perJointCount = {};
    currentConstraintFires = {};
    let overallMax = 0;
    let overallSum = 0;
    let overallCount = 0;
    let worstJoint = null;
    let worstFrame = -1;

    for (let i = 0; i < SAMPLES; i++) {
      const t = (i / Math.max(1, SAMPLES - 1)) * Math.max(1e-3, clip.duration);
      mixer.setTime(t);
      psoModel.updateMatrixWorld(true);
      runRetarget();
      const errs = measureFrameErrors();
      for (const [joint, err] of Object.entries(errs)) {
        if (err == null) continue;
        if (!Number.isFinite(err)) continue;
        if (err > (perJointMax[joint] ?? 0)) { perJointMax[joint] = err; }
        perJointMean[joint] = (perJointMean[joint] ?? 0) + err;
        perJointCount[joint] = (perJointCount[joint] ?? 0) + 1;
        if (err > overallMax) { overallMax = err; worstJoint = joint; worstFrame = i; }
        overallSum += err;
        overallCount += 1;
      }
    }
    action.stop();
    mixer.stopAllAction();

    for (const j of Object.keys(perJointMean)) perJointMean[j] /= perJointCount[j];

    const meanErr = overallCount > 0 ? overallSum / overallCount : 0;
    const passed = overallMax < THRESHOLD;
    const constraintFireTotal = Object.values(currentConstraintFires).reduce((s, v) => s + v, 0);
    report.clips.push({
      name: clip.name,
      friendly,
      duration: clip.duration,
      max_error: overallMax,
      mean_error: meanErr,
      worst_joint: worstJoint,
      worst_frame: worstFrame,
      per_joint_max: perJointMax,
      per_joint_mean: perJointMean,
      constraint_fires: { ...currentConstraintFires },
      constraint_fires_total: constraintFireTotal,
      passed,
    });
  }

  // === Summary ===
  const sorted = [...report.clips].sort((a, b) => b.max_error - a.max_error);
  const passed = report.clips.filter((c) => c.passed).length;
  const failed = report.clips.length - passed;

  console.log();
  console.log(`=== top 20 by max error (worst first) ===`);
  for (const c of sorted.slice(0, 20)) {
    const tag = c.passed ? 'PASS' : 'FAIL';
    console.log(`  [${tag}] max=${c.max_error.toFixed(1)}° mean=${c.mean_error.toFixed(1)}° ${c.friendly.padEnd(20)} worst=${c.worst_joint}@f${c.worst_frame}`);
  }
  console.log();
  console.log(`=== per-joint worst-case across all tested clips ===`);
  const jointMaxes = {};
  for (const c of report.clips) {
    for (const [j, m] of Object.entries(c.per_joint_max)) {
      if (m > (jointMaxes[j] ?? 0)) jointMaxes[j] = m;
    }
  }
  for (const [j, m] of Object.entries(jointMaxes).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${m.toFixed(1)}°  ${j}`);
  }
  console.log();
  console.log(`=== summary ===`);
  console.log(`  pass:    ${passed}/${report.clips.length}  (${(passed / report.clips.length * 100).toFixed(1)}%)`);
  console.log(`  fail:    ${failed}/${report.clips.length}`);
  console.log(`  threshold: ${THRESHOLD}° per-bone aim direction divergence`);

  if (CONSTRAINTS) {
    // Aggregate constraint firings across all clips and report.
    const allFires = {};
    let clipsWithFires = 0;
    let totalFires = 0;
    let totalFrames = 0;
    for (const c of report.clips) {
      totalFrames += SAMPLES;
      if (c.constraint_fires_total > 0) clipsWithFires++;
      totalFires += c.constraint_fires_total;
      for (const [joint, n] of Object.entries(c.constraint_fires)) {
        allFires[joint] = (allFires[joint] ?? 0) + n;
      }
    }
    const totalCheckedFrames = totalFrames * chains.length;
    console.log();
    console.log(`=== constraint firings (--constraints enabled) ===`);
    console.log(`  ${clipsWithFires}/${report.clips.length} clips had at least one hyperextension corrected`);
    console.log(`  ${totalFires} total firings across ${totalCheckedFrames} joint-checks (${(totalFires / totalCheckedFrames * 100).toFixed(2)}%)`);
    for (const [joint, n] of Object.entries(allFires).sort((a, b) => b[1] - a[1])) {
      console.log(`    ${joint.padEnd(10)} ${n}`);
    }
    console.log();
    console.log(`top 10 clips by constraint firings:`);
    const byFires = [...report.clips].sort((a, b) => b.constraint_fires_total - a.constraint_fires_total).slice(0, 10);
    for (const c of byFires) {
      if (c.constraint_fires_total === 0) break;
      console.log(`  ${c.constraint_fires_total.toString().padStart(3)} ${c.friendly}`);
    }
  }

  fs.writeFileSync(REPORT_OUT, JSON.stringify(report, null, 2));
  console.log(`\n[validate] report: ${REPORT_OUT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
