import { useEffect, useMemo, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';
import {
  captureRestPose,
  getWorldRestQuat,
  resetToBindPose,
  BONE_MAPPINGS_VRM,
  type RestPoseData,
} from './retarget-utils';
import { measureChain, solveTwoBoneIK, type ChainRest } from './ik-utils';

// PSO → VRM retarget prototype using IK on the limbs instead of pure
// rotation copy. The hypothesis (from the in-game playtest of the rotation-
// copy bake): when PSO's arms-down rest disagrees with VRM's T-pose, the
// F-correction step needs a 180° shoulder flip to align, and tiny residual
// errors there are what produces the "almost right" jank. IK sidesteps it
// by aiming the VRM hand at the PSO hand's world position, letting the
// VRM's own rest pose stand untouched.
//
// Spine + head are still rotation-copied (rest poses already agree).
// Root position is copied. Compare side-by-side with the rotation-copy
// bake from /retarget-tuner-vrm or /vrma-to-psz to judge.

const PSO_MODEL_PATH = assetUrl('/data/retarget/Humar_body.glb');
const VRM_MODEL_PATH = assetUrl('assets/npcs/item_shop/item_shop.glb');
const ANIMATION_MAP_PATH = assetUrl('/data/retarget/pso_animation_map.json');

// Spine + head bones to copy via rotation retargeting (PSO source → VRM
// target). Same set as buildRetargetedClip uses for non-limb bones.
const ROTATION_COPY_BONES: Array<[string, string]> = [
  ['bone_002', 'J_Bip_C_Hips'],
  ['bone_024', 'J_Bip_C_Chest'],
  ['bone_025', 'J_Bip_C_UpperChest'],
  ['bone_056', 'J_Bip_C_Head'],
];

// Limb chains: PSO 3-bone chain (origin/middle/end) + VRM 3-bone chain.
// The IK target is computed as the PSO end-effector's position *relative
// to the PSO chain origin*, scaled by (VRM chain length / PSO chain
// length), then added to the VRM chain origin in world space. That way
// the gesture (which direction the hand reaches, how far) ports across
// rigs that disagree about absolute scale — PSO Humar is roughly 10×
// larger than VRM in three.js units, so using PSO world positions as
// targets directly leaves VRM permanently stretched to max reach.
interface LimbChainSpec {
  label: string;
  psoUpper: string;             // PSO chain origin (shoulder / hip)
  psoLower: string;
  psoEnd: string;               // PSO end effector (hand / foot)
  vrmUpper: string;
  vrmLower: string;
  vrmEnd: string;
  // Pole hint in world space, relative to upper-bone (shoulder/hip)
  // origin. Down-and-forward for arms (elbow points that way), forward
  // for legs (knees lead).
  poleOffset: THREE.Vector3;
}

const LIMB_CHAINS: LimbChainSpec[] = [
  {
    label: 'L arm',
    psoUpper: 'bone_028', psoLower: 'bone_029', psoEnd: 'bone_030',
    vrmUpper: 'J_Bip_L_UpperArm', vrmLower: 'J_Bip_L_LowerArm', vrmEnd: 'J_Bip_L_Hand',
    poleOffset: new THREE.Vector3(0, -1, -0.6),
  },
  {
    label: 'R arm',
    psoUpper: 'bone_041', psoLower: 'bone_042', psoEnd: 'bone_043',
    vrmUpper: 'J_Bip_R_UpperArm', vrmLower: 'J_Bip_R_LowerArm', vrmEnd: 'J_Bip_R_Hand',
    poleOffset: new THREE.Vector3(0, -1, -0.6),
  },
  {
    label: 'L leg',
    psoUpper: 'bone_004', psoLower: 'bone_005', psoEnd: 'bone_006',
    vrmUpper: 'J_Bip_L_UpperLeg', vrmLower: 'J_Bip_L_LowerLeg', vrmEnd: 'J_Bip_L_Foot',
    // Knees lead forward when walking/squatting. VRoid VRMs face +Z in
    // three.js's default coordinate frame, so pole is forward (+Z).
    poleOffset: new THREE.Vector3(0, 0, 1),
  },
  {
    label: 'R leg',
    psoUpper: 'bone_013', psoLower: 'bone_014', psoEnd: 'bone_015',
    vrmUpper: 'J_Bip_R_UpperLeg', vrmLower: 'J_Bip_R_LowerLeg', vrmEnd: 'J_Bip_R_Foot',
    poleOffset: new THREE.Vector3(0, 0, 1),
  },
];

function findBone(root: THREE.Object3D, name: string): THREE.Bone | null {
  let found: THREE.Bone | null = null;
  root.traverse((obj) => {
    if (!found && (obj as THREE.Bone).isBone && obj.name === name) {
      found = obj as THREE.Bone;
    }
  });
  return found;
}

interface ResolvedChain {
  spec: LimbChainSpec;
  vrmUpper: THREE.Bone;
  vrmLower: THREE.Bone;
  psoUpper: THREE.Bone;          // chain origin on the source rig
  psoEnd: THREE.Bone;            // end effector whose offset drives the IK target
  rest: ChainRest;
  // Per-chain length ratio. PSO Humar is in ~cm-ish units, VRM in
  // meters — without this ratio the offset (PSO_end - PSO_origin)
  // overshoots VRM's reach by ~10× and the chain stays locked-out.
  scale: number;
}

interface ResolvedRotationCopy {
  psoBone: string;
  vrmBone: THREE.Bone;
  // Precomputed prefix/suffix matrices for the F-correction rotation copy.
  // Identical to the math in retarget-utils.buildRetargetedClip, but inlined
  // here so we can drive it from a live AnimationMixer instead of baking.
  prefix: THREE.Quaternion;
  suffix: THREE.Quaternion;
  psoLocalRestInv: THREE.Quaternion;
}

// Parse PSO animation map: { mappings: { "016": "pso_ri_stand", ... } }.
// The GLB clip names look like "plymotiondata_016" — we extract the index
// and look up the friendly name.
function buildClipLabel(
  clipName: string,
  map: Record<string, string>,
): { label: string; sortKey: number } {
  const m = clipName.match(/(\d+)/);
  const idx = m ? m[1].padStart(3, '0') : null;
  const friendly = idx ? map[idx] : undefined;
  if (idx && friendly) return { label: `${friendly}  (${idx})`, sortKey: Number(idx) };
  if (idx) return { label: `plymotiondata_${idx}`, sortKey: Number(idx) };
  return { label: clipName, sortKey: 9999 };
}

// Curated default set — first 5+ that cover idle / locomotion / attack /
// damage. The dropdown shows all clips but this drives the initial pick
// and the "quick picks" buttons. Indices map onto plymotiondata_NNN.
const QUICK_PICKS: string[] = ['016', '015', '022', '012', '017', '038'];

export default function PsoIkVrmViewer() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [clipNames, setClipNames] = useState<string[]>([]);
  const [clipLabels, setClipLabels] = useState<Record<string, string>>({});
  const [selectedClip, setSelectedClip] = useState<string>('');
  const [status, setStatus] = useState<string>('Loading…');
  const [showPsoSkel, setShowPsoSkel] = useState(true);

  const stateRef = useRef<{
    psoModel: THREE.Object3D | null;
    vrmModel: THREE.Object3D | null;
    psoMixer: THREE.AnimationMixer | null;
    psoRest: RestPoseData | null;
    vrmRest: RestPoseData | null;
    chains: ResolvedChain[];
    rotCopies: ResolvedRotationCopy[];
    clips: THREE.AnimationClip[];
    action: THREE.AnimationAction | null;
    psoHelper: THREE.SkeletonHelper | null;
    /** Root bones + rest positions on both rigs. The PSO clip drives
     *  bone_000.position (knockback hops in damage anims, locomotion
     *  in walk/run); we mirror the world-space delta onto the VRM root
     *  scaled by the PSO→VRM display ratio so both rigs move together. */
    psoRootBone: THREE.Bone | null;
    psoRootRest: THREE.Vector3;
    vrmRootBone: THREE.Bone | null;
    vrmRootRest: THREE.Vector3;
    /** Scale we applied to psoModel to match VRM height. Position deltas
     *  read from PSO bones are in raw GLB units and need this factor to
     *  end up in VRM-world units when copied across. */
    psoDisplayScale: number;
  }>({
    psoModel: null, vrmModel: null, psoMixer: null, psoRest: null, vrmRest: null,
    chains: [], rotCopies: [], clips: [], action: null, psoHelper: null,
    psoRootBone: null, psoRootRest: new THREE.Vector3(),
    vrmRootBone: null, vrmRootRest: new THREE.Vector3(),
    psoDisplayScale: 1,
  });

  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2e);
    const camera = new THREE.PerspectiveCamera(45, canvas.clientWidth / canvas.clientHeight, 0.1, 100);
    camera.position.set(0, 1.4, 3.5);
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(canvas.clientWidth, canvas.clientHeight, false);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const controls = new OrbitControls(camera, canvas);
    controls.target.set(0, 1.0, 0);
    controls.update();
    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(3, 4, 5);
    scene.add(key);
    scene.add(new THREE.GridHelper(4, 8, 0x4a4a6a, 0x2a2a4a));

    let disposed = false;
    let raf = 0;

    (async () => {
      try {
        setStatus('Loading PSO + VRM…');
        const loader = new GLTFLoader();
        const [psoGltf, vrmGltf, animMapRes] = await Promise.all([
          loader.loadAsync(PSO_MODEL_PATH),
          loader.loadAsync(VRM_MODEL_PATH),
          fetch(ANIMATION_MAP_PATH).then((r) => r.json()),
        ]);
        if (disposed) return;

        const psoModel = psoGltf.scene;
        const vrmModel = vrmGltf.scene;

        // Hide PSO mesh — we only need its skeleton for the source pose,
        // and showing it would obstruct the VRM. Keep the bones updating
        // by leaving the model in the scene graph.
        psoModel.traverse((c) => {
          if ((c as THREE.SkinnedMesh).isSkinnedMesh) {
            (c as THREE.SkinnedMesh).visible = false;
          }
        });
        scene.add(psoModel);
        scene.add(vrmModel);

        // PSO Humar's GLB lives in units roughly 10× the VRM's, which
        // makes the skeleton-helper visualization span the whole viewport
        // and crowds out the VRM character. The IK math is already
        // unit-agnostic (driven by chain-relative offsets * scale), so
        // we can shrink the PSO model purely for display without
        // affecting retargeting. Match VRM bbox height; both rigs face
        // the same direction by GLB convention.
        const vrmBox = new THREE.Box3().setFromObject(vrmModel);
        const psoBox = new THREE.Box3().setFromObject(psoModel);
        const vrmHeight = vrmBox.max.y - vrmBox.min.y;
        const psoHeight = psoBox.max.y - psoBox.min.y;
        let psoDisplayScale = 1;
        if (psoHeight > 1e-6 && vrmHeight > 1e-6) {
          psoDisplayScale = vrmHeight / psoHeight;
          psoModel.scale.multiplyScalar(psoDisplayScale);
        }
        psoModel.updateMatrixWorld(true);

        // Rest pose captures (PSO and VRM) — captureRestPose snapshots
        // local + world quaternions per bone before any animation runs.
        resetToBindPose(psoModel);
        psoModel.updateMatrixWorld(true);
        const psoRest = captureRestPose(psoModel);

        resetToBindPose(vrmModel);
        vrmModel.updateMatrixWorld(true);
        const vrmRest = captureRestPose(vrmModel);

        // Resolve limb chains: find named bones, measure rest lengths
        // on both rigs, and compute the per-chain scale ratio so PSO
        // joint offsets retarget into VRM proportions.
        const chains: ResolvedChain[] = [];
        for (const spec of LIMB_CHAINS) {
          const vrmUpper = findBone(vrmModel, spec.vrmUpper);
          const vrmLower = findBone(vrmModel, spec.vrmLower);
          const vrmEnd = findBone(vrmModel, spec.vrmEnd);
          const psoUpper = findBone(psoModel, spec.psoUpper);
          const psoLower = findBone(psoModel, spec.psoLower);
          const psoEnd = findBone(psoModel, spec.psoEnd);
          if (!vrmUpper || !vrmLower || !vrmEnd || !psoUpper || !psoLower || !psoEnd) {
            console.warn(`[PsoIkVrm] Missing bone in chain ${spec.label}`);
            continue;
          }
          const rest = measureChain(vrmUpper, vrmLower, vrmEnd);
          // PSO chain rest length in world units (after any model scale
          // applied to the PSO model — currently identity, so this is
          // raw GLB units).
          const psoUpperW = new THREE.Vector3();
          const psoLowerW = new THREE.Vector3();
          const psoEndW = new THREE.Vector3();
          psoUpper.getWorldPosition(psoUpperW);
          psoLower.getWorldPosition(psoLowerW);
          psoEnd.getWorldPosition(psoEndW);
          const psoTotal = psoUpperW.distanceTo(psoLowerW) + psoLowerW.distanceTo(psoEndW);
          const vrmTotal = rest.upperLength + rest.lowerLength;
          const scale = psoTotal > 1e-6 ? vrmTotal / psoTotal : 1.0;
          console.log(`[PsoIkVrm] ${spec.label}: pso=${psoTotal.toFixed(3)} vrm=${vrmTotal.toFixed(3)} scale=${scale.toFixed(4)}`);
          chains.push({ spec, vrmUpper, vrmLower, psoUpper, psoEnd, rest, scale });
        }

        // Resolve rotation-copy bones (spine/head) — precompute the
        // prefix/suffix quaternions so the per-frame work is small.
        const rotCopies: ResolvedRotationCopy[] = [];
        for (const [psoBone, vrmBoneName] of ROTATION_COPY_BONES) {
          const vrmBone = findBone(vrmModel, vrmBoneName);
          if (!vrmBone) {
            console.warn(`[PsoIkVrm] Missing VRM bone: ${vrmBoneName}`);
            continue;
          }
          const psoLocalRest = psoRest.localQuats[psoBone] || new THREE.Quaternion();
          const vrmLocalRest = vrmRest.localQuats[vrmBoneName] || new THREE.Quaternion();
          const psoWorldRest = getWorldRestQuat(psoBone, psoRest);
          const vrmWorldRest = getWorldRestQuat(vrmBoneName, vrmRest);
          const F = vrmWorldRest.clone().invert().multiply(psoWorldRest);
          const psoLocalRestInv = psoLocalRest.clone().invert();
          const prefix = vrmLocalRest.clone().multiply(F).multiply(psoLocalRestInv.clone());
          const suffix = F.clone().invert();
          rotCopies.push({ psoBone, vrmBone, prefix, suffix, psoLocalRestInv });
        }

        // Mixer drives the PSO source skeleton — VRM bones are written
        // each frame in the render loop after PSO has posed itself.
        const psoMixer = new THREE.AnimationMixer(psoModel);

        // Clip name lookup
        const map = (animMapRes as { mappings: Record<string, string> }).mappings;
        const labels: Record<string, string> = {};
        const sortable = psoGltf.animations.map((c) => {
          const { label, sortKey } = buildClipLabel(c.name, map);
          labels[c.name] = label;
          return { name: c.name, sortKey };
        });
        sortable.sort((a, b) => a.sortKey - b.sortKey);
        const names = sortable.map((s) => s.name);

        // Optional: a thin skeleton helper for the PSO source so the
        // user can see exactly what the IK is targeting.
        const helper = new THREE.SkeletonHelper(psoModel);
        (helper.material as THREE.LineBasicMaterial).color.set(0x00ffff);
        (helper.material as THREE.LineBasicMaterial).linewidth = 2;
        helper.renderOrder = 999;
        scene.add(helper);

        const psoRootBone = findBone(psoModel, 'bone_000');
        const psoRootRest = psoRootBone ? psoRootBone.position.clone() : new THREE.Vector3();
        // VRoid VRMs put a "Root" node above the J_Bip_* chain. We move
        // that to translate the whole character; if it's missing, the
        // model itself stays at origin and only PSO will translate.
        const vrmRootBone = findBone(vrmModel, 'Root');
        const vrmRootRest = vrmRootBone ? vrmRootBone.position.clone() : new THREE.Vector3();
        if (!vrmRootBone) console.warn('[PsoIkVrm] No "Root" bone on VRM — root translation will be skipped.');

        stateRef.current = {
          psoModel, vrmModel, psoMixer, psoRest, vrmRest,
          chains, rotCopies, clips: psoGltf.animations, action: null, psoHelper: helper,
          psoRootBone, psoRootRest,
          vrmRootBone, vrmRootRest,
          psoDisplayScale,
        };

        setClipNames(names);
        setClipLabels(labels);
        // Default to first quick-pick that exists, else first clip
        const defaultName = names.find((n) => {
          const m = n.match(/(\d+)/);
          return m && QUICK_PICKS.includes(m[1].padStart(3, '0'));
        }) ?? names[0];
        setSelectedClip(defaultName);
        setStatus(`Loaded ${names.length} clips • ${chains.length} chains • ${rotCopies.length} copy bones`);
      } catch (err) {
        console.error(err);
        setStatus(`Error: ${(err as Error).message}`);
      }
    })();

    const clock = new THREE.Clock();
    const tick = () => {
      const dt = clock.getDelta();
      const s = stateRef.current;
      if (s.psoMixer && s.vrmModel && s.psoRest && s.vrmRest) {
        s.psoMixer.update(dt);
        // Mirror the PSO root's position delta onto the VRM root so
        // knockback hops (Y in damage clips) and translation (Z in
        // walk/run) come along. PSO bone-local position is in raw GLB
        // units; multiply by the display scale we applied to psoModel
        // so the delta lands in VRM-world units.
        if (s.psoRootBone && s.vrmRootBone) {
          const dx = (s.psoRootBone.position.x - s.psoRootRest.x) * s.psoDisplayScale;
          const dy = (s.psoRootBone.position.y - s.psoRootRest.y) * s.psoDisplayScale;
          const dz = (s.psoRootBone.position.z - s.psoRootRest.z) * s.psoDisplayScale;
          s.vrmRootBone.position.set(
            s.vrmRootRest.x + dx,
            s.vrmRootRest.y + dy,
            s.vrmRootRest.z + dz,
          );
        }
        // PSO has been posed by the mixer; matrices auto-update via mixer.
        s.psoModel?.updateMatrixWorld(true);

        // Rotation-copy bones (spine/head). Read PSO local quat, apply
        // prefix * pso * suffix → write VRM local quat.
        for (const rc of s.rotCopies) {
          const psoBoneObj = findBoneCached(s.psoModel!, rc.psoBone);
          if (!psoBoneObj) continue;
          const psoLocal = psoBoneObj.quaternion;
          rc.vrmBone.quaternion
            .copy(rc.prefix)
            .multiply(psoLocal)
            .multiply(rc.suffix);
        }
        s.vrmModel.updateMatrixWorld(true);

        // Limb IK. The PSO source is much larger than the VRM (different
        // GLB unit conventions), so we can't use PSO end-effector world
        // positions directly. Instead, take the *offset* from the PSO
        // chain origin (shoulder/hip) to the PSO end (hand/foot), scale
        // it by the VRM/PSO length ratio, and add to the VRM chain
        // origin. That preserves the gesture (direction + relative
        // reach) without inheriting PSO's absolute scale.
        const psoOriginW = new THREE.Vector3();
        const psoEndW = new THREE.Vector3();
        const vrmShoulderW = new THREE.Vector3();
        for (const chain of s.chains) {
          chain.psoUpper.getWorldPosition(psoOriginW);
          chain.psoEnd.getWorldPosition(psoEndW);
          chain.vrmUpper.getWorldPosition(vrmShoulderW);
          const targetWorld = new THREE.Vector3()
            .subVectors(psoEndW, psoOriginW)
            .multiplyScalar(chain.scale)
            .add(vrmShoulderW);
          const poleWorld = vrmShoulderW.clone().add(chain.spec.poleOffset);
          solveTwoBoneIK(chain.vrmUpper, chain.vrmLower, targetWorld, poleWorld, chain.rest);
        }
      }
      if (stateRef.current.psoHelper) {
        stateRef.current.psoHelper.visible = showPsoSkel;
      }
      controls.update();
      renderer.render(scene, camera);
      raf = requestAnimationFrame(tick);
    };
    tick();

    const handleResize = () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', handleResize);

    return () => {
      disposed = true;
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', handleResize);
      controls.dispose();
      renderer.dispose();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Swap clip when dropdown changes
  useEffect(() => {
    const s = stateRef.current;
    if (!s.psoMixer || !selectedClip) return;
    if (s.action) s.action.stop();
    const clip = s.clips.find((c) => c.name === selectedClip);
    if (!clip) return;
    const next = s.psoMixer.clipAction(clip);
    next.reset();
    next.setLoop(THREE.LoopRepeat, Infinity);
    next.play();
    s.action = next;
  }, [selectedClip]);

  const clipDescription = useMemo(() => {
    const s = stateRef.current;
    const c = s.clips.find((x) => x.name === selectedClip);
    if (!c) return '';
    return `${c.duration.toFixed(2)}s • ${c.tracks.length} tracks`;
  }, [selectedClip, clipNames]);

  const quickPickButtons = useMemo(() => {
    return clipNames
      .filter((n) => {
        const m = n.match(/(\d+)/);
        return m && QUICK_PICKS.includes(m[1].padStart(3, '0'));
      })
      .slice(0, 8);
  }, [clipNames]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '8px 16px', background: '#12122a',
        borderBottom: '1px solid #2a2a4a', fontSize: 13, color: '#ccc',
        flexWrap: 'wrap',
      }}>
        <strong style={{ color: '#fff' }}>PSO → VRM (IK)</strong>
        <select
          value={selectedClip}
          onChange={(e) => setSelectedClip(e.target.value)}
          style={{
            background: '#222244', color: '#fff',
            border: '1px solid #444466', padding: '4px 8px', fontSize: 13,
            minWidth: 220,
          }}
        >
          {clipNames.map((n) => (
            <option key={n} value={n}>{clipLabels[n] ?? n}</option>
          ))}
        </select>
        <span style={{ color: '#88aaff' }}>{clipDescription}</span>
        <label style={{ marginLeft: 12, display: 'flex', alignItems: 'center', gap: 4, color: '#88f' }}>
          <input
            type="checkbox"
            checked={showPsoSkel}
            onChange={(e) => setShowPsoSkel(e.target.checked)}
          />
          show PSO skeleton (cyan)
        </label>
        <span style={{ marginLeft: 'auto', color: '#888' }}>{status}</span>
      </div>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        padding: '4px 16px', background: '#0f0f24',
        borderBottom: '1px solid #2a2a4a', fontSize: 12, color: '#aaa',
        flexWrap: 'wrap',
      }}>
        <span style={{ color: '#666' }}>quick picks:</span>
        {quickPickButtons.map((n) => (
          <button
            key={n}
            onClick={() => setSelectedClip(n)}
            style={{
              background: selectedClip === n ? '#3a3a6a' : '#1a1a3a',
              color: '#ccc', border: '1px solid #333355',
              padding: '2px 8px', fontSize: 12, cursor: 'pointer',
            }}
          >
            {clipLabels[n] ?? n}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        <canvas ref={canvasRef} style={{ display: 'block', width: '100%', height: '100%' }} />
      </div>
    </div>
  );
}

// Tiny per-render bone cache. The PSO skeleton is the same instance every
// frame, so reusing the lookup table avoids the O(n) traversal in findBone.
const _boneCache = new WeakMap<THREE.Object3D, Map<string, THREE.Bone>>();
function findBoneCached(root: THREE.Object3D, name: string): THREE.Bone | null {
  let map = _boneCache.get(root);
  if (!map) {
    map = new Map();
    root.traverse((obj) => {
      if ((obj as THREE.Bone).isBone) {
        map!.set(obj.name, obj as THREE.Bone);
      }
    });
    _boneCache.set(root, map);
  }
  return map.get(name) ?? null;
}

// Silence "unused" lint for now — BONE_MAPPINGS_VRM is re-exported via
// the same module the IK viewer imports from, but we don't reference it
// here directly. Touching it keeps tree-shaking honest.
void BONE_MAPPINGS_VRM;
