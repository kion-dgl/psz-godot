// Test different retargeting approaches on actual animation data
// to identify the correct quaternion multiplication order.
import { Blob } from 'buffer';
globalThis.self = globalThis;
globalThis.Blob = Blob;
globalThis.document = { createElementNS: () => ({}) };
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import fs from 'fs';
import path from 'path';

const MAPPINGS = {
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

function loadGLB(filePath) {
  return new Promise((resolve, reject) => {
    const data = fs.readFileSync(filePath);
    const loader = new GLTFLoader();
    loader.parse(data.buffer, '', (gltf) => resolve(gltf), reject);
  });
}

function fmt(q, d = 4) {
  if (q instanceof THREE.Quaternion)
    return `(${q.x.toFixed(d)}, ${q.y.toFixed(d)}, ${q.z.toFixed(d)}, ${q.w.toFixed(d)})`;
  if (q instanceof THREE.Euler) {
    const deg = (r) => (r * 180 / Math.PI).toFixed(1);
    return `(${deg(q.x)}, ${deg(q.y)}, ${deg(q.z)})°`;
  }
  return String(q);
}

function captureRestPose(model) {
  const localQuats = {};
  const worldQuats = {};
  const parentMap = {};

  model.traverse((child) => {
    if (child.isSkinnedMesh && child.skeleton) child.skeleton.pose();
  });
  model.updateMatrixWorld(true);

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

// Compute world rest quat by walking the parent chain (same as RetargetViewer)
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

async function main() {
  const pszPath = path.resolve('public/player/pc_000/pc_000/pc_000_000.glb');
  const psoPath = path.resolve('../data/retarget/Humar_body.glb');

  console.log('Loading models...');
  const [pszGltf, psoGltf] = await Promise.all([loadGLB(pszPath), loadGLB(psoPath)]);

  const psoRest = captureRestPose(psoGltf.scene);
  const pszRest = captureRestPose(pszGltf.scene);

  // Verify getWorldRestQuat matches actual world quats
  console.log('\n=== VERIFY getWorldRestQuat vs actual world quats ===');
  for (const boneName of Object.keys(MAPPINGS)) {
    const computed = getWorldRestQuat(boneName, psoRest);
    const actual = psoRest.worldQuats[boneName];
    if (!actual) { console.log(`  ${boneName}: MISSING`); continue; }
    const diff = computed.angleTo(actual) * 180 / Math.PI;
    if (diff > 0.1) {
      console.log(`  ${boneName}: MISMATCH! diff=${diff.toFixed(2)}° computed=${fmt(computed)} actual=${fmt(actual)}`);
    }
  }
  console.log('  (only mismatches shown)');

  // Pick an animation with visible movement (try walk or attack)
  const anims = psoGltf.animations;
  // Use animation index 0 (first idle), and also try a few others
  const testAnims = [0, 7, 25]; // idle, some others

  for (const animIdx of testAnims) {
    if (animIdx >= anims.length) continue;
    const clip = anims[animIdx];
    console.log(`\n${'='.repeat(60)}`);
    console.log(`ANIMATION: ${clip.name} (${clip.duration.toFixed(2)}s, ${clip.tracks.length} tracks)`);
    console.log(`${'='.repeat(60)}`);

    // For each mapped bone, get the quaternion track and test retargeting at frame 0 and mid-frame
    for (const [psoBone, pszBone] of Object.entries(MAPPINGS)) {
      const trackName = `${psoBone}.quaternion`;
      const track = clip.tracks.find((t) => t.name === trackName);
      if (!track) continue;

      // Get rest quaternions
      const psoLocalRest = psoRest.localQuats[psoBone] || new THREE.Quaternion();
      const pszLocalRest = pszRest.localQuats[pszBone] || new THREE.Quaternion();

      const psoParent = psoRest.parentMap[psoBone];
      const pszParent = pszRest.parentMap[pszBone];
      const psoParentWorldRest = psoParent ? getWorldRestQuat(psoParent, psoRest) : new THREE.Quaternion();
      const pszParentWorldRest = pszParent ? getWorldRestQuat(pszParent, pszRest) : new THREE.Quaternion();

      const psoWorldRest = psoParentWorldRest.clone().multiply(psoLocalRest);
      const pszWorldRest = pszParentWorldRest.clone().multiply(pszLocalRest);

      // Test at a few keyframes
      const numKf = track.times.length;
      const testFrames = [0, Math.floor(numKf / 4), Math.floor(numKf / 2)];

      console.log(`\n  ${psoBone} -> ${pszBone} (${numKf} keyframes):`);
      console.log(`    PSO local rest: ${fmt(psoLocalRest)}  euler: ${fmt(new THREE.Euler().setFromQuaternion(psoLocalRest))}`);
      console.log(`    PSZ local rest: ${fmt(pszLocalRest)}  euler: ${fmt(new THREE.Euler().setFromQuaternion(pszLocalRest))}`);

      for (const fi of testFrames) {
        if (fi >= numKf) continue;
        const i = fi * 4;
        const psoLocalAnim = new THREE.Quaternion(
          track.values[i], track.values[i + 1], track.values[i + 2], track.values[i + 3]
        );

        // How much does this frame differ from rest?
        const localDeltaAngle = psoLocalRest.angleTo(psoLocalAnim) * 180 / Math.PI;

        // ---- APPROACH 1: Current buggy (left extract, right apply) ----
        const psoWorld1 = psoParentWorldRest.clone().multiply(psoLocalAnim);
        const worldDelta1 = psoWorldRest.clone().invert().clone().premultiply(psoWorld1);
        // worldDelta1 = psoWorld1 * inv(psoWorldRest) — LEFT delta
        const pszWorldAnim1 = pszWorldRest.clone().multiply(worldDelta1);
        // pszWorldAnim1 = pszWorldRest * worldDelta1 — RIGHT apply (BUG)
        const pszLocal1 = pszParentWorldRest.clone().invert().multiply(pszWorldAnim1);

        // ---- APPROACH 2: Fixed left-left (world frame delta) ----
        const psoWorld2 = psoParentWorldRest.clone().multiply(psoLocalAnim);
        const worldDelta2L = psoWorld2.clone().multiply(psoWorldRest.clone().invert());
        // worldDelta2L = psoWorld2 * inv(psoWorldRest) — LEFT delta
        const pszWorldAnim2 = worldDelta2L.clone().multiply(pszWorldRest);
        // pszWorldAnim2 = worldDelta2L * pszWorldRest — LEFT apply (FIXED)
        const pszLocal2 = pszParentWorldRest.clone().invert().multiply(pszWorldAnim2);

        // ---- APPROACH 3: Right-right (bone frame delta) ----
        const psoWorld3 = psoParentWorldRest.clone().multiply(psoLocalAnim);
        const worldDelta3R = psoWorldRest.clone().invert().multiply(psoWorld3);
        // worldDelta3R = inv(psoWorldRest) * psoWorld3 — RIGHT delta
        const pszWorldAnim3 = pszWorldRest.clone().multiply(worldDelta3R);
        // pszWorldAnim3 = pszWorldRest * worldDelta3R — RIGHT apply
        const pszLocal3 = pszParentWorldRest.clone().invert().multiply(pszWorldAnim3);

        // ---- APPROACH 4: Conjugation (frame-corrected local delta) ----
        const localDelta = psoLocalRest.clone().invert().multiply(psoLocalAnim);
        const F = pszWorldRest.clone().invert().multiply(psoWorldRest);
        const Finv = F.clone().invert();
        const pszDelta = F.clone().multiply(localDelta).multiply(Finv);
        const pszLocal4 = pszLocalRest.clone().multiply(pszDelta);

        // Compare approaches
        const diff12 = pszLocal1.angleTo(pszLocal2) * 180 / Math.PI;
        const diff23 = pszLocal2.angleTo(pszLocal3) * 180 / Math.PI;
        const diff24 = pszLocal2.angleTo(pszLocal4) * 180 / Math.PI;
        const diff34 = pszLocal3.angleTo(pszLocal4) * 180 / Math.PI;

        // How far is each result from PSZ rest? (should be non-zero for animated frames)
        const restDelta1 = pszLocalRest.angleTo(pszLocal1) * 180 / Math.PI;
        const restDelta2 = pszLocalRest.angleTo(pszLocal2) * 180 / Math.PI;
        const restDelta3 = pszLocalRest.angleTo(pszLocal3) * 180 / Math.PI;
        const restDelta4 = pszLocalRest.angleTo(pszLocal4) * 180 / Math.PI;

        if (localDeltaAngle < 0.5) continue; // skip near-rest frames

        console.log(`    kf[${fi}] t=${track.times[fi].toFixed(3)}s  PSO anim delta from rest: ${localDeltaAngle.toFixed(1)}°`);
        console.log(`      Approach 1 (LEFT-RIGHT bug):  deviation from PSZ rest: ${restDelta1.toFixed(1)}°  euler: ${fmt(new THREE.Euler().setFromQuaternion(pszLocal1))}`);
        console.log(`      Approach 2 (LEFT-LEFT fix):   deviation from PSZ rest: ${restDelta2.toFixed(1)}°  euler: ${fmt(new THREE.Euler().setFromQuaternion(pszLocal2))}`);
        console.log(`      Approach 3 (RIGHT-RIGHT):     deviation from PSZ rest: ${restDelta3.toFixed(1)}°  euler: ${fmt(new THREE.Euler().setFromQuaternion(pszLocal3))}`);
        console.log(`      Approach 4 (CONJUGATION):     deviation from PSZ rest: ${restDelta4.toFixed(1)}°  euler: ${fmt(new THREE.Euler().setFromQuaternion(pszLocal4))}`);
        console.log(`      Diff 1vs2: ${diff12.toFixed(1)}°  2vs3: ${diff23.toFixed(1)}°  2vs4: ${diff24.toFixed(1)}°  3vs4: ${diff34.toFixed(1)}°`);
      }
    }
  }

  // Summary: which approaches agree?
  console.log('\n=== APPROACH EQUIVALENCE SUMMARY ===');
  console.log('Approach 2 (left-left) and Approach 4 (conjugation) should be mathematically equivalent.');
  console.log('Approach 3 (right-right) is different — it applies the delta in PSO bone frame without correction.');
  console.log('Approach 1 (current bug) mixes left extraction with right application.');
  console.log('\nApproach 2 = Approach 4 means the world-frame delta is correctly preserved.');
  console.log('If 2 != 3, the frame correction matters (different bone orientations).');
}

main().catch(console.error);
