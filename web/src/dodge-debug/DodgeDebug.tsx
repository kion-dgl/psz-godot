import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Side-view debug view for the player dodge roll.
 *
 * The in-game dodge currently runs the `pmsa_esc_f` clip from
 * `assets/player/animations/saver_m.glb` while translating the player
 * along their facing direction at DODGE_SPEED for DODGE_DURATION
 * (4.0 m over 0.8 s, see scripts/3d/player/player.gd). There are no
 * iframes in the live build; this tool is for tuning what they should
 * be, plus per-pose X (cumulative distance) and Y (lift) curves so the
 * dodge can match the visible roll pacing instead of sliding linearly.
 *
 * Layout:
 *  - Ghost row: N skinned-mesh instances at the X position the user has
 *    set for each pose. Each ghost has its own mixer parked at a fixed
 *    time, plus a per-pose Y offset slider. Ghosts inside the i-frame
 *    window are tinted red.
 *  - Live preview: a single model plays the animation once, sliding
 *    through xPositions[] (linearly interpolated by anim t-fraction)
 *    and lifting by yOffsets[]. Tinted red while inside the i-frame
 *    window. All horizontal motion happens during the clip — when the
 *    animation freezes at the end, the model parks at xPositions[last].
 *  - Right panel: per-pose X & Y sliders, i-frame range, pose count,
 *    weapon type, a copy-as-gdscript button.
 *
 * State persists to localStorage so re-loads keep the in-progress tune.
 */

const STORAGE_KEY = 'psz-dodge-debug:v2';
const STORAGE_KEY_V1 = 'psz-dodge-debug:v1';

type WeaponKey =
  | 'saver' | 'sword' | 'dagger' | 'spear' | 'claw'
  | 'slicer' | 'rod' | 'wand' | 'shotgun' | 'handgun' | 'machinegun';

const WEAPON_OPTIONS: { id: WeaponKey; label: string; animPrefix: string }[] = [
  { id: 'saver', label: 'Saber', animPrefix: 'pmsa' },
  { id: 'sword', label: 'Sword', animPrefix: 'pmsw' },
  { id: 'dagger', label: 'Dagger', animPrefix: 'pmda' },
  { id: 'spear', label: 'Spear', animPrefix: 'pmsp' },
  { id: 'claw', label: 'Claw', animPrefix: 'pmcl' },
  { id: 'slicer', label: 'Slicer', animPrefix: 'pmsl' },
  { id: 'rod', label: 'Rod', animPrefix: 'pmro' },
  { id: 'wand', label: 'Wand', animPrefix: 'pmwa' },
  { id: 'shotgun', label: 'Rifle', animPrefix: 'pmsh' },
  { id: 'handgun', label: 'Handgun', animPrefix: 'pmhg' },
  { id: 'machinegun', label: 'Machinegun', animPrefix: 'pmmg' },
];

// In player.gd: const DODGE_DURATION: float = 0.8 / DODGE_SPEED: float = 5.0
// (4.0 m over 0.8 s, before per-pose tuning).
const DEFAULT_TOTAL_DISTANCE = 4.0;

interface DodgeConfig {
  weapon: WeaponKey;
  numPoses: number;
  // length === numPoses; cumulative X distance (m from start) at each pose.
  // xPositions[0] is always 0 (start of dodge); the user can tune each
  // subsequent pose. The total dodge distance is xPositions[numPoses-1].
  xPositions: number[];
  yOffsets: number[];      // length === numPoses; world-space lift per sampled time
  iframeStart: number;     // 0..1 fraction of animation duration
  iframeEnd: number;       // 0..1 fraction of animation duration
}

/**
 * Default X curve for the dodge: front-loaded so most of the distance is
 * covered during the rolling portion (poses 0–4), with a plateau through
 * the stand-up (poses 5–7). Approximates the original animation's root
 * motion shape (rapid Z gain in the first ~50% of the clip, then settle).
 */
function defaultXPositions(n: number, totalDistance: number = DEFAULT_TOTAL_DISTANCE): number[] {
  // Eight-pose reference curve (as fraction of total distance), shaped to
  // match the rolling/stand-up split. ease-out then plateau.
  const ref = [0, 0.30, 0.55, 0.75, 0.92, 1.00, 1.00, 1.00];
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0 : i / (n - 1);
    const srcIdx = t * (ref.length - 1);
    const lo = Math.floor(srcIdx);
    const hi = Math.min(ref.length - 1, lo + 1);
    const f = srcIdx - lo;
    out.push((ref[lo] * (1 - f) + ref[hi] * f) * totalDistance);
  }
  // Lock pose 0 at exactly 0.
  if (out.length > 0) out[0] = 0;
  return out;
}

const DEFAULT_CONFIG: DodgeConfig = {
  weapon: 'saver',
  numPoses: 8,
  xPositions: defaultXPositions(8),
  yOffsets: Array(8).fill(0),
  iframeStart: 0.15,
  iframeEnd: 0.65,
};

function loadConfig(): DodgeConfig {
  if (typeof window === 'undefined') return DEFAULT_CONFIG;
  try {
    let raw = window.localStorage.getItem(STORAGE_KEY);
    let v1Migrated = false;
    if (!raw) {
      // v1 migration: old config had a single `distance: number`. Map that
      // onto the default X curve scaled to the saved total.
      const legacy = window.localStorage.getItem(STORAGE_KEY_V1);
      if (legacy) {
        const parsedLegacy = JSON.parse(legacy) as Partial<DodgeConfig> & { distance?: number };
        const total = typeof parsedLegacy.distance === 'number' ? parsedLegacy.distance : DEFAULT_TOTAL_DISTANCE;
        const n = parsedLegacy.numPoses ?? 8;
        raw = JSON.stringify({ ...parsedLegacy, xPositions: defaultXPositions(n, total) });
        v1Migrated = true;
      }
    }
    if (!raw) return DEFAULT_CONFIG;
    const parsed = JSON.parse(raw) as Partial<DodgeConfig>;
    const cfg: DodgeConfig = { ...DEFAULT_CONFIG, ...parsed } as DodgeConfig;
    if (!Array.isArray(cfg.yOffsets) || cfg.yOffsets.length !== cfg.numPoses) {
      cfg.yOffsets = resampleCurve(cfg.yOffsets || [], cfg.numPoses);
    }
    if (!Array.isArray(cfg.xPositions) || cfg.xPositions.length !== cfg.numPoses) {
      cfg.xPositions = cfg.xPositions && cfg.xPositions.length > 0
        ? resampleCurve(cfg.xPositions, cfg.numPoses)
        : defaultXPositions(cfg.numPoses);
    }
    if (cfg.xPositions.length > 0) cfg.xPositions[0] = 0; // pose 0 is always 0
    if (v1Migrated) {
      try { window.localStorage.removeItem(STORAGE_KEY_V1); } catch { /* ignore */ }
    }
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

function resampleCurve(prev: number[], n: number): number[] {
  if (prev.length === 0) return Array(n).fill(0);
  if (prev.length === n) return prev.slice();
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0 : i / (n - 1);
    const srcIdx = t * (prev.length - 1);
    const lo = Math.floor(srcIdx);
    const hi = Math.min(prev.length - 1, lo + 1);
    const f = srcIdx - lo;
    out.push(prev[lo] * (1 - f) + prev[hi] * f);
  }
  return out;
}

/** Linear interp of a per-pose curve at fractional time t in [0,1]. */
function sampleCurve(values: number[], t: number): number {
  if (values.length === 0) return 0;
  if (values.length === 1) return values[0];
  const clamped = Math.max(0, Math.min(1, t));
  const idx = clamped * (values.length - 1);
  const lo = Math.floor(idx);
  const hi = Math.min(values.length - 1, lo + 1);
  const f = idx - lo;
  return values[lo] * (1 - f) + values[hi] * f;
}

function isInIframeWindow(t: number, start: number, end: number): boolean {
  if (start <= end) return t >= start && t <= end;
  return t >= start || t <= end;
}

/**
 * Strip the 000_Root position track from a dodge clip.
 *
 * The PSO dodge animations have ~4 m of Z-translation baked into the root
 * bone that does NOT return to zero by the final frame (pmsa_esc_f ends
 * with root_z ≈ 4.36). Three.js's AnimationMixer applies the root bone
 * translation in addition to whatever world position we set on the parent
 * group, so the visible mesh ends up far ahead of the group origin and
 * stays there when LoopOnce + clampWhenFinished freezes the animation —
 * this is the "huge slide after stand-up" you see in the viewport.
 *
 * Stripping the root position track makes the visible mesh stay aligned
 * with `group.position`, which is the only thing we want driving the
 * horizontal position in the debug view. The rotation/quaternion track on
 * the root, plus all other bones, are untouched — so the body still curls
 * into the roll and recovers normally.
 */
function stripRootMotion(clip: THREE.AnimationClip): void {
  clip.tracks = clip.tracks.filter((t) => {
    // GLTFLoader names skeleton-targeted tracks "<boneName>.<property>".
    // Match exact "000_Root.position" plus a defensive trailing-segment
    // form in case the loader prefixes a path.
    if (t.name === '000_Root.position') return false;
    if (t.name.endsWith('/000_Root.position')) return false;
    return true;
  });
}

interface GhostHandle {
  group: THREE.Group;            // root for x-translation + y-lift
  mixer: THREE.AnimationMixer;
  meshes: THREE.SkinnedMesh[];   // for tint swap
  baseColor: THREE.Color | null;
  poseTime: number;              // anim time in seconds
}

export default function DodgeDebug() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<{
    scene: THREE.Scene;
    camera: THREE.OrthographicCamera;
    renderer: THREE.WebGLRenderer;
    controls: OrbitControls;
    groundGrid: THREE.GridHelper;
    iframeBand: THREE.Mesh | null;
    distanceMarker: THREE.Group;
    ghosts: GhostHandle[];
    live: {
      group: THREE.Group;
      mixer: THREE.AnimationMixer;
      action: THREE.AnimationAction | null;
      meshes: THREE.SkinnedMesh[];
      baseColor: THREE.Color | null;
    } | null;
    clip: THREE.AnimationClip | null;
    modelGltf: THREE.Group | null;
  } | null>(null);

  const [config, setConfig] = useState<DodgeConfig>(loadConfig);
  const [duration, setDuration] = useState(0.8); // overwritten by clip
  const [liveTime, setLiveTime] = useState(0);
  const [showGhosts, setShowGhosts] = useState(true);
  const [showLive, setShowLive] = useState(true);
  const [replayTick, setReplayTick] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Persist config to localStorage
  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
    } catch { /* ignore quota */ }
  }, [config]);

  // Resample both curves when pose count changes
  const setNumPoses = (n: number) => {
    setConfig((cfg) => {
      const xs = resampleCurve(cfg.xPositions, n);
      if (xs.length > 0) xs[0] = 0;
      return {
        ...cfg,
        numPoses: n,
        yOffsets: resampleCurve(cfg.yOffsets, n),
        xPositions: xs,
      };
    });
  };

  const setYAt = (i: number, v: number) => {
    setConfig((cfg) => {
      const next = cfg.yOffsets.slice();
      next[i] = v;
      return { ...cfg, yOffsets: next };
    });
  };

  const setXAt = (i: number, v: number) => {
    if (i === 0) return; // pose 0 is locked at 0
    setConfig((cfg) => {
      const next = cfg.xPositions.slice();
      next[i] = v;
      return { ...cfg, xPositions: next };
    });
  };

  // Initialize Three.js scene (side ortho view)
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;
    const aspect = width / height;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const viewSize = 3.0; // half-height in world units
    const camera = new THREE.OrthographicCamera(
      -viewSize * aspect, viewSize * aspect,
      viewSize, -viewSize,
      -50, 50,
    );
    // Side view: looking at +X axis from +Z. Player faces +X.
    camera.position.set(0, 1.2, 8);
    camera.lookAt(2, 1.0, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(2, 5, 4);
    scene.add(dir);

    // Ground plane + grid (5×5 grid above the X-axis travel range)
    const grid = new THREE.GridHelper(10, 20, 0x444466, 0x222238);
    grid.position.set(2, 0, 0);
    scene.add(grid);

    // Ground line (the x-axis itself, for the side-view "floor")
    const groundLineMat = new THREE.LineBasicMaterial({ color: 0x6688ff });
    const groundLineGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-1, 0, 0), new THREE.Vector3(7, 0, 0),
    ]);
    scene.add(new THREE.Line(groundLineGeo, groundLineMat));

    // Distance markers: vertical ticks at 0, 1, 2, ... metres
    const distanceMarker = new THREE.Group();
    for (let m = 0; m <= 6; m++) {
      const tickGeo = new THREE.BufferGeometry().setFromPoints([
        new THREE.Vector3(m, 0, 0), new THREE.Vector3(m, 0.08, 0),
      ]);
      distanceMarker.add(new THREE.Line(tickGeo, new THREE.LineBasicMaterial({ color: 0x6688ff })));
    }
    scene.add(distanceMarker);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(2, 1.0, 0);

    sceneRef.current = {
      scene, camera, renderer, controls, groundGrid: grid,
      iframeBand: null, distanceMarker,
      ghosts: [], live: null, clip: null, modelGltf: null,
    };

    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const delta = clock.getDelta();
      if (sceneRef.current?.live?.action) {
        sceneRef.current.live.mixer.update(delta);
      }
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const onResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      const a = w / h;
      camera.left = -viewSize * a;
      camera.right = viewSize * a;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', onResize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
    };
  }, []);

  // Resolve animation clip name from selected weapon
  const animationClipName = useMemo(() => {
    const w = WEAPON_OPTIONS.find((w) => w.id === config.weapon);
    return w ? `${w.animPrefix}_esc_f` : 'pmsa_esc_f';
  }, [config.weapon]);

  // Load model + animation
  useEffect(() => {
    if (!sceneRef.current) return;
    const sref = sceneRef.current;
    const { scene } = sref;
    setIsLoading(true);
    setLoadError(null);

    // Tear down previous
    sref.ghosts.forEach((g) => scene.remove(g.group));
    sref.ghosts = [];
    if (sref.live) {
      scene.remove(sref.live.group);
      sref.live = null;
    }
    sref.clip = null;
    sref.modelGltf = null;

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const modelPath = assetUrl('assets/player/pc_000/pc_000_000.glb');
    const animPath = assetUrl(`assets/player/animations/${config.weapon}_m.glb`);
    const texPath = assetUrl('assets/player/pc_000/textures/pc_000_000.png');

    let cancelled = false;

    loader.load(modelPath, (gltf) => {
      if (cancelled) return;

      const tex = texLoader.load(texPath, (t) => {
        t.magFilter = THREE.NearestFilter;
        t.minFilter = THREE.NearestFilter;
        t.flipY = false;
        t.colorSpace = THREE.SRGBColorSpace;
      });

      const applyTex = (root: THREE.Object3D) => {
        root.traverse((child) => {
          const m = child as THREE.Mesh;
          if (m.isMesh && m.material) {
            const mat = (m.material as THREE.MeshBasicMaterial);
            mat.map = tex;
            mat.needsUpdate = true;
          }
        });
      };

      applyTex(gltf.scene);
      sref.modelGltf = gltf.scene;

      loader.load(animPath, (animGltf) => {
        if (cancelled) return;
        const clip = animGltf.animations.find((a) => a.name === animationClipName);
        if (!clip) {
          setLoadError(`Animation "${animationClipName}" not in ${config.weapon}_m.glb. Available: ${animGltf.animations.map((a) => a.name).join(', ')}`);
          setIsLoading(false);
          return;
        }
        stripRootMotion(clip);
        sref.clip = clip;
        setDuration(clip.duration);

        // Build live model
        if (showLive) {
          const liveGroup = new THREE.Group();
          // For skinned meshes, SkeletonUtils.clone is the safe deep-clone.
          // We don't have it imported — fall back to using the original
          // gltf.scene directly for "live" and clone-from-glb for ghosts.
          // For simplicity: re-load the model for each instance below. The
          // first model is reused for live.
          const liveModel = gltf.scene;
          liveGroup.add(liveModel);
          // Player faces +X (sin(0)=0, cos(0)=1 in player.gd → +Z facing,
          // but in this side view we treat travel as +X). Rotate so the
          // model faces +X.
          liveModel.rotation.y = Math.PI / 2;
          scene.add(liveGroup);

          const meshes: THREE.SkinnedMesh[] = [];
          let baseColor: THREE.Color | null = null;
          liveModel.traverse((c) => {
            const m = c as THREE.SkinnedMesh;
            if (m.isSkinnedMesh) {
              meshes.push(m);
              if (!baseColor && (m.material as THREE.MeshBasicMaterial).color) {
                baseColor = (m.material as THREE.MeshBasicMaterial).color.clone();
              }
            }
          });

          const mixer = new THREE.AnimationMixer(liveModel);
          const action = mixer.clipAction(clip);
          // Play once and freeze on the last frame — the in-game dodge is
          // a one-shot, looping it during tuning is misleading.
          action.setLoop(THREE.LoopOnce, 1);
          action.clampWhenFinished = true;
          action.play();

          sref.live = { group: liveGroup, mixer, action, meshes, baseColor };
        }

        setIsLoading(false);
      }, undefined, (err) => {
        setLoadError(`Failed to load animation: ${err}`);
        setIsLoading(false);
      });
    }, undefined, (err) => {
      setLoadError(`Failed to load model: ${err}`);
      setIsLoading(false);
    });

    return () => {
      cancelled = true;
    };
    // animationClipName is derived from config.weapon; depending on
    // showLive triggers a full reload which is fine.
  }, [config.weapon, animationClipName, showLive]);

  // Build ghost row separately (loads model N times since we don't have SkeletonUtils.clone)
  useEffect(() => {
    if (!sceneRef.current) return;
    const sref = sceneRef.current;
    const { scene } = sref;

    // Clear existing ghosts
    sref.ghosts.forEach((g) => scene.remove(g.group));
    sref.ghosts = [];

    if (!showGhosts) return;

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const modelPath = assetUrl('assets/player/pc_000/pc_000_000.glb');
    const animPath = assetUrl(`assets/player/animations/${config.weapon}_m.glb`);
    const texPath = assetUrl('assets/player/pc_000/textures/pc_000_000.png');

    let cancelled = false;

    const tex = texLoader.load(texPath, (t) => {
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestFilter;
      t.flipY = false;
      t.colorSpace = THREE.SRGBColorSpace;
    });

    const buildGhost = (i: number) => new Promise<void>((resolve) => {
      loader.load(modelPath, (gltf) => {
        if (cancelled) { resolve(); return; }
        const ghostScene = gltf.scene;
        ghostScene.rotation.y = Math.PI / 2;
        ghostScene.traverse((c) => {
          const m = c as THREE.Mesh;
          if (m.isMesh && m.material) {
            const mat = (m.material as THREE.MeshBasicMaterial).clone();
            mat.map = tex;
            mat.transparent = true;
            mat.opacity = 0.65;
            mat.needsUpdate = true;
            (m as THREE.Mesh).material = mat;
          }
        });

        const group = new THREE.Group();
        group.add(ghostScene);
        scene.add(group);

        loader.load(animPath, (animGltf) => {
          if (cancelled) { resolve(); return; }
          const clip = animGltf.animations.find((a) => a.name === animationClipName);
          if (!clip) { resolve(); return; }
          stripRootMotion(clip);
          const mixer = new THREE.AnimationMixer(ghostScene);
          const action = mixer.clipAction(clip);
          action.play();

          const meshes: THREE.SkinnedMesh[] = [];
          let baseColor: THREE.Color | null = null;
          ghostScene.traverse((c) => {
            const m = c as THREE.SkinnedMesh;
            if (m.isSkinnedMesh) {
              meshes.push(m);
              if (!baseColor && (m.material as THREE.MeshBasicMaterial).color) {
                baseColor = (m.material as THREE.MeshBasicMaterial).color.clone();
              }
            }
          });

          // Park at the pose time and freeze.
          const tFrac = config.numPoses === 1 ? 0 : i / (config.numPoses - 1);
          const poseTime = tFrac * clip.duration;
          mixer.setTime(poseTime);
          action.paused = true;

          sref.ghosts[i] = { group, mixer, meshes, baseColor, poseTime };
          resolve();
        }, undefined, () => resolve());
      }, undefined, () => resolve());
    });

    sref.ghosts = new Array(config.numPoses);
    Promise.all(Array.from({ length: config.numPoses }, (_, i) => buildGhost(i))).then(() => {
      // Ghosts loaded — positioning will be applied by the layout effect.
    });

    return () => {
      cancelled = true;
    };
  }, [config.weapon, animationClipName, config.numPoses, showGhosts]);

  // Apply ghost positions + tint based on iframe window + Y/X curves
  useEffect(() => {
    if (!sceneRef.current) return;
    const { ghosts } = sceneRef.current;
    for (let i = 0; i < ghosts.length; i++) {
      const g = ghosts[i];
      if (!g) continue;
      const tFrac = config.numPoses === 1 ? 0 : i / (config.numPoses - 1);
      const x = config.xPositions[i] ?? 0;
      const y = config.yOffsets[i] ?? 0;
      g.group.position.set(x, y, 0);

      const inIframe = isInIframeWindow(tFrac, config.iframeStart, config.iframeEnd);
      const tint = inIframe ? new THREE.Color(0xff5555) : (g.baseColor || new THREE.Color(0xffffff));
      for (const m of g.meshes) {
        const mat = m.material as THREE.MeshBasicMaterial;
        if (mat.color) mat.color.copy(tint);
      }
    }
  }, [config.numPoses, config.xPositions, config.yOffsets, config.iframeStart, config.iframeEnd]);

  // Replay the live preview from t=0
  const replay = useCallback(() => {
    if (!sceneRef.current?.live?.action) return;
    sceneRef.current.live.action.reset();
    sceneRef.current.live.action.play();
    setReplayTick((n) => n + 1);
  }, []);

  // Drive live model along x and y based on its mixer time. With LoopOnce +
  // clampWhenFinished, action.time stops advancing past clip.duration, so we
  // clamp tFrac to [0,1] and read straight from action.time (no modulo).
  useEffect(() => {
    if (!sceneRef.current?.live) return;
    const live = sceneRef.current.live;
    let raf = 0;
    const loop = () => {
      raf = requestAnimationFrame(loop);
      if (!live.action || !sceneRef.current?.clip) return;
      const dur = sceneRef.current.clip.duration;
      const t = Math.min(live.action.time, dur);
      const tFrac = dur > 0 ? Math.min(1, t / dur) : 0;
      // x and y are both interpolated from the per-pose curves so they
      // freeze at xPositions[last] / yOffsets[last] when the clip ends.
      // No movement after the animation freezes — that's the whole point
      // of having per-pose X positions instead of a linear distance ramp.
      const x = sampleCurve(config.xPositions, tFrac);
      const y = sampleCurve(config.yOffsets, tFrac);
      live.group.position.set(x, y, 0);

      const inIframe = isInIframeWindow(tFrac, config.iframeStart, config.iframeEnd);
      const tint = inIframe ? new THREE.Color(0xff5555) : (live.baseColor || new THREE.Color(0xffffff));
      for (const m of live.meshes) {
        const mat = m.material as THREE.MeshBasicMaterial;
        if (mat.color) mat.color.copy(tint);
      }
      setLiveTime(t);
    };
    loop();
    return () => cancelAnimationFrame(raf);
  }, [config.xPositions, config.yOffsets, config.iframeStart, config.iframeEnd, isLoading, replayTick]);

  // I-frame band overlay (red translucent strip on the ground). The band's
  // X bounds are computed by mapping the iframe time-fractions through the
  // xPositions curve so the strip lines up with where the player actually
  // is at those moments, even when the X curve is nonlinear.
  useEffect(() => {
    if (!sceneRef.current) return;
    const sref = sceneRef.current;
    if (sref.iframeBand) {
      sref.scene.remove(sref.iframeBand);
      (sref.iframeBand.geometry as THREE.BufferGeometry).dispose();
      (sref.iframeBand.material as THREE.Material).dispose();
      sref.iframeBand = null;
    }
    const x0 = sampleCurve(config.xPositions, config.iframeStart);
    const x1 = sampleCurve(config.xPositions, config.iframeEnd);
    const w = Math.max(0.001, Math.abs(x1 - x0));
    const geo = new THREE.PlaneGeometry(w, 0.6);
    const mat = new THREE.MeshBasicMaterial({ color: 0xff3344, transparent: true, opacity: 0.18, side: THREE.DoubleSide });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set((x0 + x1) / 2, 0.01, 0);
    sref.scene.add(mesh);
    sref.iframeBand = mesh;
  }, [config.iframeStart, config.iframeEnd, config.xPositions]);

  const copyGdscript = useCallback(() => {
    const totalDistance = config.xPositions[config.xPositions.length - 1] ?? 0;
    const lines: string[] = [];
    lines.push(`# Dodge tuning — copy into scripts/3d/player/player.gd`);
    lines.push(`const DODGE_DURATION: float = ${duration.toFixed(3)} # matches pmsa_esc_f clip length`);
    lines.push(`const DODGE_DISTANCE: float = ${totalDistance.toFixed(3)} # final X position`);
    lines.push(`const DODGE_IFRAME_START: float = ${(config.iframeStart * duration).toFixed(3)} # ${(config.iframeStart * 100).toFixed(1)}%`);
    lines.push(`const DODGE_IFRAME_END:   float = ${(config.iframeEnd * duration).toFixed(3)} # ${(config.iframeEnd * 100).toFixed(1)}%`);
    lines.push(`# Per-pose curves (linear-interp samples across the animation, ${config.numPoses} poses)`);
    lines.push(`const DODGE_X_POSITIONS: PackedFloat32Array = PackedFloat32Array([${config.xPositions.map((v) => v.toFixed(3)).join(', ')}])`);
    lines.push(`const DODGE_Y_OFFSETS:   PackedFloat32Array = PackedFloat32Array([${config.yOffsets.map((v) => v.toFixed(3)).join(', ')}])`);
    const out = lines.join('\n');
    navigator.clipboard.writeText(out);
  }, [config, duration]);

  const resetAll = () => {
    if (!confirm('Reset dodge tuning to defaults?')) return;
    setConfig(DEFAULT_CONFIG);
  };

  const liveTimeFrac = duration > 0 ? (liveTime % duration) / duration : 0;
  const liveInIframe = isInIframeWindow(liveTimeFrac, config.iframeStart, config.iframeEnd);

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: '16px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: '16px', height: '100%' }}>
        {/* Center - 3D Canvas */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '8px', minWidth: 0 }}>
          <div style={{
            background: '#2d2d44', borderRadius: '8px', padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16,
          }}>
            <span style={{ fontSize: '14px', fontWeight: 'bold', color: '#6bf' }}>
              Dodge Roll Debug — {animationClipName}
            </span>
            <span style={{ fontSize: '12px', color: '#888' }}>
              duration {duration.toFixed(3)}s · distance {(config.xPositions[config.xPositions.length - 1] ?? 0).toFixed(2)}m ·
              avg speed {((config.xPositions[config.xPositions.length - 1] ?? 0) / Math.max(0.0001, duration)).toFixed(2)} m/s
            </span>
            <span style={{ fontSize: '12px', color: liveInIframe ? '#ff8888' : '#666' }}>
              t={liveTime.toFixed(3)}s ({(liveTimeFrac * 100).toFixed(0)}%) {liveInIframe && '· IFRAME'}
            </span>
            {isLoading && <span style={{ color: '#888', fontSize: 12 }}>(loading…)</span>}
            {loadError && <span style={{ color: '#f88', fontSize: 12 }}>{loadError}</span>}
          </div>
          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: '8px', overflow: 'hidden' }} ref={containerRef} />

          {/* Pose strip controls — X (cumulative distance) and Y (lift) */}
          <div style={{ background: '#2d2d44', borderRadius: 8, padding: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <span style={{ fontSize: 12, color: '#6b8afd', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                Per-pose X (cumulative m) / Y (lift m)
              </span>
              <span style={{ fontSize: 11, color: '#888' }}>
                {config.numPoses} poses across {duration.toFixed(2)}s · pose 0 locked at x=0
              </span>
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              {config.xPositions.map((xv, i) => {
                const tFrac = config.numPoses === 1 ? 0 : i / (config.numPoses - 1);
                const inIframe = isInIframeWindow(tFrac, config.iframeStart, config.iframeEnd);
                const yv = config.yOffsets[i] ?? 0;
                const tSeconds = tFrac * duration;
                const prev = i > 0 ? config.xPositions[i - 1] : 0;
                const dx = xv - prev;
                const isFirst = i === 0;
                return (
                  <div key={i} style={{
                    flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
                    background: inIframe ? '#3a1a1a' : 'transparent',
                    borderRadius: 4, padding: '4px 2px',
                  }}>
                    <span style={{ fontSize: 10, color: inIframe ? '#ff8888' : '#bbb', fontWeight: 'bold' }}>
                      {i}{inIframe ? ' ★' : ''}
                    </span>
                    <span style={{ fontSize: 9, color: '#666', fontVariantNumeric: 'tabular-nums' }}>
                      {tSeconds.toFixed(2)}s
                    </span>

                    {/* X (horizontal) slider */}
                    <span style={{ fontSize: 9, color: '#88a', marginTop: 2 }}>X</span>
                    <input
                      type="range"
                      min={0}
                      max={8}
                      step={0.05}
                      value={xv}
                      disabled={isFirst}
                      onChange={(e) => setXAt(i, parseFloat(e.target.value))}
                      style={{ width: '100%' }}
                    />
                    <span style={{ fontSize: 10, color: '#aaa', fontVariantNumeric: 'tabular-nums' }}>
                      {xv.toFixed(2)}
                    </span>
                    <span style={{ fontSize: 9, color: '#666', fontVariantNumeric: 'tabular-nums' }}>
                      Δ {isFirst ? '—' : (dx >= 0 ? '+' : '') + dx.toFixed(2)}
                    </span>

                    {/* Y (vertical) slider */}
                    <span style={{ fontSize: 9, color: '#8a8', marginTop: 4 }}>Y</span>
                    <input
                      type="range"
                      min={-0.5}
                      max={2.0}
                      step={0.01}
                      value={yv}
                      onChange={(e) => setYAt(i, parseFloat(e.target.value))}
                      style={{
                        WebkitAppearance: 'slider-vertical',
                        writingMode: 'vertical-lr' as React.CSSProperties['writingMode'],
                        height: 70,
                        width: 18,
                      }}
                    />
                    <span style={{ fontSize: 10, color: '#aaa', fontVariantNumeric: 'tabular-nums' }}>
                      {yv.toFixed(2)}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Right - Controls */}
        <div style={{
          width: '320px', background: '#2d2d44', borderRadius: '8px', padding: '12px',
          overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '14px',
        }}>
          {/* Weapon */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '10px' }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Weapon</h3>
            <select
              value={config.weapon}
              onChange={(e) => setConfig((c) => ({ ...c, weapon: e.target.value as WeaponKey }))}
              style={{
                width: '100%', padding: 8, background: '#1a1a2e', color: '#fff',
                border: '1px solid #444', borderRadius: 4, fontSize: 12,
              }}
            >
              {WEAPON_OPTIONS.map((w) => (
                <option key={w.id} value={w.id}>{w.label} ({w.animPrefix}_esc_f)</option>
              ))}
            </select>
          </div>

          {/* Visualization toggles */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '10px' }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>View</h3>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#aaa', marginBottom: 6 }}>
              <input type="checkbox" checked={showGhosts} onChange={(e) => setShowGhosts(e.target.checked)} />
              Ghost row (one per pose)
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#aaa', marginBottom: 8 }}>
              <input type="checkbox" checked={showLive} onChange={(e) => setShowLive(e.target.checked)} />
              Live preview
            </label>
            <button onClick={replay} disabled={!showLive} style={{
              padding: '8px 12px', width: '100%',
              background: showLive ? '#2d5a2d' : '#1a1a2e',
              border: showLive ? '1px solid #4a4' : '1px solid #444',
              borderRadius: 4, color: showLive ? '#6f6' : '#555',
              cursor: showLive ? 'pointer' : 'not-allowed', fontSize: 12, fontWeight: 'bold',
            }}>
              ▶ Replay live preview
            </button>
          </div>

          {/* Distance summary (read-only) — drive the X curve from the pose strip */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '10px' }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Distance</h3>
            <div style={{ fontSize: 11, color: '#aaa', marginBottom: 4 }}>
              Total: <strong>{(config.xPositions[config.xPositions.length - 1] ?? 0).toFixed(2)} m</strong>
              {' · '}
              avg {((config.xPositions[config.xPositions.length - 1] ?? 0) / Math.max(0.0001, duration)).toFixed(2)} m/s
            </div>
            <div style={{ fontSize: 10, color: '#666' }}>
              Tune X position per pose in the strip below the viewport.
              All horizontal motion happens during the {duration.toFixed(2)}s clip; once it
              ends the model parks at the final pose's X.
            </div>
            <div style={{ fontSize: 10, color: '#666', marginTop: 4 }}>
              In-game default: 4.00 m (DODGE_SPEED 5.0 × DODGE_DURATION 0.8)
            </div>
          </div>

          {/* I-frames */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '10px' }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>I-frame window</h3>
            <div style={{ fontSize: 11, color: '#888', marginBottom: 4 }}>
              {(config.iframeStart * 100).toFixed(0)}% – {(config.iframeEnd * 100).toFixed(0)}%
              ({(config.iframeStart * duration).toFixed(3)}s – {(config.iframeEnd * duration).toFixed(3)}s)
            </div>
            <label style={{ fontSize: 10, color: '#888' }}>Start</label>
            <input
              type="range" min={0} max={1} step={0.01}
              value={config.iframeStart}
              onChange={(e) => {
                const v = parseFloat(e.target.value);
                setConfig((c) => ({ ...c, iframeStart: Math.min(v, c.iframeEnd) }));
              }}
              style={{ width: '100%' }}
            />
            <label style={{ fontSize: 10, color: '#888' }}>End</label>
            <input
              type="range" min={0} max={1} step={0.01}
              value={config.iframeEnd}
              onChange={(e) => {
                const v = parseFloat(e.target.value);
                setConfig((c) => ({ ...c, iframeEnd: Math.max(v, c.iframeStart) }));
              }}
              style={{ width: '100%' }}
            />
            <div style={{ fontSize: 10, color: '#666', marginTop: 4 }}>
              Frames marked ★ in the pose strip are inside the i-frame window. Live model tints red while invincible.
            </div>
          </div>

          {/* Pose count */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '10px' }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Pose count</h3>
            <div style={{ fontSize: 11, color: '#888', marginBottom: 4 }}>
              {config.numPoses} samples (existing offsets are resampled when this changes)
            </div>
            <input
              type="range" min={3} max={16} step={1}
              value={config.numPoses}
              onChange={(e) => setNumPoses(parseInt(e.target.value, 10))}
              style={{ width: '100%' }}
            />
          </div>

          {/* Export / reset */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <button onClick={copyGdscript} style={{
              padding: '10px', background: '#2a4a6a', border: '1px solid #6b8afd',
              borderRadius: 4, color: '#fff', cursor: 'pointer', fontSize: 12, fontWeight: 'bold',
            }}>
              Copy GDScript constants
            </button>
            <button onClick={resetAll} style={{
              padding: '8px', background: '#1a1a2e', border: '1px solid #444',
              borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 12,
            }}>
              Reset to in-game defaults
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
