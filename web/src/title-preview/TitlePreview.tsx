import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';

const CANVAS_W = 1920;
const CANVAS_H = 1080;

/** Large background sphere with inside-out sky gradient. */
function SkyDome() {
  const shader = useMemo(() => ({
    uniforms: {
      topColor: { value: new THREE.Color('#050820') },
      midColor: { value: new THREE.Color('#151a48') },
      horizonColor: { value: new THREE.Color('#2a3868') },
    },
    vertexShader: `
      varying vec3 vWorldPos;
      void main() {
        vec4 worldPos = modelMatrix * vec4(position, 1.0);
        vWorldPos = worldPos.xyz;
        gl_Position = projectionMatrix * viewMatrix * worldPos;
      }
    `,
    fragmentShader: `
      uniform vec3 topColor;
      uniform vec3 midColor;
      uniform vec3 horizonColor;
      varying vec3 vWorldPos;
      void main() {
        float h = normalize(vWorldPos).y;
        vec3 color;
        if (h < 0.0) {
          color = mix(midColor, horizonColor, smoothstep(-0.3, 0.0, h));
        } else {
          color = mix(midColor, topColor, smoothstep(0.0, 0.7, h));
        }
        gl_FragColor = vec4(color, 1.0);
      }
    `,
    side: THREE.BackSide,
  }), []);
  return (
    <mesh>
      <sphereGeometry args={[500, 32, 32]} />
      <shaderMaterial args={[shader]} depthWrite={false} />
    </mesh>
  );
}

function Starfield({ count = 2500 }: { count?: number }) {
  const pointsRef = useRef<THREE.Points>(null);
  const { positions, sizes, phases, colors } = useMemo(() => {
    const positions = new Float32Array(count * 3);
    const sizes = new Float32Array(count);
    const phases = new Float32Array(count);
    const colors = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      // Spherical distribution on a dome (upper hemisphere)
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(Math.random() * 0.95 + 0.05); // bias toward top
      const r = 400;
      positions[i * 3 + 0] = r * Math.sin(phi) * Math.cos(theta);
      positions[i * 3 + 1] = r * Math.cos(phi);
      positions[i * 3 + 2] = r * Math.sin(phi) * Math.sin(theta);
      const big = Math.random() < 0.08;
      sizes[i] = big ? 2.5 + Math.random() * 3.0 : 0.5 + Math.random() * 1.5;
      phases[i] = Math.random() * Math.PI * 2;
      const tint = Math.random();
      if (tint < 0.1) {
        colors[i * 3 + 0] = 0.7; colors[i * 3 + 1] = 0.8; colors[i * 3 + 2] = 1.0;
      } else if (tint < 0.18) {
        colors[i * 3 + 0] = 1.0; colors[i * 3 + 1] = 0.9; colors[i * 3 + 2] = 0.7;
      } else {
        colors[i * 3 + 0] = 1.0; colors[i * 3 + 1] = 1.0; colors[i * 3 + 2] = 1.0;
      }
    }
    return { positions, sizes, phases, colors };
  }, [count]);

  const shader = useMemo(() => ({
    uniforms: { time: { value: 0 } },
    vertexShader: `
      attribute float size;
      attribute float phase;
      attribute vec3 color;
      uniform float time;
      varying float vTwinkle;
      varying vec3 vColor;
      void main() {
        vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
        vTwinkle = 0.5 + 0.5 * sin(time * 2.0 + phase);
        vColor = color;
        gl_PointSize = size * (0.7 + vTwinkle * 0.6);
        gl_Position = projectionMatrix * mvPosition;
      }
    `,
    fragmentShader: `
      varying float vTwinkle;
      varying vec3 vColor;
      void main() {
        vec2 c = gl_PointCoord - vec2(0.5);
        float d = length(c);
        float alpha = smoothstep(0.5, 0.0, d);
        gl_FragColor = vec4(vColor * (0.8 + vTwinkle * 0.4), alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  }), []);

  useFrame((state) => {
    if (pointsRef.current) {
      const mat = pointsRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <points ref={pointsRef}>
      <bufferGeometry>
        <bufferAttribute attach="attributes-position" args={[positions, 3]} />
        <bufferAttribute attach="attributes-size" args={[sizes, 1]} />
        <bufferAttribute attach="attributes-phase" args={[phases, 1]} />
        <bufferAttribute attach="attributes-color" args={[colors, 3]} />
      </bufferGeometry>
      <shaderMaterial args={[shader]} />
    </points>
  );
}

/** Real 3D moon — SphereGeometry with MeshStandardMaterial lit by the sun directional. */
function Moon({ position = [0, 18, -60] as [number, number, number] }) {
  return (
    <group position={position}>
      {/* The moon body */}
      <mesh>
        <sphereGeometry args={[6, 64, 64]} />
        <meshStandardMaterial
          color="#cfd8e8"
          roughness={0.95}
          metalness={0.0}
          emissive="#1a2050"
          emissiveIntensity={0.25}
        />
      </mesh>
      {/* Eerie blue halo — billboard sprite behind the moon */}
      <MoonHalo />
    </group>
  );
}

function MoonHalo() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      inner: { value: new THREE.Color('#6a90e8') },
      outer: { value: new THREE.Color('#1a2870') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 inner;
      uniform vec3 outer;
      uniform float time;
      varying vec2 vUv;
      void main() {
        vec2 c = vUv - vec2(0.5);
        float d = length(c) * 2.0;
        if (d > 1.0) discard;
        float ring = smoothstep(0.4, 0.5, d) * (1.0 - smoothstep(0.5, 1.0, d));
        float outerGlow = (1.0 - smoothstep(0.45, 1.0, d)) * 0.4;
        float pulse = 0.85 + 0.15 * sin(time * 0.8);
        vec3 color = mix(inner, outer, smoothstep(0.45, 1.0, d));
        float alpha = (ring * 0.9 + outerGlow) * pulse;
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  }), []);
  useFrame((state) => {
    if (meshRef.current) {
      const mat = meshRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
      // Keep halo facing the camera
      meshRef.current.lookAt(state.camera.position);
    }
  });
  return (
    <mesh ref={meshRef} position={[0, 0, -0.2]}>
      <planeGeometry args={[24, 24]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

/** Huge sphere representing the planet we're standing on.
 *  Camera sits just above its surface; the curvature creates the horizon. */
function Planet({
  radius = 200,
  surfaceY = -200, // center of planet (camera is at y=0, surface top at y = surfaceY + radius)
}: {
  radius?: number;
  surfaceY?: number;
}) {
  // Position so top of planet is just below camera (at y = -0.5)
  // surface top = surfaceY + radius -> -0.5 = surfaceY + radius -> surfaceY = -radius - 0.5
  const centerY = -radius - 0.5;
  return (
    <mesh position={[0, centerY, 0]}>
      <sphereGeometry args={[radius, 128, 64]} />
      <meshStandardMaterial
        color="#0c1028"
        roughness={1.0}
        metalness={0.0}
        emissive="#050714"
        emissiveIntensity={0.2}
      />
    </mesh>
  );
}

/** Glowing sphere at the beam source — emissive, attracts a point light. */
function BeamSource({
  position = [0, 0.2, -25] as [number, number, number],
}) {
  const pointRef = useRef<THREE.PointLight>(null);
  useFrame((state) => {
    if (pointRef.current) {
      const t = state.clock.elapsedTime;
      pointRef.current.intensity = 60 + Math.sin(t * 1.6) * 10;
    }
  });
  return (
    <group position={position}>
      <mesh>
        <sphereGeometry args={[0.5, 32, 32]} />
        <meshBasicMaterial color="#e8f0ff" toneMapped={false} />
      </mesh>
      {/* Outer glow sphere */}
      <mesh>
        <sphereGeometry args={[1.4, 32, 32]} />
        <meshBasicMaterial color="#6090ff" transparent opacity={0.3} toneMapped={false} />
      </mesh>
      <pointLight ref={pointRef} color="#a8c8ff" intensity={60} distance={40} decay={1.2} />
    </group>
  );
}

/** Light beam — plane always facing the camera, going from source up to moon. */
function LightBeam({
  from = new THREE.Vector3(0, 0.2, -25),
  to = new THREE.Vector3(0, 18, -60),
}: {
  from?: THREE.Vector3;
  to?: THREE.Vector3;
}) {
  const groupRef = useRef<THREE.Group>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      beamColor: { value: new THREE.Color('#c8dcff') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 beamColor;
      uniform float time;
      varying vec2 vUv;
      void main() {
        // vUv.y = 0 at source (narrow), 1 at moon (wider)
        float y = vUv.y;
        float halfW = mix(0.03, 0.35, y);
        float cx = abs(vUv.x - 0.5);
        float edge = 1.0 - smoothstep(0.0, halfW, cx);
        float feather = pow(edge, 1.8);
        float vertical = smoothstep(0.0, 0.1, y) * (1.0 - smoothstep(0.7, 1.0, y) * 0.4);
        float shimmer = 0.85 + 0.15 * sin(time * 2.0 + y * 10.0);
        float intensity = feather * vertical * shimmer;
        gl_FragColor = vec4(beamColor * intensity * 1.4, intensity);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.DoubleSide,
  }), []);

  useFrame((state) => {
    if (groupRef.current) {
      // Update time uniform
      const mesh = groupRef.current.children[0] as THREE.Mesh;
      if (mesh && mesh.material) {
        (mesh.material as THREE.ShaderMaterial).uniforms.time.value = state.clock.elapsedTime;
      }
    }
  });

  // Place beam as a plane stretched from 'from' to 'to'
  const mid = from.clone().add(to).multiplyScalar(0.5);
  const direction = to.clone().sub(from);
  const length = direction.length();
  const angle = Math.atan2(direction.x, direction.y); // rotate around z

  return (
    <group ref={groupRef} position={mid.toArray()} rotation={[0, 0, -angle]}>
      <mesh>
        <planeGeometry args={[8, length]} />
        <shaderMaterial args={[shader]} />
      </mesh>
    </group>
  );
}

function Scene() {
  return (
    <>
      {/* Lights */}
      <ambientLight intensity={0.15} color="#4060a0" />
      {/* "Sun" — offscreen, lights the moon's crescent and planet rim */}
      <directionalLight position={[30, 20, 10]} intensity={1.5} color="#f0e8d8" />

      {/* Scene */}
      <SkyDome />
      <Starfield count={2500} />
      <Planet />
      <Moon />
      <BeamSource />
      <LightBeam />
    </>
  );
}

export default function TitlePreview() {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', height: '100vh',
      background: '#000', overflow: 'hidden',
    }}>
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
        overflow: 'hidden',
      }}>
        <div style={{ width: CANVAS_W, height: CANVAS_H, position: 'relative', flexShrink: 0 }}>
          <Canvas
            gl={{ antialias: true, preserveDrawingBuffer: true }}
            camera={{ position: [0, 0, 0], fov: 50, near: 0.1, far: 1000 }}
            style={{ width: CANVAS_W, height: CANVAS_H, background: '#000' }}
          >
            <Scene />
            <OrbitControls
              enablePan
              enableZoom
              enableRotate
              minDistance={0.1}
              maxDistance={50}
            />
          </Canvas>
        </div>
      </div>
    </div>
  );
}
