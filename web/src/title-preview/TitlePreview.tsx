import { Canvas, useFrame } from '@react-three/fiber';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';

const CANVAS_W = 1920;
const CANVAS_H = 1080;

function SkyGradient() {
  const shader = useMemo(() => ({
    uniforms: {
      topColor: { value: new THREE.Color('#0a0e2a') },
      midColor: { value: new THREE.Color('#1a2050') },
      horizonColor: { value: new THREE.Color('#f0b880') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 topColor;
      uniform vec3 midColor;
      uniform vec3 horizonColor;
      varying vec2 vUv;
      void main() {
        float y = vUv.y;
        vec3 color;
        if (y < 0.2) {
          color = mix(horizonColor, midColor, smoothstep(0.0, 0.2, y));
        } else {
          color = mix(midColor, topColor, smoothstep(0.2, 1.0, y));
        }
        gl_FragColor = vec4(color, 1.0);
      }
    `,
  }), []);
  return (
    <mesh position={[0, 0, -50]}>
      <planeGeometry args={[120, 70]} />
      <shaderMaterial args={[shader]} depthWrite={false} />
    </mesh>
  );
}

function Starfield({ count = 800 }: { count?: number }) {
  const pointsRef = useRef<THREE.Points>(null);
  const { positions, sizes, phases } = useMemo(() => {
    const positions = new Float32Array(count * 3);
    const sizes = new Float32Array(count);
    const phases = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      positions[i * 3 + 0] = (Math.random() - 0.5) * 100;
      positions[i * 3 + 1] = Math.random() * 40 + 2;
      positions[i * 3 + 2] = -40 + Math.random() * 10;
      sizes[i] = 0.05 + Math.random() * 0.18;
      phases[i] = Math.random() * Math.PI * 2;
    }
    return { positions, sizes, phases };
  }, [count]);

  const shader = useMemo(() => ({
    uniforms: { time: { value: 0 } },
    vertexShader: `
      attribute float size;
      attribute float phase;
      uniform float time;
      varying float vTwinkle;
      void main() {
        vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
        vTwinkle = 0.7 + 0.3 * sin(time * 2.0 + phase);
        gl_PointSize = size * (400.0 / -mvPosition.z) * vTwinkle;
        gl_Position = projectionMatrix * mvPosition;
      }
    `,
    fragmentShader: `
      varying float vTwinkle;
      void main() {
        vec2 c = gl_PointCoord - vec2(0.5);
        float d = length(c);
        float alpha = smoothstep(0.5, 0.0, d);
        gl_FragColor = vec4(vec3(1.0) * vTwinkle, alpha);
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
      </bufferGeometry>
      <shaderMaterial args={[shader]} />
    </points>
  );
}

function Moon() {
  const shader = useMemo(() => ({
    uniforms: {
      coreColor: { value: new THREE.Color('#f5f8ff') },
      glowColor: { value: new THREE.Color('#7090e8') },
      haloColor: { value: new THREE.Color('#3a5099') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 coreColor;
      uniform vec3 glowColor;
      uniform vec3 haloColor;
      varying vec2 vUv;
      void main() {
        vec2 c = vUv - vec2(0.5);
        float d = length(c) * 2.0;
        if (d > 1.0) discard;

        float core = 1.0 - smoothstep(0.0, 0.45, d);
        float glow = 1.0 - smoothstep(0.35, 0.65, d);
        float halo = 1.0 - smoothstep(0.55, 1.0, d);

        // Subtle crater detail
        float n = sin(c.x * 20.0) * sin(c.y * 20.0) * 0.08;
        n += sin(c.x * 40.0 + 1.0) * sin(c.y * 35.0) * 0.04;

        vec3 color = mix(haloColor, glowColor, glow);
        color = mix(color, coreColor * (1.0 + n), core);
        float alpha = max(core, max(glow * 0.9, halo * 0.6));
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
  }), []);

  return (
    <mesh position={[0, 10, -30]}>
      <planeGeometry args={[14, 14]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function LightBeam() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      beamColor: { value: new THREE.Color('#a8c8ff') },
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
        // Distance from vertical center line
        float cx = abs(vUv.x - 0.5) * 2.0;
        // Fade from top (narrow) to bottom (wider, brighter)
        float vertical = vUv.y;
        float edge = smoothstep(1.0, 0.0, cx);
        float intensity = edge * edge;
        intensity *= mix(0.3, 1.4, 1.0 - vertical);
        // Pulsing shimmer
        intensity *= 0.9 + 0.1 * sin(time * 1.5);
        gl_FragColor = vec4(beamColor * intensity, intensity * 0.9);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.DoubleSide,
  }), []);

  useFrame((state) => {
    if (meshRef.current) {
      const mat = meshRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh ref={meshRef} position={[0, 3, -28]}>
      <planeGeometry args={[18, 18]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function HorizonGlow() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      coreColor: { value: new THREE.Color('#fff0d0') },
      glowColor: { value: new THREE.Color('#f0a070') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 coreColor;
      uniform vec3 glowColor;
      uniform float time;
      varying vec2 vUv;
      void main() {
        vec2 c = vUv - vec2(0.5, 0.1);
        float d = length(vec2(c.x * 0.7, c.y * 2.2));
        float core = 1.0 - smoothstep(0.0, 0.25, d);
        float glow = 1.0 - smoothstep(0.15, 0.8, d);
        float pulse = 0.92 + 0.08 * sin(time * 1.2);
        vec3 color = mix(glowColor, coreColor, core);
        float alpha = max(core, glow * 0.6) * pulse;
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
    }
  });

  return (
    <mesh ref={meshRef} position={[0, -4, -27]}>
      <planeGeometry args={[50, 20]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function Cloud({ position, scale, seed }: { position: [number, number, number]; scale: number; seed: number }) {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      seed: { value: seed },
      color: { value: new THREE.Color('#2a3466') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform float time;
      uniform float seed;
      uniform vec3 color;
      varying vec2 vUv;

      float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
      }
      float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
                   mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
      }
      float fbm(vec2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
          v += a * noise(p);
          p *= 2.0;
          a *= 0.5;
        }
        return v;
      }
      void main() {
        vec2 c = vUv - vec2(0.5);
        float shape = 1.0 - smoothstep(0.0, 0.5, length(c * vec2(1.0, 1.6)));
        float n = fbm(vUv * 3.0 + vec2(seed, time * 0.02));
        float alpha = shape * smoothstep(0.3, 0.9, n) * 0.7;
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
  }), [seed]);

  useFrame((state) => {
    if (meshRef.current) {
      const mat = meshRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh ref={meshRef} position={position} scale={[scale, scale, 1]}>
      <planeGeometry args={[12, 6]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function Scene() {
  return (
    <>
      <SkyGradient />
      <Starfield count={800} />
      <Cloud position={[-14, 4, -26]} scale={1.4} seed={0.1} />
      <Cloud position={[15, 6, -26]} scale={1.3} seed={0.5} />
      <Cloud position={[-20, 2, -25]} scale={1.1} seed={0.9} />
      <Cloud position={[19, 3, -25]} scale={1.2} seed={1.3} />
      <Cloud position={[-8, 0, -24]} scale={0.9} seed={1.7} />
      <Cloud position={[10, 1, -24]} scale={1.0} seed={2.1} />
      <LightBeam />
      <Moon />
      <HorizonGlow />
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
            camera={{ position: [0, 0, 0], fov: 50 }}
            style={{ width: CANVAS_W, height: CANVAS_H, background: '#000' }}
          >
            <Scene />
          </Canvas>
          {/* PSZ Logo overlay */}
          <div style={{
            position: 'absolute', top: '8%', left: '50%', transform: 'translateX(-50%)',
            pointerEvents: 'none',
          }}>
            <img
              src={assetUrl('assets/images/logo.png')}
              alt="Phantasy Star Zero"
              style={{ width: 560, filter: 'drop-shadow(0 4px 20px rgba(0, 0, 0, 0.8))' }}
            />
          </div>
          <div style={{
            position: 'absolute', bottom: '12%', left: '50%', transform: 'translateX(-50%)',
            color: '#cfd8f0', fontSize: 24, fontFamily: 'serif', letterSpacing: 4,
            textShadow: '0 2px 8px rgba(0,0,0,0.8)', pointerEvents: 'none',
          }}>
            Press Start
          </div>
        </div>
      </div>
    </div>
  );
}
