import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';
import {
  captureRestPose,
  buildRetargetedClip,
  resetToBindPose,
  BONE_MAPPINGS_VRM,
  type RestPoseData,
} from './retarget-utils';

// VRM target uses item_shop NPC's converted GLB. Textures are embedded
// (unlike the PSZ player tuner that side-loads a flat PNG), so no
// separate texture path — the GLTFLoader's materials carry through.
const VRM_MODEL_PATH = assetUrl('assets/npcs/item_shop/item_shop.glb');
const PSO_MODEL_PATH = assetUrl('/data/retarget/Humar_body.glb');
const ANIMATION_MAP_PATH = assetUrl('/data/retarget/pso_animation_map.json');

// VRM bones that can be adjusted, in display order. The field is still
// called `pszBone` for parity with the PSZ tuner so the rest of the
// component reads identically; semantically it's the *target-skeleton*
// bone name and here that's a VRM J_Bip_* identifier.
const TUNABLE_BONES = [
  { pszBone: 'Root', label: 'Root' },
  { pszBone: 'J_Bip_C_Hips', label: 'Hip' },
  { pszBone: 'J_Bip_C_Chest', label: 'Chest' },
  { pszBone: 'J_Bip_C_UpperChest', label: 'UpperChest' },
  { pszBone: 'J_Bip_C_Head', label: 'Head' },
  { pszBone: 'J_Bip_L_UpperArm', label: 'L Upper Arm' },
  { pszBone: 'J_Bip_L_LowerArm', label: 'L Forearm' },
  { pszBone: 'J_Bip_R_UpperArm', label: 'R Upper Arm' },
  { pszBone: 'J_Bip_R_LowerArm', label: 'R Forearm' },
  { pszBone: 'J_Bip_L_UpperLeg', label: 'L Upper Leg' },
  { pszBone: 'J_Bip_L_LowerLeg', label: 'L Lower Leg' },
  { pszBone: 'J_Bip_R_UpperLeg', label: 'R Upper Leg' },
  { pszBone: 'J_Bip_R_LowerLeg', label: 'R Lower Leg' },
];

// Direction-reference: for each tunable bone, the child bone whose
// world position (relative to the parent's world position) defines the
// parent bone's "forward" direction. Used by the auto-calibrator to
// align VRM bone orientation with the PSO equivalent. Head and forearm
// leaf reference points are non-tunable VRM bones (hand, foot, chest)
// — we just need a downstream point to define direction, not a bone we
// also adjust. PSO references come from inspecting the Humar_body.glb
// hierarchy (numeric bones; child indices are usually n+1 along a chain
// but the hip/spine branching makes some pairings non-obvious).
const VRM_DIRECTION_CHILD: Record<string, string> = {
  'Root': 'J_Bip_C_Hips',
  'J_Bip_C_Hips': 'J_Bip_C_Spine',
  'J_Bip_C_Chest': 'J_Bip_C_UpperChest',
  'J_Bip_C_UpperChest': 'J_Bip_C_Neck',
  'J_Bip_L_UpperArm': 'J_Bip_L_LowerArm',
  'J_Bip_L_LowerArm': 'J_Bip_L_Hand',
  'J_Bip_R_UpperArm': 'J_Bip_R_LowerArm',
  'J_Bip_R_LowerArm': 'J_Bip_R_Hand',
  'J_Bip_L_UpperLeg': 'J_Bip_L_LowerLeg',
  'J_Bip_L_LowerLeg': 'J_Bip_L_Foot',
  'J_Bip_R_UpperLeg': 'J_Bip_R_LowerLeg',
  'J_Bip_R_LowerLeg': 'J_Bip_R_Foot',
  // J_Bip_C_Head is a leaf for our purposes — no direction child.
};
const PSO_DIRECTION_CHILD: Record<string, string> = {
  bone_000: 'bone_002',    // Root → Hip
  bone_002: 'bone_024',    // Hip → Spine
  bone_024: 'bone_025',    // Chest → UpperChest (co-located in PSO)
  bone_025: 'bone_056',    // UpperChest → Head (skips through neck since
                           // PSO bone_055/Neck not in mapping)
  bone_028: 'bone_029',    // L upper arm → L forearm
  bone_029: 'bone_030',    // L forearm → L wrist (WRIST_BONES entry)
  bone_041: 'bone_042',    // R upper arm → R forearm
  bone_042: 'bone_043',    // R forearm → R wrist
  bone_004: 'bone_005',    // L upper leg → L lower leg
  bone_005: 'bone_006',    // L lower leg → L foot (assumed n+1)
  bone_013: 'bone_014',    // R upper leg → R lower leg
  bone_014: 'bone_015',    // R lower leg → R foot (assumed n+1)
};

interface BoneOffset {
  x: number; // degrees
  y: number;
  z: number;
}

type OffsetMap = Record<string, BoneOffset>;

// Defaults seeded from Auto Calibrate (direction matching from rest
// pose). Geometrically meaningful — each value is the local rotation
// that aligns the VRM bone's (head→child) direction with the PSO
// equivalent at rest. Combined with the arm-correction in
// buildRetargetedClip (which independently aligns arm rest world
// quats), this gives a visually-correct retargeting without any
// manual tuning. The Optimize button explores around these for
// numerical refinement, but the position+rotation metric still finds
// local minima that look visually wrong, so prefer the auto-cal
// values unless you're verifying with screenshots after each step.
const BAKED_OPTIMAL_OFFSETS: Record<string, BoneOffset> = {
  // Hips / upper-chest / legs from Auto Calibrate's geometric direction
  // matching at rest.
  Root: { x: -0.2, y: 0, z: 0 },
  // Hip X zeroed — auto-cal's -13.5° was geometrically correct at rest
  // but stacks badly during animation and tilts the character ~20°
  // backward. See bake-retarget-vrm.mjs for the full reasoning.
  J_Bip_C_Hips: { x: 0, y: 0, z: 0 },
  J_Bip_C_UpperChest: { x: 14.7, y: 0, z: -0.4 },
  J_Bip_L_UpperLeg: { x: -5.3, y: -0.2, z: 4.6 },
  J_Bip_L_LowerLeg: { x: 1.4, y: 0.1, z: 4.6 },
  J_Bip_R_UpperLeg: { x: -5.3, y: 0.2, z: -4.5 },
  J_Bip_R_LowerLeg: { x: 1.4, y: -0.1, z: -4.5 },
  // Manual arm fixes after visual review of several PSO animations:
  //   L Forearm   X +90  → thumb forward (the VRM rig anatomically wants
  //                       a forearm twist that the auto-calibrator's
  //                       direction-only match doesn't supply)
  //   R Upper Arm Z +180 → fixes alignment of the entire right arm. PSO
  //                       has asymmetric L vs R chains (bone_026/027/028
  //                       on left but bone_038/039/040/041 on right with
  //                       different intermediate rotations) so the right
  //                       side needs a half-turn that the left doesn't.
  //   R Forearm   X -90  → thumb forward, mirror of L forearm twist
  J_Bip_L_LowerArm: { x: 90, y: 0, z: 0 },
  J_Bip_R_UpperArm: { x: 0, y: 0, z: 180 },
  J_Bip_R_LowerArm: { x: -90, y: 0, z: 0 },
};

function defaultOffsets(): OffsetMap {
  const m: OffsetMap = {};
  for (const b of TUNABLE_BONES) {
    m[b.pszBone] = BAKED_OPTIMAL_OFFSETS[b.pszBone] ? { ...BAKED_OPTIMAL_OFFSETS[b.pszBone] } : { x: 0, y: 0, z: 0 };
  }
  return m;
}


interface SceneState {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  pszModel: THREE.Object3D | null;
  psoModel: THREE.Object3D | null;
  pszMixer: THREE.AnimationMixer | null;
  psoMixer: THREE.AnimationMixer | null;
  psoAnimations: THREE.AnimationClip[];
  psoRest: RestPoseData;
  pszRest: RestPoseData;
  psoScale: number;
  currentAction: THREE.AnimationAction | null;
  currentPsoAction: THREE.AnimationAction | null;
  helper: THREE.SkeletonHelper | null;
}

export default function RetargetTuner() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneState | null>(null);

  const [offsets, setOffsets] = useState<OffsetMap>(() => {
    // Restore previously-saved offsets from localStorage if present so
    // the user doesn't lose hard-won optimization runs on reload.
    try {
      const raw = localStorage.getItem('vrm-tuner-offsets-v1');
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object') return parsed as OffsetMap;
      }
    } catch { /* ignore */ }
    return defaultOffsets();
  });
  const [psoAnimNames, setPsoAnimNames] = useState<string[]>([]);
  const [selectedAnim, setSelectedAnim] = useState<string | null>(null);
  const [animNameMap, setAnimNameMap] = useState<Record<string, string>>({});
  const [animSearch, setAnimSearch] = useState('');
  const [playbackSpeed, setPlaybackSpeed] = useState(1);
  const [isPlaying, setIsPlaying] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [showSkeleton, setShowSkeleton] = useState(true);

  // Load animation name mappings
  useEffect(() => {
    fetch(ANIMATION_MAP_PATH)
      .then((r) => r.json())
      .then((data: { mappings: Record<string, string> }) => setAnimNameMap(data.mappings || {}))
      .catch(() => {});
  }, []);

  // Persist offsets to localStorage on every change so reloads restore
  // the optimization state — important for long-running brute-force
  // searches that take 30+ seconds to find a good configuration.
  useEffect(() => {
    try {
      localStorage.setItem('vrm-tuner-offsets-v1', JSON.stringify(offsets));
    } catch { /* quota exceeded — ignore */ }
  }, [offsets]);

  // Expose state setters + an in-place measurement helper to window so
  // headless / playwright-driven optimizers can run offset grid
  // searches without going through DOM events. Re-exposed on each
  // render so consumers always see the latest closure.
  useEffect(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const w = window as any;
    w.__setOffsets = setOffsets;
    w.__getOffsets = () => offsets;
    w.__getSelectedAnim = () => selectedAnim;
    w.__setSelectedAnim = setSelectedAnim;
    // In-place measurement: takes an offsets map + anim name, applies
    // them via a synchronous clip rebuild + mixer step, returns total
    // per-frame error WITHOUT going through React state. Much faster
    // than dispatching slider events for grid search.
    // Anim track inspector: list bones with quaternion tracks in a clip,
    // plus a sample of their values, so we can see which PSO
    // intermediate bones actually animate vs sit static at rest.
    // Probe arbitrary bone world positions — useful for figuring out
    // which VRM bone is geometrically closest to a given PSO bone.
    w.__probeBones = (vrmNames: string[], psoNames: string[]) => {
      const s = sceneRef.current;
      if (!s || !s.pszModel || !s.psoModel) return null;
      resetToBindPose(s.pszModel);
      resetToBindPose(s.psoModel);
      s.pszModel.updateMatrixWorld(true);
      s.psoModel.updateMatrixWorld(true);
      const find = (root: THREE.Object3D, name: string): THREE.Bone | null => {
        let f: THREE.Bone | null = null;
        root.traverse((c) => { if (!f && (c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone; });
        return f;
      };
      const out: Record<string, [number, number, number]> = {};
      for (const n of vrmNames) {
        const b = find(s.pszModel, n);
        if (b) {
          const v = new THREE.Vector3();
          b.getWorldPosition(v);
          out[`vrm:${n}`] = [v.x, v.y, v.z];
        }
      }
      for (const n of psoNames) {
        const b = find(s.psoModel, n);
        if (b) {
          const v = new THREE.Vector3();
          b.getWorldPosition(v);
          out[`pso:${n}`] = [v.x, v.y, v.z];
        }
      }
      return out;
    };

    w.__inspectAnim = (animName: string) => {
      const s = sceneRef.current;
      if (!s) return null;
      const clip = s.psoAnimations.find((a) => a.name === animName);
      if (!clip) return null;
      const bones: Array<{ bone: string; trackTypes: string[]; quatRange?: number }> = [];
      const byBone: Record<string, { types: Set<string>; quatRange: number }> = {};
      for (const tr of clip.tracks) {
        const dotIdx = tr.name.lastIndexOf('.');
        const boneName = tr.name.substring(0, dotIdx);
        const prop = tr.name.substring(dotIdx + 1);
        if (!byBone[boneName]) byBone[boneName] = { types: new Set(), quatRange: 0 };
        byBone[boneName].types.add(prop);
        if (prop === 'quaternion') {
          // Estimate animation magnitude — max angle traversed from t=0
          const vals = tr.values;
          if (vals.length >= 8) {
            const q0 = new THREE.Quaternion(vals[0], vals[1], vals[2], vals[3]);
            let maxAng = 0;
            for (let i = 4; i < vals.length; i += 4) {
              const qi = new THREE.Quaternion(vals[i], vals[i + 1], vals[i + 2], vals[i + 3]);
              const a = q0.angleTo(qi);
              if (a > maxAng) maxAng = a;
            }
            byBone[boneName].quatRange = maxAng;
          }
        }
      }
      for (const [b, info] of Object.entries(byBone)) {
        bones.push({
          bone: b,
          trackTypes: Array.from(info.types),
          quatRange: Math.round(info.quatRange * 180 / Math.PI * 10) / 10,
        });
      }
      bones.sort((a, b) => parseInt(a.bone.replace('bone_', '')) - parseInt(b.bone.replace('bone_', '')));
      return bones;
    };

    // Motion correlation: for each frame t > 0, compare the world
    // *delta* of each bone (rotation change since t-1) on VRM vs PSO.
    // If the deltas match, the animations are visually aligned even
    // when absolute orientations differ (e.g. baked R Upper Arm Z+180
    // offset makes the arm twist correctly but bakes a 180° absolute
    // rotation difference — the motion-delta sees through that).
    w.__measureMotion = (testOffsets: OffsetMap, animName: string, nFrames = 20) => {
      const s = sceneRef.current;
      if (!s || !s.pszModel || !s.psoModel || !s.pszMixer || !s.psoMixer) return null;
      const clip = s.psoAnimations.find((a) => a.name === animName);
      if (!clip) return null;
      if (s.currentAction) {
        s.currentAction.stop();
        s.pszMixer.uncacheAction(s.currentAction.getClip());
      }
      if (s.currentPsoAction) {
        s.currentPsoAction.stop();
        s.psoMixer.uncacheAction(s.currentPsoAction.getClip());
      }
      resetToBindPose(s.pszModel);
      const retargeted = buildRetargetedClip(
        clip, s.psoRest, s.pszRest, BONE_MAPPINGS_VRM, s.psoScale,
        undefined, undefined, testOffsets,
      );
      if (!retargeted) return null;
      const action = s.pszMixer.clipAction(retargeted);
      action.play();
      const psoAction = s.psoMixer.clipAction(clip);
      psoAction.play();
      s.currentAction = action;
      s.currentPsoAction = psoAction;
      const findBone = (root: THREE.Object3D, name: string): THREE.Bone | null => {
        let f: THREE.Bone | null = null;
        root.traverse((c) => { if (!f && (c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone; });
        return f;
      };
      // First pass: capture per-frame world quats for every mapped bone
      const vrmFrames: Record<string, THREE.Quaternion[]> = {};
      const psoFrames: Record<string, THREE.Quaternion[]> = {};
      for (const [, vrmName] of Object.entries(BONE_MAPPINGS_VRM)) vrmFrames[vrmName] = [];
      for (const [psoName] of Object.entries(BONE_MAPPINGS_VRM)) psoFrames[psoName] = [];
      for (let i = 0; i < nFrames; i++) {
        const t = (i / Math.max(1, nFrames - 1)) * clip.duration;
        s.pszMixer.setTime(t);
        s.psoMixer.setTime(t);
        s.pszModel.updateMatrixWorld(true);
        s.psoModel.updateMatrixWorld(true);
        for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
          const vBone = findBone(s.pszModel, vrmBoneName);
          const pBone = findBone(s.psoModel, psoBoneName);
          if (!vBone || !pBone) continue;
          const vq = new THREE.Quaternion(); const pq = new THREE.Quaternion();
          vBone.getWorldQuaternion(vq);
          pBone.getWorldQuaternion(pq);
          vrmFrames[vrmBoneName].push(vq);
          psoFrames[psoBoneName].push(pq);
        }
      }
      // For each bone compute the sum-of-squared-differences between
      // frame-to-frame angular deltas on VRM vs PSO. A perfect motion
      // match has zero. Total over bones and frames is the motion
      // correlation error.
      const rad2deg = 180 / Math.PI;
      const perBoneMotionDeg: Record<string, number> = {};
      let totalDeltaErr = 0;
      let totalRangeDeg = 0;
      for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
        const vrm = vrmFrames[vrmBoneName];
        const pso = psoFrames[psoBoneName];
        if (!vrm || vrm.length < 2 || !pso || pso.length < 2) continue;
        let sumErr = 0;
        let psoRange = 0;
        for (let i = 1; i < vrm.length; i++) {
          // Delta = relative quat from i-1 to i; angle is the change.
          const vDelta = vrm[i - 1].clone().invert().multiply(vrm[i]);
          const pDelta = pso[i - 1].clone().invert().multiply(pso[i]);
          // Difference of motion magnitudes: how much they each moved
          // and in what direction. Use angle as a scalar; sign-aware
          // diff via axis comparison would be more nuanced.
          const vAng = 2 * Math.acos(Math.min(1, Math.abs(vDelta.w)));
          const pAng = 2 * Math.acos(Math.min(1, Math.abs(pDelta.w)));
          sumErr += Math.abs(vAng - pAng);
          psoRange += pAng;
        }
        perBoneMotionDeg[vrmBoneName] = sumErr * rad2deg;
        totalDeltaErr += sumErr;
        totalRangeDeg += psoRange * rad2deg;
      }
      return {
        animName,
        nFrames,
        // Sum of |Δ_vrm - Δ_pso| in degrees across all bones and frames
        motionErrDeg: totalDeltaErr * rad2deg,
        // For context: total PSO motion magnitude (how much PSO actually moved)
        psoMotionRangeDeg: totalRangeDeg,
        // Normalised: motion error as fraction of PSO motion
        normalisedErr: totalRangeDeg > 0 ? (totalDeltaErr * rad2deg) / totalRangeDeg : 0,
        perBoneMotionDeg,
      };
    };

    // Direct probe of how a specific PSO bone's world position changes
    // across a clip after setTime — used to confirm the mixer is
    // actually advancing.
    w.__debugPsoMotion = (animName: string, psoBoneName: string) => {
      const s = sceneRef.current;
      if (!s || !s.psoModel || !s.psoMixer) return null;
      const clip = s.psoAnimations.find((a) => a.name === animName);
      if (!clip) return { error: 'no clip' };
      const find = (root: THREE.Object3D, name: string): THREE.Bone | null => {
        let f: THREE.Bone | null = null;
        root.traverse((c) => { if (!f && (c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone; });
        return f;
      };
      const bone = find(s.psoModel, psoBoneName);
      if (!bone) return { error: 'no bone' };
      // Stop existing PSO action
      if (s.currentPsoAction) {
        s.currentPsoAction.stop();
        s.psoMixer.uncacheAction(s.currentPsoAction.getClip());
      }
      const action = s.psoMixer.clipAction(clip);
      action.play();
      s.currentPsoAction = action;
      const samples: Array<{ t: number; pos: number[] }> = [];
      for (let i = 0; i < 5; i++) {
        const t = (i / 4) * clip.duration;
        s.psoMixer.setTime(t);
        s.psoModel!.updateMatrixWorld(true);
        const p = new THREE.Vector3();
        bone.getWorldPosition(p);
        samples.push({ t: Math.round(t * 100) / 100, pos: [p.x, p.y, p.z].map((n) => Math.round(n * 1000) / 1000) });
      }
      return { animName, psoBoneName, duration: clip.duration, samples };
    };

    w.__measureOffsets = (testOffsets: OffsetMap, animName: string, nFrames = 5) => {
      const s = sceneRef.current;
      if (!s || !s.pszModel || !s.psoModel || !s.pszMixer || !s.psoMixer) return null;
      const clip = s.psoAnimations.find((a) => a.name === animName);
      if (!clip) return null;
      // Stop current actions
      if (s.currentAction) {
        s.currentAction.stop();
        s.pszMixer.uncacheAction(s.currentAction.getClip());
      }
      if (s.currentPsoAction) {
        s.currentPsoAction.stop();
        s.psoMixer.uncacheAction(s.currentPsoAction.getClip());
      }
      resetToBindPose(s.pszModel);
      const retargeted = buildRetargetedClip(
        clip, s.psoRest, s.pszRest, BONE_MAPPINGS_VRM, s.psoScale,
        undefined, undefined, testOffsets,
      );
      if (!retargeted) return null;
      const action = s.pszMixer.clipAction(retargeted);
      action.play();
      const psoAction = s.psoMixer.clipAction(clip);
      psoAction.play();
      s.currentAction = action;
      s.currentPsoAction = psoAction;

      const findBone = (root: THREE.Object3D, name: string): THREE.Bone | null => {
        let f: THREE.Bone | null = null;
        root.traverse((c) => { if (!f && (c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone; });
        return f;
      };
      // Combined metric: position L2 distance + rotation angular
      // distance (weighted). Position alone is under-constrained for
      // rotation; rotation pins the bone's full orientation. Weight 0.5
      // puts a 90° rotation error roughly on par with a 0.78m position
      // error. We track both components separately so callers can pick
      // what matters — position alone (visual placement) vs combined
      // (twist-aware optimization).
      const ROT_WEIGHT = 0.5;
      let total = 0;
      let totalPos = 0;
      let totalRotRad = 0;
      const perBone: Record<string, number> = {};
      const perBonePos: Record<string, number> = {};
      const perBoneRotDeg: Record<string, number> = {};
      const rad2deg = 180 / Math.PI;
      for (let i = 0; i < nFrames; i++) {
        const t = (i / Math.max(1, nFrames - 1)) * clip.duration;
        s.pszMixer.setTime(t);
        s.psoMixer.setTime(t);
        s.pszModel.updateMatrixWorld(true);
        s.psoModel.updateMatrixWorld(true);
        for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
          const vrmBone = findBone(s.pszModel, vrmBoneName);
          const psoBone = findBone(s.psoModel, psoBoneName);
          if (!vrmBone || !psoBone) continue;
          const vp = new THREE.Vector3();
          const pp = new THREE.Vector3();
          vrmBone.getWorldPosition(vp);
          psoBone.getWorldPosition(pp);
          const posErr = vp.distanceTo(pp);
          const vq = new THREE.Quaternion();
          const pq = new THREE.Quaternion();
          vrmBone.getWorldQuaternion(vq);
          psoBone.getWorldQuaternion(pq);
          const rotRad = vq.angleTo(pq);
          const d = posErr + rotRad * ROT_WEIGHT;
          total += d;
          totalPos += posErr;
          totalRotRad += rotRad;
          perBone[vrmBoneName] = (perBone[vrmBoneName] || 0) + d;
          perBonePos[vrmBoneName] = (perBonePos[vrmBoneName] || 0) + posErr;
          perBoneRotDeg[vrmBoneName] = (perBoneRotDeg[vrmBoneName] || 0) + rotRad * rad2deg;
        }
      }
      for (const k in perBone) {
        perBone[k] /= nFrames;
        perBonePos[k] /= nFrames;
        perBoneRotDeg[k] /= nFrames;
      }
      return {
        total: total / nFrames,
        perBone,
        positionTotal: totalPos / nFrames,
        positionPerBone: perBonePos,
        rotationTotalDeg: (totalRotRad * rad2deg) / nFrames,
        rotationPerBoneDeg: perBoneRotDeg,
      };
    };
  });

  // Filter animations
  const filteredAnims = useMemo(() => {
    if (!animSearch) return psoAnimNames;
    const q = animSearch.toLowerCase();
    return psoAnimNames.filter((name) => {
      const idx = name.replace('plymotiondata_', '');
      const mapped = animNameMap[idx];
      return idx.includes(q) || (mapped && mapped.toLowerCase().includes(q)) || name.toLowerCase().includes(q);
    });
  }, [psoAnimNames, animSearch, animNameMap]);

  // Initialize scene
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 100);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setClearColor(0x0a0a1a);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(5, 5, 5);
    scene.add(dirLight);
    scene.add(new THREE.GridHelper(10, 10, 0x333333, 0x222222));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    // Aim at the midpoint between VRM (x=-1) and PSO (x=1.5). Pull
    // the camera back further so both characters fit in frame.
    controls.target.set(0.25, 1.0, 0);
    camera.position.set(0.25, 1.3, 4.5);

    sceneRef.current = {
      scene, camera, renderer, controls,
      pszModel: null, psoModel: null,
      pszMixer: null, psoMixer: null, psoAnimations: [],
      psoRest: { localQuats: {}, worldQuats: {}, parentMap: {} },
      pszRest: { localQuats: {}, worldQuats: {}, parentMap: {} },
      psoScale: 1, currentAction: null, currentPsoAction: null, helper: null,
    };

    const clock = new THREE.Clock();
    const animate = () => {
      requestAnimationFrame(animate);
      const delta = clock.getDelta();
      if (sceneRef.current?.pszMixer) sceneRef.current.pszMixer.update(delta);
      if (sceneRef.current?.psoMixer) sceneRef.current.psoMixer.update(delta);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const loader = new GLTFLoader();

    // Load VRM target (embedded textures; no side-load override).
    loader.load(VRM_MODEL_PATH, (gltf) => {
      const model = gltf.scene;
      // Side-by-side layout: VRM on the left, PSO reference on the
      // right. Co-location (both at x=0) was useful for measuring
      // bone-position errors during calibration, but with the
      // retargeting now matching motion 1:1 (see __measureMotion in
      // the tuner), comparison is more readable as two normal-opacity
      // characters next to each other.
      model.position.x = -1.0;
      scene.add(model);
      sceneRef.current!.pszModel = model;
      const helper = new THREE.SkeletonHelper(model);
      (helper.material as THREE.LineBasicMaterial).color.set(0x44ff44);
      (helper.material as THREE.LineBasicMaterial).linewidth = 2;
      helper.renderOrder = 998;
      scene.add(helper);
      sceneRef.current!.helper = helper;

      sceneRef.current!.pszMixer = new THREE.AnimationMixer(model);
      model.updateMatrixWorld(true);
      sceneRef.current!.pszRest = captureRestPose(model);

      // Load PSO reference. Full opacity now that we're side-by-side.
      // The Snap/Restore diagnostic still works with this layout —
      // Snap moves VRM bone positions onto PSO bones in world space,
      // so visually the VRM will jump to overlap PSO if you click it.
      loader.load(PSO_MODEL_PATH, (psoGltf) => {
        const psoModel = psoGltf.scene;
        psoModel.position.x = 1.5;
        scene.add(psoModel);

        // Scale BEFORE resetting — animated pose gives reliable bounding box
        psoModel.updateMatrixWorld(true);
        const pszBox = new THREE.Box3().setFromObject(model);
        const psoBox = new THREE.Box3().setFromObject(psoModel);
        const pszH = pszBox.max.y - pszBox.min.y;
        const psoH = psoBox.max.y - psoBox.min.y;
        const scale = psoH > 0 ? pszH / psoH : 1;
        sceneRef.current!.psoScale = scale;
        psoModel.scale.multiplyScalar(scale);
        psoModel.updateMatrixWorld(true);

        // Reset to bind pose THEN capture rest quaternions
        resetToBindPose(psoModel);
        psoModel.updateMatrixWorld(true);
        sceneRef.current!.psoRest = captureRestPose(psoModel);

        // Second skeleton helper, colored orange, so PSO bones are
        // visible alongside the green VRM skeleton when overlaid.
        const psoHelper = new THREE.SkeletonHelper(psoModel);
        (psoHelper.material as THREE.LineBasicMaterial).color.set(0xff8844);
        (psoHelper.material as THREE.LineBasicMaterial).linewidth = 2;
        psoHelper.renderOrder = 999;
        scene.add(psoHelper);

        sceneRef.current!.psoModel = psoModel;
        sceneRef.current!.psoMixer = new THREE.AnimationMixer(psoModel);
        sceneRef.current!.psoAnimations = psoGltf.animations;

        const names = psoGltf.animations.map((a) => a.name).sort((a, b) => {
          const numA = parseInt(a.replace('plymotiondata_', ''), 10);
          const numB = parseInt(b.replace('plymotiondata_', ''), 10);
          return numA - numB;
        });
        setPsoAnimNames(names);
        setLoaded(true);
      });
    });

    const handleResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
    };
  }, []);

  // Static preview when no animation is selected: write each tunable
  // bone's local quat = native_rest * offsetQuat so the slider effect
  // is visible on the VRM at rest. Lets the user dial in arm-down
  // offsets against the PSO model's rest pose side-by-side, instead of
  // chasing a moving target. Skipped when an animation is selected —
  // the AnimationMixer owns the bones then.
  useEffect(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel) return;
    if (selectedAnim) return;
    if (!loaded) return;

    const deg2rad = Math.PI / 180;
    s.pszModel.traverse((c) => {
      if (!(c as THREE.Bone).isBone) return;
      const base = s.pszRest.localQuats[c.name];
      if (!base) return;
      const off = offsets[c.name];
      if (!off || (off.x === 0 && off.y === 0 && off.z === 0)) {
        c.quaternion.copy(base);
        return;
      }
      const e = new THREE.Euler(off.x * deg2rad, off.y * deg2rad, off.z * deg2rad, 'XYZ');
      const offQuat = new THREE.Quaternion().setFromEuler(e);
      c.quaternion.copy(base).multiply(offQuat);
    });
    s.pszModel.updateMatrixWorld(true);
  }, [offsets, selectedAnim, loaded]);

  // Rebuild retargeted clip when animation or offsets change
  useEffect(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel || !s.pszMixer) return;

    // Always stop the previous actions first so a selectedAnim → null
    // transition hands the bones back to the static-preview effect.
    if (s.currentAction) {
      s.currentAction.stop();
      s.pszMixer.uncacheAction(s.currentAction.getClip());
      s.currentAction = null;
    }
    if (s.currentPsoAction && s.psoMixer) {
      s.currentPsoAction.stop();
      s.psoMixer.uncacheAction(s.currentPsoAction.getClip());
      s.currentPsoAction = null;
    }

    if (!selectedAnim) return;

    const clip = s.psoAnimations.find((a) => a.name === selectedAnim);
    if (!clip) return;

    // Reset to bind pose
    resetToBindPose(s.pszModel);

    // Build retargeted clip — pass original rest + offsets separately
    // so offsets are applied AFTER arm correction (not overwritten by it)
    const retargetedClip = buildRetargetedClip(
      clip, s.psoRest, s.pszRest, BONE_MAPPINGS_VRM, s.psoScale,
      undefined, undefined, offsets,
    );

    if (retargetedClip) {
      const action = s.pszMixer.clipAction(retargetedClip);
      action.timeScale = playbackSpeed;
      action.play();
      if (!isPlaying) action.paused = true;
      s.currentAction = action;
    }

    // Play original animation on PSO model as reference
    if (s.psoMixer) {
      const psoAction = s.psoMixer.clipAction(clip);
      psoAction.timeScale = playbackSpeed;
      psoAction.play();
      if (!isPlaying) psoAction.paused = true;
      s.currentPsoAction = psoAction;
    }
  }, [selectedAnim, offsets, isPlaying]);

  // Update playback speed
  useEffect(() => {
    const s = sceneRef.current;
    if (s?.currentAction) s.currentAction.timeScale = playbackSpeed;
    if (s?.currentPsoAction) s.currentPsoAction.timeScale = playbackSpeed;
  }, [playbackSpeed]);

  // Toggle play/pause
  useEffect(() => {
    const s = sceneRef.current;
    if (s?.currentAction) s.currentAction.paused = !isPlaying;
    if (s?.currentPsoAction) s.currentPsoAction.paused = !isPlaying;
  }, [isPlaying]);

  // Toggle skeleton helper
  useEffect(() => {
    const s = sceneRef.current;
    if (s?.helper) s.helper.visible = showSkeleton;
  }, [showSkeleton]);

  const updateOffset = useCallback((bone: string, axis: 'x' | 'y' | 'z', value: number) => {
    setOffsets((prev) => ({
      ...prev,
      [bone]: { ...prev[bone], [axis]: value },
    }));
  }, []);

  const resetBone = useCallback((bone: string) => {
    setOffsets((prev) => ({ ...prev, [bone]: { x: 0, y: 0, z: 0 } }));
  }, []);

  const resetAll = useCallback(() => {
    setOffsets(defaultOffsets());
  }, []);

  const hasAnyOffset = Object.values(offsets).some((o) => o.x !== 0 || o.y !== 0 || o.z !== 0);

  const exportOffsets = useCallback(() => {
    const nonZero: OffsetMap = {};
    for (const [k, v] of Object.entries(offsets)) {
      if (v.x !== 0 || v.y !== 0 || v.z !== 0) nonZero[k] = v;
    }
    navigator.clipboard.writeText(JSON.stringify(nonZero, null, 2));
  }, [offsets]);

  // Direction-match auto-calibrator. For each tunable bone with a
  // discoverable child reference on both skeletons, compute the
  // rotation that aligns the VRM bone's (head → child) direction with
  // the PSO bone's equivalent direction, then express it as a local
  // offset that can be plugged into the slider state. Math is the
  // standard "rotate vector A onto vector B then conjugate into local
  // frame" pattern: O_local = inv(W_bone) * R_world * W_bone where
  // R_world = setFromUnitVectors(vrmDir, psoDir).
  const autoCalibrate = useCallback(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel || !s.psoModel) return;

    // Force both models into bind pose so the captured world matrices
    // reflect the true skeletal rest, not whatever the last animation
    // left behind.
    setSelectedAnim(null);
    resetToBindPose(s.pszModel);
    resetToBindPose(s.psoModel);
    s.pszModel.updateMatrixWorld(true);
    s.psoModel.updateMatrixWorld(true);

    const findBone = (root: THREE.Object3D, name: string): THREE.Bone | null => {
      let found: THREE.Bone | null = null;
      root.traverse((c) => {
        if (found) return;
        if ((c as THREE.Bone).isBone && c.name === name) found = c as THREE.Bone;
      });
      return found;
    };

    const rad2deg = 180 / Math.PI;
    const next: OffsetMap = defaultOffsets();
    const debug: Array<{ vrm: string; pso: string; vrmDir: number[]; psoDir: number[]; offset: number[] }> = [];

    // buildRetargetedClip applies its own arm-rest correction for these
    // PSO bones, mapping their VRM equivalents' world rest orientation
    // onto PSO's. Computing direction-match offsets on top of that
    // double-rotates the arms ~90° beyond where they should be. Skip
    // them here and let the arm-correction path do the work — frame
    // error testing confirms this gives the lowest residuals.
    const ARM_CORRECTED_PSO = new Set(['bone_028', 'bone_029', 'bone_041', 'bone_042']);

    for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
      if (ARM_CORRECTED_PSO.has(psoBoneName)) continue;
      const vrmChildName = VRM_DIRECTION_CHILD[vrmBoneName];
      const psoChildName = PSO_DIRECTION_CHILD[psoBoneName];
      if (!vrmChildName || !psoChildName) continue;

      const vrmBone = findBone(s.pszModel, vrmBoneName);
      const vrmChild = findBone(s.pszModel, vrmChildName);
      const psoBone = findBone(s.psoModel, psoBoneName);
      const psoChild = findBone(s.psoModel, psoChildName);
      if (!vrmBone || !vrmChild || !psoBone || !psoChild) continue;

      const vrmHead = new THREE.Vector3();
      const vrmTip = new THREE.Vector3();
      vrmBone.getWorldPosition(vrmHead);
      vrmChild.getWorldPosition(vrmTip);
      const vrmDir = new THREE.Vector3().subVectors(vrmTip, vrmHead);
      if (vrmDir.lengthSq() < 1e-8) continue;
      vrmDir.normalize();

      const psoHead = new THREE.Vector3();
      const psoTip = new THREE.Vector3();
      psoBone.getWorldPosition(psoHead);
      psoChild.getWorldPosition(psoTip);
      const psoDir = new THREE.Vector3().subVectors(psoTip, psoHead);
      if (psoDir.lengthSq() < 1e-8) continue;
      psoDir.normalize();

      // World rotation that maps VRM direction onto PSO direction
      const Rworld = new THREE.Quaternion().setFromUnitVectors(vrmDir, psoDir);

      // Conjugate into the VRM bone's local frame so the offset can
      // post-multiply the bone's existing local rotation (same
      // application path as the slider offsets through buildRetargetedClip
      // and the static-preview useEffect).
      const W = new THREE.Quaternion();
      vrmBone.getWorldQuaternion(W);
      const Olocal = W.clone().invert().multiply(Rworld).multiply(W);

      const euler = new THREE.Euler().setFromQuaternion(Olocal, 'XYZ');
      next[vrmBoneName] = {
        x: Math.round(euler.x * rad2deg * 10) / 10,
        y: Math.round(euler.y * rad2deg * 10) / 10,
        z: Math.round(euler.z * rad2deg * 10) / 10,
      };
      debug.push({
        vrm: vrmBoneName,
        pso: psoBoneName,
        vrmDir: [vrmDir.x, vrmDir.y, vrmDir.z],
        psoDir: [psoDir.x, psoDir.y, psoDir.z],
        offset: [next[vrmBoneName].x, next[vrmBoneName].y, next[vrmBoneName].z],
      });
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (window as any).__autoCalDebug = debug;
    // eslint-disable-next-line no-console
    console.table(debug);

    // Also dump the rest-pose WORLD POSITIONS of every mapped bone on
    // both rigs, plus per-side rest distance. Lets us see whether
    // residual position error is anchor-mismatch (e.g. VRM right
    // shoulder sitting noticeably away from PSO right shoulder even at
    // rest) vs accumulated rotation drift down a chain.
    const restProbe: Array<{
      vrm: string; pso: string;
      vrmPos: number[]; psoPos: number[];
      restDist: number;
    }> = [];
    for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
      const vrmBone = findBone(s.pszModel, vrmBoneName);
      const psoBone = findBone(s.psoModel, psoBoneName);
      if (!vrmBone || !psoBone) continue;
      const vp = new THREE.Vector3();
      const pp = new THREE.Vector3();
      vrmBone.getWorldPosition(vp);
      psoBone.getWorldPosition(pp);
      restProbe.push({
        vrm: vrmBoneName,
        pso: psoBoneName,
        vrmPos: [vp.x, vp.y, vp.z].map((n) => Math.round(n * 10000) / 10000),
        psoPos: [pp.x, pp.y, pp.z].map((n) => Math.round(n * 10000) / 10000),
        restDist: Math.round(vp.distanceTo(pp) * 10000) / 10000,
      });
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (window as any).__restProbe = restProbe;
    // eslint-disable-next-line no-console
    console.table(restProbe);

    setOffsets(next);
  }, []);

  // Brute-force coordinate-descent optimizer. Sweeps every tunable bone
  // × axis combination, picks the value that minimizes mean per-frame
  // bone-position error averaged across a few training animations.
  // Runs entirely off __measureOffsets (no React re-renders inside the
  // loop) so a full sweep takes a few seconds. Best to run AFTER Snap +
  // Auto Calibrate so we start from a reasonable seed.
  const [optimizing, setOptimizing] = useState(false);
  const [optimizeStatus, setOptimizeStatus] = useState('');
  const runOptimizer = useCallback(async () => {
    const s = sceneRef.current;
    if (!s || !s.pszModel || !s.psoModel) return;
    setOptimizing(true);
    setOptimizeStatus('warming up…');
    // Yield to React so the UI re-renders before the long sync loop.
    await new Promise((f) => setTimeout(f, 50));

    // Diverse training set covering different motion types.
    const trainAnims = [
      'plymotiondata_000', 'plymotiondata_002', 'plymotiondata_003',
      'plymotiondata_022', 'plymotiondata_019',
    ].filter((a) => s.psoAnimations.some((c) => c.name === a));
    if (trainAnims.length === 0) {
      setOptimizing(false);
      setOptimizeStatus('no PSO animations loaded');
      return;
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const measureOffsets = (window as any).__measureOffsets as (o: OffsetMap, a: string, n?: number) => { total: number } | null;
    const multiMeasure = (o: OffsetMap) => {
      let total = 0;
      let count = 0;
      for (const a of trainAnims) {
        const r = measureOffsets(o, a, 5);
        if (r) { total += r.total; count++; }
      }
      return count > 0 ? total / count : Infinity;
    };

    const tunableBones = TUNABLE_BONES.map((t) => t.pszBone);
    const axes: Array<'x' | 'y' | 'z'> = ['x', 'y', 'z'];
    let best: OffsetMap = JSON.parse(JSON.stringify(offsets));
    let bestErr = multiMeasure(best);
    const initialErr = bestErr;

    const coarseValues = [-90, -75, -60, -45, -30, -15, 0, 15, 30, 45, 60, 75, 90];
    for (let round = 0; round < 2; round++) {
      for (const bone of tunableBones) {
        for (const axis of axes) {
          for (const v of coarseValues) {
            const test = JSON.parse(JSON.stringify(best));
            test[bone] = { ...test[bone], [axis]: v };
            const t = multiMeasure(test);
            if (t < bestErr) { bestErr = t; best = test; }
          }
          setOptimizeStatus(`round ${round + 1}/2 · ${bone}.${axis} · best ${bestErr.toFixed(3)}m`);
          await new Promise((f) => setTimeout(f, 0));
        }
      }
    }
    // Fine pass
    for (const bone of tunableBones) {
      for (const axis of axes) {
        const cur = best[bone][axis];
        for (let d = -5; d <= 5; d++) {
          const v = Math.round((cur + d) * 10) / 10;
          const test = JSON.parse(JSON.stringify(best));
          test[bone] = { ...test[bone], [axis]: v };
          const t = multiMeasure(test);
          if (t < bestErr) { bestErr = t; best = test; }
        }
        setOptimizeStatus(`fine · ${bone}.${axis} · best ${bestErr.toFixed(3)}m`);
        await new Promise((f) => setTimeout(f, 0));
      }
    }

    setOffsets(best);
    setOptimizing(false);
    setOptimizeStatus(`done · ${initialErr.toFixed(3)} → ${bestErr.toFixed(3)} (-${Math.round((1 - bestErr / initialErr) * 100)}%)`);
  }, [offsets]);

  // Diagnostic: snap VRM bone positions onto PSO bone positions in the
  // rest pose. The skinned mesh deforms because vertex weights stay tied
  // to the original bone positions, but the skeleton helper now shows
  // VRM bones exactly where PSO's are — useful for isolating rotation
  // error from skeletal-proportion noise. Stores the original local
  // positions on the sceneRef so a Restore step can undo it.
  const snapToPso = useCallback(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel || !s.psoModel) return;
    setSelectedAnim(null);
    resetToBindPose(s.pszModel);
    resetToBindPose(s.psoModel);
    s.pszModel.updateMatrixWorld(true);
    s.psoModel.updateMatrixWorld(true);

    const findBone = (root: THREE.Object3D, name: string): THREE.Bone | null => {
      let f: THREE.Bone | null = null;
      root.traverse((c) => {
        if (f) return;
        if ((c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone;
      });
      return f;
    };

    // Cache originals so Restore can revert. Keyed by bone name.
    const orig: Record<string, [number, number, number]> = {};
    // Process in top-down order so each bone's parent matrixWorld is
    // already at its final value before we read it.
    const order = [
      'Root',
      'J_Bip_C_Hips',
      'J_Bip_C_Chest',
      'J_Bip_C_UpperChest',
      'J_Bip_C_Head',
      'J_Bip_L_UpperArm', 'J_Bip_L_LowerArm',
      'J_Bip_R_UpperArm', 'J_Bip_R_LowerArm',
      'J_Bip_L_UpperLeg', 'J_Bip_L_LowerLeg',
      'J_Bip_R_UpperLeg', 'J_Bip_R_LowerLeg',
    ];
    // Reverse-lookup PSO bone name from VRM bone name via the mapping.
    const vrmToPso: Record<string, string> = {};
    for (const [pso, vrm] of Object.entries(BONE_MAPPINGS_VRM)) vrmToPso[vrm] = pso;

    // VRM intermediates the PSO skeleton doesn't have (PSO collapses
    // these into the chest/upper-arm/head). For a clean diagnostic
    // skeleton render we snap each intermediate onto its mapped
    // descendant's target PSO position — making the intermediate
    // effectively zero-length so the chain draws as a single segment
    // from mapped ancestor to mapped descendant.
    const INTERMEDIATE_TO_TARGET: Record<string, string> = {
      // Spine is now Chest's parent in our mapping (Chest = bone_024,
      // UpperChest = bone_025). Snap Spine onto bone_024's position so
      // there's no kink between Hips and Chest.
      'J_Bip_C_Spine': 'bone_024',
      'J_Bip_L_Shoulder': 'bone_028',
      'J_Bip_R_Shoulder': 'bone_041',
      'J_Bip_C_Neck': 'bone_056',
    };

    const snapOne = (vrmName: string, psoName: string) => {
      const vrmBone = findBone(s.pszModel!, vrmName);
      const psoBone = findBone(s.psoModel!, psoName);
      if (!vrmBone || !psoBone || !vrmBone.parent) return;
      orig[vrmName] = [vrmBone.position.x, vrmBone.position.y, vrmBone.position.z];
      const psoWorld = new THREE.Vector3();
      psoBone.getWorldPosition(psoWorld);
      const parentWorldInverse = new THREE.Matrix4().copy(vrmBone.parent.matrixWorld).invert();
      const localPos = psoWorld.clone().applyMatrix4(parentWorldInverse);
      vrmBone.position.copy(localPos);
      vrmBone.updateMatrixWorld(true);
    };

    // Walk mapped + intermediate bones in top-down order. Whenever we
    // reach a mapped bone, also snap any intermediate that should
    // collapse onto it.
    for (const vrmName of order) {
      const psoName = vrmToPso[vrmName];
      if (!psoName) continue;
      // First: snap any intermediate that collapses onto THIS bone's
      // PSO target. Must happen BEFORE we move the mapped bone so the
      // intermediate's parent chain is still in its updated state.
      // Actually order doesn't matter for the intermediate→mapped
      // collapse since we're snapping both to the same world position;
      // they share parent state at that moment.
      for (const [interName, interTarget] of Object.entries(INTERMEDIATE_TO_TARGET)) {
        if (interTarget !== psoName) continue;
        snapOne(interName, interTarget);
      }
      snapOne(vrmName, psoName);
    }
    s.pszModel.updateMatrixWorld(true);

    // Re-derive each skeleton's boneInverses from the snapped matrices
    // so that resetToBindPose / skeleton.pose() restore TO the snapped
    // state, not the original VRM bind pose. Without this, picking any
    // animation would revert the snap on its first frame.
    s.pszModel.traverse((c) => {
      const sm = c as THREE.SkinnedMesh;
      if (sm.isSkinnedMesh && sm.skeleton) sm.skeleton.calculateInverses();
    });


    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (window as any).__snapOriginals = orig;
    // eslint-disable-next-line no-console
    console.log('[snap-to-pso] cached originals for', Object.keys(orig).length, 'bones');
  }, []);

  const restorePositions = useCallback(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel) return;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const orig = (window as unknown as { __snapOriginals?: Record<string, [number, number, number]> }).__snapOriginals;
    if (!orig) {
      // eslint-disable-next-line no-console
      console.warn('[restore-positions] nothing to restore');
      return;
    }
    s.pszModel.traverse((c) => {
      if (!(c as THREE.Bone).isBone) return;
      const o = orig[c.name];
      if (o) c.position.set(o[0], o[1], o[2]);
    });
    s.pszModel.updateMatrixWorld(true);
    s.pszModel.traverse((c) => {
      const sm = c as THREE.SkinnedMesh;
      if (sm.isSkinnedMesh && sm.skeleton) sm.skeleton.calculateInverses();
    });
  }, []);

  // Frame-by-frame bone-position error logger. Steps the currently
  // selected animation through 10 evenly-spaced samples, captures
  // mapped-bone world positions on both rigs at each sample, computes
  // L2 distance per bone, and dumps to console + window for further
  // inspection. Tells us where the retargeting still drifts (e.g. a
  // bone with consistently high error across frames likely has the
  // wrong PSO↔VRM mapping or needs a larger offset correction).
  const logFrameErrors = useCallback(() => {
    const s = sceneRef.current;
    if (!s || !s.pszModel || !s.psoModel || !s.pszMixer || !s.psoMixer) {
      // eslint-disable-next-line no-console
      console.warn('[frame-errors] no scene');
      return;
    }
    if (!selectedAnim) {
      // eslint-disable-next-line no-console
      console.warn('[frame-errors] pick an animation first');
      return;
    }
    const psoClip = s.psoAnimations.find((a) => a.name === selectedAnim);
    if (!psoClip) return;

    const findBone = (root: THREE.Object3D, name: string): THREE.Bone | null => {
      let f: THREE.Bone | null = null;
      root.traverse((c) => {
        if (f) return;
        if ((c as THREE.Bone).isBone && c.name === name) f = c as THREE.Bone;
      });
      return f;
    };

    // Need playback enabled so mixer.setTime actually writes bones.
    // Snapshot pause state so we can restore it after sampling.
    const wasPlaying = isPlaying;
    if (s.currentAction) s.currentAction.paused = false;
    if (s.currentPsoAction) s.currentPsoAction.paused = false;

    const N = 10;
    const dur = psoClip.duration;
    const samples: Array<{ time: number; totalError: number; perBone: Record<string, number> }> = [];

    for (let i = 0; i < N; i++) {
      const t = (i / Math.max(1, N - 1)) * dur;
      s.pszMixer.setTime(t);
      s.psoMixer.setTime(t);
      s.pszModel.updateMatrixWorld(true);
      s.psoModel.updateMatrixWorld(true);

      const perBone: Record<string, number> = {};
      let totalError = 0;
      let counted = 0;
      for (const [psoBoneName, vrmBoneName] of Object.entries(BONE_MAPPINGS_VRM)) {
        const vrmBone = findBone(s.pszModel, vrmBoneName);
        const psoBone = findBone(s.psoModel, psoBoneName);
        if (!vrmBone || !psoBone) continue;
        const vp = new THREE.Vector3();
        const pp = new THREE.Vector3();
        vrmBone.getWorldPosition(vp);
        psoBone.getWorldPosition(pp);
        const d = vp.distanceTo(pp);
        perBone[vrmBoneName] = Math.round(d * 10000) / 10000;
        totalError += d;
        counted++;
      }
      samples.push({
        time: Math.round(t * 1000) / 1000,
        totalError: Math.round(totalError * 10000) / 10000,
        perBone,
      });
      if (counted === 0) break;
    }

    // Restore pause state
    if (s.currentAction) s.currentAction.paused = !wasPlaying;
    if (s.currentPsoAction) s.currentPsoAction.paused = !wasPlaying;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (window as any).__frameErrors = { animation: selectedAnim, samples };
    // Summary table: per-bone average error across all sampled frames
    const avgByBone: Record<string, number> = {};
    for (const s2 of samples) {
      for (const [b, d] of Object.entries(s2.perBone)) {
        avgByBone[b] = (avgByBone[b] || 0) + d;
      }
    }
    for (const b in avgByBone) avgByBone[b] = Math.round((avgByBone[b] / samples.length) * 10000) / 10000;
    const tableRows = Object.entries(avgByBone)
      .map(([bone, avg]) => ({ bone, avgDistance: avg }))
      .sort((a, b) => b.avgDistance - a.avgDistance);
    // eslint-disable-next-line no-console
    console.log('[frame-errors]', selectedAnim, 'avg-by-bone (m):');
    // eslint-disable-next-line no-console
    console.table(tableRows);
    // eslint-disable-next-line no-console
    console.log('[frame-errors] per-frame totals (m):', samples.map((sp) => sp.totalError));
  }, [selectedAnim, isPlaying]);

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0a1a', color: '#ccc' }}>
      {/* Left panel: bone offset sliders */}
      <div style={{
        width: '300px', flexShrink: 0, display: 'flex', flexDirection: 'column',
        background: '#12122a', borderRight: '1px solid #2a2a4a', overflow: 'hidden',
      }}>
        <div style={{
          padding: '8px 12px', borderBottom: '1px solid #2a2a4a',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <span style={{ fontSize: '13px', fontWeight: 600 }}>Bone Offsets</span>
          <div style={{ display: 'flex', gap: '4px' }}>
            <button
              onClick={autoCalibrate}
              disabled={!loaded}
              title="Direction-match VRM bones to PSO rest pose"
              style={{
                padding: '2px 8px', fontSize: '10px',
                background: loaded ? '#2a3a5a' : '#1a1a2e',
                border: '1px solid #4488ff', borderRadius: '3px',
                color: loaded ? '#88c0ff' : '#555',
                cursor: loaded ? 'pointer' : 'default',
              }}
            >
              Auto Calibrate
            </button>
            <button
              onClick={runOptimizer}
              disabled={!loaded || optimizing}
              title="Brute-force grid-search optimizer over offset space, multi-animation objective"
              style={{
                padding: '2px 8px', fontSize: '10px',
                background: optimizing ? '#5a4a2a' : loaded ? '#3a4a2a' : '#1a1a2e',
                border: '1px solid #ffcc44', borderRadius: '3px',
                color: optimizing ? '#ffaa44' : loaded ? '#ffff88' : '#555',
                cursor: (loaded && !optimizing) ? 'pointer' : 'default',
              }}
            >
              {optimizing ? '…' : 'Optimize'}
            </button>
            <button
              onClick={logFrameErrors}
              disabled={!loaded || !selectedAnim}
              title="Sample 10 frames of the selected animation and log per-bone position error to console"
              style={{
                padding: '2px 8px', fontSize: '10px',
                background: (loaded && selectedAnim) ? '#3a3a2a' : '#1a1a2e',
                border: '1px solid #aa8844', borderRadius: '3px',
                color: (loaded && selectedAnim) ? '#ffcc88' : '#555',
                cursor: (loaded && selectedAnim) ? 'pointer' : 'default',
              }}
            >
              Log Errors
            </button>
            <button
              onClick={snapToPso}
              disabled={!loaded}
              title="Diagnostic: move VRM bone positions onto PSO bone positions (mesh deforms). Use Restore to revert."
              style={{
                padding: '2px 8px', fontSize: '10px',
                background: loaded ? '#3a2a3a' : '#1a1a2e',
                border: '1px solid #aa44aa', borderRadius: '3px',
                color: loaded ? '#ff88ff' : '#555',
                cursor: loaded ? 'pointer' : 'default',
              }}
            >
              Snap
            </button>
            <button
              onClick={restorePositions}
              disabled={!loaded}
              title="Restore VRM bone positions to their original rest"
              style={{
                padding: '2px 8px', fontSize: '10px',
                background: loaded ? '#2a2a2a' : '#1a1a2e',
                border: '1px solid #666', borderRadius: '3px',
                color: loaded ? '#aaa' : '#555',
                cursor: loaded ? 'pointer' : 'default',
              }}
            >
              Restore
            </button>
            {hasAnyOffset && (
              <button
                onClick={exportOffsets}
                style={{
                  padding: '2px 8px', fontSize: '10px', background: '#2d5a2d',
                  border: '1px solid #4a4', borderRadius: '3px', color: '#6f6', cursor: 'pointer',
                }}
              >
                Copy
              </button>
            )}
            <button
              onClick={resetAll}
              disabled={!hasAnyOffset}
              style={{
                padding: '2px 8px', fontSize: '10px', background: hasAnyOffset ? '#4a2a2a' : '#1a1a2e',
                border: '1px solid #444', borderRadius: '3px',
                color: hasAnyOffset ? '#f88' : '#555', cursor: hasAnyOffset ? 'pointer' : 'default',
              }}
            >
              Reset All
            </button>
          </div>
        </div>

        {optimizeStatus && (
          <div style={{
            padding: '4px 10px', fontSize: '10px', color: '#ffcc88',
            background: '#2a2a3a', borderBottom: '1px solid #2a2a4a',
            fontFamily: 'monospace', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>
            {optimizeStatus}
          </div>
        )}

        <div style={{ flex: 1, overflowY: 'auto', padding: '4px 0' }}>
          {TUNABLE_BONES.map(({ pszBone, label }) => {
            const o = offsets[pszBone];
            const hasOffset = o.x !== 0 || o.y !== 0 || o.z !== 0;
            return (
              <div key={pszBone} style={{
                padding: '4px 10px', borderBottom: '1px solid #1a1a2e',
              }}>
                <div style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  marginBottom: '2px',
                }}>
                  <span style={{
                    fontSize: '11px', fontWeight: 600,
                    color: hasOffset ? '#8cf' : '#999',
                  }}>
                    {label}
                  </span>
                  {hasOffset && (
                    <button
                      onClick={() => resetBone(pszBone)}
                      style={{
                        padding: '1px 6px', fontSize: '9px', background: 'transparent',
                        border: '1px solid #444', borderRadius: '2px', color: '#888', cursor: 'pointer',
                      }}
                    >
                      reset
                    </button>
                  )}
                </div>
                {(['x', 'y', 'z'] as const).map((axis) => (
                  <div key={axis} style={{
                    display: 'flex', alignItems: 'center', gap: '4px', height: '18px',
                  }}>
                    <span style={{
                      fontSize: '10px', width: '10px', textAlign: 'center', fontWeight: 600,
                      color: axis === 'x' ? '#f66' : axis === 'y' ? '#6f6' : '#66f',
                    }}>
                      {axis.toUpperCase()}
                    </span>
                    <input
                      type="range"
                      min={-180} max={180} step={1}
                      value={o[axis]}
                      onChange={(e) => updateOffset(pszBone, axis, parseFloat(e.target.value))}
                      style={{ flex: 1, height: '12px' }}
                    />
                    <span style={{
                      fontSize: '10px', color: '#888', width: '32px', textAlign: 'right',
                      fontFamily: 'monospace',
                    }}>
                      {o[axis]}°
                    </span>
                  </div>
                ))}
              </div>
            );
          })}
        </div>
      </div>

      {/* Center: 3D viewport */}
      <div style={{ flex: 1, position: 'relative' }}>
        <div ref={containerRef} style={{ width: '100%', height: '100%' }} />
        {!loaded && (
          <div style={{
            position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
            color: '#888', fontSize: '14px',
          }}>
            Loading models...
          </div>
        )}
      </div>

      {/* Right panel: animation picker */}
      <div style={{
        width: '260px', flexShrink: 0, display: 'flex', flexDirection: 'column',
        background: '#12122a', borderLeft: '1px solid #2a2a4a', overflow: 'hidden',
      }}>
        <div style={{ padding: '8px 10px', borderBottom: '1px solid #2a2a4a' }}>
          <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '6px' }}>Animations</div>
          <input
            type="text"
            placeholder="Filter (walk, run, atk...)"
            value={animSearch}
            onChange={(e) => setAnimSearch(e.target.value)}
            style={{
              width: '100%', padding: '4px 8px', fontSize: '11px', fontFamily: 'monospace',
              background: '#1a1a2e', border: '1px solid #444', borderRadius: '4px',
              color: '#ccc', outline: 'none', boxSizing: 'border-box', marginBottom: '6px',
            }}
          />
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '4px' }}>
            <button
              onClick={() => setIsPlaying(!isPlaying)}
              style={{
                padding: '3px 10px', fontSize: '11px',
                background: isPlaying ? '#2d5a2d' : '#5a2d2d',
                border: `1px solid ${isPlaying ? '#4a4' : '#a44'}`,
                borderRadius: '4px', color: isPlaying ? '#6f6' : '#f66', cursor: 'pointer',
              }}
            >
              {isPlaying ? 'Pause' : 'Play'}
            </button>
            <label style={{ fontSize: '10px', color: '#888', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <input type="checkbox" checked={showSkeleton} onChange={(e) => setShowSkeleton(e.target.checked)} />
              Skeleton
            </label>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <label style={{ fontSize: '10px', color: '#888', whiteSpace: 'nowrap' }}>
              Speed: {playbackSpeed.toFixed(1)}x
            </label>
            <input
              type="range" min="0.1" max="2" step="0.1"
              value={playbackSpeed}
              onChange={(e) => setPlaybackSpeed(parseFloat(e.target.value))}
              style={{ flex: 1 }}
            />
          </div>
        </div>

        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '1px', padding: '4px' }}>
          {/* "None" pops back to static preview so offset sliders affect
              the VRM at rest instead of fighting a moving animation. */}
          <button
            onClick={() => { setSelectedAnim(null); }}
            style={{
              padding: '3px 6px', display: 'flex', alignItems: 'center', gap: '4px',
              background: selectedAnim === null ? '#4a4a6a' : 'transparent',
              border: selectedAnim === null ? '1px solid #6b8afd' : '1px solid #2a2a4a',
              borderRadius: '3px',
              color: selectedAnim === null ? '#fff' : '#aaa',
              cursor: 'pointer', fontSize: '10px', textAlign: 'left', fontFamily: 'monospace',
              marginBottom: '4px',
            }}
          >
            <span style={{
              fontSize: '9px', color: '#666', background: '#1a1a2e',
              padding: '1px 4px', borderRadius: '2px', minWidth: '24px', textAlign: 'center',
            }}>—</span>
            <span style={{ flex: 1 }}>None (static rest pose)</span>
          </button>
          {filteredAnims.map((name) => {
            const idx = name.replace('plymotiondata_', '');
            const mappedName = animNameMap[idx];
            return (
              <button
                key={name}
                onClick={() => { setSelectedAnim(name); setIsPlaying(true); }}
                style={{
                  padding: '3px 6px', display: 'flex', alignItems: 'center', gap: '4px',
                  background: selectedAnim === name ? '#4a4a6a' : 'transparent',
                  border: selectedAnim === name ? '1px solid #6b8afd' : '1px solid transparent',
                  borderRadius: '3px',
                  color: selectedAnim === name ? '#fff' : mappedName ? '#8c8' : '#aaa',
                  cursor: 'pointer', fontSize: '10px', textAlign: 'left', fontFamily: 'monospace',
                }}
              >
                <span style={{
                  fontSize: '9px', color: '#666', background: mappedName ? '#1a3a1a' : '#1a1a2e',
                  padding: '1px 4px', borderRadius: '2px', minWidth: '24px', textAlign: 'center',
                }}>
                  {idx}
                </span>
                <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {mappedName || name}
                </span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
