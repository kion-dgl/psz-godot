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

  // Located at the base of the beam, on top of the ground bulge (UV ~0.36 → world y≈2)
  return (
    <mesh ref={meshRef} position={[0, 1.5, -25]}>
      <planeGeometry args={[6, 6]} />
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

/** Clouds swirling up from the beam source and flowing outward to screen edges.
 *  Color ramp by distance: warm cream near source -> pink -> purple -> deep blue at edges. */
function SwirlingClouds() {
  const meshRef = useRef<THREE.Mesh>(null);
  const shader = useMemo(() => ({
    uniforms: {
      time: { value: 0 },
      hotColor: { value: new THREE.Color('#fde8c8') },   // cream near source
      warmColor: { value: new THREE.Color('#f0a0a8') },  // pink mid
      coolColor: { value: new THREE.Color('#5a5890') },  // purple
      darkColor: { value: new THREE.Color('#14193e') },  // deep navy at edges
      shadowColor: { value: new THREE.Color('#0a0e28') }, // self-shadow
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
      uniform vec3 hotColor;
      uniform vec3 warmColor;
      uniform vec3 coolColor;
      uniform vec3 darkColor;
      uniform vec3 shadowColor;
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
        vec2 d = vec2((vUv.x - source.x) * 1.78, vUv.y - source.y);
        float r = length(d);

        // Directional drift: clouds flow outward at ~60° from vertical
        // Left half drifts up-and-left, right half drifts up-and-right
        // 60° from vertical = atan2 angle of ±30° from horizontal
        float side = sign(d.x);  // -1 left, +1 right
        // Drift vector per side: (±cos30, sin30) = (±0.866, 0.5)
        vec2 drift = vec2(side * 0.866, 0.5);

        // Sample FBM in world-ish coordinates, offset by time along drift direction.
        // Larger scale = bigger billows (cumulus feel)
        vec2 worldP = vec2(d.x * 1.4, d.y * 1.4);
        worldP -= drift * time * 0.12;

        // Heavy domain warping for curling/billowing shapes
        vec2 warp1 = vec2(fbm(worldP * 0.8 + vec2(0.0, time * 0.06)),
                          fbm(worldP * 0.8 + vec2(5.2, 1.3)));
        vec2 warp2 = vec2(fbm(worldP * 1.5 + warp1 * 2.0),
                          fbm(worldP * 1.5 + warp1 * 2.0 + vec2(8.3, 2.8)));
        float n = fbm(worldP + warp1 * 1.5 + warp2 * 0.6);

        // Thick clouds — lower threshold, wider tonal range
        float density = smoothstep(0.22, 0.72, n);

        // Volume/shading noise — creates billowing self-shadows
        float volume = fbm(worldP * 2.5 + warp2);
        volume = smoothstep(0.1, 0.9, volume);

        // Proximity-based color ramp (closeness to source)
        float proximity = 1.0 - smoothstep(0.0, 0.55, r);
        vec3 lit = mix(warmColor, hotColor, smoothstep(0.55, 0.95, proximity));
        vec3 mid = mix(coolColor, warmColor, proximity);
        vec3 far = mix(darkColor, coolColor, smoothstep(0.0, 0.35, proximity));
        vec3 color = mix(far, mid, smoothstep(0.15, 0.55, proximity));
        color = mix(color, lit, smoothstep(0.55, 0.9, proximity));

        // Self-shadow: darker on the anti-light side of each billow
        color = mix(shadowColor, color, volume * 0.7 + 0.3);

        // Masks
        float sourceFade = smoothstep(0.04, 0.14, r);
        float outerFade = 1.0 - smoothstep(0.6, 0.98, r);
        float centerColumn = smoothstep(0.0, 0.08, abs(vUv.x - 0.5));
        float upward = smoothstep(source.y - 0.08, source.y + 0.08, vUv.y);

        float alpha = density * sourceFade * outerFade * centerColumn * upward;
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
