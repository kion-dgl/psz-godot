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
  // Moon disk — sun-lit from upper-right, dark side with eerie blue glow
  const diskShader = useMemo(() => ({
    uniforms: {
      litColor: { value: new THREE.Color('#e8ecf5') },
      shadowColor: { value: new THREE.Color('#1a2850') },
      terminatorTint: { value: new THREE.Color('#6a80c0') },
      sunDir: { value: new THREE.Vector2(0.6, 0.6).normalize() },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 litColor;
      uniform vec3 shadowColor;
      uniform vec3 terminatorTint;
      uniform vec2 sunDir;
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

      void main() {
        vec2 c = vUv - vec2(0.5);
        float d = length(c) * 2.0;
        if (d > 1.0) discard;

        // Sphere normal approximation
        float z = sqrt(max(0.0, 1.0 - d * d));
        vec3 n = vec3(c * 2.0, z);
        vec3 L = normalize(vec3(sunDir.x, sunDir.y, 0.6));
        float lambert = max(0.0, dot(n, L));

        // Crater noise for surface detail
        float crater = noise(c * 18.0) * 0.25 + noise(c * 40.0) * 0.12;
        crater = (crater - 0.2) * 0.5;

        vec3 color = mix(shadowColor, litColor, smoothstep(0.0, 0.7, lambert));
        // Warm tint near terminator
        float term = 1.0 - abs(lambert - 0.3) * 3.0;
        color = mix(color, terminatorTint, max(0.0, term) * 0.2);
        color += crater;

        // Soft edge
        float edge = smoothstep(1.0, 0.85, d);
        gl_FragColor = vec4(color, edge);
      }
    `,
    transparent: true,
    depthWrite: false,
  }), []);

  // Eerie blue halo around the moon
  const haloShader = useMemo(() => ({
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
        // Halo ring — weak at the moon disk (d < 0.3), fade out by d=1
        float ring = smoothstep(0.25, 0.35, d) * (1.0 - smoothstep(0.35, 1.0, d));
        float outerGlow = (1.0 - smoothstep(0.3, 1.0, d)) * 0.5;
        float pulse = 0.85 + 0.15 * sin(time * 0.8);
        vec3 color = mix(inner, outer, smoothstep(0.3, 1.0, d));
        float alpha = (ring * 0.9 + outerGlow) * pulse;
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  }), []);

  const haloRef = useRef<THREE.Mesh>(null);
  useFrame((state) => {
    if (haloRef.current) {
      const mat = haloRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <group position={[0, 11, -30]}>
      <mesh ref={haloRef}>
        <planeGeometry args={[28, 28]} />
        <shaderMaterial args={[haloShader]} />
      </mesh>
      <mesh position={[0, 0, 0.1]}>
        <planeGeometry args={[10, 10]} />
        <shaderMaterial args={[diskShader]} />
      </mesh>
    </group>
  );
}

function LightBeam() {
  const meshRef = useRef<THREE.Mesh>(null);
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
        // Beam rises from a point (bottom center, vUv.y=0) up to the moon (vUv.y=1).
        // Width grows with height: narrow at source, wider at moon.
        float y = vUv.y;
        float beamHalfWidth = mix(0.015, 0.35, y);
        float cx = abs(vUv.x - 0.5);
        float edge = 1.0 - smoothstep(0.0, beamHalfWidth, cx);
        // Soft feathering
        float feather = pow(edge, 1.8);
        // Intensity: brightest at source and mid-beam, fading near moon
        float vertical = smoothstep(0.0, 0.15, y) * (1.0 - smoothstep(0.7, 1.0, y) * 0.4);
        // Shimmer
        float shimmer = 0.85 + 0.15 * sin(time * 2.0 + y * 10.0);
        float intensity = feather * vertical * shimmer;
        gl_FragColor = vec4(beamColor * intensity * 1.3, intensity);
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

  // Plane from y=-5 (source above horizon) up to y=11 (at moon). Center at y=3, height 16.
  return (
    <mesh ref={meshRef} position={[0, 3, -27]}>
      <planeGeometry args={[18, 16]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

/** Ground-level point where the beam originates — bright spark on the landscape */
function BeamSource() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      coreColor: { value: new THREE.Color('#ffffff') },
      glowColor: { value: new THREE.Color('#a8c8ff') },
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
        vec2 c = vUv - vec2(0.5);
        float d = length(c) * 2.0;
        float pulse = 0.88 + 0.12 * sin(time * 1.6);
        float core = (1.0 - smoothstep(0.0, 0.1, d)) * pulse;
        float glow = (1.0 - smoothstep(0.05, 0.55, d)) * 0.7 * pulse;
        vec3 color = mix(glowColor, coreColor, core);
        float alpha = max(core, glow);
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

  // Located at the base of the beam, in front of the horizon
  return (
    <mesh ref={meshRef} position={[0, -5, -25]}>
      <planeGeometry args={[6, 6]} />
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

/** Clouds swirling up from the beam source and flowing outward to screen edges. */
function SwirlingClouds() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      colorA: { value: new THREE.Color('#1a2050') },
      colorB: { value: new THREE.Color('#4860a8') },
      colorC: { value: new THREE.Color('#8a5090') },
      // Source point in UV space — bottom center, just above the horizon
      source: { value: new THREE.Vector2(0.5, 0.18) },
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
      uniform vec2 source;
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

      void main() {
        // Scale the sky horizontally to correct aspect — aspect ratio ~1.78.
        // Offset to source, measure radial distance + angle.
        vec2 d = vec2((vUv.x - source.x) * 1.78, vUv.y - source.y);
        float r = length(d);
        float theta = atan(d.y, d.x);

        // Flow: radius moves outward over time, angle slowly rotates.
        // Using log-polar so noise stretches as it moves out (gives the "spiral out" feel).
        float u = theta * 1.8 + time * 0.08;
        float v = -log(max(r, 0.02)) * 0.9 + time * 0.25;

        // Domain warping for curling swirl details
        vec2 p = vec2(u, v);
        vec2 warp = vec2(fbm(p + vec2(0.0, time * 0.1)),
                         fbm(p + vec2(5.2, 1.3)));
        float n = fbm(p + 2.0 * warp);

        // Density gate
        float density = smoothstep(0.35, 0.85, n);

        // Radial mask — fade near the source (let beam read) and fade at the far edge
        float sourceFade = smoothstep(0.04, 0.18, r);  // don't cover the beam spark
        float outerFade = 1.0 - smoothstep(0.45, 0.9, r);

        // Vertical mask — let the beam & moon breathe through the center column
        float centerColumn = smoothstep(0.0, 0.14, abs(vUv.x - 0.5));

        // Prefer upward flow — dim below the source
        float upward = smoothstep(source.y - 0.05, source.y + 0.15, vUv.y);

        vec3 color = mix(colorA, colorB, n);
        color = mix(color, colorC, smoothstep(0.55, 0.9, n) * 0.5);

        float alpha = density * sourceFade * outerFade * centerColumn * upward * 0.9;
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
      <HorizonGlow />
      <LightBeam />
      <BeamSource />
      <Moon />
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
