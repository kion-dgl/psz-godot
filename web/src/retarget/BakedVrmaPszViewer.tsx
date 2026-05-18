import { useState, useEffect, useRef, useMemo } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

// Visual confirmation page for assets/animations/vrma_psz.glb — the
// reverse-direction retarget output (VRM source → PSZ target). Loads
// the PSZ player character and applies each baked clip onto its
// skeleton via Three.js AnimationMixer. If the limbs and root track
// look right here, the bake produced a valid PSZ-targeted glTF and
// the same file will play correctly inside Godot.

const PSZ_MODEL_PATH = assetUrl('assets/player/pc_000/pc_000_000.glb');
const PSZ_TEXTURE_PATH = assetUrl('assets/player/pc_000/textures/pc_000_000.png');
const BAKED_ANIM_PATH = assetUrl('assets/animations/vrma_psz.glb');

function applyTexture(model: THREE.Object3D, texture: THREE.Texture): void {
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.magFilter = THREE.NearestFilter;
  texture.minFilter = THREE.NearestFilter;
  model.traverse((child) => {
    if ((child as THREE.SkinnedMesh).isSkinnedMesh) {
      const mesh = child as THREE.SkinnedMesh;
      const mat = mesh.material as THREE.MeshStandardMaterial;
      if (mat && 'map' in mat) {
        mat.map = texture;
        mat.needsUpdate = true;
      }
    }
  });
}

export default function BakedVrmaPszViewer() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [clipNames, setClipNames] = useState<string[]>([]);
  const [selectedClip, setSelectedClip] = useState<string>('');
  const [status, setStatus] = useState<string>('Loading…');

  // Persistent refs that survive re-renders
  const sceneRef = useRef<{
    mixer: THREE.AnimationMixer | null;
    clips: THREE.AnimationClip[];
    action: THREE.AnimationAction | null;
  }>({ mixer: null, clips: [], action: null });

  // Boot the scene once
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

    const grid = new THREE.GridHelper(4, 8, 0x4a4a6a, 0x2a2a4a);
    scene.add(grid);

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();

    let disposed = false;
    let pszRoot: THREE.Object3D | null = null;
    let helper: THREE.SkeletonHelper | null = null;

    (async () => {
      try {
        setStatus('Loading PSZ model…');
        const [pszGltf, animGltf, texture] = await Promise.all([
          loader.loadAsync(PSZ_MODEL_PATH),
          loader.loadAsync(BAKED_ANIM_PATH),
          texLoader.loadAsync(PSZ_TEXTURE_PATH).catch(() => null),
        ]);
        if (disposed) return;

        pszRoot = pszGltf.scene;
        if (texture) applyTexture(pszRoot, texture);
        scene.add(pszRoot);

        helper = new THREE.SkeletonHelper(pszRoot);
        (helper.material as THREE.LineBasicMaterial).color.set(0x88ff88);
        scene.add(helper);

        // Build mixer on the PSZ skeleton and stash the baked clips.
        // Each clip's tracks reference bone names like '010_Hip.quaternion'
        // — Three.js binds by name automatically when the mixer's root
        // contains those bones, so no per-bone wiring needed.
        const mixer = new THREE.AnimationMixer(pszRoot);
        sceneRef.current.mixer = mixer;
        sceneRef.current.clips = animGltf.animations;

        const names = animGltf.animations.map((c) => c.name);
        setClipNames(names);
        if (names.length > 0) setSelectedClip(names[0]);
        setStatus(`Loaded ${names.length} clip(s) from vrma_psz.glb`);
      } catch (err) {
        setStatus(`Error: ${(err as Error).message}`);
      }
    })();

    const clock = new THREE.Clock();
    let raf = 0;
    const tick = () => {
      const dt = clock.getDelta();
      if (sceneRef.current.mixer) sceneRef.current.mixer.update(dt);
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
  }, []);

  // Swap the running clip whenever the user changes the dropdown
  useEffect(() => {
    const { mixer, clips, action } = sceneRef.current;
    if (!mixer || !selectedClip) return;
    if (action) action.stop();
    const clip = clips.find((c) => c.name === selectedClip);
    if (!clip) return;
    const next = mixer.clipAction(clip);
    next.reset();
    next.setLoop(THREE.LoopRepeat, Infinity);
    next.play();
    sceneRef.current.action = next;
  }, [selectedClip]);

  const clipDescription = useMemo(() => {
    const { clips } = sceneRef.current;
    const c = clips.find((x) => x.name === selectedClip);
    if (!c) return '';
    return `${c.duration.toFixed(2)}s • ${c.tracks.length} tracks`;
  }, [selectedClip, clipNames]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 }}>
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '8px 16px',
        background: '#12122a',
        borderBottom: '1px solid #2a2a4a',
        fontSize: 13,
        color: '#ccc',
      }}>
        <strong style={{ color: '#fff' }}>VRMA → PSZ bake viewer</strong>
        <select
          value={selectedClip}
          onChange={(e) => setSelectedClip(e.target.value)}
          style={{
            background: '#222244',
            color: '#fff',
            border: '1px solid #444466',
            padding: '4px 8px',
            fontSize: 13,
          }}
        >
          {clipNames.map((n) => (
            <option key={n} value={n}>{n}</option>
          ))}
        </select>
        <span style={{ color: '#88aaff' }}>{clipDescription}</span>
        <span style={{ marginLeft: 'auto', color: '#888' }}>{status}</span>
      </div>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        <canvas
          ref={canvasRef}
          style={{ display: 'block', width: '100%', height: '100%' }}
        />
      </div>
    </div>
  );
}
