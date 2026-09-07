import { Suspense, useMemo, useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Grid } from '@react-three/drei';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import { applyObjectTextures, detachSkinnedBind } from '../elements/materials';

/**
 * FlapLab — a small workbench for the ambient critters' FLAP MECHANIC (#644).
 *
 * The models are single-frame unlit billboards (no embedded animation), so
 * the wing beat is ours to author and nobody has measured the original's
 * runtime code. The Godot port currently squeezes the quad on X; kion's
 * playtest says it doesn't read as wings flapping up and down. This page
 * loads the real GLB + texture and lets you drive every candidate mechanic
 * with live sliders, so the winner can be transplanted into
 * scripts/3d/elements/ambient_critter.gd.
 *
 * Mechanics: squeezeX (current port), squashY, see-saw (roll oscillation —
 * the "wings see-saw up and down" reading), pitch (nod), yaw (wobble), and
 * none. Billboard modes: off / yaw-only (the failed first attempt) / full
 * camera-facing (the current port). The bird link is here too — it carries
 * real wing joints, so its beat may want joint rotation instead.
 */

const MODELS = [
  { id: 'o0c_butterfly', label: 'Butterfly (o0c_butterfly)', scale: 6 },
  { id: 'o0c_dragonfly', label: 'Dragonfly (o0c_dragonfly)', scale: 6 },
  { id: 'o0c_bird', label: 'Bird (o0c_bird — jointed rig)', scale: 4 },
] as const;

const MECHANICS = ['none', 'squeezeX', 'squashY', 'seeSaw', 'pitch', 'yaw'] as const;
const FACINGS = ['off', 'yaw', 'full'] as const;

type Mechanic = (typeof MECHANICS)[number];
type Facing = (typeof FACINGS)[number];

interface Params {
  mechanic: Mechanic;
  facing: Facing;
  amplitude: number; // 0..1 — scale depth for squeezes, degrees for rotations
  flapHz: number;
  bob: number;
  driftRadius: number;
  driftSpeed: number;
  playing: boolean;
}

const DEFAULT_PARAMS: Params = {
  mechanic: 'squeezeX',
  facing: 'full',
  amplitude: 0.45,
  flapHz: 6,
  bob: 0.12,
  driftRadius: 0.35,
  driftSpeed: 0.4,
  playing: true,
};

function Critter({ model, params }: { model: string; params: Params }) {
  const group = useRef<THREE.Group>(null);
  const mesh = useRef<THREE.Object3D>(null);
  const t = useRef(0);

  const { scene } = useGLTF(assetUrl(`/assets/objects/special_z/${model}.glb`));
  const cloned = useMemo(() => {
    const root = scene.clone(true);
    applyObjectTextures(root);
    detachSkinnedBind(root);
    return root;
  }, [scene]);

  const meshTarget = useMemo(() => cloned.children[0] ?? cloned, [cloned]);

  useFrame((state, delta) => {
    if (params.playing) t.current += delta;
    const time = t.current;
    const flap = 0.5 + 0.5 * Math.sin(time * params.flapHz * Math.PI * 2);

    if (group.current) {
      const g = group.current;
      g.position.x = params.driftRadius * Math.sin(time * params.driftSpeed);
      g.position.z = params.driftRadius * 0.7 * Math.sin(time * params.driftSpeed * 0.618 + 2);
      g.position.y = params.bob * Math.sin(time * 2 * Math.PI * 0.9);
      if (params.facing !== 'off') {
        const toCam = state.camera.position.clone().sub(g.getWorldPosition(new THREE.Vector3()));
        if (params.facing === 'yaw') {
          g.rotation.y = Math.atan2(toCam.x, toCam.z);
        } else {
          g.lookAt(state.camera.position);
        }
      } else {
        g.rotation.set(0, 0, 0);
      }
    }
    if (meshTarget) {
      const m = meshTarget;
      m.rotation.set(0, 0, 0);
      m.scale.setScalar(1);
      switch (params.mechanic) {
        case 'squeezeX':
          m.scale.x = 1 - params.amplitude * flap;
          break;
        case 'squashY':
          m.scale.y = 1 - params.amplitude * flap;
          break;
        case 'seeSaw':
          m.rotation.z = THREE.MathUtils.degToRad(params.amplitude * 90) * (flap - 0.5);
          break;
        case 'pitch':
          m.rotation.x = THREE.MathUtils.degToRad(params.amplitude * 90) * (flap - 0.5);
          break;
        case 'yaw':
          m.rotation.y = THREE.MathUtils.degToRad(params.amplitude * 90) * (flap - 0.5);
          break;
      }
    }
    void mesh;
  });

  return (
    <group ref={group} position={[0, 1, 0]}>
      <primitive object={cloned} ref={mesh} />
    </group>
  );
}

function Slider({
  label, value, min, max, step, onChange,
}: {
  label: string; value: number; min: number; max: number; step: number;
  onChange: (v: number) => void;
}) {
  return (
    <label style={{ display: 'block', marginBottom: 8 }}>
      {label}: <strong>{value.toFixed(2)}</strong>
      <input
        type="range" min={min} max={max} step={step} value={value}
        style={{ width: '100%' }}
        onChange={(e) => onChange(parseFloat(e.target.value))}
      />
    </label>
  );
}

export default function FlapLab() {
  const [modelId, setModelId] = useState<string>('o0c_butterfly');
  const [params, setParams] = useState<Params>(DEFAULT_PARAMS);
  const model = MODELS.find((m) => m.id === modelId) ?? MODELS[0];
  const set = <K extends keyof Params>(key: K, value: Params[K]) =>
    setParams((p) => ({ ...p, [key]: value }));

  return (
    <div style={{ padding: 16 }}>
      <h2 style={{ marginTop: 0 }}>Flap Lab — ambient critter flap mechanic (#644)</h2>
      <p style={{ maxWidth: 720 }}>
        Every candidate mechanic against the real model. When one reads as the original's
        wings-beating-up-and-down, transplant its shape (the{' '}
        <code>switch</code> in <code>Critter</code>'s frame loop) into{' '}
        <code>scripts/3d/elements/ambient_critter.gd</code>. The pad on the ground is a
        1m reference.
      </p>
      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        <div style={{ width: 640, height: 480, border: '1px solid #444' }}>
          <Canvas camera={{ position: [2.5, 2, 3.5], fov: 45 }}>
            <color attach="background" args={['#202028']} />
            <ambientLight intensity={2} />
            <Suspense fallback={null}>
              <Critter model={model.id} params={params} />
            </Suspense>
            <mesh position={[0, 0.005, 0]} rotation={[-Math.PI / 2, 0, 0]}>
              <planeGeometry args={[1, 1]} />
              <meshBasicMaterial color="#666" transparent opacity={0.35} />
            </mesh>
            <Grid args={[8, 8]} cellColor="#3a3a44" sectionColor="#555" infiniteGrid />
            <OrbitControls target={[0, 1, 0]} />
          </Canvas>
        </div>
        <div style={{ width: 280 }}>
          <label style={{ display: 'block', marginBottom: 8 }}>
            Model{' '}
            <select value={modelId} onChange={(e) => setModelId(e.target.value)}>
              {MODELS.map((m) => (
                <option key={m.id} value={m.id}>{m.label}</option>
              ))}
            </select>
          </label>
          <label style={{ display: 'block', marginBottom: 8 }}>
            Mechanic{' '}
            <select value={params.mechanic} onChange={(e) => set('mechanic', e.target.value as Mechanic)}>
              {MECHANICS.map((m) => <option key={m}>{m}</option>)}
            </select>
          </label>
          <label style={{ display: 'block', marginBottom: 8 }}>
            Facing{' '}
            <select value={params.facing} onChange={(e) => set('facing', e.target.value as Facing)}>
              {FACINGS.map((f) => <option key={f}>{f}</option>)}
            </select>
          </label>
          <Slider label="Amplitude (scale or degrees/90)" value={params.amplitude}
            min={0} max={1} step={0.01} onChange={(v) => set('amplitude', v)} />
          <Slider label="Flap speed (Hz)" value={params.flapHz}
            min={0.5} max={20} step={0.5} onChange={(v) => set('flapHz', v)} />
          <Slider label="Bob amplitude" value={params.bob}
            min={0} max={1} step={0.01} onChange={(v) => set('bob', v)} />
          <Slider label="Drift radius" value={params.driftRadius}
            min={0} max={2} step={0.05} onChange={(v) => set('driftRadius', v)} />
          <Slider label="Drift speed" value={params.driftSpeed}
            min={0} max={2} step={0.05} onChange={(v) => set('driftSpeed', v)} />
          <button onClick={() => set('playing', !params.playing)}>
            {params.playing ? 'Pause' : 'Play'}
          </button>
          {' '}
          <button onClick={() => setParams(DEFAULT_PARAMS)}>Reset</button>
        </div>
      </div>
    </div>
  );
}
