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
      horizonColor: { value: new THREE.Color('#2a3868') },
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
    <mesh ref={meshRef} position={[0, 3, -26]}>
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
        float pulse = 0.85 + 0.15 * sin(time * 1.6);
        // Bright white core
        float core = (1.0 - smoothstep(0.0, 0.08, d)) * pulse;
        // Inner glow (blueish)
        float innerGlow = (1.0 - smoothstep(0.06, 0.3, d)) * pulse;
        // Outer soft halo
        float outerGlow = (1.0 - smoothstep(0.15, 1.0, d)) * 0.6 * pulse;
        vec3 color = mix(glowColor, coreColor, core + innerGlow * 0.6);
        float alpha = max(core, max(innerGlow * 0.95, outerGlow));
        // Boost total intensity so it reads
        gl_FragColor = vec4(color * 1.4, alpha);
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

  // Located on top of the mountain bulge. Ground horizon at center is around world y=-3.5
  // at z=-27; to sit on that peak at z=-25 we need y ≈ -3.
  return (
    <mesh ref={meshRef} position={[0, -3, -25]}>
      <planeGeometry args={[10, 10]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

/** Rocky planet surface — jagged horizon with peaks/ridges and surface texture. */
function PlanetSurface() {
  const shader = useMemo(() => ({
    uniforms: {
      groundColor: { value: new THREE.Color('#05081a') },
      rockColor: { value: new THREE.Color('#1a1a2e') },
      rimLight: { value: new THREE.Color('#3a4a80') },
      peakTint: { value: new THREE.Color('#6a7ab0') },
      hazeColor: { value: new THREE.Color('#3a4a88') },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 groundColor;
      uniform vec3 rockColor;
      uniform vec3 rimLight;
      uniform vec3 peakTint;
      uniform vec3 hazeColor;
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
        float cx = (vUv.x - 0.5) * 2.0;

        // Foreground horizon — takes up the bottom ~40% of the frame.
        // Soft gentle hills with a central bulge under the beam source.
        float big = fbm(vec2(vUv.x * 3.0, 1.3)) * 0.06;
        float mid = fbm(vec2(vUv.x * 8.0, 2.7)) * 0.025;
        float mountain = 0.08 * exp(-cx * cx * 4.0); // gaussian bulge in the middle
        float horizonY = 0.36 + big + mid + mountain;

        // Distant secondary ridge behind the foreground (atmospheric haze)
        float farBig = fbm(vec2(vUv.x * 2.5 + 100.0, 4.2)) * 0.04;
        float farMid = fbm(vec2(vUv.x * 6.0 + 50.0, 1.9)) * 0.02;
        float farHorizonY = 0.30 + farBig + farMid;

        if (vUv.y < horizonY) {
          // Solid opaque ground with subtle texture
          vec2 rockP = vec2(vUv.x * 40.0, vUv.y * 40.0);
          float rockTex = fbm(rockP) * 0.5 + fbm(rockP * 2.0 + 3.0) * 0.25;

          // Base dark color, slight variation from rock texture
          vec3 color = mix(groundColor, rockColor, rockTex);

          // Illumination from the beam source at UV (0.5, 0.33).
          // Ground under/around the beam source catches warm light.
          vec2 srcDir = vec2((vUv.x - 0.5) * 1.78, vUv.y - 0.32);
          float srcDist = length(srcDir);
          float srcLight = 1.0 - smoothstep(0.0, 0.5, srcDist);
          color = mix(color, rimLight, srcLight * 0.55);

          // Rim light along the top silhouette (lit against the sky)
          float rim = smoothstep(horizonY - 0.008, horizonY, vUv.y);
          color = mix(color, peakTint, rim * 0.7);

          // Darker toward the very bottom of the frame
          float deep = smoothstep(0.0, 0.1, vUv.y);
          color *= 0.55 + deep * 0.45;

          gl_FragColor = vec4(color, 1.0);
          return;
        }

        // Between the two horizons: distant hills in haze (still opaque)
        if (vUv.y < farHorizonY) {
          float depth = smoothstep(horizonY, horizonY + 0.025, vUv.y);
          vec3 color = mix(rockColor, hazeColor * 0.45, depth);
          gl_FragColor = vec4(color, 1.0);
          return;
        }

        // Thin atmospheric haze strip just above the distant ridges
        float haze = 1.0 - smoothstep(farHorizonY, farHorizonY + 0.06, vUv.y);
        if (haze > 0.01) {
          gl_FragColor = vec4(hazeColor, haze * 0.45);
          return;
        }
        discard;
      }
    `,
    transparent: true,
    depthWrite: false,
  }), []);

  return (
    <mesh position={[0, 0, -27]}>
      <planeGeometry args={[120, 70]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

/** Single cloud layer with horizontal outward flow and swirl around source. */
function CloudLayer({
  z, scale, speed, densityThresh, opacity, bandTop, bandBottom,
}: {
  z: number; scale: number; speed: number; densityThresh: [number, number];
  opacity: number; bandTop: number; bandBottom: number;
}) {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      hotColor: { value: new THREE.Color('#fde8c8') },
      warmColor: { value: new THREE.Color('#f0a0a8') },
      coolColor: { value: new THREE.Color('#5a5890') },
      darkColor: { value: new THREE.Color('#14193e') },
      shadowColor: { value: new THREE.Color('#0a0e28') },
      source: { value: new THREE.Vector2(0.5, 0.45) },
      scale: { value: scale },
      speed: { value: speed },
      dLo: { value: densityThresh[0] },
      dHi: { value: densityThresh[1] },
      opacity: { value: opacity },
      bandTop: { value: bandTop },
      bandBottom: { value: bandBottom },
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
      uniform vec3 hotColor;
      uniform vec3 warmColor;
      uniform vec3 coolColor;
      uniform vec3 darkColor;
      uniform vec3 shadowColor;
      uniform vec2 source;
      uniform float scale;
      uniform float speed;
      uniform float dLo;
      uniform float dHi;
      uniform float opacity;
      uniform float bandTop;
      uniform float bandBottom;
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
        // Aspect-corrected offset from source
        vec2 d = vec2((vUv.x - source.x) * 1.78, vUv.y - source.y);
        float r = length(d);

        // Horizontal flow: left side drifts left, right side drifts right. Pure X.
        float side = sign(d.x);

        // Curl offset — swirl around the source point (stronger near it)
        float swirlStrength = exp(-r * 3.0) * 0.25;
        float ang = time * 0.4;
        vec2 swirlOffset = vec2(cos(ang), sin(ang)) * swirlStrength;

        // Sample coordinates: scale the world, drift horizontally with time.
        vec2 p = vec2(d.x, d.y) * scale + swirlOffset;
        p.x -= side * time * speed;

        // Heavy domain warping for thick curling cloud shapes
        vec2 warp1 = vec2(fbm(p * 0.8 + vec2(0.0, time * 0.05)),
                          fbm(p * 0.8 + vec2(5.2, 1.3)));
        vec2 warp2 = vec2(fbm(p * 1.4 + warp1 * 2.0),
                          fbm(p * 1.4 + warp1 * 2.0 + vec2(8.3, 2.8)));
        float n = fbm(p + warp1 * 1.5 + warp2 * 0.5);

        float density = smoothstep(dLo, dHi, n);

        // Volume/shading noise for billowing self-shadow
        float volume = fbm(p * 2.5 + warp2);
        volume = smoothstep(0.1, 0.9, volume);

        // Proximity-based color ramp
        float proximity = 1.0 - smoothstep(0.0, 0.55, r);
        vec3 lit = mix(warmColor, hotColor, smoothstep(0.55, 0.95, proximity));
        vec3 mid = mix(coolColor, warmColor, proximity);
        vec3 far = mix(darkColor, coolColor, smoothstep(0.0, 0.35, proximity));
        vec3 color = mix(far, mid, smoothstep(0.15, 0.55, proximity));
        color = mix(color, lit, smoothstep(0.55, 0.9, proximity));
        color = mix(shadowColor, color, volume * 0.7 + 0.3);

        // Triangular wedge mask: clouds form two triangles, each with apex at the
        // source and fanning up-and-outward to the screen edges. A V-shape gap in
        // the middle lets the beam read clearly.
        // d.x = horizontal offset, d.y = vertical (positive = above source)
        // Require |d.x| to be at least some fraction of d.y (i.e. not too vertical).
        // wedge = 0 directly above source, 1 at diagonals, 1 horizontally.
        float horizRatio = abs(d.x) / max(d.y, 0.01);
        float wedge = smoothstep(0.2, 0.6, horizRatio);
        // Below source: fade out (we don't want clouds under the horizon)
        wedge *= smoothstep(-0.02, 0.05, d.y);

        // Soft band edges so clouds taper out at top and bottom of the band
        float softBand = smoothstep(bandBottom - 0.03, bandBottom + 0.04, vUv.y)
                       * smoothstep(bandTop + 0.03, bandTop - 0.04, vUv.y);

        // Fade at the left/right screen edges
        float leftRightFade = smoothstep(0.0, 0.08, vUv.x) * smoothstep(1.0, 0.92, vUv.x);

        float alpha = density * wedge * softBand * leftRightFade * opacity;
        gl_FragColor = vec4(color, alpha);
      }
    `,
    transparent: true,
    depthWrite: false,
  }), [scale, speed, densityThresh, opacity, bandTop, bandBottom]);

  useFrame((state) => {
    if (meshRef.current) {
      const mat = meshRef.current.material as THREE.ShaderMaterial;
      mat.uniforms.time.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh ref={meshRef} position={[0, 3, z]}>
      <planeGeometry args={[80, 45]} />
      <shaderMaterial args={[shader]} />
    </mesh>
  );
}

function SwirlingClouds() {
  return (
    <>
      {/* Base layer — slowest, widest, solid fill */}
      <CloudLayer
        z={-26.3} scale={1.3} speed={0.04}
        densityThresh={[0.18, 0.55]} opacity={1.0}
        bandTop={0.78} bandBottom={0.40}
      />
      {/* Mid layer — main billow texture, full opacity */}
      <CloudLayer
        z={-26.0} scale={1.0} speed={0.08}
        densityThresh={[0.20, 0.60]} opacity={1.0}
        bandTop={0.76} bandBottom={0.42}
      />
      {/* Foreground wisps — faster, bigger features */}
      <CloudLayer
        z={-25.7} scale={0.7} speed={0.15}
        densityThresh={[0.28, 0.72]} opacity={0.80}
        bandTop={0.74} bandBottom={0.44}
      />
    </>
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
      <PlanetSurface />
      <BeamSource />
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
