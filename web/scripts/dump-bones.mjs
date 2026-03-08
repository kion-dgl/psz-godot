// Dump rest-pose bone info for PSZ and PSO models side by side
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

function fmt(v, decimals = 4) {
  if (v instanceof THREE.Quaternion) {
    return `(${v.x.toFixed(decimals)}, ${v.y.toFixed(decimals)}, ${v.z.toFixed(decimals)}, ${v.w.toFixed(decimals)})`;
  }
  if (v instanceof THREE.Vector3) {
    return `(${v.x.toFixed(decimals)}, ${v.y.toFixed(decimals)}, ${v.z.toFixed(decimals)})`;
  }
  if (v instanceof THREE.Euler) {
    const deg = (r) => (r * 180 / Math.PI).toFixed(1);
    return `(${deg(v.x)}, ${deg(v.y)}, ${deg(v.z)})°`;
  }
  return String(v);
}

function collectBoneInfo(model) {
  const info = {};
  // Reset to bind pose
  model.traverse((child) => {
    if (child.isSkinnedMesh && child.skeleton) {
      child.skeleton.pose();
    }
  });
  model.updateMatrixWorld(true);

  model.traverse((child) => {
    if (child.isBone) {
      const worldQuat = new THREE.Quaternion();
      const worldPos = new THREE.Vector3();
      child.getWorldQuaternion(worldQuat);
      child.getWorldPosition(worldPos);

      const euler = new THREE.Euler().setFromQuaternion(child.quaternion);
      const worldEuler = new THREE.Euler().setFromQuaternion(worldQuat);

      info[child.name] = {
        localQuat: child.quaternion.clone(),
        localEuler: euler,
        localPos: child.position.clone(),
        worldQuat,
        worldEuler,
        worldPos,
        parent: child.parent?.isBone ? child.parent.name : null,
      };
    }
  });
  return info;
}

async function main() {
  const pszPath = path.resolve('public/player/pc_000/pc_000/pc_000_000.glb');
  const psoPath = path.resolve('../data/retarget/Humar_body.glb');

  console.log('Loading PSZ model...');
  const pszGltf = await loadGLB(pszPath);
  const pszInfo = collectBoneInfo(pszGltf.scene);

  console.log('Loading PSO model...');
  const psoGltf = await loadGLB(psoPath);
  const psoInfo = collectBoneInfo(psoGltf.scene);

  console.log('\n=== ALL PSZ BONES ===');
  for (const [name, b] of Object.entries(pszInfo)) {
    console.log(`  ${name}`);
    console.log(`    parent: ${b.parent || '(root)'}`);
    console.log(`    localQuat: ${fmt(b.localQuat)}  euler: ${fmt(b.localEuler)}`);
    console.log(`    localPos:  ${fmt(b.localPos)}`);
    console.log(`    worldQuat: ${fmt(b.worldQuat)}  euler: ${fmt(b.worldEuler)}`);
    console.log(`    worldPos:  ${fmt(b.worldPos)}`);
  }

  console.log('\n=== ALL PSO BONES (mapped only) ===');
  for (const [psoName, b] of Object.entries(psoInfo)) {
    if (!(psoName in MAPPINGS)) continue;
    console.log(`  ${psoName}`);
    console.log(`    parent: ${b.parent || '(root)'}`);
    console.log(`    localQuat: ${fmt(b.localQuat)}  euler: ${fmt(b.localEuler)}`);
    console.log(`    localPos:  ${fmt(b.localPos)}`);
    console.log(`    worldQuat: ${fmt(b.worldQuat)}  euler: ${fmt(b.worldEuler)}`);
    console.log(`    worldPos:  ${fmt(b.worldPos)}`);
  }

  console.log('\n=== SIDE-BY-SIDE COMPARISON ===');
  for (const [psoName, pszName] of Object.entries(MAPPINGS)) {
    const pso = psoInfo[psoName];
    const psz = pszInfo[pszName];
    if (!pso || !psz) {
      console.log(`\n${psoName} -> ${pszName}: MISSING`);
      continue;
    }
    console.log(`\n${psoName} -> ${pszName}:`);
    console.log(`  PSO local euler: ${fmt(pso.localEuler)}   PSZ local euler: ${fmt(psz.localEuler)}`);
    console.log(`  PSO local quat:  ${fmt(pso.localQuat)}   PSZ local quat:  ${fmt(psz.localQuat)}`);
    console.log(`  PSO world euler: ${fmt(pso.worldEuler)}   PSZ world euler: ${fmt(psz.worldEuler)}`);
    console.log(`  PSO local pos:   ${fmt(pso.localPos)}   PSZ local pos:   ${fmt(psz.localPos)}`);

    // Compute the correction quaternion: what rotation transforms PSO's world frame to PSZ's world frame
    const correction = psz.worldQuat.clone().multiply(pso.worldQuat.clone().invert());
    const corrEuler = new THREE.Euler().setFromQuaternion(correction);
    console.log(`  correction quat: ${fmt(correction)}  euler: ${fmt(corrEuler)}`);
  }

  // Also dump full PSO bone hierarchy
  console.log('\n=== FULL PSO BONE HIERARCHY ===');
  for (const [name, b] of Object.entries(psoInfo)) {
    console.log(`  ${name} (parent: ${b.parent || 'root'})  euler: ${fmt(b.localEuler)}  pos: ${fmt(b.localPos)}`);
  }
}

main().catch(console.error);
