import { Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { OrbitControls, useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import { clone as skeletonClone } from 'three/examples/jsm/utils/SkeletonUtils.js';
import { assetUrl } from '../utils/assets';
import { applyObjectTextures } from '../elements/materials';
import { detectLanterns } from '../stage-editor/lanternDetect';

/**
 * LightingLab — adaptive-lighting viability testbed for field/city rooms.
 *
 * The DS rooms are unlit (KHR_materials_unlit): final color is texture ×
 * COLOR_0, full stop. COLOR_0 therefore carries ALL of the shading — and it
 * was authored for one time of day. Snowfield's bake is heavily saturated
 * (mean sat ≈ 0.4–0.5): blue/purple tint in the snow shadows, not just AO.
 *
 * The experiment this page runs, per room:
 *  - LEFT  (unlit): the DS render — texture × COLOR_0, what ships today.
 *  - RIGHT (lit):   MeshStandardMaterial under a TimeManager-preset rig
 *                   (hemisphere ambient + directional sun, values mirrored
 *                   from time_manager.gd so results translate to Godot).
 * The COLOR_0 strategy is the thesis: keep the authored CHROMA (the blue
 * shadow tint) but hand the LUMINANCE job to the dynamic lights, instead of
 * the whole bake fighting the rig. The room GLBs carry no NORMAL attribute
 * (the exporter assumed unlit), so the lit side runs on computed normals —
 * viability of that is itself a result of this page.
 */

type VcStrategy = 'original' | 'chroma' | 'ao' | 'white';
type PhaseKey = 'day' | 'sunset' | 'night' | 'sunrise';
type ViewMode = 'unlit' | 'lit' | 'lambert' | 'phong';

interface StageDef {
  id: string;
  label: string;
  path: string;
}

const STAGES: StageDef[] = [
  { id: 's03a_ic1', label: 'Snowfield A · ic1 (enclosed mid)', path: 'assets/stages/snowfield_a/s03a_ic1/lndmd/s03a_ic1_m.glb' },
  { id: 's03a_sa1', label: 'Snowfield A · sa1 (start)', path: 'assets/stages/snowfield_a/s03a_sa1/lndmd/s03a_sa1_m.glb' },
  { id: 's03a_ga1', label: 'Snowfield A · ga1 (goal)', path: 'assets/stages/snowfield_a/s03a_ga1/lndmd/s03a_ga1_m.glb' },
  { id: 's03a_na1', label: 'Snowfield A · na1 (boss)', path: 'assets/stages/snowfield_a/s03a_na1/lndmd/s03a_na1_m.glb' },
  { id: 's03b_ic1', label: 'Snowfield B · ic1 (enclosed mid)', path: 'assets/stages/snowfield_b/s03b_ic1/lndmd/s03b_ic1_m.glb' },
  { id: 's03b_ga1', label: 'Snowfield B · ga1 (goal)', path: 'assets/stages/snowfield_b/s03b_ga1/lndmd/s03b_ga1_m.glb' },
  { id: 's01b_ic1', label: 'Valley B · ic1 (contrast)', path: 'assets/stages/valley_b/s01b_ic1/lndmd/s01b_ic1_m.glb' },
  { id: 's00e_sa2', label: 'City E · sa2 (contrast)', path: 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb' },
];

/** Fixed luminance the chroma strategy normalises each vertex to. */
const CHROMA_TARGET_LUM = 0.78;

/** Snow flake count — sized for the lab's whole-room framing. */
const SNOW_COUNT = 1500;

interface PhaseDef {
  sky: string;
  ambient: string;
  ambientEnergy: number;
  sun: string;
  sunEnergy: number;
  elevation: number;
  azimuth: number;
}

/**
 * TimeManager's four configs (time_manager.gd), translated to a three.js
 * hemisphere + directional rig. light_pitch → sun elevation; azimuth is ours
 * (Godot derives it from the sky material orbit, not the table).
 */
const PHASES: Record<PhaseKey, PhaseDef> = {
  day: {
    sky: '#99b2a6', ambient: '#e6ebe0', ambientEnergy: 1.1,
    sun: '#fffaf0', sunEnergy: 0.5, elevation: 45, azimuth: 135,
  },
  sunset: {
    sky: '#f2732e', ambient: '#d98033', ambientEnergy: 0.55,
    sun: '#ff801a', sunEnergy: 0.7, elevation: 12, azimuth: 265,
  },
  night: {
    sky: '#0d141f', ambient: '#334073', ambientEnergy: 0.5,
    sun: '#99b3ff', sunEnergy: 0.25, elevation: 40, azimuth: 320,
  },
  sunrise: {
    sky: '#e68c4d', ambient: '#bf9973', ambientEnergy: 0.55,
    sun: '#ffb366', sunEnergy: 0.5, elevation: 12, azimuth: 80,
  },
};

interface Controls {
  view: ViewMode;
  strategy: VcStrategy;
  neutralize: number;
  phase: PhaseKey;
  ambientGain: number;
  sunGain: number;
  elevation: number;
  azimuth: number;
  ambientColor: string;
  sunColor: string;
  roughness: number;
  shininess: number;
  flatShading: boolean;
  exposure: number;
  fog: number;
  fires: boolean;
  fireIntensity: number;
  sunShadows: boolean;
  ambientOn: boolean;
  snow: boolean;
}

const DEFAULT_CONTROLS: Controls = {
  view: 'lit',
  strategy: 'original',
  neutralize: 0,
  phase: 'day',
  ambientGain: 1.5,
  sunGain: 2.8,
  elevation: PHASES.day.elevation,
  azimuth: PHASES.day.azimuth,
  ambientColor: PHASES.day.ambient,
  sunColor: PHASES.day.sun,
  roughness: 0.95,
  shininess: 30,
  flatShading: false,
  exposure: 1.1,
  fog: 0.25,
  fires: true,
  fireIntensity: 2.5,
  sunShadows: true,
  ambientOn: true,
  snow: true,
};

interface RoomStats {
  verts: number;
  prims: number;
  lumMin: number;
  lumP10: number;
  lumMed: number;
  lumP90: number;
  lumMax: number;
  meanSat: number;
  maxSat: number;
  meanR: number;
  meanG: number;
  meanB: number;
  histogram: number[]; // 48 bins over luminance 0..1
}

function luminance(r: number, g: number, b: number): number {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function quantile(sorted: number[], q: number): number {
  return sorted[Math.round(q * (sorted.length - 1))];
}

/** Collect COLOR_0 stats + histogram from a prepared room node (reads the
 * untouched original color copy each mesh stashes in its geometry userData). */
function collectStats(meshes: THREE.Mesh[]): RoomStats | null {
  let verts = 0;
  const lums: number[] = [];
  let satSum = 0;
  let maxSat = 0;
  let rSum = 0;
  let gSum = 0;
  let bSum = 0;
  for (const mesh of meshes) {
    const attr = mesh.geometry.attributes.color as THREE.BufferAttribute | undefined;
    if (!attr) continue;
    const orig = (mesh.geometry.userData.origColors as Uint8Array | undefined)
      ?? (attr.array as Uint8Array);
    for (let i = 0; i < orig.length; i += 3) {
      const r = orig[i] / 255, g = orig[i + 1] / 255, b = orig[i + 2] / 255;
      lums.push(luminance(r, g, b));
      const sat = Math.max(r, g, b) - Math.min(r, g, b);
      satSum += sat;
      if (sat > maxSat) maxSat = sat;
      rSum += r;
      gSum += g;
      bSum += b;
    }
    verts += attr.count;
  }
  if (!lums.length) return null;
  const sorted = [...lums].sort((a, b) => a - b);
  const bins = new Array(48).fill(0);
  for (const l of lums) bins[Math.min(47, Math.floor(l * 48))]++;
  return {
    verts,
    prims: meshes.length,
    lumMin: sorted[0],
    lumP10: quantile(sorted, 0.1),
    lumMed: quantile(sorted, 0.5),
    lumP90: quantile(sorted, 0.9),
    lumMax: sorted[sorted.length - 1],
    meanSat: satSum / lums.length,
    maxSat,
    meanR: rSum / lums.length,
    meanG: gSum / lums.length,
    meanB: bSum / lums.length,
    histogram: bins,
  };
}


/**
 * The fire rig: one flickering point light + additive glow per lantern.
 * The light is the point — judging how a red-orange pool reads against each
 * time-of-day preset — so the "flame" is a deliberately cheap billboard.
 */
function LampFires({ lamps, ctrl }: { lamps: THREE.Vector3[]; ctrl: Controls }) {
  const lights = useRef<(THREE.PointLight | null)[]>([]);
  const glows = useRef<(THREE.MeshBasicMaterial | null)[]>([]);

  useFrame(({ clock }) => {
    const t = clock.elapsedTime;
    // Visible but calm flicker: slow organic wander (the mixed product) plus
    // a faster sparkle term — peaks around ±12%.
    for (let i = 0; i < lamps.length; i++) {
      const f = 0.93
        + 0.08 * Math.sin(t * 7 + i * 1.7) * Math.sin(t * 3.1 + i * 2.1)
        + 0.04 * Math.sin(t * 15 + i * 4.3);
      const light = lights.current[i];
      if (light) light.intensity = ctrl.fireIntensity * 100 * f;
      const glow = glows.current[i];
      if (glow) glow.opacity = 0.24 + 0.1 * f;
    }
  });

  return (
    <>
      {lamps.map((p, i) => (
        <group key={i} position={p}>
          <pointLight
            ref={(l) => { lights.current[i] = l; }}
            color="#ff3b1f"
            intensity={ctrl.fireIntensity * 100}
            distance={22}
            decay={2}
          />
          <mesh>
            <sphereGeometry args={[0.22, 8, 8]} />
            <meshBasicMaterial color="#ffb340" toneMapped={false} fog={false} />
          </mesh>
          <mesh>
            <sphereGeometry args={[0.5, 8, 8]} />
            <meshBasicMaterial
              ref={(m) => { glows.current[i] = m; }}
              color="#ff4a1c"
              transparent
              opacity={0.3}
              blending={THREE.AdditiveBlending}
              toneMapped={false}
              fog={false}
              depthWrite={false}
            />
          </mesh>
        </group>
      ))}
    </>
  );
}

/**
 * Falling snow — a room-sized CPU particle field. Fall speeds mirror the
 * Godot weather rig (2–3.5 u/s, weather_controller.gd's snow GPUParticles),
 * with per-flake sway; the count is higher than Godot's 300 because the
 * lab frames the whole room instead of a player-attached volume.
 */
function Snow({ radius, top }: { radius: number; top: number }) {
  const count = SNOW_COUNT;
  const geo = useMemo(() => {
    const pos = new Float32Array(count * 3);
    // speed, sway phase, sway amplitude, sway frequency scale
    const meta = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) {
      pos[i * 3] = (Math.random() * 2 - 1) * radius;
      pos[i * 3 + 1] = Math.random() * top;
      pos[i * 3 + 2] = (Math.random() * 2 - 1) * radius;
      meta[i * 4] = 2 + Math.random() * 1.5;
      meta[i * 4 + 1] = Math.random() * Math.PI * 2;
      meta[i * 4 + 2] = 0.3 + Math.random() * 0.7;
      meta[i * 4 + 3] = 0.5 + Math.random();
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.userData.meta = meta;
    return g;
  }, [count, radius, top]);

  // Soft round flake sprite.
  const sprite = useMemo(() => {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 32;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    const grad = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
    grad.addColorStop(0, 'rgba(255,255,255,0.95)');
    grad.addColorStop(0.5, 'rgba(255,255,255,0.4)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 32, 32);
    return new THREE.CanvasTexture(canvas);
  }, []);

  useFrame((_, delta) => {
    const arr = geo.attributes.position.array as Float32Array;
    const meta = geo.userData.meta as Float32Array;
    const t = performance.now() / 1000;
    const step = Math.min(delta, 0.1);
    for (let i = 0; i < count; i++) {
      const speed = meta[i * 4];
      const phase = meta[i * 4 + 1];
      const amp = meta[i * 4 + 2];
      const fw = meta[i * 4 + 3];
      arr[i * 3 + 1] -= speed * step;
      arr[i * 3] += Math.sin(t * 0.9 * fw + phase) * amp * step * 2;
      arr[i * 3 + 2] += Math.cos(t * 0.7 * fw + phase * 1.3) * amp * step;
      if (arr[i * 3 + 1] < 0) {
        arr[i * 3 + 1] += top;
        arr[i * 3] = (Math.random() * 2 - 1) * radius;
        arr[i * 3 + 2] = (Math.random() * 2 - 1) * radius;
      }
    }
    geo.attributes.position.needsUpdate = true;
  });

  return (
    <points geometry={geo} frustumCulled={false}>
      <pointsMaterial
        map={sprite ?? undefined}
        size={0.55}
        sizeAttenuation
        transparent
        opacity={0.85}
        depthWrite={false}
      />
    </points>
  );
}

interface RoomProps {
  def: StageDef;
  mode: 'unlit' | 'standard' | 'lambert' | 'phong';
  ctrl: Controls;
  onReady?: (meshes: THREE.Mesh[], box: THREE.Box3, lamps: THREE.Vector3[]) => void;
}

/**
 * The room on stage. The GLTF cache is shared, so each load clones the
 * scene (SkeletonUtils — the rooms are skinned) AND clones every geometry:
 * the primitives share one COLOR_0 accessor and rewrites happen in place.
 */
function Room({ def, mode, ctrl, onReady }: RoomProps) {
  const { scene } = useGLTF(assetUrl(def.path));

  const prepared = useMemo(() => {
    const node = skeletonClone(scene);
    applyObjectTextures(node);
    const meshes: THREE.Mesh[] = [];
    node.traverse((child) => {
      const mesh = child as THREE.Mesh;
      if (!mesh.isMesh) return;
      mesh.geometry = mesh.geometry.clone();
      mesh.geometry.userData.origColors = Uint8Array.from(
        (mesh.geometry.attributes.color as THREE.BufferAttribute).array as Uint8Array,
      );
      // The exporter wrote no NORMALs (unlit materials don't need them); the
      // lit rig does. Computed smooth normals — DS rooms are low-poly enough
      // that this reads as the intended look, and flatShading stays available
      // as the fallback comparison.
      if (!mesh.geometry.attributes.normal) mesh.geometry.computeVertexNormals();
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      meshes.push(mesh);
    });
    return { node, meshes };
  }, [scene]);

  // Box and lamp anchors are measured in the room's own coordinates after
  // the skeleton resolves (matrixWorld composed from the cloned root).
  useEffect(() => {
    prepared.node.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(prepared.node);
    const lamps = detectLanterns(prepared.node);
    onReady?.(prepared.meshes, box, lamps);
  }, [prepared, onReady]);

  // Materials per view: unlit keeps the DS render; standard, lambert and
  // phong are the three adaptive candidates (PBR, cheap diffuse, specular).
  // The source NAME is copied because lamp discovery re-runs under React
  // StrictMode's second effect pass, after these replacements — unnamed
  // materials would make the name-based lamp lookup miss.
  useEffect(() => {
    for (const mesh of prepared.meshes) {
      const src = mesh.material as THREE.MeshBasicMaterial;
      const shared = {
        map: src.map,
        name: src.name,
        vertexColors: true,
        alphaTest: src.alphaTest,
        transparent: src.transparent,
        side: src.side,
        color: 0xffffff,
      };
      if (mode === 'unlit') {
        mesh.material = new THREE.MeshBasicMaterial({ ...shared, fog: false });
      } else if (mode === 'lambert') {
        mesh.material = new THREE.MeshLambertMaterial({ ...shared, flatShading: ctrl.flatShading });
      } else if (mode === 'phong') {
        mesh.material = new THREE.MeshPhongMaterial({
          ...shared,
          specular: new THREE.Color('#556677'),
          shininess: ctrl.shininess,
          flatShading: ctrl.flatShading,
        });
      } else {
        mesh.material = new THREE.MeshStandardMaterial({
          ...shared, metalness: 0, roughness: ctrl.roughness, flatShading: ctrl.flatShading,
        });
      }
    }
  }, [prepared, mode]); // eslint-disable-line react-hooks/exhaustive-deps

  // Live material tweaks without rebuilding.
  useEffect(() => {
    for (const mesh of prepared.meshes) {
      const mat = mesh.material as THREE.MeshStandardMaterial;
      if (mat.isMeshStandardMaterial) {
        mat.roughness = ctrl.roughness;
        if (mat.flatShading !== ctrl.flatShading) {
          mat.flatShading = ctrl.flatShading;
          mat.needsUpdate = true;
        }
      }
      const phong = mesh.material as THREE.MeshPhongMaterial;
      if (phong.isMeshPhongMaterial && phong.shininess !== ctrl.shininess) {
        phong.shininess = ctrl.shininess;
        if (phong.flatShading !== ctrl.flatShading) {
          phong.flatShading = ctrl.flatShading;
          phong.needsUpdate = true;
        }
      }
      const lambert = mesh.material as THREE.MeshLambertMaterial;
      if (lambert.isMeshLambertMaterial && lambert.flatShading !== ctrl.flatShading) {
        lambert.flatShading = ctrl.flatShading;
        lambert.needsUpdate = true;
      }
    }
  }, [prepared, ctrl.roughness, ctrl.shininess, ctrl.flatShading]);

  // The COLOR_0 strategy — rewritten in place against the stashed originals.
  useEffect(() => {
    for (const mesh of prepared.meshes) {
      const attr = mesh.geometry.attributes.color as THREE.BufferAttribute;
      const orig = mesh.geometry.userData.origColors as Uint8Array;
      const arr = attr.array as Uint8Array;
      for (let i = 0; i < orig.length; i += 3) {
        let r = orig[i] / 255, g = orig[i + 1] / 255, b = orig[i + 2] / 255;
        if (ctrl.strategy === 'white') {
          r = g = b = 1;
        } else if (ctrl.strategy === 'ao') {
          const l = luminance(r, g, b);
          r = g = b = l;
        } else if (ctrl.strategy === 'chroma') {
          // Keep hue + channel ratios; pin brightness. Near-black vertices
          // have no readable chroma — lift them to flat grey instead of
          // amplifying quantisation noise.
          const mx = Math.max(r, g, b);
          if (mx < 0.02) {
            r = g = b = CHROMA_TARGET_LUM;
          } else {
            r = (r / mx) * CHROMA_TARGET_LUM;
            g = (g / mx) * CHROMA_TARGET_LUM;
            b = (b / mx) * CHROMA_TARGET_LUM;
          }
        }
        const t = ctrl.strategy === 'white' ? 0 : ctrl.neutralize;
        r += (1 - r) * t;
        g += (1 - g) * t;
        b += (1 - b) * t;
        arr[i] = Math.round(r * 255);
        arr[i + 1] = Math.round(g * 255);
        arr[i + 2] = Math.round(b * 255);
      }
      attr.needsUpdate = true;
    }
  }, [prepared, ctrl.strategy, ctrl.neutralize]);

  return <primitive object={prepared.node} />;
}

/** Hemisphere + directional rig; numbers start from the TimeManager preset
 * and scale through the gain sliders. Ambient/sun colors are live controls
 * (seeded by the preset) so the rig can be hand-tuned toward the bake. The
 * sun casts — a flat floor under a shadowless directional is a uniform wash,
 * which reads as "no lighting"; the shadows are what make ground response
 * visible. */
function LightingRig({ ctrl, radius }: { ctrl: Controls; radius: number }) {
  const sunRef = useRef<THREE.DirectionalLight>(null);
  const phase = PHASES[ctrl.phase];

  useEffect(() => {
    const light = sunRef.current;
    if (!light) return;
    // Shadow frustum sized to the room — one ortho sun covering the stage.
    const cam = light.shadow.camera;
    cam.left = -radius;
    cam.right = radius;
    cam.top = radius;
    cam.bottom = -radius;
    cam.near = 1;
    cam.far = radius * 4;
    cam.updateProjectionMatrix();
    light.shadow.mapSize.set(2048, 2048);
    // The DS rooms are chunky low-poly; normalBias kills the acne that
    // plain bias would only trade for peter-panning here.
    light.shadow.normalBias = 0.6;
    light.shadow.bias = -0.0004;
  }, [radius]);

  const el = THREE.MathUtils.degToRad(ctrl.elevation);
  const az = THREE.MathUtils.degToRad(ctrl.azimuth);
  const dir = new THREE.Vector3(Math.cos(el) * Math.cos(az), Math.sin(el), Math.cos(el) * Math.sin(az));
  const sunPos = dir.multiplyScalar(radius * 1.8);
  const ground = new THREE.Color(ctrl.ambientColor).multiplyScalar(0.55);

  return (
    <>
      <hemisphereLight
        color={ctrl.ambientColor}
        groundColor={ground}
        intensity={ctrl.ambientOn ? phase.ambientEnergy * ctrl.ambientGain : 0}
      />
      <directionalLight
        ref={sunRef}
        position={sunPos}
        color={ctrl.sunColor}
        intensity={phase.sunEnergy * ctrl.sunGain}
        castShadow={ctrl.sunShadows}
      />
    </>
  );
}

function SceneEffects({ ctrl, radius }: { ctrl: Controls; radius: number }) {
  const scene = useThree((s) => s.scene);
  const gl = useThree((s) => s.gl);
  const phase = PHASES[ctrl.phase];

  useEffect(() => {
    gl.toneMappingExposure = ctrl.exposure;
  }, [gl, ctrl.exposure]);

  useEffect(() => {
    const tint = new THREE.Color(phase.sky);
    if (ctrl.fog > 0.01) {
      const far = THREE.MathUtils.lerp(radius * 9, radius * 1.25, ctrl.fog);
      scene.fog = new THREE.Fog(tint, radius * 1.1, far);
    } else {
      scene.fog = null;
    }
  }, [scene, phase.sky, ctrl.fog, radius]);

  return (
    <color attach="background" args={[phase.sky]} />
  );
}

/** Frame the camera on whatever is currently on stage (single room or the
 * side-by-side pair) whenever the stage or view mode changes. */
function FitCamera({ target, radius }: { target: THREE.Vector3; radius: number }) {
  const camera = useThree((s) => s.camera);
  const controls = useThree((s) => s.controls) as { target: THREE.Vector3; update: () => void } | null;

  useEffect(() => {
    camera.position.set(
      target.x + radius * 0.85,
      target.y + radius * 0.6,
      target.z + radius * 0.85,
    );
    camera.lookAt(target);
    if (controls) {
      controls.target.copy(target);
      controls.update();
    }
  }, [camera, controls, target, radius]);

  return null;
}

function Slider(props: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
}) {
  const { label, value, min, max, step, onChange } = props;
  return (
    <label style={{ display: 'block', marginBottom: 6, fontSize: 12 }}>
      {label}{' '}
      <b>{step < 1 ? value.toFixed(2) : Math.round(value)}</b>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ width: '100%' }}
      />
    </label>
  );
}

export default function LightingLab() {
  const [stageId, setStageId] = useState(STAGES[0].id);
  const [ctrl, setCtrl] = useState<Controls>(DEFAULT_CONTROLS);
  const [stats, setStats] = useState<RoomStats | null>(null);
  const [stageBox, setStageBox] = useState<THREE.Box3 | null>(null);
  const [lamps, setLamps] = useState<THREE.Vector3[]>([]);
  const [peek, setPeek] = useState(false);
  const def = STAGES.find((s) => s.id === stageId) ?? STAGES[0];
  const set = <K extends keyof Controls>(key: K, value: Controls[K]) =>
    setCtrl((c) => ({ ...c, [key]: value }));

  const onReady = useRef((meshes: THREE.Mesh[], box: THREE.Box3, fires: THREE.Vector3[]) => {
    setStageBox(box.clone());
    setStats(collectStats(meshes));
    setLamps(fires);
  });
  useEffect(() => {
    onReady.current = (meshes, box, fires) => {
      setStageBox(box.clone());
      setStats(collectStats(meshes));
      setLamps(fires);
    };
  }, []);

  const applyPhase = (phase: PhaseKey) => {
    const p = PHASES[phase];
    // Presets re-seed the rig, including colors — hand-tuning then drifts
    // them for the bake-recreation workflow.
    setCtrl((c) => ({
      ...c, phase, elevation: p.elevation, azimuth: p.azimuth,
      ambientColor: p.ambient, sunColor: p.sun,
    }));
  };

  // Stage framing from the MEASURED mesh bounds — the room GLBs run 135–150
  // units across (view walls included), so the camera distance has to scale
  // per room. The default covers the first frame before the box arrives.
  const layout = useMemo(() => {
    if (!stageBox) return { radius: 105, target: new THREE.Vector3(0, 2, 0) };
    const size = stageBox.getSize(new THREE.Vector3());
    const center = stageBox.getCenter(new THREE.Vector3());
    return {
      radius: Math.max(size.x, size.z, size.y * 2.2) * 0.62,
      target: center,
    };
  }, [stageBox]);

  const histogramRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = histogramRef.current;
    if (!canvas || !stats) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const { width, height } = canvas;
    ctx.clearRect(0, 0, width, height);
    const max = Math.max(...stats.histogram);
    const binW = width / stats.histogram.length;
    ctx.fillStyle = '#7ab8e8';
    stats.histogram.forEach((count, i) => {
      const h = (count / max) * (height - 12);
      ctx.fillRect(i * binW, height - h, binW - 0.5, h);
    });
    ctx.strokeStyle = '#555';
    ctx.strokeRect(0.5, 0.5, width - 1, height - 1);
    ctx.fillStyle = '#888';
    ctx.font = '9px monospace';
    ctx.fillText('0', 2, height - 2);
    ctx.fillText('COLOR_0 luminance → 1', width - 108, height - 2);
  }, [stats]);

  return (
    <div style={{ display: 'flex', height: '100%' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <Canvas shadows camera={{ position: [22, 16, 22], fov: 45, near: 0.1, far: 400 }}>
          <Suspense fallback={null}>
            <Room
              def={def}
              mode={peek ? 'unlit'
                : ctrl.view === 'unlit' ? 'unlit'
                : ctrl.view === 'lambert' ? 'lambert'
                : ctrl.view === 'phong' ? 'phong'
                : 'standard'}
              ctrl={ctrl}
              onReady={onReady.current}
            />
          </Suspense>
          {ctrl.view !== 'unlit' && ctrl.fires && <LampFires lamps={lamps} ctrl={ctrl} />}
          {ctrl.snow && (
            <Snow radius={layout.radius} top={stageBox ? stageBox.getSize(new THREE.Vector3()).y + 6 : 30} />
          )}
          <LightingRig ctrl={ctrl} radius={layout.radius} />
          <SceneEffects ctrl={ctrl} radius={layout.radius} />
          <FitCamera target={layout.target} radius={layout.radius} />
          <OrbitControls makeDefault />
        </Canvas>
        <div style={{
          position: 'absolute', left: 12, top: 10, padding: '2px 8px',
          background: 'rgba(0,0,0,0.55)',
          color: ctrl.view === 'unlit' ? '#f7d78a' : '#8ae8c0',
          fontSize: 12, borderRadius: 4,
        }}>
          {(peek || ctrl.view === 'unlit')
            ? 'UNLIT — texture × COLOR_0 (the DS render)'
            : `${ctrl.view.toUpperCase()} — ${ctrl.strategy} colors, ${ctrl.phase} rig${ctrl.fires && lamps.length ? `, ${lamps.length} fires` : ''}`}
        </div>
      </div>

      <div style={{ width: 320, padding: 12, background: '#18181e', color: '#ddd', fontSize: 12, overflowY: 'auto' }}>
        <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Lighting Lab</h3>
        <p style={{ margin: '0 0 10px', color: '#999', lineHeight: 1.45 }}>
          Can the snowfield rooms go adaptive? Toggle between the DS unlit
          render and the same mesh re-lit. Neutralise the baked luminance,
          keep the authored chroma, and drive brightness from the rig.
        </p>

        <label style={{ display: 'block', marginBottom: 8 }}>
          Room{' '}
          <select value={stageId} onChange={(e) => setStageId(e.target.value)}>
            {STAGES.map((s) => (
              <option key={s.id} value={s.id}>{s.label}</option>
            ))}
          </select>
        </label>

        <label style={{ display: 'block', marginBottom: 8 }}>
          View{' '}
          <select value={ctrl.view} onChange={(e) => set('view', e.target.value as ViewMode)}>
            <option value="unlit">unlit — DS render</option>
            <option value="lit">lit — standard material</option>
            <option value="lambert">lambert — cheap diffuse</option>
            <option value="phong">phong — specular highlights</option>
          </select>
        </label>

        <div style={{ borderTop: '1px solid #333', margin: '10px 0', paddingTop: 8 }}>
          <label style={{ display: 'block', marginBottom: 6 }}>
            COLOR_0 strategy{' '}
            <select value={ctrl.strategy} onChange={(e) => set('strategy', e.target.value as VcStrategy)}>
              <option value="original">original bake</option>
              <option value="chroma">chroma only (pin luminance)</option>
              <option value="ao">luminance only (AO inspect)</option>
              <option value="white">white (pure dynamic)</option>
            </select>
          </label>
          <Slider label="Neutralize → white" value={ctrl.neutralize}
            min={0} max={1} step={0.01} onChange={(v) => set('neutralize', v)} />
        </div>

        <div style={{ borderTop: '1px solid #333', margin: '10px 0', paddingTop: 8 }}>
          <label style={{ display: 'block', marginBottom: 6 }}>
            Time-of-day preset{' '}
            <select value={ctrl.phase} onChange={(e) => applyPhase(e.target.value as PhaseKey)}>
              {Object.keys(PHASES).map((p) => (
                <option key={p} value={p}>{p}</option>
              ))}
            </select>
          </label>
          <Slider label="Ambient gain" value={ctrl.ambientGain}
            min={0} max={4} step={0.05} onChange={(v) => set('ambientGain', v)} />
          <label style={{ display: 'block', marginBottom: 6, fontSize: 12 }}>
            <input type="checkbox" checked={ctrl.ambientOn}
              onChange={(e) => set('ambientOn', e.target.checked)} />{' '}
            ambient light (off = fires + sun only)
          </label>
          <Slider label="Sun gain" value={ctrl.sunGain}
            min={0} max={8} step={0.05} onChange={(v) => set('sunGain', v)} />
          <Slider label="Sun elevation (°)" value={ctrl.elevation}
            min={5} max={85} step={1} onChange={(v) => set('elevation', v)} />
          <Slider label="Sun azimuth (°)" value={ctrl.azimuth}
            min={0} max={360} step={1} onChange={(v) => set('azimuth', v)} />
          <label style={{ display: 'block', marginBottom: 6, fontSize: 12 }}>
            <input type="checkbox" checked={ctrl.sunShadows}
              onChange={(e) => set('sunShadows', e.target.checked)} />{' '}
            sun shadows — the ground only reads as lit through them
          </label>
          <label style={{ display: 'block', marginBottom: 6, fontSize: 12 }}>
            <input type="checkbox" checked={ctrl.snow}
              onChange={(e) => set('snow', e.target.checked)} />{' '}
            falling snow (1500 flakes, Godot-speed fall)
          </label>
          <label style={{ display: 'block', marginBottom: 6, fontSize: 12 }}>
            ambient{' '}
            <input type="color" value={ctrl.ambientColor}
              onChange={(e) => set('ambientColor', e.target.value)}
              style={{ verticalAlign: 'middle' }} />
            {'\u2002'}sun{' '}
            <input type="color" value={ctrl.sunColor}
              onChange={(e) => set('sunColor', e.target.value)}
              style={{ verticalAlign: 'middle' }} />
          </label>
          <button
            onPointerDown={() => setPeek(true)}
            onPointerUp={() => setPeek(false)}
            onPointerLeave={() => setPeek(false)}
            style={{ width: '100%', padding: '4px 0', marginBottom: 6, cursor: 'pointer' }}
          >
            hold: DS bake reference
          </button>
        </div>

        <div style={{ borderTop: '1px solid #333', margin: '10px 0', paddingTop: 8 }}>
          <label style={{ display: 'block', marginBottom: 6 }}>
            <input type="checkbox" checked={ctrl.fires}
              onChange={(e) => set('fires', e.target.checked)} />{' '}
            lamp fires{lamps.length ? ` — ${lamps.length} lanterns` : ' (none in this room)'}
          </label>
          {lamps.length > 0 && (
            <pre style={{ margin: '0 0 6px', fontSize: 10, color: '#777', maxHeight: 120, overflowY: 'auto' }}>
              {lamps.map((p) => `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`).join('\n')}
            </pre>
          )}
          <Slider label="Fire intensity" value={ctrl.fireIntensity}
            min={0} max={8} step={0.05} onChange={(v) => set('fireIntensity', v)} />
          {ctrl.view === 'unlit' && (
            <p style={{ margin: '0 0 6px', color: '#888', lineHeight: 1.4 }}>
              Lights need a lit view — switch to standard or lambert to see
              the pools against each time of day.
            </p>
          )}
        </div>

        <div style={{ borderTop: '1px solid #333', margin: '10px 0', paddingTop: 8 }}>
          <Slider label="Exposure" value={ctrl.exposure}
            min={0.2} max={3} step={0.05} onChange={(v) => set('exposure', v)} />
          <Slider label="Fog (snow haze)" value={ctrl.fog}
            min={0} max={1} step={0.01} onChange={(v) => set('fog', v)} />
          <Slider label="Roughness (standard)" value={ctrl.roughness}
            min={0.3} max={1} step={0.01} onChange={(v) => set('roughness', v)} />
          <Slider label="Shininess (phong)" value={ctrl.shininess}
            min={2} max={128} step={1} onChange={(v) => set('shininess', v)} />
          <label style={{ display: 'block', marginBottom: 6 }}>
            <input type="checkbox" checked={ctrl.flatShading}
              onChange={(e) => set('flatShading', e.target.checked)} />{' '}
            flat shading (vs computed smooth normals)
          </label>
        </div>

        <div style={{ borderTop: '1px solid #333', margin: '10px 0', paddingTop: 8 }}>
          <div style={{ color: '#999', marginBottom: 4 }}>COLOR_0 analysis — original bake</div>
          <canvas ref={histogramRef} width={288} height={64}
            style={{ width: '100%', background: '#101014', borderRadius: 4 }} />
          {stats && (
            <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 6 }}>
              <tbody>
                {[
                  ['vertices / prims', `${stats.verts} / ${stats.prims}`],
                  ['luminance p10 / med / p90', `${stats.lumP10.toFixed(2)} / ${stats.lumMed.toFixed(2)} / ${stats.lumP90.toFixed(2)}`],
                  ['luminance min / max', `${stats.lumMin.toFixed(2)} / ${stats.lumMax.toFixed(2)}`],
                  ['saturation mean / max', `${stats.meanSat.toFixed(2)} / ${stats.maxSat.toFixed(2)}`],
                ].map(([k, v]) => (
                  <tr key={k}>
                    <td style={{ color: '#999', padding: '2px 0' }}>{k}</td>
                    <td style={{ textAlign: 'right', fontFamily: 'monospace' }}>{v}</td>
                  </tr>
                ))}
                <tr>
                  <td style={{ color: '#999', padding: '2px 0' }}>bake mean color</td>
                  <td style={{ textAlign: 'right' }}>
                    <span style={{
                      display: 'inline-block', width: 12, height: 12,
                      background: `rgb(${Math.round(stats.meanR * 255)},${Math.round(stats.meanG * 255)},${Math.round(stats.meanB * 255)})`,
                      border: '1px solid #555', verticalAlign: 'middle', marginRight: 4,
                    }} />
                    <span style={{ fontFamily: 'monospace' }}>
                      #{[stats.meanR, stats.meanG, stats.meanB].map((c) => Math.round(c * 255).toString(16).padStart(2, '0')).join('')}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          )}
          {stats && stats.meanSat > 0.15 && (
            <p style={{ margin: '8px 0 0', color: '#e8b87a', lineHeight: 1.4 }}>
              High saturation: this bake carries authored color (tinted snow
              shadows), not just occlusion — try <b>chroma only</b>.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
