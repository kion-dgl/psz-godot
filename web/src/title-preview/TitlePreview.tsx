import { Canvas, useFrame } from '@react-three/fiber';
import { useMemo, useRef } from 'react';
import * as THREE from 'three';

const CANVAS_W = 1920;
const CANVAS_H = 1080;

function SkyGradient() {
  const shader = useMemo(() => ({
    uniforms: {
      topColor: { value: new THREE.Color('#050820') },
      midColor: { value: new THREE.Color('#151a48') },
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
        if (y < 0.18) {
          color = mix(horizonColor, midColor, smoothstep(0.0, 0.18, y));
        } else {
          color = mix(midColor, topColor, smoothstep(0.18, 1.0, y));
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

function GalaxyField() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      tintA: { value: new THREE.Color('#6a4fb0') },
      tintB: { value: new THREE.Color('#3a70d8') },
      tintC: { value: new THREE.Color('#d07090') },
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
      uniform vec3 tintA;
      uniform vec3 tintB;
      uniform vec3 tintC;
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
        for (int i = 0; i < 6; i++) {
          v += a * noise(p);
          p *= 2.0;
          a *= 0.5;
        }
        return v;
      }
      void main() {
        // Only render in upper sky (not on horizon)
        float skyMask = smoothstep(0.25, 0.55, vUv.y);

        vec2 p = vUv * 3.0;
        float n1 = fbm(p + vec2(time * 0.01, 0.0));
        float n2 = fbm(p * 1.8 + vec2(5.0, time * 0.015));
        float n3 = fbm(p * 0.6 + vec2(-2.0, time * 0.008));

        // Sparse nebula patches — only bright in certain regions
        float nebula = smoothstep(0.55, 0.85, n1) * 0.6;
        float wisps = smoothstep(0.65, 0.95, n2) * 0.4;

        vec3 color = mix(tintA, tintB, n3);
        color = mix(color, tintC, smoothstep(0.5, 0.9, n1));

        float alpha = (nebula + wisps) * skyMask;
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
    <mesh ref={meshRef} position={[0, 0, -48]}>
      <planeGeometry args={[120, 70]} />
      <shaderMaterial args={[shader]} />
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
      positions[i * 3 + 0] = (Math.random() - 0.5) * 110;
      positions[i * 3 + 1] = Math.random() * 45 + 3;
      positions[i * 3 + 2] = -42 + Math.random() * 12;
      const big = Math.random() < 0.08;
      sizes[i] = big ? 0.25 + Math.random() * 0.35 : 0.04 + Math.random() * 0.15;
      phases[i] = Math.random() * Math.PI * 2;
      // Mostly white with a few tinted (blue/yellow) stars
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
        gl_PointSize = size * (400.0 / -mvPosition.z) * (0.7 + vTwinkle * 0.6);
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
        float cx = abs(vUv.x - 0.5) * 2.0;
        float vertical = vUv.y;
        float edge = smoothstep(1.0, 0.0, cx);
        float intensity = edge * edge;
        intensity *= mix(0.3, 1.4, 1.0 - vertical);
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

/** Swirling cloud / nebula layer using flowing domain-warped FBM. */
function SwirlingClouds() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      colorA: { value: new THREE.Color('#1a2050') },
      colorB: { value: new THREE.Color('#4860a8') },
      colorC: { value: new THREE.Color('#8a5090') },
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
      uniform vec3 colorA;
      uniform vec3 colorB;
      uniform vec3 colorC;
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
        for (int i = 0; i < 6; i++) {
          v += a * noise(p);
          p *= 2.02;
          a *= 0.5;
        }
        return v;
      }

      // Domain-warped FBM creates curling/swirling motion
      float swirl(vec2 p, float t) {
        vec2 q = vec2(fbm(p + vec2(0.0, t * 0.05)),
                      fbm(p + vec2(5.2, 1.3) + vec2(t * 0.04, 0.0)));
        vec2 r = vec2(fbm(p + 4.0 * q + vec2(1.7, 9.2) + vec2(t * 0.02, 0.0)),
                      fbm(p + 4.0 * q + vec2(8.3, 2.8) + vec2(0.0, t * 0.03)));
        return fbm(p + 4.0 * r);
      }

      void main() {
        // Mask: cloud band in the mid-sky, fading at top and bottom
        float band = smoothstep(0.0, 0.25, vUv.y) * smoothstep(0.85, 0.45, vUv.y);
        // Also keep the center dimmer so the beam reads clearly
        float centerFade = smoothstep(0.0, 0.35, abs(vUv.x - 0.5));

        vec2 p = vec2(vUv.x * 3.5, vUv.y * 2.0);
        float n = swirl(p, time);

        float density = smoothstep(0.35, 0.85, n);
        vec3 color = mix(colorA, colorB, n);
        color = mix(color, colorC, smoothstep(0.55, 0.9, n) * 0.6);

        float alpha = density * band * centerFade * 0.85;
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
  }), []);

  useFrame((state) => {
    if (meshRef.current) {
      const mat = meshRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh ref={meshRef} position={[0, 3, -26]}>
      <planeGeometry args={[80, 45]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function Scene() {
  return (
    <>
      <SkyGradient />
      <GalaxyField />
      <Starfield count={2500} />
      <SwirlingClouds />
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
        </div>
      </div>
    </div>
  );
}
