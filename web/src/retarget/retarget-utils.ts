import * as THREE from 'three';

// PSO wrist bones → their forearm parent (PSO) and the PSZ forearm they attach to
// These have identity rest rotation, so animation = pure wrist twist/bend
export const WRIST_BONES: Record<string, { forearmPso: string; forearmPsz: string }> = {
  bone_030: { forearmPso: 'bone_029', forearmPsz: '040_LArm02' },
  bone_043: { forearmPso: 'bone_042', forearmPsz: '070_RArm02' },
};

export const BONE_MAPPINGS: Record<string, string> = {
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

export interface RestPoseData {
  localQuats: Record<string, THREE.Quaternion>;
  worldQuats: Record<string, THREE.Quaternion>;
  parentMap: Record<string, string | null>;
}

export function captureRestPose(model: THREE.Object3D): RestPoseData {
  const localQuats: Record<string, THREE.Quaternion> = {};
  const worldQuats: Record<string, THREE.Quaternion> = {};
  const parentMap: Record<string, string | null> = {};
  model.traverse((child) => {
    if ((child as THREE.Bone).isBone) {
      localQuats[child.name] = child.quaternion.clone();
      const wq = new THREE.Quaternion();
      child.getWorldQuaternion(wq);
      worldQuats[child.name] = wq;
      parentMap[child.name] = child.parent && (child.parent as THREE.Bone).isBone ? child.parent.name : null;
    }
  });
  return { localQuats, worldQuats, parentMap };
}

export function getWorldRestQuat(boneName: string, restData: RestPoseData): THREE.Quaternion {
  const result = new THREE.Quaternion();
  const chain: string[] = [];
  let cur: string | null = boneName;
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

export function resetToBindPose(model: THREE.Object3D): void {
  model.traverse((child) => {
    if ((child as THREE.SkinnedMesh).isSkinnedMesh) {
      const skeleton = (child as THREE.SkinnedMesh).skeleton;
      if (skeleton) skeleton.pose();
    }
  });
  model.updateMatrixWorld(true);
}

// wristTargets: maps PSO wrist bone name → target Object3D name in PSZ scene
// e.g. { bone_030: '_wristL', bone_043: '_wristR' }
export function buildRetargetedClip(
  clip: THREE.AnimationClip,
  psoRest: RestPoseData,
  pszRest: RestPoseData,
  boneMap: Record<string, string>,
  posScale: number,
  outputName?: string,
  wristTargets?: Record<string, string>,
): THREE.AnimationClip | null {
  if (Object.keys(boneMap).length === 0) return null;

  // Create a modified copy of PSZ rest data with arm bones adjusted
  const adjustedPszRest: RestPoseData = {
    localQuats: { ...pszRest.localQuats },
    worldQuats: { ...pszRest.worldQuats },
    parentMap: pszRest.parentMap,
  };
  // Correct arm rest poses so PSZ bone world orientations match PSO's.
  // Upper arms first (parents), then forearms (children depend on corrected parents).
  const armCorrectionBones: [string, string][] = [
    ['bone_028', '030_LArm01'],   // left upper arm
    ['bone_041', '060_RArm01'],   // right upper arm
    ['bone_029', '040_LArm02'],   // left forearm
    ['bone_042', '070_RArm02'],   // right forearm
  ];
  for (const [psoBone, pszBone] of armCorrectionBones) {
    if (!(psoBone in boneMap) || boneMap[psoBone] !== pszBone) continue;
    const pszParent = adjustedPszRest.parentMap[pszBone];
    const pszParentWorld = pszParent ? getWorldRestQuat(pszParent, adjustedPszRest) : new THREE.Quaternion();
    const psoArmWorld = getWorldRestQuat(psoBone, psoRest);
    adjustedPszRest.localQuats[pszBone] = pszParentWorld.clone().invert().multiply(psoArmWorld);
  }

  const tracks: THREE.KeyframeTrack[] = [];
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
      // Rotate root position to match retargeted root orientation.
      // Without this, root rotation retargeting changes facing direction
      // but position still moves in the original direction → shuffling.
      const psoWorldRest = getWorldRestQuat(boneName, psoRest);
      const pszWorldRest = getWorldRestQuat(pszBoneName, adjustedPszRest);
      const F = pszWorldRest.clone().invert().multiply(psoWorldRest);
      const posRotation = F.clone().invert(); // same 'suffix' applied to root rotation

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
  // Build wrist tracks: PSO wrist bones (identity rest) → weapon wrapper nodes
  if (wristTargets) {
    for (const [psoWristBone, targetName] of Object.entries(wristTargets)) {
      const wristInfo = WRIST_BONES[psoWristBone];
      if (!wristInfo) continue;

      const wristTrack = clip.tracks.find((t) => t.name === psoWristBone + '.quaternion');
      if (!wristTrack) continue;

      // F = inv(pszForearmWorldRest) * psoForearmWorldRest
      // Same F used for the forearm retargeting — wrist is a child with identity rest
      const psoForearmWorld = getWorldRestQuat(wristInfo.forearmPso, psoRest);
      const pszForearmWorld = getWorldRestQuat(wristInfo.forearmPsz, adjustedPszRest);
      const F = pszForearmWorld.clone().invert().multiply(psoForearmWorld);
      const Finv = F.clone().invert();

      const srcValues = wristTrack.values;
      const dstValues = new Float32Array(srcValues.length);
      const wristAnim = new THREE.Quaternion();

      for (let i = 0; i < srcValues.length; i += 4) {
        wristAnim.set(srcValues[i], srcValues[i + 1], srcValues[i + 2], srcValues[i + 3]);
        const corrected = F.clone().multiply(wristAnim).multiply(Finv);
        dstValues[i] = corrected.x;
        dstValues[i + 1] = corrected.y;
        dstValues[i + 2] = corrected.z;
        dstValues[i + 3] = corrected.w;
      }

      tracks.push(new THREE.QuaternionKeyframeTrack(
        targetName + '.quaternion',
        Array.from(wristTrack.times),
        Array.from(dstValues),
      ));
    }
  }

  if (tracks.length === 0) return null;
  return new THREE.AnimationClip(outputName || clip.name + '_retargeted', clip.duration, tracks);
}

// PSO animation definitions per weapon category
// Each entry: PSO animation index → { name (internal clip name), label (display name) }
export interface PsoAnimDef {
  index: number;
  name: string;
  label: string;
}

export const PSO_CATEGORY_ANIMATIONS: Record<string, PsoAnimDef[]> = {
  saver: [
    { index: 97, name: 'pso_sa_walk_ready', label: 'PSO Walk Ready' },
    { index: 98, name: 'pso_sa_tec', label: 'PSO Cast Tech' },
    { index: 99, name: 'pso_sa_atk1', label: 'PSO Attack 1' },
    { index: 100, name: 'pso_sa_atk2', label: 'PSO Attack 2' },
    { index: 101, name: 'pso_sa_atk3', label: 'PSO Attack 3' },
    { index: 102, name: 'pso_sa_wait', label: 'PSO Idle Ready' },
    { index: 103, name: 'pso_sa_block', label: 'PSO Block' },
    { index: 104, name: 'pso_sa_walk', label: 'PSO Walk' },
    { index: 105, name: 'pso_sa_dam_h', label: 'PSO Damage Flip' },
    { index: 106, name: 'pso_sa_dam_d_wa', label: 'PSO Get Up' },
    { index: 107, name: 'pso_sa_dam_n', label: 'PSO Damage Light' },
    { index: 108, name: 'pso_sa_dam_d', label: 'PSO Damage Down' },
    { index: 109, name: 'pso_sa_press', label: 'PSO Press Button' },
    { index: 110, name: 'pso_sa_pb', label: 'PSO Photon Blast' },
    { index: 111, name: 'pso_sa_run', label: 'PSO Run' },
  ],
  sword: [
    { index: 112, name: 'pso_sw_walk_ready', label: 'PSO Walk Ready' },
    { index: 113, name: 'pso_sw_tec', label: 'PSO Cast Tech' },
    { index: 114, name: 'pso_sw_atk1', label: 'PSO Attack 1' },
    { index: 115, name: 'pso_sw_atk2', label: 'PSO Attack 2' },
    { index: 116, name: 'pso_sw_atk3', label: 'PSO Attack 3' },
    { index: 117, name: 'pso_sw_wait', label: 'PSO Idle Ready' },
    { index: 118, name: 'pso_sw_block', label: 'PSO Block' },
    { index: 119, name: 'pso_sw_walk', label: 'PSO Walk' },
    { index: 120, name: 'pso_sw_dam_h', label: 'PSO Damage Flip' },
    { index: 121, name: 'pso_sw_dam_d_wa', label: 'PSO Get Up' },
    { index: 122, name: 'pso_sw_dam_n', label: 'PSO Damage Light' },
    { index: 123, name: 'pso_sw_dam_d', label: 'PSO Damage Down' },
    { index: 124, name: 'pso_sw_pb', label: 'PSO Photon Blast' },
  ],
};
