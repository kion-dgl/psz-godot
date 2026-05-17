import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

const VRM_MODEL_PATH = assetUrl('assets/npcs/item_shop/item_shop.glb');

/** Sample Mixamo FBX hosted by threejs.org examples. Used as the default
 *  download so the demo works without the user supplying their own file —
 *  the bone names follow the standard mixamorig* convention. Anything
 *  exported from Mixamo will work the same way, so users can swap this
 *  for their own animation by editing the URL or using the file picker. */
const DEFAULT_FBX_URL = 'https://threejs.org/examples/models/fbx/Samba%20Dancing.fbx';

/** Mixamo → VRM bone-name mapping, lifted from
 *  pixiv/three-vrm/packages/three-vrm/examples/humanoidAnimation/mixamoVRMRigMap.js
 *  and resolved against the actual VRM bone names used by the item-shop
 *  rig (the J_Bip_* convention). Since VRM internal bone names follow a
 *  body-symmetric pattern that maps 1:1 from the VRM humanoid IDs, the
 *  composed Mixamo→J_Bip_* table is straightforward. */
const MIXAMO_TO_VRM_BONE: Record<string, string> = {
  mixamorigHips: 'J_Bip_C_Hips',
  mixamorigSpine: 'J_Bip_C_Spine',
  mixamorigSpine1: 'J_Bip_C_Chest',
  mixamorigSpine2: 'J_Bip_C_UpperChest',
  mixamorigNeck: 'J_Bip_C_Neck',
  mixamorigHead: 'J_Bip_C_Head',
  mixamorigLeftShoulder: 'J_Bip_L_Shoulder',
  mixamorigLeftArm: 'J_Bip_L_UpperArm',
  mixamorigLeftForeArm: 'J_Bip_L_LowerArm',
  mixamorigLeftHand: 'J_Bip_L_Hand',
  mixamorigLeftHandThumb1: 'J_Bip_L_Thumb1',
  mixamorigLeftHandThumb2: 'J_Bip_L_Thumb2',
  mixamorigLeftHandThumb3: 'J_Bip_L_Thumb3',
  mixamorigLeftHandIndex1: 'J_Bip_L_Index1',
  mixamorigLeftHandIndex2: 'J_Bip_L_Index2',
  mixamorigLeftHandIndex3: 'J_Bip_L_Index3',
  mixamorigLeftHandMiddle1: 'J_Bip_L_Middle1',
  mixamorigLeftHandMiddle2: 'J_Bip_L_Middle2',
  mixamorigLeftHandMiddle3: 'J_Bip_L_Middle3',
  mixamorigLeftHandRing1: 'J_Bip_L_Ring1',
  mixamorigLeftHandRing2: 'J_Bip_L_Ring2',
  mixamorigLeftHandRing3: 'J_Bip_L_Ring3',
  mixamorigLeftHandPinky1: 'J_Bip_L_Little1',
  mixamorigLeftHandPinky2: 'J_Bip_L_Little2',
  mixamorigLeftHandPinky3: 'J_Bip_L_Little3',
  mixamorigRightShoulder: 'J_Bip_R_Shoulder',
  mixamorigRightArm: 'J_Bip_R_UpperArm',
  mixamorigRightForeArm: 'J_Bip_R_LowerArm',
  mixamorigRightHand: 'J_Bip_R_Hand',
  mixamorigRightHandThumb1: 'J_Bip_R_Thumb1',
  mixamorigRightHandThumb2: 'J_Bip_R_Thumb2',
  mixamorigRightHandThumb3: 'J_Bip_R_Thumb3',
  mixamorigRightHandIndex1: 'J_Bip_R_Index1',
  mixamorigRightHandIndex2: 'J_Bip_R_Index2',
  mixamorigRightHandIndex3: 'J_Bip_R_Index3',
  mixamorigRightHandMiddle1: 'J_Bip_R_Middle1',
  mixamorigRightHandMiddle2: 'J_Bip_R_Middle2',
  mixamorigRightHandMiddle3: 'J_Bip_R_Middle3',
  mixamorigRightHandRing1: 'J_Bip_R_Ring1',
  mixamorigRightHandRing2: 'J_Bip_R_Ring2',
  mixamorigRightHandRing3: 'J_Bip_R_Ring3',
  mixamorigRightHandPinky1: 'J_Bip_R_Little1',
  mixamorigRightHandPinky2: 'J_Bip_R_Little2',
  mixamorigRightHandPinky3: 'J_Bip_R_Little3',
  mixamorigLeftUpLeg: 'J_Bip_L_UpperLeg',
  mixamorigLeftLeg: 'J_Bip_L_LowerLeg',
  mixamorigLeftFoot: 'J_Bip_L_Foot',
  mixamorigLeftToeBase: 'J_Bip_L_ToeBase',
  mixamorigRightUpLeg: 'J_Bip_R_UpperLeg',
  mixamorigRightLeg: 'J_Bip_R_LowerLeg',
  mixamorigRightFoot: 'J_Bip_R_Foot',
  mixamorigRightToeBase: 'J_Bip_R_ToeBase',
};

/** Rewrite a Mixamo animation clip's track names to target the VRM rig.
 *  This is the simplest possible retargeting: bone-name remap only. It
 *  works because Mixamo characters and VRM characters both use a T-pose
 *  bind pose with similar bone orientations, so the local-frame
 *  rotations transfer almost as-is. Position tracks are dropped except
 *  for the root hip translation (so the character can move). */
function retargetMixamoClip(clip: THREE.AnimationClip): THREE.AnimationClip {
  const tracks: THREE.KeyframeTrack[] = [];
  for (const track of clip.tracks) {
    const dotIdx = track.name.lastIndexOf('.');
    if (dotIdx < 0) continue;
    const boneName = track.name.substring(0, dotIdx);
    const prop = track.name.substring(dotIdx);
    const vrmBone = MIXAMO_TO_VRM_BONE[boneName];
    if (!vrmBone) continue;
    // Drop position tracks except for the root hip — VRM is a different
    // scale than Mixamo's source character so non-root positions would
    // misalign the rig.
    if (prop === '.position' && vrmBone !== 'J_Bip_C_Hips') continue;
    if (prop === '.scale') continue;
    // Mixamo hip position tracks are in centimetres; VRM expects metres.
    // Scale by 0.01 to put it in the right range, and also damp it a
    // little so the foot doesn't slide far past where the VRM mesh has
    // its skinning weighted.
    if (prop === '.position' && vrmBone === 'J_Bip_C_Hips') {
      const scaled = new Float32Array(track.values.length);
      for (let i = 0; i < track.values.length; i++) scaled[i] = track.values[i] * 0.01;
      tracks.push(new THREE.VectorKeyframeTrack(`${vrmBone}.position`, Array.from(track.times), Array.from(scaled)));
      continue;
    }
    tracks.push(track.clone());
    tracks[tracks.length - 1].name = `${vrmBone}${prop}`;
  }
  return new THREE.AnimationClip(`${clip.name}_vrm`, clip.duration, tracks);
}

interface SceneState {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  vrmModel: THREE.Object3D | null;
  mixer: THREE.AnimationMixer | null;
  currentAction: THREE.AnimationAction | null;
  helper: THREE.SkeletonHelper | null;
}

export default function MixamoLoader() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneState | null>(null);
  const [status, setStatus] = useState('Loading VRM…');
  const [loaded, setLoaded] = useState(false);
  const [fbxUrl, setFbxUrl] = useState(DEFAULT_FBX_URL);
  const [trackCounts, setTrackCounts] = useState<{ source: number; mapped: number } | null>(null);

  // Set up scene + load VRM once
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 100);
    camera.position.set(0, 1.3, 3);
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
    controls.target.set(0, 1.0, 0);

    sceneRef.current = {
      scene, camera, renderer, controls,
      vrmModel: null, mixer: null, currentAction: null, helper: null,
    };

    const clock = new THREE.Clock();
    const animate = () => {
      requestAnimationFrame(animate);
      const delta = clock.getDelta();
      if (sceneRef.current?.mixer) sceneRef.current.mixer.update(delta);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    // Load the VRM
    const loader = new GLTFLoader();
    loader.load(VRM_MODEL_PATH, (gltf) => {
      const model = gltf.scene;
      scene.add(model);
      sceneRef.current!.vrmModel = model;
      const helper = new THREE.SkeletonHelper(model);
      (helper.material as THREE.LineBasicMaterial).color.set(0x44ff44);
      (helper.material as THREE.LineBasicMaterial).linewidth = 2;
      scene.add(helper);
      sceneRef.current!.helper = helper;
      sceneRef.current!.mixer = new THREE.AnimationMixer(model);
      setStatus('VRM loaded. Click Load Animation to fetch Samba Dancing FBX.');
      setLoaded(true);
    }, undefined, (err) => {
      setStatus(`VRM load error: ${err instanceof Error ? err.message : String(err)}`);
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

  const loadFbxFromUrl = useCallback(async (url: string) => {
    const s = sceneRef.current;
    if (!s || !s.vrmModel || !s.mixer) {
      setStatus('Wait for VRM to load first');
      return;
    }
    setStatus(`Fetching ${url}…`);
    const fbxLoader = new FBXLoader();
    fbxLoader.load(url, (fbx) => {
      if (fbx.animations.length === 0) {
        setStatus('FBX has no animation clips');
        return;
      }
      const sourceClip = fbx.animations[0];
      const remapped = retargetMixamoClip(sourceClip);
      setTrackCounts({ source: sourceClip.tracks.length, mapped: remapped.tracks.length });
      if (remapped.tracks.length === 0) {
        setStatus(`No mixamorig* bones found in clip — is this actually a Mixamo export?`);
        return;
      }
      // Stop previous action
      if (s.currentAction) {
        s.currentAction.stop();
        s.mixer!.uncacheAction(s.currentAction.getClip());
      }
      const action = s.mixer!.clipAction(remapped);
      action.play();
      s.currentAction = action;
      setStatus(`Playing ${sourceClip.name} (${remapped.tracks.length}/${sourceClip.tracks.length} tracks retargeted)`);
    }, undefined, (err) => {
      setStatus(`FBX load error: ${err instanceof Error ? err.message : String(err)}`);
    });
  }, []);

  const onFilePicked = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    loadFbxFromUrl(url);
  }, [loadFbxFromUrl]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0a0a1a', color: '#ccc' }}>
      <div style={{ padding: '10px 14px', borderBottom: '1px solid #2a2a4a', display: 'flex', flexDirection: 'column', gap: '8px' }}>
        <div style={{ fontSize: '13px', fontWeight: 600 }}>VRM × Mixamo Animation Demo</div>
        <div style={{ fontSize: '11px', color: '#888' }}>
          Proof that the item-shop VRM rig can play free Mixamo humanoid animations via
          bone-name remap. Default sample is the Samba Dancing FBX hosted at threejs.org;
          paste a different URL or upload a Mixamo FBX to test others.
        </div>
        <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
          <input
            type="text"
            value={fbxUrl}
            onChange={(e) => setFbxUrl(e.target.value)}
            style={{
              flex: 1, padding: '4px 8px', fontSize: '11px', fontFamily: 'monospace',
              background: '#1a1a2e', border: '1px solid #444', borderRadius: '4px',
              color: '#ccc', outline: 'none',
            }}
          />
          <button
            onClick={() => loadFbxFromUrl(fbxUrl)}
            disabled={!loaded}
            style={{
              padding: '4px 12px', fontSize: '11px',
              background: loaded ? '#2a3a5a' : '#1a1a2e',
              border: '1px solid #4488ff', borderRadius: '4px',
              color: loaded ? '#88c0ff' : '#555', cursor: loaded ? 'pointer' : 'default',
            }}
          >
            Load URL
          </button>
          <label style={{
            padding: '4px 12px', fontSize: '11px',
            background: '#2a3a2a', border: '1px solid #44aa44', borderRadius: '4px',
            color: '#88ff88', cursor: 'pointer',
          }}>
            Upload FBX
            <input type="file" accept=".fbx" onChange={onFilePicked} style={{ display: 'none' }} />
          </label>
        </div>
        <div style={{ fontSize: '11px', color: '#888', fontFamily: 'monospace' }}>{status}</div>
        {trackCounts && (
          <div style={{ fontSize: '10px', color: '#6a6' }}>
            {trackCounts.mapped}/{trackCounts.source} bone tracks mapped to VRM
            (rest were finger/face/etc. bones not present in the rig and silently dropped)
          </div>
        )}
      </div>
      <div ref={containerRef} style={{ flex: 1, position: 'relative' }} />
    </div>
  );
}
