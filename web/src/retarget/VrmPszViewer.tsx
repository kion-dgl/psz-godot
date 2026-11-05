import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

// Side-by-side confirmation page for the VRM × PSZ animation pipeline
// (web/scripts/bake-retarget-vrm-chibi.py): the PSZ player model plays the
// game's native PSZ-targeted clip on the left while a VRM model plays the
// same PSO motion retargeted onto its J_Bip_* rig on the right — one clock,
// two mixers, so the poses stay in lockstep for comparison. Presentation
// mirrors /tools/retarget (dark panels, PSZ left / counterpart right).
//
// Loading: on localhost the VRM side auto-loads the committed example model
// (assets/npcs/vrm_example/ — a standard VRoid Studio export) through the
// dev server's root-relative file serving; on the deployed site that 404s
// and the two file pickers become the source, same as ?model=&lib=
// query-param overrides. The PSZ side always loads through assetUrl
// (R2 CDN / pack). Clip names pair up by stripping the VRM bake's
// suffix (_vrm etc.): pso_f_sa_stand_vrm ↔ pso_f_sa_stand.

const PSZ_MODEL_PATH = assetUrl('assets/player/pc_000/pc_000_000.glb');
const PSZ_TEXTURE_PATH = assetUrl('assets/player/pc_000/textures/pc_000_000.png');
const PSZ_CLIPS_PATH = assetUrl('assets/player/animations/npc_idles.glb');

const BASE = import.meta.env.BASE_URL || '/';
const isLocalhost = import.meta.env.DEV &&
  (location.hostname === 'localhost' || location.hostname === '127.0.0.1');
// Dev-server defaults: Astro's vite serves repo files at base-relative URLs
// (server.fs.allow covers the repo root), so no absolute /@fs path is needed.
const DEFAULT_VRM_MODEL = `${BASE}assets/npcs/vrm_example/vrm_example.glb`;
const DEFAULT_VRM_CLIPS = `${BASE}assets/npcs/vrm_example/npc_idles_vrm.glb`;

const HALF_SPACING = 0.95;

interface Side {
  model: THREE.Object3D | null;
  mixer: THREE.AnimationMixer | null;
  helper: THREE.SkeletonHelper | null;
  action: THREE.AnimationAction | null;
  clips: THREE.AnimationClip[];
}

interface SceneState {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  psz: Side;
  vrm: Side;
}

function groundAlign(model: THREE.Object3D): void {
  model.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(model);
  if (isFinite(box.min.y)) model.position.y -= box.min.y;
}

/** Pair each VRM-baked clip name with the PSZ-native clip of the same
 *  motion by stripping the bake suffix (_chibi, _stcl, _gucl, _vrm…). */
function pszNameFor(vrmClip: string, pszClips: string[]): string | null {
  if (pszClips.includes(vrmClip)) return vrmClip;
  const stripped = vrmClip.replace(/_[a-z0-9]+$/i, '');
  return pszClips.includes(stripped) ? stripped : null;
}

export default function VrmPszViewer() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneState | null>(null);
  const [searchParams] = useSearchParams();
  const modelParam = searchParams.get('model') ?? '';
  const libParam = searchParams.get('lib') ?? '';

  const [pszStatus, setPszStatus] = useState('loading…');
  const [vrmStatus, setVrmStatus] = useState(isLocalhost ? 'auto-loading local test model…' : 'pick or pass ?model=');
  const [pairs, setPairs] = useState<{ vrm: string; psz: string | null }[]>([]);
  const [selected, setSelected] = useState('');
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [showSkeleton, setShowSkeleton] = useState(false);

  // Boot the scene once.
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 0.01, 100);
    camera.position.set(0, 1.0, 3.4);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.75, 0);
    controls.update();

    scene.add(new THREE.AmbientLight(0xffffff, 0.75));
    const key = new THREE.DirectionalLight(0xffffff, 0.9);
    key.position.set(3, 4, 5);
    scene.add(key);
    scene.add(new THREE.GridHelper(6, 12, 0x4a4a6a, 0x2a2a4a));

    sceneRef.current = {
      scene, camera, renderer, controls,
      psz: { model: null, mixer: null, helper: null, action: null, clips: [] },
      vrm: { model: null, mixer: null, helper: null, action: null, clips: [] },
    };

    const clock = new THREE.Clock();
    let raf = 0;
    const tick = () => {
      raf = requestAnimationFrame(tick);
      const dt = clock.getDelta();
      const s = sceneRef.current;
      if (s) {
        // One clock drives both mixers — the poses stay in lockstep.
        s.psz.mixer?.update(dt);
        s.vrm.mixer?.update(dt);
        controls.update();
        renderer.render(scene, camera);
      }
    };
    tick();

    const handleResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', handleResize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', handleResize);
      controls.dispose();
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
    };
  }, []);

  const attachModel = useCallback((side: 'psz' | 'vrm', model: THREE.Object3D, helperColor: number) => {
    const s = sceneRef.current;
    if (!s) return;
    const target = side === 'psz' ? s.psz : s.vrm;
    if (target.model) {
      s.scene.remove(target.model);
      if (target.helper) s.scene.remove(target.helper);
      target.mixer?.stopAllAction();
    }
    model.position.x = side === 'psz' ? -HALF_SPACING : HALF_SPACING;
    groundAlign(model);
    s.scene.add(model);
    const helper = new THREE.SkeletonHelper(model);
    (helper.material as THREE.LineBasicMaterial).color.set(helperColor);
    helper.visible = showSkeleton;
    s.scene.add(helper);
    target.model = model;
    target.helper = helper;
    target.mixer = new THREE.AnimationMixer(model);
    target.action = null;
  }, [showSkeleton]);

  // PSZ reference side — always loads from the CDN/pack.
  useEffect(() => {
    let cancelled = false;
    const loader = new GLTFLoader();
    (async () => {
      try {
        const gltf = await loader.loadAsync(PSZ_MODEL_PATH);
        if (cancelled) return;
        attachModel('psz', gltf.scene, 0x44ff44);
        // Authentic PSO look: nearest-filtered texture on unlit basic material.
        const texture = await new THREE.TextureLoader().loadAsync(PSZ_TEXTURE_PATH).catch(() => null);
        if (cancelled || !texture) return;
        texture.magFilter = THREE.NearestFilter;
        texture.minFilter = THREE.NearestFilter;
        texture.flipY = false;
        texture.colorSpace = THREE.SRGBColorSpace;
        gltf.scene.traverse((child: THREE.Object3D) => {
          if ((child as THREE.Mesh).isMesh) {
            (child as THREE.Mesh).material = new THREE.MeshBasicMaterial({ map: texture });
          }
        });
        const clipsGltf = await loader.loadAsync(PSZ_CLIPS_PATH);
        if (cancelled) return;
        const s = sceneRef.current;
        if (s) {
          s.psz.clips = clipsGltf.animations;
          setPszStatus(`native clips: ${clipsGltf.animations.length}`);
          setPairs((prev) => {
            if (prev.length > 0) return prev; // pairs rebuild when the VRM lib lands
            return prev;
          });
          // Re-pair now that PSZ clips are known.
          const vrmNames = s.vrm.clips.map((c) => c.name);
          if (vrmNames.length > 0) {
            const next = vrmNames
              .map((name) => ({ vrm: name, psz: pszNameFor(name, clipsGltf.animations.map((c) => c.name)) }));
            setPairs(next);
          }
        }
      } catch (err) {
        if (!cancelled) setPszStatus(`error: ${(err as Error).message}`);
      }
    })();
    return () => { cancelled = true; };
  }, [attachModel]);

  // VRM side — localhost auto-load, query-param override, or file picker.
  const loadVrmModel = useCallback(async (url: string) => {
    const loader = new GLTFLoader();
    setVrmStatus(`loading model…`);
    try {
      const gltf = await loader.loadAsync(url);
      attachModel('vrm', gltf.scene, 0x66aaff);
      setVrmStatus('model loaded — load clips');
    } catch (err) {
      setVrmStatus(`model error: ${(err as Error).message}`);
      throw err;
    }
  }, [attachModel]);

  const loadVrmClips = useCallback(async (url: string) => {
    const s = sceneRef.current;
    if (!s?.vrm.model) {
      setVrmStatus('load a model first');
      return;
    }
    const loader = new GLTFLoader();
    try {
      const gltf = await loader.loadAsync(url);
      if (gltf.animations.length === 0) {
        setVrmStatus('clip library has no animations');
        return;
      }
      s.vrm.clips = gltf.animations;
      const pszNames = s.psz.clips.map((c) => c.name);
      const next = gltf.animations.map((c) => ({ vrm: c.name, psz: pszNameFor(c.name, pszNames) }));
      setPairs(next);
      if (next.length > 0) setSelected(next[0].vrm);
      const unmatched = next.filter((p) => !p.psz).length;
      setVrmStatus(`${next.length} clip(s)${unmatched ? ` · ${unmatched} without PSZ pair` : ''}`);
    } catch (err) {
      setVrmStatus(`clip error: ${(err as Error).message}`);
    }
  }, []);

  useEffect(() => {
    if (modelParam) {
      void loadVrmModel(modelParam)
        .then(() => { if (libParam) void loadVrmClips(libParam); })
        .catch(() => {});
    } else if (isLocalhost) {
      // Auto-load the local test assets — no clicking required on the dev box.
      void loadVrmModel(DEFAULT_VRM_MODEL)
        .then(() => loadVrmClips(DEFAULT_VRM_CLIPS))
        .catch(() => setVrmStatus('auto-load failed — use the pickers (?model/&lib= also works)'));
    }
  }, [modelParam, libParam, loadVrmModel, loadVrmClips]);

  // Play the selected motion on BOTH sides, reset together.
  useEffect(() => {
    const s = sceneRef.current;
    if (!s || !selected) return;
    const pair = pairs.find((p) => p.vrm === selected);
    if (!pair) return;
    for (const side of [s.psz, s.vrm]) {
      side.action?.stop();
      side.action = null;
    }
    const vrmClip = s.vrm.clips.find((c) => c.name === pair.vrm);
    if (vrmClip && s.vrm.mixer) {
      const action = s.vrm.mixer.clipAction(vrmClip);
      action.reset().play();
      action.setLoop(THREE.LoopRepeat, Infinity);
      action.timeScale = speed;
      action.paused = !playing;
      s.vrm.action = action;
    }
    if (pair.psz && s.psz.mixer) {
      const pszClip = s.psz.clips.find((c) => c.name === pair.psz);
      if (pszClip) {
        const action = s.psz.mixer.clipAction(pszClip);
        action.reset().play();
        action.setLoop(THREE.LoopRepeat, Infinity);
        action.timeScale = speed;
        action.paused = !playing;
        s.psz.action = action;
      }
    }
    // Re-run when the PSZ clips land after the VRM ones.
  }, [selected, pairs, playing, speed]);

  useEffect(() => {
    const s = sceneRef.current;
    if (!s) return;
    if (s.psz.action) s.psz.action.paused = !playing;
    if (s.vrm.action) s.vrm.action.paused = !playing;
  }, [playing, selected]);

  useEffect(() => {
    const s = sceneRef.current;
    if (!s) return;
    if (s.psz.action) s.psz.action.timeScale = speed;
    if (s.vrm.action) s.vrm.action.timeScale = speed;
  }, [speed, selected]);

  useEffect(() => {
    const s = sceneRef.current;
    if (!s) return;
    if (s.psz.helper) s.psz.helper.visible = showSkeleton;
    if (s.vrm.helper) s.vrm.helper.visible = showSkeleton;
  }, [showSkeleton]);

  const onModelPicked = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) void loadVrmModel(URL.createObjectURL(file)).catch(() => {});
  }, [loadVrmModel]);

  const onLibPicked = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) void loadVrmClips(URL.createObjectURL(file));
  }, [loadVrmClips]);

  const selectedInfo = useMemo(() => {
    const s = sceneRef.current;
    const pair = pairs.find((p) => p.vrm === selected);
    if (!pair || !s) return '';
    const vrmClip = s.vrm.clips.find((c) => c.name === pair.vrm);
    return vrmClip ? `${vrmClip.duration.toFixed(2)}s · psz: ${pair.psz ?? '—'}` : '';
  }, [selected, pairs]);

  const btn: React.CSSProperties = {
    padding: '4px 12px', fontSize: 11, cursor: 'pointer',
    background: '#2a3a5a', border: '1px solid #4488ff', borderRadius: 4, color: '#88c0ff',
  };
  const pick: React.CSSProperties = {
    padding: '4px 12px', fontSize: 11, cursor: 'pointer',
    background: '#2a3a2a', border: '1px solid #44aa44', borderRadius: 4, color: '#88ff88',
  };
  const label: React.CSSProperties = {
    position: 'absolute', bottom: 10, fontSize: 11, fontFamily: 'monospace',
    padding: '3px 10px', borderRadius: 6, background: 'rgba(10,10,26,0.8)',
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0, background: '#1a1a2e' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
        padding: '10px 16px', background: '#2d2d44',
      }}>
        <span style={{ fontSize: 14, fontWeight: 600 }}>
          <span style={{ color: pszStatus.startsWith('error') ? '#f66' : '#44ff44' }}>PSZ</span>
          {' vs '}
          <span style={{ color: '#88c0ff' }}>VRM</span>
          {' — same PSO clip'}
        </span>
        <select
          value={selected}
          onChange={(e) => setSelected(e.target.value)}
          disabled={pairs.length === 0}
          style={{ background: '#1a1a2e', color: '#fff', border: '1px solid #444466', padding: '4px 8px', fontSize: 13 }}
        >
          {pairs.map((p) => (
            <option key={p.vrm} value={p.vrm}>
              {p.vrm.replace(/_[a-z0-9]+$/i, '')}{p.psz ? '' : ' (no PSZ pair)'}
            </option>
          ))}
        </select>
        <button style={btn} onClick={() => setPlaying((p) => !p)} disabled={!selected}>
          {playing ? 'Pause' : 'Play'}
        </button>
        <label style={{ fontSize: 11, color: '#888', display: 'flex', alignItems: 'center', gap: 6 }}>
          speed {speed.toFixed(1)}x
          <input type="range" min="0.1" max="1.5" step="0.1" value={speed}
            onChange={(e) => setSpeed(parseFloat(e.target.value))} style={{ width: 90 }} />
        </label>
        <label style={{ fontSize: 11, color: '#888', display: 'flex', alignItems: 'center', gap: 4 }}>
          <input type="checkbox" checked={showSkeleton} onChange={(e) => setShowSkeleton(e.target.checked)} /> skeleton
        </label>
        <label style={pick}>
          VRM model (.vrm/.glb)
          <input type="file" accept=".vrm,.glb" onChange={onModelPicked} style={{ display: 'none' }} />
        </label>
        <label style={pick}>
          Clips (.glb)
          <input type="file" accept=".glb" onChange={onLibPicked} style={{ display: 'none' }} />
        </label>
        <span style={{ marginLeft: 'auto', textAlign: 'right', fontFamily: 'monospace', fontSize: 11, lineHeight: 1.4 }}>
          <span style={{ color: pszStatus.startsWith('error') ? '#f66' : '#44ff44' }}>psz: {pszStatus}</span>
          <br />
          <span style={{ color: vrmStatus.startsWith('error') || vrmStatus.includes('failed') ? '#f66' : '#88c0ff' }}>vrm: {vrmStatus}</span>
        </span>
      </div>
      <div style={{ flex: 1, minHeight: 0, position: 'relative', background: '#0a0a1a' }} ref={containerRef}>
        {selectedInfo && (
          <div style={{ ...label, left: '50%', transform: 'translateX(-50%)', color: '#88aaff' }}>{selectedInfo}</div>
        )}
        <div style={{ ...label, left: 12, color: '#44ff44' }}>PSZ · native clip</div>
        <div style={{ ...label, right: 12, color: '#88c0ff' }}>VRM · baked clip</div>
      </div>
    </div>
  );
}
