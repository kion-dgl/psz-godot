/**
 * ParticleOverlay — Renders particle effects in the stage editor 3D canvas.
 *
 * Three categories:
 *   - placed:  localized emitters at specific x,z (mushroom spores, campfire sparks)
 *   - weather: global fill (snow, rain, sandstorm)
 *   - floor:   rise from ground across the whole stage area
 *
 * Placed effects include a point light that illuminates the area around them.
 * Supports click-to-place mode with a preview that follows the mouse.
 */

import { useRef, useMemo } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';

// ---------- Types ----------

interface BaseEffect {
  id: string;
  color: [number, number, number];
  count: number;
  speed: number;
  size: number;
}

export interface PlacedEffect extends BaseEffect {
  category: 'placed';
  preset: string;
  position: [number, number, number];
  radius: number;
  height: number;
  lightIntensity: number;
  lightRadius: number;
}

export interface WeatherEffect extends BaseEffect {
  category: 'weather';
  preset: 'snow' | 'rain' | 'sandstorm';
  area: number;
  height: number;
}

export interface FloorEffect extends BaseEffect {
  category: 'floor';
  preset: string;
  area: number;
  height: number;
}

export type ParticleEffect = PlacedEffect | WeatherEffect | FloorEffect;

// ---------- Shader ----------

const VERT = `
  attribute float aLife;
  attribute float aSize;
  varying float vAlpha;
  void main() {
    vAlpha = aLife;
    vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
    gl_PointSize = aSize * (200.0 / -mvPos.z);
    gl_Position = projectionMatrix * mvPos;
  }
`;

const FRAG = `
  varying float vAlpha;
  uniform vec3 uColor;
  void main() {
    float d = length(gl_PointCoord - vec2(0.5));
    if (d > 0.5) discard;
    float glow = smoothstep(0.5, 0.0, d);
    gl_FragColor = vec4(uColor, vAlpha * glow);
  }
`;

// ---------- Rising particle system (placed + floor) ----------

interface RisingSystemProps {
  effect: PlacedEffect | FloorEffect;
}

function RisingSystem({ effect }: RisingSystemProps) {
  const meshRef = useRef<THREE.Points>(null);
  const count = effect.count;
  const cx = effect.category === 'placed' ? effect.position[0] : 0;
  const cy = effect.category === 'placed' ? effect.position[1] : 0;
  const cz = effect.category === 'placed' ? effect.position[2] : 0;
  const radius = effect.category === 'placed' ? effect.radius : effect.area;

  const { positions, lifetimes, sizes, velocities } = useMemo(() => {
    const pos = new Float32Array(count * 3);
    const life = new Float32Array(count);
    const sz = new Float32Array(count);
    const vel = new Float32Array(count * 3);

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const r = Math.random() * radius;
      pos[i * 3] = cx + Math.cos(angle) * r;
      pos[i * 3 + 1] = cy + Math.random() * 0.5;
      pos[i * 3 + 2] = cz + Math.sin(angle) * r;

      life[i] = Math.random();
      sz[i] = effect.size * (0.6 + Math.random() * 0.8);

      vel[i * 3] = (Math.random() - 0.5) * 0.3;
      vel[i * 3 + 1] = effect.speed * (0.7 + Math.random() * 0.6);
      vel[i * 3 + 2] = (Math.random() - 0.5) * 0.3;
    }
    return { positions: pos, lifetimes: life, sizes: sz, velocities: vel };
  }, [count, radius, effect.speed, effect.size, cx, cy, cz]);

  const material = useMemo(() => {
    return new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG,
      uniforms: { uColor: { value: new THREE.Color(...effect.color) } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
  }, [effect.color]);

  useFrame((_, delta) => {
    if (!meshRef.current) return;
    const geo = meshRef.current.geometry;
    const posAttr = geo.getAttribute('position') as THREE.BufferAttribute;
    const lifeAttr = geo.getAttribute('aLife') as THREE.BufferAttribute;
    const posArr = posAttr.array as Float32Array;
    const lifeArr = lifeAttr.array as Float32Array;

    for (let i = 0; i < count; i++) {
      posArr[i * 3] += velocities[i * 3] * delta;
      posArr[i * 3 + 1] += velocities[i * 3 + 1] * delta;
      posArr[i * 3 + 2] += velocities[i * 3 + 2] * delta;

      lifeArr[i] -= delta / (effect.height / velocities[i * 3 + 1]);

      if (lifeArr[i] <= 0) {
        const angle = Math.random() * Math.PI * 2;
        const r = Math.random() * radius;
        posArr[i * 3] = cx + Math.cos(angle) * r;
        posArr[i * 3 + 1] = cy + Math.random() * 0.5;
        posArr[i * 3 + 2] = cz + Math.sin(angle) * r;
        lifeArr[i] = 0.8 + Math.random() * 0.2;
      }
    }
    posAttr.needsUpdate = true;
    lifeAttr.needsUpdate = true;
  });

  return (
    <group>
      <points ref={meshRef} material={material}>
        <bufferGeometry>
          <bufferAttribute attach="attributes-position" args={[positions, 3]} />
          <bufferAttribute attach="attributes-aLife" args={[lifetimes, 1]} />
          <bufferAttribute attach="attributes-aSize" args={[sizes, 1]} />
        </bufferGeometry>
      </points>
      {/* Point light for placed effects */}
      {effect.category === 'placed' && (effect as PlacedEffect).lightIntensity > 0 && (
        <pointLight
          position={[cx, cy + 2, cz]}
          color={new THREE.Color(...effect.color)}
          intensity={(effect as PlacedEffect).lightIntensity * 100}
          distance={0}
          decay={1.2}
        />
      )}
    </group>
  );
}

// ---------- Weather system ----------

interface WeatherSystemProps {
  effect: WeatherEffect;
}

function WeatherSystem({ effect }: WeatherSystemProps) {
  const meshRef = useRef<THREE.Points>(null);
  const count = effect.count;

  const { positions, lifetimes, sizes, velocities } = useMemo(() => {
    const pos = new Float32Array(count * 3);
    const life = new Float32Array(count);
    const sz = new Float32Array(count);
    const vel = new Float32Array(count * 3);

    for (let i = 0; i < count; i++) {
      pos[i * 3] = (Math.random() - 0.5) * effect.area * 2;
      pos[i * 3 + 1] = Math.random() * effect.height;
      pos[i * 3 + 2] = (Math.random() - 0.5) * effect.area * 2;

      life[i] = Math.random();
      sz[i] = effect.size * (0.5 + Math.random() * 1.0);

      switch (effect.preset) {
        case 'snow':
          vel[i * 3] = (Math.random() - 0.5) * 0.5;
          vel[i * 3 + 1] = -(effect.speed * (0.5 + Math.random() * 0.5));
          vel[i * 3 + 2] = (Math.random() - 0.5) * 0.5;
          break;
        case 'rain':
          vel[i * 3] = (Math.random() - 0.5) * 0.2;
          vel[i * 3 + 1] = -(effect.speed * (0.8 + Math.random() * 0.4));
          vel[i * 3 + 2] = (Math.random() - 0.5) * 0.2;
          break;
        case 'sandstorm':
          vel[i * 3] = effect.speed * (0.6 + Math.random() * 0.8);
          vel[i * 3 + 1] = (Math.random() - 0.5) * 0.3;
          vel[i * 3 + 2] = (Math.random() - 0.5) * 0.6;
          break;
      }
    }
    return { positions: pos, lifetimes: life, sizes: sz, velocities: vel };
  }, [count, effect.area, effect.height, effect.speed, effect.size, effect.preset]);

  const material = useMemo(() => {
    const blending = effect.preset === 'sandstorm' ? THREE.NormalBlending : THREE.AdditiveBlending;
    return new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG,
      uniforms: { uColor: { value: new THREE.Color(...effect.color) } },
      transparent: true, depthWrite: false, blending,
    });
  }, [effect.color, effect.preset]);

  useFrame((_, delta) => {
    if (!meshRef.current) return;
    const geo = meshRef.current.geometry;
    const posAttr = geo.getAttribute('position') as THREE.BufferAttribute;
    const lifeAttr = geo.getAttribute('aLife') as THREE.BufferAttribute;
    const posArr = posAttr.array as Float32Array;
    const lifeArr = lifeAttr.array as Float32Array;
    const halfArea = effect.area;

    for (let i = 0; i < count; i++) {
      posArr[i * 3] += velocities[i * 3] * delta;
      posArr[i * 3 + 1] += velocities[i * 3 + 1] * delta;
      posArr[i * 3 + 2] += velocities[i * 3 + 2] * delta;

      const outOfBounds = Math.abs(posArr[i * 3]) > halfArea
        || Math.abs(posArr[i * 3 + 2]) > halfArea
        || posArr[i * 3 + 1] < 0
        || posArr[i * 3 + 1] > effect.height;

      if (outOfBounds) {
        posArr[i * 3] = (Math.random() - 0.5) * halfArea * 2;
        posArr[i * 3 + 2] = (Math.random() - 0.5) * halfArea * 2;
        if (effect.preset === 'sandstorm') {
          posArr[i * 3] = -halfArea;
          posArr[i * 3 + 1] = Math.random() * effect.height * 0.5;
        } else {
          posArr[i * 3 + 1] = effect.height;
        }
        lifeArr[i] = 0.8 + Math.random() * 0.2;
      }
    }
    posAttr.needsUpdate = true;
    lifeAttr.needsUpdate = true;
  });

  return (
    <points ref={meshRef} material={material}>
      <bufferGeometry>
        <bufferAttribute attach="attributes-position" args={[positions, 3]} />
        <bufferAttribute attach="attributes-aLife" args={[lifetimes, 1]} />
        <bufferAttribute attach="attributes-aSize" args={[sizes, 1]} />
      </bufferGeometry>
    </points>
  );
}

// ---------- Placement preview (follows mouse) ----------

function PlacementPreview({ preset, color }: { preset: string; color: [number, number, number] }) {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  useFrame(() => {
    if (!groupRef.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 0, intersection.z);
    }
  });

  return (
    <group ref={groupRef}>
      {/* Ring showing emitter radius */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.05, 0]}>
        <ringGeometry args={[2.8, 3, 32]} />
        <meshBasicMaterial color={new THREE.Color(...color)} transparent opacity={0.5} side={THREE.DoubleSide} />
      </mesh>
      {/* Center dot */}
      <mesh position={[0, 0.1, 0]}>
        <sphereGeometry args={[0.2, 8, 8]} />
        <meshBasicMaterial color={new THREE.Color(...color)} />
      </mesh>
      {/* Label */}
      <sprite position={[0, 1.5, 0]} scale={[2, 0.5, 1]}>
        <spriteMaterial color={new THREE.Color(...color)} transparent opacity={0.7} />
      </sprite>
    </group>
  );
}

// ---------- Emitter marker (clickable ring for selecting placed effects) ----------

function EmitterMarker({ effect, selected, onClick }: {
  effect: PlacedEffect; selected: boolean; onClick: () => void;
}) {
  const col = new THREE.Color(...effect.color);
  return (
    <group position={effect.position}>
      <mesh
        rotation={[-Math.PI / 2, 0, 0]}
        position={[0, 0.05, 0]}
        onClick={(e) => { e.stopPropagation(); onClick(); }}
      >
        <ringGeometry args={[effect.radius - 0.15, effect.radius, 32]} />
        <meshBasicMaterial
          color={selected ? new THREE.Color('#4a9eff') : col}
          transparent opacity={selected ? 0.8 : 0.4}
          side={THREE.DoubleSide}
        />
      </mesh>
      {/* Center pip */}
      <mesh position={[0, 0.1, 0]} onClick={(e) => { e.stopPropagation(); onClick(); }}>
        <sphereGeometry args={[0.15, 8, 8]} />
        <meshBasicMaterial color={selected ? new THREE.Color('#4a9eff') : col} />
      </mesh>
    </group>
  );
}

// ---------- Overlay ----------

interface ParticleOverlayProps {
  effects: ParticleEffect[];
  placementMode?: boolean;
  placementPreset?: string;
  placementColor?: [number, number, number];
  selectedEffectId?: string | null;
  onPlaceEffect?: (position: [number, number, number]) => void;
  onSelectEffect?: (id: string) => void;
}

export default function ParticleOverlay({
  effects,
  placementMode = false,
  placementPreset = 'spores',
  placementColor = [0.2, 1.0, 0.3],
  selectedEffectId = null,
  onPlaceEffect,
  onSelectEffect,
}: ParticleOverlayProps) {
  const { camera, raycaster, pointer } = useThree();
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  const handleClick = () => {
    if (!placementMode || !onPlaceEffect) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      onPlaceEffect([intersection.x, 0, intersection.z]);
    }
  };

  return (
    <group>
      {/* Ground plane for click detection in placement mode */}
      {placementMode && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.01, 0]} onClick={handleClick}>
          <planeGeometry args={[200, 200]} />
          <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Placement preview following mouse */}
      {placementMode && (
        <PlacementPreview preset={placementPreset} color={placementColor} />
      )}

      {/* Render all effects */}
      {effects.map(e => {
        if (e.category === 'weather') return <WeatherSystem key={e.id} effect={e} />;
        return (
          <group key={e.id}>
            <RisingSystem effect={e} />
            {/* Clickable marker for placed effects */}
            {e.category === 'placed' && onSelectEffect && (
              <EmitterMarker
                effect={e}
                selected={e.id === selectedEffectId}
                onClick={() => onSelectEffect(e.id)}
              />
            )}
          </group>
        );
      })}
    </group>
  );
}
