import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { createNoise2D, createNoise3D } from 'simplex-noise';

const CANVAS_W = 1280;
const CANVAS_H = 720;

const ASSET_BASE = '/psz-godot/assets/title';
const GLB_PATH = `${ASSET_BASE}/scene.glb`;

const TEXTURE_SLOTS: Record<string, string> = {
  none: '',
  clouds: `${ASSET_BASE}/clouds.png`,
  beam: `${ASSET_BASE}/beam.png`,
  waves: `${ASSET_BASE}/waves.png`,
};

const DEFAULT_SCROLLS: Record<string, { scrollX: number; scrollY: number }> = {
  dstitle_2: { scrollX: 0.03, scrollY: 0 },
  dstitle_3: { scrollX: 0.02, scrollY: 0 },
  dstitle_4: { scrollX: 0, scrollY: 0.02 },
  dstitle_6: { scrollX: 0, scrollY: 0.02 },
};

// Meshes share a skeleton in the GLB, so to transform a subset independently
// we load extra GLB instances — one per group — with everything else hidden.
type Group = {
  names: string[];
  offset?: [number, number, number];
  scale?: number;
  renderOrder?: number;
};

const GROUPS: Group[] = [
  // Clouds — sit behind the light
  { names: ['dstitle_2', 'dstitle_3'], offset: [0, 16, 0] },
  // Light / title — scaled down and dropped to sit in front of the clouds
  { names: ['dstitle_4', 'dstitle_5', 'dstitle_6'], offset: [0, -27, 0], scale: 0.8, renderOrder: 10 },
];

// Kept for the copy-config output so per-node scale still appears.
const DEFAULT_SCALES: Record<string, number> = Object.fromEntries(
  GROUPS.flatMap((g) => (g.scale !== undefined ? g.names.map((n) => [n, g.scale as number]) : [])),
);

type NodeMeta = {
  uuid: string;
  name: string;
  type: string;
  depth: number;
  visible: boolean;
  position: [number, number, number];
  rotation: [number, number, number];
  scale: [number, number, number];
  textureSlot: keyof typeof TEXTURE_SLOTS;
  hasMesh: boolean;
  scrollX: number;
  scrollY: number;
};

function formatVec(v: THREE.Vector3 | THREE.Euler): [number, number, number] {
  return [+v.x.toFixed(3), +v.y.toFixed(3), +v.z.toFixed(3)];
}

// Find the root bone of a SkinnedMesh's skeleton (bone whose parent isn't a bone).
function findSkeletonRootBone(root: THREE.Object3D): THREE.Bone | null {
  let firstSkinned: THREE.SkinnedMesh | null = null;
  root.traverse((obj) => {
    const m = obj as THREE.SkinnedMesh;
    if (!firstSkinned && m.isSkinnedMesh) firstSkinned = m;
  });
  if (!firstSkinned) return null;
  const skel = (firstSkinned as THREE.SkinnedMesh).skeleton;
  if (!skel || skel.bones.length === 0) return null;
  return skel.bones.find((b) => !b.parent || !(b.parent as THREE.Bone).isBone) ?? null;
}

export default function TitleScreen() {
  const hostRef = useRef<HTMLDivElement>(null);
  const objectsRef = useRef<Map<string, THREE.Object3D>>(new Map());
  const materialsRef = useRef<Map<string, THREE.MeshBasicMaterial>>(new Map());
  const texCacheRef = useRef<Map<string, THREE.Texture>>(new Map());
  const scrollSpeedsRef = useRef<Map<string, { x: number; y: number }>>(new Map());
  const [nodes, setNodes] = useState<NodeMeta[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [cameraY, setCameraY] = useState(-58);
  const [cameraZ, setCameraZ] = useState(144);
  const [fov, setFov] = useState(45);
  const [bgVisible, setBgVisible] = useState(true);
  const [showHelpers, setShowHelpers] = useState(false);
  const [bboxInfo, setBboxInfo] = useState<string>('');
  const sceneRefs = useRef<{
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    renderer: THREE.WebGLRenderer;
    bg: THREE.Mesh | null;
    helpers: THREE.Group;
    root: THREE.Object3D | null;
  } | null>(null);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x05051a);

    const camera = new THREE.PerspectiveCamera(fov, CANVAS_W / CANVAS_H, 0.1, 2000);
    camera.position.set(0, cameraY, cameraZ);
    camera.lookAt(0, cameraY, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(CANVAS_W, CANVAS_H);
    renderer.setPixelRatio(1);
    host.appendChild(renderer.domElement);

    // Low ambient so the moon's shadowed side actually reads dark. The GLB
    // meshes and backdrop use MeshBasicMaterial, which ignores lighting
    // entirely, so this only affects the moon.
    scene.add(new THREE.AmbientLight(0xffffff, 0.12));

    const helpers = new THREE.Group();
    helpers.add(new THREE.AxesHelper(1));
    helpers.add(new THREE.GridHelper(4, 8, 0x444466, 0x222244));
    scene.add(helpers);

    // Backdrop sits further back than the horizon plane so it shows through
    // the transparent parts of horizon.png.
    const STAR_X = 520;
    const STAR_Y_LO = -220;
    const STAR_Y_HI = 140;
    const STAR_Z_MIN = -60;
    const STAR_Z_MAX = -40;
    const randY = () => STAR_Y_LO + Math.random() * (STAR_Y_HI - STAR_Y_LO);
    const randZ = () => STAR_Z_MIN + Math.random() * (STAR_Z_MAX - STAR_Z_MIN);

    // Shared radial-gradient texture used by nebulae and halo.
    const nebulaTex = (() => {
      const c = document.createElement('canvas');
      c.width = c.height = 256;
      const ctx = c.getContext('2d')!;
      const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
      g.addColorStop(0, 'rgba(255,255,255,1)');
      g.addColorStop(0.35, 'rgba(255,255,255,0.5)');
      g.addColorStop(0.7, 'rgba(255,255,255,0.15)');
      g.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, 256, 256);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      return t;
    })();
    // Seeded pseudo-random so nebula/star colors stay stable across hot reloads.
    const NEBULA_COLORS = [0x5566ff, 0xaa55ff, 0x4488dd, 0xff88cc, 0x6644aa, 0x3355aa, 0xcc66ee, 0x88aaff, 0x552288, 0xffaaee];
    const NEBULAE: { pos: [number, number, number]; size: number; color: number; opacity: number }[] = [];
    for (let i = 0; i < 16; i++) {
      const x = (Math.random() - 0.5) * 480;
      const y = STAR_Y_LO + Math.random() * (STAR_Y_HI - STAR_Y_LO) + 20;
      NEBULAE.push({
        pos: [x, y, -55 - Math.random() * 10],
        size: 90 + Math.random() * 140,
        color: NEBULA_COLORS[Math.floor(Math.random() * NEBULA_COLORS.length)],
        opacity: 0.15 + Math.random() * 0.25,
      });
    }
    NEBULAE.forEach((n) => {
      const mat = new THREE.MeshBasicMaterial({
        map: nebulaTex,
        color: n.color,
        transparent: true,
        opacity: n.opacity,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      });
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(n.size, n.size), mat);
      mesh.position.set(...n.pos);
      mesh.renderOrder = -25;
      scene.add(mesh);
    });

    // Colored, varied-size stars via shader. Temperature-style palette.
    const STAR_PALETTE: [number, number, number][] = [
      [1.0, 1.0, 1.0],   // white
      [1.0, 1.0, 1.0],
      [1.0, 1.0, 1.0],
      [1.0, 1.0, 1.0],
      [0.75, 0.85, 1.0], // blue
      [0.65, 0.8, 1.0],
      [1.0, 0.95, 0.75], // pale yellow
      [1.0, 0.8, 0.55],  // orange
      [1.0, 0.65, 0.55], // red
      [0.9, 0.8, 1.0],   // lavender
    ];
    const STATIC_COUNT = 3200;
    const staticPositions = new Float32Array(STATIC_COUNT * 3);
    const staticColors = new Float32Array(STATIC_COUNT * 3);
    const staticSizes = new Float32Array(STATIC_COUNT);
    for (let i = 0; i < STATIC_COUNT; i++) {
      staticPositions[i * 3 + 0] = (Math.random() - 0.5) * STAR_X;
      staticPositions[i * 3 + 1] = randY();
      staticPositions[i * 3 + 2] = randZ();
      const [r, g, b] = STAR_PALETTE[Math.floor(Math.random() * STAR_PALETTE.length)];
      staticColors[i * 3 + 0] = r;
      staticColors[i * 3 + 1] = g;
      staticColors[i * 3 + 2] = b;
      // Mostly small stars, a few larger ones.
      const roll = Math.random();
      staticSizes[i] = roll < 0.7 ? 1.0 + Math.random() * 0.8 : roll < 0.95 ? 2.0 + Math.random() * 1.0 : 3.5 + Math.random() * 1.5;
    }
    const staticGeo = new THREE.BufferGeometry();
    staticGeo.setAttribute('position', new THREE.BufferAttribute(staticPositions, 3));
    staticGeo.setAttribute('aColor', new THREE.BufferAttribute(staticColors, 3));
    staticGeo.setAttribute('aSize', new THREE.BufferAttribute(staticSizes, 1));
    const staticMat = new THREE.ShaderMaterial({
      vertexShader: `
        attribute vec3 aColor;
        attribute float aSize;
        varying vec3 vColor;
        void main() {
          vColor = aColor;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_Position = projectionMatrix * mv;
          gl_PointSize = aSize * (180.0 / -mv.z);
        }
      `,
      fragmentShader: `
        varying vec3 vColor;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = length(c);
          float a = smoothstep(0.5, 0.0, d);
          gl_FragColor = vec4(vColor, a);
        }
      `,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const stars = new THREE.Points(staticGeo, staticMat);
    stars.name = 'Starfield';
    stars.renderOrder = -20;
    scene.add(stars);

    // Sparkle stars — sparser, custom shader pulses size/alpha by per-vertex phase.
    const SPARKLE_COUNT = 220;
    const sparklePositions = new Float32Array(SPARKLE_COUNT * 3);
    const sparklePhases = new Float32Array(SPARKLE_COUNT);
    for (let i = 0; i < SPARKLE_COUNT; i++) {
      sparklePositions[i * 3 + 0] = (Math.random() - 0.5) * STAR_X;
      sparklePositions[i * 3 + 1] = randY();
      sparklePositions[i * 3 + 2] = randZ();
      sparklePhases[i] = Math.random();
    }
    const sparkleGeo = new THREE.BufferGeometry();
    sparkleGeo.setAttribute('position', new THREE.BufferAttribute(sparklePositions, 3));
    sparkleGeo.setAttribute('aPhase', new THREE.BufferAttribute(sparklePhases, 1));
    const sparkleMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 } },
      vertexShader: `
        attribute float aPhase;
        uniform float uTime;
        varying float vAlpha;
        void main() {
          float pulse = 0.5 + 0.5 * sin(uTime * 2.5 + aPhase * 6.2831);
          vAlpha = 0.2 + 0.8 * pulse;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_Position = projectionMatrix * mv;
          gl_PointSize = (1.5 + 2.5 * pulse) * (200.0 / -mv.z);
        }
      `,
      fragmentShader: `
        varying float vAlpha;
        void main() {
          vec2 c = gl_PointCoord - 0.5;
          float d = length(c);
          float a = smoothstep(0.5, 0.0, d) * vAlpha;
          gl_FragColor = vec4(1.0, 1.0, 1.0, a);
        }
      `,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const sparkles = new THREE.Points(sparkleGeo, sparkleMat);
    sparkles.name = 'Sparkles';
    sparkles.renderOrder = -19;
    scene.add(sparkles);

    // Moon — simplex-noise painted rocky surface. Sample 3D noise on unit
    // sphere coords so the equirectangular texture has no seam.
    const moonTex = (() => {
      const W = 1024;
      const H = 512;
      const noise = createNoise3D();
      const c = document.createElement('canvas');
      c.width = W;
      c.height = H;
      const ctx = c.getContext('2d')!;
      const img = ctx.createImageData(W, H);
      const data = img.data;

      const fbm = (x: number, y: number, z: number, octaves: number, lac = 2.0, gain = 0.5) => {
        let amp = 1;
        let freq = 1;
        let v = 0;
        let tot = 0;
        for (let i = 0; i < octaves; i++) {
          v += noise(x * freq, y * freq, z * freq) * amp;
          tot += amp;
          amp *= gain;
          freq *= lac;
        }
        return v / tot; // -1..1
      };
      const ridged = (x: number, y: number, z: number, octaves: number) => {
        let amp = 1;
        let freq = 1;
        let v = 0;
        let tot = 0;
        for (let i = 0; i < octaves; i++) {
          v += (1 - Math.abs(noise(x * freq, y * freq, z * freq))) * amp;
          tot += amp;
          amp *= 0.5;
          freq *= 2;
        }
        return v / tot; // 0..1
      };

      const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
      // Color ramp: dark purple → mid purple → blue-purple → pale blue-white
      const ramp = (t: number): [number, number, number] => {
        t = Math.max(0, Math.min(1, t));
        const stops: [number, [number, number, number]][] = [
          [0.0, [0x12, 0x10, 0x2a]],
          [0.3, [0x2a, 0x22, 0x54]],
          [0.55, [0x48, 0x40, 0x8a]],
          [0.75, [0x6c, 0x70, 0xb8]],
          [0.9, [0x9a, 0xa8, 0xd8]],
          [1.0, [0xd0, 0xdc, 0xf4]],
        ];
        for (let i = 0; i < stops.length - 1; i++) {
          const [t0, c0] = stops[i];
          const [t1, c1] = stops[i + 1];
          if (t <= t1) {
            const k = (t - t0) / (t1 - t0);
            return [lerp(c0[0], c1[0], k), lerp(c0[1], c1[1], k), lerp(c0[2], c1[2], k)];
          }
        }
        return stops[stops.length - 1][1];
      };

      for (let y = 0; y < H; y++) {
        const theta = (y / (H - 1)) * Math.PI; // 0..PI (pole to pole)
        const sTheta = Math.sin(theta);
        const cTheta = Math.cos(theta);
        for (let x = 0; x < W; x++) {
          const phi = (x / W) * Math.PI * 2; // 0..2PI
          const nx = sTheta * Math.cos(phi);
          const ny = sTheta * Math.sin(phi);
          const nz = cTheta;

          // Base rocky terrain
          const base = fbm(nx * 2.5, ny * 2.5, nz * 2.5, 5);
          // Cloud bands — stretch horizontally by scaling y-sample less
          const cloud = ridged(nx * 3, ny * 1.2 + 5, nz * 3, 4);
          // Domain-warp the clouds a touch for wispy feel
          const warp = fbm(nx * 1.5 + 10, ny * 1.5, nz * 1.5, 3) * 0.6;

          let v = (base + 1) * 0.5; // 0..1
          v = Math.min(1, v + Math.max(0, cloud - 0.45) * 0.7 + warp * 0.15);
          // Boost contrast
          v = Math.pow(v, 0.85);

          const [r, g, b] = ramp(v);
          const idx = (y * W + x) * 4;
          data[idx + 0] = r | 0;
          data[idx + 1] = g | 0;
          data[idx + 2] = b | 0;
          data[idx + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      t.wrapS = THREE.RepeatWrapping;
      return t;
    })();
    const moonGeo = new THREE.SphereGeometry(28, 64, 64);
    const moonMat = new THREE.MeshLambertMaterial({
      map: moonTex,
      emissive: 0x060614,
    });
    const moon = new THREE.Mesh(moonGeo, moonMat);
    moon.position.set(0, 8, -25);
    moon.renderOrder = -15;
    scene.add(moon);
    // Back-light the moon so the camera-facing hemisphere is almost fully
    // shadowed, with just a rim catching light from behind/above.
    const moonLight = new THREE.DirectionalLight(0xbfd0ff, 1.6);
    moonLight.position.set(10, 30, -120);
    moonLight.target = moon;
    scene.add(moonLight);
    scene.add(moonLight.target);
    // Under-rim light from below-behind for the unnatural crescent: bottom
    // and sides wrap into light while the face stays dark.
    const moonUnderLight = new THREE.DirectionalLight(0xa8c4ff, 1.3);
    moonUnderLight.position.set(0, -80, -40);
    moonUnderLight.target = moon;
    scene.add(moonUnderLight);

    // Blue halo behind the moon — larger sprite with radial gradient.
    const haloTex = (() => {
      const c = document.createElement('canvas');
      c.width = c.height = 256;
      const ctx = c.getContext('2d')!;
      const g = ctx.createRadialGradient(128, 128, 40, 128, 128, 128);
      g.addColorStop(0, 'rgba(180,210,255,0.9)');
      g.addColorStop(0.25, 'rgba(140,180,255,0.55)');
      g.addColorStop(0.55, 'rgba(90,140,220,0.2)');
      g.addColorStop(1, 'rgba(90,140,220,0)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, 256, 256);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      return t;
    })();
    const haloMat = new THREE.SpriteMaterial({
      map: haloTex,
      color: 0xffffff,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const halo = new THREE.Sprite(haloMat);
    halo.scale.set(90, 90, 1);
    halo.position.set(moon.position.x, moon.position.y, moon.position.z - 2);
    halo.renderOrder = -16;
    scene.add(halo);

    // Background plane sits in the scene at the back, sized for 16:9.
    // Initial size (240 × 135) roughly matches the GLB Y extent (135) scaled out to 16:9.
    const BG_W = 240;
    const BG_H = BG_W * (9 / 16);
    const bgGeo = new THREE.PlaneGeometry(BG_W, BG_H);
    const bgMat = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      side: THREE.DoubleSide,
      transparent: true,
      depthWrite: false,
    });
    const bg = new THREE.Mesh(bgGeo, bgMat);
    bg.name = 'Background';
    bg.renderOrder = -10;
    // Place behind GLB contents (GLB min.z ≈ 5.92, so sit a bit behind that)
    bg.position.set(0, -60, 0);
    scene.add(bg);
    objectsRef.current.set(bg.uuid, bg);
    materialsRef.current.set(bg.uuid, bgMat);

    // Horizon texture — painted procedurally from simplex noise so there's
    // no AI-generated art involved. Atmospheric haze gradient plus three
    // layered silhouette ridges for depth.
    const horizonTex = (() => {
      const W = 1280;
      const H = 720;
      const c = document.createElement('canvas');
      c.width = W;
      c.height = H;
      const ctx = c.getContext('2d')!;
      const noise = createNoise2D();

      const HORIZON_Y = Math.floor(H * 0.6);

      // Atmospheric haze — fades from transparent just above the horizon
      // into a deep purple at the canvas bottom.
      const grad = ctx.createLinearGradient(0, HORIZON_Y - H * 0.18, 0, H);
      grad.addColorStop(0, 'rgba(70, 45, 120, 0)');
      grad.addColorStop(0.22, 'rgba(95, 60, 150, 0.32)');
      grad.addColorStop(0.5, 'rgba(60, 35, 105, 0.7)');
      grad.addColorStop(0.78, 'rgba(25, 15, 55, 0.94)');
      grad.addColorStop(1, 'rgba(8, 5, 22, 1.0)');
      ctx.fillStyle = grad;
      ctx.fillRect(0, HORIZON_Y - H * 0.18, W, H);

      // Three silhouette layers back→front. Earlier layers use higher
      // alpha color values (more haze); the front layer is near-black.
      type Layer = { y: number; amp: number; freq: number; fill: string };
      const layers: Layer[] = [
        { y: HORIZON_Y + 26, amp: 18, freq: 0.0028, fill: 'rgba(70, 45, 120, 0.6)' },
        { y: HORIZON_Y + 68, amp: 36, freq: 0.0050, fill: 'rgba(28, 16, 60, 0.95)' },
        { y: HORIZON_Y + 130, amp: 58, freq: 0.0078, fill: 'rgba(8, 4, 20, 1.0)' },
      ];
      for (const L of layers) {
        ctx.beginPath();
        ctx.moveTo(0, H);
        for (let x = 0; x <= W; x += 2) {
          let n = 0;
          let amp = 1;
          let freq = L.freq;
          let tot = 0;
          for (let o = 0; o < 4; o++) {
            n += noise(x * freq, o * 31.7) * amp;
            tot += amp;
            amp *= 0.5;
            freq *= 2;
          }
          n /= tot;
          ctx.lineTo(x, L.y + n * L.amp);
        }
        ctx.lineTo(W, H);
        ctx.closePath();
        ctx.fillStyle = L.fill;
        ctx.fill();
      }

      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      return t;
    })();
    bgMat.map = horizonTex;
    bgMat.needsUpdate = true;

    const bgNode: NodeMeta = {
      uuid: bg.uuid,
      name: bg.name,
      type: 'Background',
      depth: 0,
      visible: bg.visible,
      position: formatVec(bg.position),
      rotation: formatVec(bg.rotation),
      scale: formatVec(bg.scale),
      textureSlot: 'none',
      hasMesh: true,
      scrollX: 0,
      scrollY: 0,
    };

    sceneRefs.current = { scene, camera, renderer, bg, helpers, root: null };

    const gltf = new GLTFLoader();
    const loadGLB = () =>
      new Promise<THREE.Object3D>((resolve) => gltf.load(GLB_PATH, (res) => resolve(res.scene)));

    const processMesh = (obj: THREE.Object3D) => {
      const mesh = obj as THREE.Mesh;
      const orig = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
      const origMap = (orig as THREE.MeshStandardMaterial | undefined)?.map ?? null;
      if (origMap) {
        origMap.wrapS = THREE.RepeatWrapping;
        origMap.wrapT = THREE.RepeatWrapping;
        origMap.needsUpdate = true;
      }
      const hasVertexColors = !!mesh.geometry.getAttribute('color');
      const mat = new THREE.MeshBasicMaterial({
        map: origMap,
        color: 0xffffff,
        vertexColors: hasVertexColors,
        transparent: true,
        alphaTest: 0.01,
        side: THREE.DoubleSide,
        depthWrite: false,
      });
      mesh.material = mat;
      materialsRef.current.set(obj.uuid, mat);
    };

    const registerNode = (
      obj: THREE.Object3D,
      depth: number,
      collected: NodeMeta[],
    ) => {
      objectsRef.current.set(obj.uuid, obj);
      const hasMesh = !!(obj as THREE.Mesh).isMesh;
      if (hasMesh) processMesh(obj);
      const defaults = DEFAULT_SCROLLS[obj.name];
      if (defaults && hasMesh) {
        scrollSpeedsRef.current.set(obj.uuid, { x: defaults.scrollX, y: defaults.scrollY });
      }
      collected.push({
        uuid: obj.uuid,
        name: obj.name || `(unnamed ${obj.type})`,
        type: obj.type,
        depth,
        visible: obj.visible,
        position: formatVec(obj.position),
        rotation: formatVec(obj.rotation),
        scale: formatVec(obj.scale),
        textureSlot: 'none',
        hasMesh,
        scrollX: defaults?.scrollX ?? 0,
        scrollY: defaults?.scrollY ?? 0,
      });
    };

    // All names claimed by some group — hidden from the default instance.
    const groupedNames = new Set(GROUPS.flatMap((g) => g.names));

    Promise.all([loadGLB(), ...GROUPS.map(() => loadGLB())]).then((roots) => {
      const rootDefault = roots[0];
      const groupRoots = roots.slice(1);
      roots.forEach((r) => scene.add(r));
      if (sceneRefs.current) sceneRefs.current.root = rootDefault;

      // Default instance: hide every mesh claimed by a group.
      rootDefault.traverse((obj) => {
        if ((obj as THREE.Mesh).isMesh && groupedNames.has(obj.name)) {
          obj.visible = false;
        }
      });

      // Group instances: hide everything except that group's meshes, then
      // apply scale/offset/renderOrder to just the visible subset.
      GROUPS.forEach((group, i) => {
        const root = groupRoots[i];
        const keep = new Set(group.names);
        root.traverse((obj) => {
          if ((obj as THREE.Mesh).isMesh && !keep.has(obj.name)) {
            obj.visible = false;
          }
        });
        if (group.scale !== undefined) {
          const bone = findSkeletonRootBone(root);
          if (bone) bone.scale.setScalar(group.scale);
        }
        if (group.offset) {
          root.position.set(
            root.position.x + group.offset[0],
            root.position.y + group.offset[1],
            root.position.z + group.offset[2],
          );
        }
        if (group.renderOrder !== undefined) {
          root.traverse((obj) => {
            if ((obj as THREE.Mesh).isMesh && keep.has(obj.name)) {
              obj.renderOrder = group.renderOrder!;
            }
          });
        }
      });

      // Inspector: walk default instance (skipping claimed meshes) plus each
      // group's own visible meshes.
      const collected: NodeMeta[] = [];
      const walkDefault = (obj: THREE.Object3D, depth: number) => {
        const isMesh = !!(obj as THREE.Mesh).isMesh;
        if (!(isMesh && groupedNames.has(obj.name))) {
          registerNode(obj, depth, collected);
        }
        obj.children.forEach((c) => walkDefault(c, depth + 1));
      };
      walkDefault(rootDefault, 0);
      GROUPS.forEach((group, i) => {
        const root = groupRoots[i];
        const keep = new Set(group.names);
        root.traverse((obj) => {
          if ((obj as THREE.Mesh).isMesh && keep.has(obj.name)) {
            registerNode(obj, 1, collected);
          }
        });
      });

      setNodes([bgNode, ...collected]);

      const box = new THREE.Box3().setFromObject(rootDefault);
      const size = new THREE.Vector3();
      const center = new THREE.Vector3();
      box.getSize(size);
      box.getCenter(center);
      const maxDim = Math.max(size.x, size.y, size.z) || 1;
      setBboxInfo(
        `bbox: min(${box.min.x.toFixed(2)}, ${box.min.y.toFixed(2)}, ${box.min.z.toFixed(2)}) ` +
          `max(${box.max.x.toFixed(2)}, ${box.max.y.toFixed(2)}, ${box.max.z.toFixed(2)}) ` +
          `size(${size.x.toFixed(2)}, ${size.y.toFixed(2)}, ${size.z.toFixed(2)})`,
      );
      helpers.clear();
      helpers.add(new THREE.AxesHelper(maxDim));
      helpers.add(new THREE.GridHelper(maxDim * 2, 10, 0x444466, 0x222244));
      helpers.position.copy(center);
    });

    let raf = 0;
    const clock = new THREE.Clock();
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = clock.getDelta();
      scrollSpeedsRef.current.forEach((speed, uuid) => {
        const mat = materialsRef.current.get(uuid);
        if (!mat || !mat.map) return;
        if (speed.x !== 0) mat.map.offset.x = (mat.map.offset.x + speed.x * dt) % 1;
        if (speed.y !== 0) mat.map.offset.y = (mat.map.offset.y + speed.y * dt) % 1;
      });
      sparkleMat.uniforms.uTime.value = clock.elapsedTime;
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(raf);
      renderer.dispose();
      if (host.contains(renderer.domElement)) host.removeChild(renderer.domElement);
      objectsRef.current.clear();
      materialsRef.current.clear();
      texCacheRef.current.clear();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Camera updates
  useEffect(() => {
    const s = sceneRefs.current;
    if (!s) return;
    s.camera.position.set(0, cameraY, cameraZ);
    s.camera.lookAt(0, cameraY, 0);
    s.camera.fov = fov;
    s.camera.updateProjectionMatrix();
  }, [cameraY, cameraZ, fov]);

  // Background visibility
  useEffect(() => {
    const s = sceneRefs.current;
    if (!s || !s.bg) return;
    s.bg.visible = bgVisible;
  }, [bgVisible]);

  // Helpers visibility
  useEffect(() => {
    const s = sceneRefs.current;
    if (!s) return;
    s.helpers.visible = showHelpers;
  }, [showHelpers]);

  const updateNode = (uuid: string, patch: Partial<NodeMeta>) => {
    setNodes((prev) => prev.map((n) => (n.uuid === uuid ? { ...n, ...patch } : n)));
    const obj = objectsRef.current.get(uuid);
    if (!obj) return;
    if (patch.visible !== undefined) obj.visible = patch.visible;
    if (patch.position) obj.position.set(...patch.position);
    if (patch.rotation) obj.rotation.set(...patch.rotation);
    if (patch.scale) obj.scale.set(...patch.scale);
    if (patch.textureSlot !== undefined) {
      const mat = materialsRef.current.get(uuid);
      const url = TEXTURE_SLOTS[patch.textureSlot];
      if (mat) {
        if (!url) {
          mat.map = null;
          mat.needsUpdate = true;
        } else {
          const cached = texCacheRef.current.get(url);
          if (cached) {
            mat.map = cached;
            mat.needsUpdate = true;
          } else {
            new THREE.TextureLoader().load(url, (tex) => {
              tex.colorSpace = THREE.SRGBColorSpace;
              tex.wrapS = THREE.RepeatWrapping;
              tex.wrapT = THREE.RepeatWrapping;
              texCacheRef.current.set(url, tex);
              mat.map = tex;
              mat.needsUpdate = true;
            });
          }
        }
      }
    }
    if (patch.scrollX !== undefined || patch.scrollY !== undefined) {
      const cur = scrollSpeedsRef.current.get(uuid) ?? { x: 0, y: 0 };
      const next = {
        x: patch.scrollX !== undefined ? patch.scrollX : cur.x,
        y: patch.scrollY !== undefined ? patch.scrollY : cur.y,
      };
      if (next.x === 0 && next.y === 0) {
        scrollSpeedsRef.current.delete(uuid);
      } else {
        scrollSpeedsRef.current.set(uuid, next);
      }
    }
  };

  const selectedNode = nodes.find((n) => n.uuid === selected) || null;

  const [copyStatus, setCopyStatus] = useState<string>('');
  const copyConfig = async () => {
    const config = {
      cameraY: +cameraY.toFixed(2),
      cameraZ: +cameraZ.toFixed(2),
      fov,
      nodes: Object.fromEntries(
        nodes
          .filter((n) => n.hasMesh)
          .map((n) => [
            n.name,
            {
              scrollX: +n.scrollX.toFixed(3),
              scrollY: +n.scrollY.toFixed(3),
            },
          ]),
      ),
    };
    const text = JSON.stringify(config, null, 2);
    try {
      await navigator.clipboard.writeText(text);
      setCopyStatus('copied');
    } catch {
      setCopyStatus('failed (see console)');
      console.log(text);
    }
    setTimeout(() => setCopyStatus(''), 1500);
  };

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0a1a', color: '#e0e0e0', overflow: 'hidden' }}>
      {/* Canvas column */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-start', padding: 4, gap: 4, overflow: 'hidden', minWidth: 0 }}>
        <div
          ref={hostRef}
          style={{
            width: CANVAS_W,
            height: CANVAS_H,
            border: '1px solid #2a2a4a',
            background: '#000',
            flexShrink: 0,
          }}
        />
        <div style={{ display: 'flex', gap: 12, alignItems: 'center', fontSize: 11, flexWrap: 'wrap', justifyContent: 'center' }}>
          <span style={{ color: '#666' }}>{CANVAS_W}×{CANVAS_H}</span>
          <label>
            Y{' '}
            <input
              type="range"
              min={-200}
              max={200}
              step={1}
              value={cameraY}
              onChange={(e) => setCameraY(+e.target.value)}
              style={{ verticalAlign: 'middle' }}
            />{' '}
            <input
              type="number"
              step={1}
              value={cameraY}
              onChange={(e) => setCameraY(+e.target.value)}
              style={{ width: 60, background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
            />
          </label>
          <label>
            Z{' '}
            <input
              type="range"
              min={-1000}
              max={1000}
              step={1}
              value={cameraZ}
              onChange={(e) => setCameraZ(+e.target.value)}
              style={{ verticalAlign: 'middle' }}
            />{' '}
            <input
              type="number"
              step={1}
              value={cameraZ}
              onChange={(e) => setCameraZ(+e.target.value)}
              style={{ width: 60, background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
            />
          </label>
          <label>
            FOV{' '}
            <input
              type="range"
              min={15}
              max={90}
              step={1}
              value={fov}
              onChange={(e) => setFov(+e.target.value)}
              style={{ verticalAlign: 'middle' }}
            />{' '}
            {fov}
          </label>
          <label>
            <input type="checkbox" checked={bgVisible} onChange={(e) => setBgVisible(e.target.checked)} /> bg
          </label>
          <label>
            <input type="checkbox" checked={showHelpers} onChange={(e) => setShowHelpers(e.target.checked)} /> helpers
          </label>
          <button
            onClick={copyConfig}
            style={{
              background: '#2a2a5a',
              color: '#88aaff',
              border: '1px solid #3a3a6a',
              padding: '3px 10px',
              fontSize: 11,
              cursor: 'pointer',
              borderRadius: 4,
            }}
          >
            Copy config
          </button>
          {copyStatus && <span style={{ color: '#88ccff', fontSize: 11 }}>{copyStatus}</span>}
          {bboxInfo && <span style={{ color: '#666', fontFamily: 'monospace' }}>{bboxInfo}</span>}
        </div>
      </div>

      {/* Inspector column */}
      <div style={{ width: 380, borderLeft: '1px solid #2a2a4a', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ padding: 12, borderBottom: '1px solid #2a2a4a', fontSize: 13, fontWeight: 600 }}>
          GLB Nodes ({nodes.length})
        </div>
        <div style={{ overflow: 'auto', flex: 1 }}>
          {nodes.map((n) => (
            <div
              key={n.uuid}
              onClick={() => setSelected(n.uuid)}
              style={{
                padding: `4px 12px 4px ${12 + n.depth * 12}px`,
                fontSize: 12,
                cursor: 'pointer',
                background: selected === n.uuid ? '#2a2a5a' : 'transparent',
                display: 'flex',
                alignItems: 'center',
                gap: 6,
              }}
            >
              <input
                type="checkbox"
                checked={n.visible}
                onClick={(e) => e.stopPropagation()}
                onChange={(e) => updateNode(n.uuid, { visible: e.target.checked })}
              />
              <span style={{ color: n.hasMesh ? '#88ccff' : '#888' }}>{n.type[0]}</span>
              <span style={{ color: '#e0e0e0' }}>{n.name}</span>
            </div>
          ))}
        </div>
        {selectedNode && (
          <div style={{ borderTop: '1px solid #2a2a4a', padding: 12, fontSize: 12, maxHeight: '50%', overflow: 'auto' }}>
            <div style={{ fontWeight: 600, marginBottom: 8 }}>{selectedNode.name}</div>
            <div style={{ color: '#888', marginBottom: 8 }}>{selectedNode.type} · {selectedNode.uuid.slice(0, 8)}</div>
            <Vec3Row label="position" value={selectedNode.position} step={0.1} onChange={(v) => updateNode(selectedNode.uuid, { position: v })} />
            <Vec3Row label="rotation" value={selectedNode.rotation} step={0.05} onChange={(v) => updateNode(selectedNode.uuid, { rotation: v })} />
            <Vec3Row label="scale" value={selectedNode.scale} step={0.05} onChange={(v) => updateNode(selectedNode.uuid, { scale: v })} />
            {selectedNode.hasMesh && (
              <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 4 }}>
                <label>
                  texture{' '}
                  <select
                    value={selectedNode.textureSlot}
                    onChange={(e) => updateNode(selectedNode.uuid, { textureSlot: e.target.value as keyof typeof TEXTURE_SLOTS })}
                  >
                    {Object.keys(TEXTURE_SLOTS).map((k) => (
                      <option key={k} value={k}>
                        {k}
                      </option>
                    ))}
                  </select>
                </label>
                <div style={{ display: 'grid', gridTemplateColumns: '60px 1fr 1fr', gap: 4, alignItems: 'center' }}>
                  <span style={{ color: '#888' }}>scroll</span>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ color: '#888', fontSize: 11 }}>X</span>
                    <input
                      type="number"
                      step={0.01}
                      value={selectedNode.scrollX}
                      onChange={(e) => updateNode(selectedNode.uuid, { scrollX: +e.target.value })}
                      style={{ width: '100%', background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
                    />
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <span style={{ color: '#888', fontSize: 11 }}>Y</span>
                    <input
                      type="number"
                      step={0.01}
                      value={selectedNode.scrollY}
                      onChange={(e) => updateNode(selectedNode.uuid, { scrollY: +e.target.value })}
                      style={{ width: '100%', background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
                    />
                  </label>
                </div>
                <div style={{ color: '#666', fontSize: 10 }}>UV units / second · needs RepeatWrapping</div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function Vec3Row({
  label,
  value,
  step,
  onChange,
}: {
  label: string;
  value: [number, number, number];
  step: number;
  onChange: (v: [number, number, number]) => void;
}) {
  const setAt = (i: 0 | 1 | 2, v: number) => {
    const next: [number, number, number] = [...value] as [number, number, number];
    next[i] = v;
    onChange(next);
  };
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '60px 1fr 1fr 1fr', gap: 4, alignItems: 'center', marginBottom: 4 }}>
      <span style={{ color: '#888' }}>{label}</span>
      {[0, 1, 2].map((i) => (
        <input
          key={i}
          type="number"
          step={step}
          value={value[i]}
          onChange={(e) => setAt(i as 0 | 1 | 2, +e.target.value)}
          style={{ width: '100%', background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
        />
      ))}
    </div>
  );
}
