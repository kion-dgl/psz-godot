import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { createNoise2D, createNoise3D } from 'simplex-noise';
import { assetUrl } from '../../utils/assets';

const CANVAS_W = 960;
const CANVAS_H = 540;

const ASSET_BASE = assetUrl('assets/title').replace(/\/$/, '');
const GLB_PATH = `${ASSET_BASE}/scene.glb`;

const DEFAULT_SCROLLS: Record<string, { scrollX: number; scrollY: number }> = {
  dstitle_2: { scrollX: 0.03, scrollY: 0 },
  dstitle_3: { scrollX: 0.02, scrollY: 0 },
  dstitle_4: { scrollX: 0, scrollY: 0.02 },
  dstitle_6: { scrollX: 0, scrollY: 0.02 },
};

type Group = {
  names: string[];
  offset?: [number, number, number];
  scale?: number;
  renderOrder?: number;
};

const GROUPS: Group[] = [
  { names: ['dstitle_2', 'dstitle_3'], offset: [0, 16, 0] },
  { names: ['dstitle_4', 'dstitle_5', 'dstitle_6'], offset: [0, -27, 0], scale: 0.8, renderOrder: 10 },
];

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

const VERSION = '0.30.18';

export default function TitleScreen() {
  const hostRef = useRef<HTMLDivElement>(null);
  const [blink, setBlink] = useState(true);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    const materialsMap = new Map<string, THREE.MeshBasicMaterial>();
    const scrollSpeeds = new Map<string, { x: number; y: number }>();

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x05051a);

    const cameraY = -59;
    const camera = new THREE.PerspectiveCamera(45, CANVAS_W / CANVAS_H, 0.1, 2000);
    camera.position.set(0, cameraY, 124);
    camera.lookAt(0, cameraY, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(CANVAS_W, CANVAS_H);
    renderer.setPixelRatio(1);
    host.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.12));

    // Stars
    const STAR_X = 520;
    const STAR_Y_LO = -220;
    const STAR_Y_HI = 140;
    const STAR_Z_MIN = -60;
    const STAR_Z_MAX = -40;
    const randY = () => STAR_Y_LO + Math.random() * (STAR_Y_HI - STAR_Y_LO);
    const randZ = () => STAR_Z_MIN + Math.random() * (STAR_Z_MAX - STAR_Z_MIN);

    // Nebula texture
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

    const NEBULA_COLORS = [0x5566ff, 0xaa55ff, 0x4488dd, 0xff88cc, 0x6644aa, 0x3355aa, 0xcc66ee, 0x88aaff, 0x552288, 0xffaaee];
    for (let i = 0; i < 16; i++) {
      const x = (Math.random() - 0.5) * 480;
      const y = STAR_Y_LO + Math.random() * (STAR_Y_HI - STAR_Y_LO) + 20;
      const size = 90 + Math.random() * 140;
      const color = NEBULA_COLORS[Math.floor(Math.random() * NEBULA_COLORS.length)];
      const opacity = 0.15 + Math.random() * 0.25;
      const mat = new THREE.MeshBasicMaterial({
        map: nebulaTex, color, transparent: true, opacity,
        blending: THREE.AdditiveBlending, depthWrite: false,
      });
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(size, size), mat);
      mesh.position.set(x, y, -55 - Math.random() * 10);
      mesh.renderOrder = -25;
      scene.add(mesh);
    }

    // Static stars
    const STAR_PALETTE: [number, number, number][] = [
      [1, 1, 1], [1, 1, 1], [1, 1, 1], [1, 1, 1],
      [0.75, 0.85, 1], [0.65, 0.8, 1], [1, 0.95, 0.75],
      [1, 0.8, 0.55], [1, 0.65, 0.55], [0.9, 0.8, 1],
    ];
    const STATIC_COUNT = 3200;
    const sPos = new Float32Array(STATIC_COUNT * 3);
    const sCol = new Float32Array(STATIC_COUNT * 3);
    const sSiz = new Float32Array(STATIC_COUNT);
    for (let i = 0; i < STATIC_COUNT; i++) {
      sPos[i * 3] = (Math.random() - 0.5) * STAR_X;
      sPos[i * 3 + 1] = randY();
      sPos[i * 3 + 2] = randZ();
      const [r, g, b] = STAR_PALETTE[Math.floor(Math.random() * STAR_PALETTE.length)];
      sCol[i * 3] = r; sCol[i * 3 + 1] = g; sCol[i * 3 + 2] = b;
      const roll = Math.random();
      sSiz[i] = roll < 0.7 ? 1 + Math.random() * 0.8 : roll < 0.95 ? 2 + Math.random() : 3.5 + Math.random() * 1.5;
    }
    const sGeo = new THREE.BufferGeometry();
    sGeo.setAttribute('position', new THREE.BufferAttribute(sPos, 3));
    sGeo.setAttribute('aColor', new THREE.BufferAttribute(sCol, 3));
    sGeo.setAttribute('aSize', new THREE.BufferAttribute(sSiz, 1));
    const sMat = new THREE.ShaderMaterial({
      vertexShader: `
        attribute vec3 aColor; attribute float aSize; varying vec3 vColor;
        void main() { vColor = aColor; vec4 mv = modelViewMatrix * vec4(position,1.0);
          gl_Position = projectionMatrix * mv; gl_PointSize = aSize * (180.0 / -mv.z); }`,
      fragmentShader: `
        varying vec3 vColor;
        void main() { vec2 c = gl_PointCoord - 0.5; float a = smoothstep(0.5, 0.0, length(c));
          gl_FragColor = vec4(vColor, a); }`,
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const stars = new THREE.Points(sGeo, sMat);
    stars.renderOrder = -20;
    scene.add(stars);

    // Sparkle stars
    const SPARKLE_COUNT = 220;
    const spPos = new Float32Array(SPARKLE_COUNT * 3);
    const spPh = new Float32Array(SPARKLE_COUNT);
    for (let i = 0; i < SPARKLE_COUNT; i++) {
      spPos[i * 3] = (Math.random() - 0.5) * STAR_X;
      spPos[i * 3 + 1] = randY();
      spPos[i * 3 + 2] = randZ();
      spPh[i] = Math.random();
    }
    const spGeo = new THREE.BufferGeometry();
    spGeo.setAttribute('position', new THREE.BufferAttribute(spPos, 3));
    spGeo.setAttribute('aPhase', new THREE.BufferAttribute(spPh, 1));
    const spMat = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 } },
      vertexShader: `
        attribute float aPhase; uniform float uTime; varying float vAlpha;
        void main() { float pulse = 0.5 + 0.5 * sin(uTime * 2.5 + aPhase * 6.2831);
          vAlpha = 0.2 + 0.8 * pulse; vec4 mv = modelViewMatrix * vec4(position,1.0);
          gl_Position = projectionMatrix * mv; gl_PointSize = (1.5 + 2.5 * pulse) * (200.0 / -mv.z); }`,
      fragmentShader: `
        varying float vAlpha;
        void main() { float a = smoothstep(0.5, 0.0, length(gl_PointCoord - 0.5)) * vAlpha;
          gl_FragColor = vec4(1.0,1.0,1.0, a); }`,
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const sparkles = new THREE.Points(spGeo, spMat);
    sparkles.renderOrder = -19;
    scene.add(sparkles);

    // Moon
    const moonTex = (() => {
      const W = 1024, H = 512;
      const noise = createNoise3D();
      const c = document.createElement('canvas');
      c.width = W; c.height = H;
      const ctx = c.getContext('2d')!;
      const img = ctx.createImageData(W, H);
      const data = img.data;
      const fbm = (x: number, y: number, z: number, oct: number) => {
        let amp = 1, freq = 1, v = 0, tot = 0;
        for (let i = 0; i < oct; i++) { v += noise(x * freq, y * freq, z * freq) * amp; tot += amp; amp *= 0.5; freq *= 2; }
        return v / tot;
      };
      const ridged = (x: number, y: number, z: number, oct: number) => {
        let amp = 1, freq = 1, v = 0, tot = 0;
        for (let i = 0; i < oct; i++) { v += (1 - Math.abs(noise(x * freq, y * freq, z * freq))) * amp; tot += amp; amp *= 0.5; freq *= 2; }
        return v / tot;
      };
      const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
      const ramp = (t: number): [number, number, number] => {
        t = Math.max(0, Math.min(1, t));
        const stops: [number, [number, number, number]][] = [
          [0, [0x12, 0x10, 0x2a]], [0.3, [0x2a, 0x22, 0x54]], [0.55, [0x48, 0x40, 0x8a]],
          [0.75, [0x6c, 0x70, 0xb8]], [0.9, [0x9a, 0xa8, 0xd8]], [1, [0xd0, 0xdc, 0xf4]],
        ];
        for (let i = 0; i < stops.length - 1; i++) {
          const [t0, c0] = stops[i], [t1, c1] = stops[i + 1];
          if (t <= t1) { const k = (t - t0) / (t1 - t0); return [lerp(c0[0], c1[0], k), lerp(c0[1], c1[1], k), lerp(c0[2], c1[2], k)]; }
        }
        return stops[stops.length - 1][1];
      };
      for (let y = 0; y < H; y++) {
        const theta = (y / (H - 1)) * Math.PI;
        const sT = Math.sin(theta), cT = Math.cos(theta);
        for (let x = 0; x < W; x++) {
          const phi = (x / W) * Math.PI * 2;
          const nx = sT * Math.cos(phi), ny = sT * Math.sin(phi), nz = cT;
          const base = fbm(nx * 2.5, ny * 2.5, nz * 2.5, 5);
          const cloud = ridged(nx * 3, ny * 1.2 + 5, nz * 3, 4);
          const warp = fbm(nx * 1.5 + 10, ny * 1.5, nz * 1.5, 3) * 0.6;
          let v = (base + 1) * 0.5;
          v = Math.min(1, v + Math.max(0, cloud - 0.45) * 0.7 + warp * 0.15);
          v = Math.pow(v, 0.85);
          const [r, g, b] = ramp(v);
          const idx = (y * W + x) * 4;
          data[idx] = r | 0; data[idx + 1] = g | 0; data[idx + 2] = b | 0; data[idx + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      t.wrapS = THREE.RepeatWrapping;
      return t;
    })();
    const moon = new THREE.Mesh(new THREE.SphereGeometry(28, 64, 64), new THREE.MeshLambertMaterial({ map: moonTex, emissive: 0x060614 }));
    moon.position.set(0, 8, -25);
    moon.renderOrder = -15;
    scene.add(moon);
    const ml = new THREE.DirectionalLight(0xbfd0ff, 1.6);
    ml.position.set(10, 30, -120); ml.target = moon; scene.add(ml); scene.add(ml.target);
    const ml2 = new THREE.DirectionalLight(0xa8c4ff, 1.3);
    ml2.position.set(0, -80, -40); ml2.target = moon; scene.add(ml2);

    // Halo
    const haloTex = (() => {
      const c = document.createElement('canvas');
      c.width = c.height = 256;
      const ctx = c.getContext('2d')!;
      const g = ctx.createRadialGradient(128, 128, 40, 128, 128, 128);
      g.addColorStop(0, 'rgba(180,210,255,0.9)');
      g.addColorStop(0.25, 'rgba(140,180,255,0.55)');
      g.addColorStop(0.55, 'rgba(90,140,220,0.2)');
      g.addColorStop(1, 'rgba(90,140,220,0)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, 256, 256);
      const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
    })();
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: haloTex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
    halo.scale.set(90, 90, 1);
    halo.position.set(0, 8, -27);
    halo.renderOrder = -16;
    scene.add(halo);

    // Horizon
    const BG_W = 240, BG_H = BG_W * (9 / 16);
    const bgMat = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, transparent: true, depthWrite: false });
    const bg = new THREE.Mesh(new THREE.PlaneGeometry(BG_W, BG_H), bgMat);
    bg.renderOrder = -10;
    bg.position.set(0, -60, 0);
    scene.add(bg);

    const horizonTex = (() => {
      const W = 1280, H = 720;
      const c = document.createElement('canvas');
      c.width = W; c.height = H;
      const ctx = c.getContext('2d')!;
      const noise = createNoise2D();
      const HY = Math.floor(H * 0.6);
      const grad = ctx.createLinearGradient(0, HY - H * 0.18, 0, H);
      grad.addColorStop(0, 'rgba(70,45,120,0)');
      grad.addColorStop(0.22, 'rgba(95,60,150,0.32)');
      grad.addColorStop(0.5, 'rgba(60,35,105,0.7)');
      grad.addColorStop(0.78, 'rgba(25,15,55,0.94)');
      grad.addColorStop(1, 'rgba(8,5,22,1)');
      ctx.fillStyle = grad; ctx.fillRect(0, HY - H * 0.18, W, H);
      const layers = [
        { y: HY + 26, amp: 18, freq: 0.0028, fill: 'rgba(70,45,120,0.6)' },
        { y: HY + 68, amp: 36, freq: 0.005, fill: 'rgba(28,16,60,0.95)' },
        { y: HY + 130, amp: 58, freq: 0.0078, fill: 'rgba(8,4,20,1)' },
      ];
      for (const L of layers) {
        ctx.beginPath(); ctx.moveTo(0, H);
        for (let x = 0; x <= W; x += 2) {
          let n = 0, amp = 1, freq = L.freq, tot = 0;
          for (let o = 0; o < 4; o++) { n += noise(x * freq, o * 31.7) * amp; tot += amp; amp *= 0.5; freq *= 2; }
          ctx.lineTo(x, L.y + (n / tot) * L.amp);
        }
        ctx.lineTo(W, H); ctx.closePath(); ctx.fillStyle = L.fill; ctx.fill();
      }
      const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
    })();
    bgMat.map = horizonTex; bgMat.needsUpdate = true;

    // Ground
    const rockTex = (() => {
      const W = 512, H = 512;
      const c = document.createElement('canvas');
      c.width = W; c.height = H;
      const ctx = c.getContext('2d')!;
      const img = ctx.createImageData(W, H);
      const data = img.data;
      const n2 = createNoise2D(), n2b = createNoise2D();
      const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
      const tileNoise = (x: number, y: number, freq: number) => {
        const fx = x * freq, fy = y * freq;
        const wx = x / W, wy = y / H;
        const a = n2(fx, fy), b = n2(fx - W * freq, fy);
        const c2 = n2(fx, fy - H * freq), d = n2(fx - W * freq, fy - H * freq);
        return a * (1 - wx) * (1 - wy) + b * wx * (1 - wy) + c2 * (1 - wx) * wy + d * wx * wy;
      };
      const fbm = (x: number, y: number, oct: number) => {
        let amp = 1, freq = 0.01, v = 0, tot = 0;
        for (let i = 0; i < oct; i++) { v += tileNoise(x, y, freq) * amp; tot += amp; amp *= 0.5; freq *= 2; }
        return v / tot;
      };
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const base = (fbm(x, y, 5) + 1) * 0.5;
        const cracks = Math.max(0, 1 - Math.abs(n2b(x * 0.04, y * 0.04)) - 0.35);
        const rocks = Math.max(0, 1 - Math.abs(n2(x * 0.08 + 300, y * 0.08)) - 0.55) * 2;
        let v = Math.max(0, Math.min(1, base - cracks * 0.35 + rocks * 0.25));
        const stops: [number, [number, number, number]][] = [
          [0, [0x1a, 0x16, 0x22]], [0.3, [0x34, 0x2e, 0x3e]], [0.6, [0x58, 0x4e, 0x62]],
          [0.85, [0x80, 0x74, 0x8a]], [1, [0xa8, 0x9e, 0xb2]],
        ];
        let col = stops[stops.length - 1][1];
        for (let i = 0; i < stops.length - 1; i++) {
          const [t0, c0] = stops[i], [t1, c1] = stops[i + 1];
          if (v <= t1) { const k = (v - t0) / (t1 - t0); col = [lerp(c0[0], c1[0], k), lerp(c0[1], c1[1], k), lerp(c0[2], c1[2], k)]; break; }
        }
        const idx = (y * W + x) * 4;
        data[idx] = col[0] | 0; data[idx + 1] = col[1] | 0; data[idx + 2] = col[2] | 0; data[idx + 3] = 255;
      }
      ctx.putImageData(img, 0, 0);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace; t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.RepeatWrapping;
      return t;
    })();
    const groundMat = new THREE.ShaderMaterial({
      uniforms: {
        uMap: { value: rockTex }, uTiles: { value: 24 },
        uFadeNear: { value: 280 }, uFadeFar: { value: 820 },
        uFadeColor: { value: new THREE.Color(0x2a1850) },
        uAmbient: { value: 0.45 },
        uKeyColor: { value: new THREE.Color(0xbfd0ff) }, uKeyIntensity: { value: 1.2 },
        uKeyDir: { value: new THREE.Vector3(0.25, 0.9, 0.35).normalize() },
        uBeamPos: { value: new THREE.Vector3(0, -100, 0) },
        uBeamColor: { value: new THREE.Color(0xbadcff) }, uBeamIntensity: { value: 3.2 }, uBeamRadius: { value: 110 },
      },
      vertexShader: `
        varying vec2 vUv; varying float vDist; varying vec3 vNormalW; varying vec3 vWorldPos;
        void main() { vUv = uv; vec4 world = modelMatrix * vec4(position,1.0); vWorldPos = world.xyz;
          vec4 mv = modelViewMatrix * vec4(position,1.0); vDist = -mv.z;
          vNormalW = normalize(mat3(modelMatrix) * normal); gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `
        uniform sampler2D uMap; uniform float uTiles; uniform float uFadeNear; uniform float uFadeFar;
        uniform vec3 uFadeColor; uniform float uAmbient; uniform vec3 uKeyColor; uniform float uKeyIntensity;
        uniform vec3 uKeyDir; uniform vec3 uBeamPos; uniform vec3 uBeamColor; uniform float uBeamIntensity; uniform float uBeamRadius;
        varying vec2 vUv; varying float vDist; varying vec3 vNormalW; varying vec3 vWorldPos;
        void main() {
          vec3 tex = texture2D(uMap, vUv * uTiles).rgb;
          vec3 N = normalize(vNormalW);
          float keyN = max(dot(N, uKeyDir), 0.0);
          vec3 toBeam = uBeamPos - vWorldPos; float beamDist = length(toBeam);
          float beamN = max(dot(N, toBeam / max(beamDist, 0.0001)), 0.0);
          float beamFall = 1.0 - smoothstep(0.0, uBeamRadius, beamDist); beamFall *= beamFall;
          vec3 light = vec3(uAmbient) + uKeyColor * uKeyIntensity * keyN + uBeamColor * uBeamIntensity * beamFall * beamN;
          float fog = smoothstep(uFadeNear, uFadeFar, vDist);
          gl_FragColor = vec4(mix(tex * light, uFadeColor, fog), 1.0); }`,
      depthWrite: true, side: THREE.DoubleSide,
    });
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(1400, 700), groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(0, -104, -200);
    ground.renderOrder = -5;
    scene.add(ground);

    // GLB — clouds + light with scrolling textures
    const gltf = new GLTFLoader();
    const loadGLB = () => new Promise<THREE.Object3D>((resolve, reject) =>
      gltf.load(GLB_PATH, (res) => resolve(res.scene), undefined, reject));

    const groupedNames = new Set(GROUPS.flatMap((g) => g.names));

    const processMesh = (obj: THREE.Object3D) => {
      const mesh = obj as THREE.Mesh;
      const orig = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
      const origMap = (orig as THREE.MeshStandardMaterial | undefined)?.map ?? null;
      if (origMap) { origMap.wrapS = THREE.RepeatWrapping; origMap.wrapT = THREE.RepeatWrapping; origMap.needsUpdate = true; }
      const mat = new THREE.MeshBasicMaterial({
        map: origMap, color: 0xffffff,
        vertexColors: !!mesh.geometry.getAttribute('color'),
        transparent: true, alphaTest: 0.01, side: THREE.DoubleSide, depthWrite: false,
      });
      mesh.material = mat;
      materialsMap.set(obj.uuid, mat);
      const defaults = DEFAULT_SCROLLS[obj.name];
      if (defaults) scrollSpeeds.set(obj.uuid, { x: defaults.scrollX, y: defaults.scrollY });
    };

    Promise.all([loadGLB(), ...GROUPS.map(() => loadGLB())]).then((roots) => {
      const rootDefault = roots[0];
      const groupRoots = roots.slice(1);
      roots.forEach((r) => scene.add(r));

      rootDefault.traverse((obj) => {
        if ((obj as THREE.Mesh).isMesh && groupedNames.has(obj.name)) obj.visible = false;
        else if ((obj as THREE.Mesh).isMesh) processMesh(obj);
      });

      GROUPS.forEach((group, i) => {
        const root = groupRoots[i];
        const keep = new Set(group.names);
        root.traverse((obj) => {
          if ((obj as THREE.Mesh).isMesh && !keep.has(obj.name)) obj.visible = false;
          else if ((obj as THREE.Mesh).isMesh) processMesh(obj);
        });
        if (group.scale !== undefined) {
          const bone = findSkeletonRootBone(root);
          if (bone) bone.scale.setScalar(group.scale);
        }
        if (group.offset) root.position.set(root.position.x + group.offset[0], root.position.y + group.offset[1], root.position.z + group.offset[2]);
        if (group.renderOrder !== undefined) root.traverse((obj) => {
          if ((obj as THREE.Mesh).isMesh && keep.has(obj.name)) obj.renderOrder = group.renderOrder!;
        });
      });
    });

    // Animate
    let raf = 0;
    const clock = new THREE.Clock();
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = clock.getDelta();
      scrollSpeeds.forEach((speed, uuid) => {
        const mat = materialsMap.get(uuid);
        if (!mat?.map) return;
        if (speed.x) mat.map.offset.x = (mat.map.offset.x + speed.x * dt) % 1;
        if (speed.y) mat.map.offset.y = (mat.map.offset.y + speed.y * dt) % 1;
      });
      spMat.uniforms.uTime.value = clock.elapsedTime;
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(raf);
      renderer.dispose();
      if (host.contains(renderer.domElement)) host.removeChild(renderer.domElement);
    };
  }, []);

  useEffect(() => {
    const id = setInterval(() => setBlink((b) => !b), 600);
    return () => clearInterval(id);
  }, []);

  return (
    <div style={{ position: 'relative', width: CANVAS_W, height: CANVAS_H, background: '#000' }}>
      <div ref={hostRef} style={{ position: 'absolute', inset: 0 }} />
      {/* Logo */}
      <img
        src="/logo.png"
        alt="PSZ Logo"
        style={{
          position: 'absolute',
          top: 22,
          left: '50%',
          transform: 'translateX(-50%)',
          width: 504,
          height: 'auto',
          imageRendering: 'auto',
          pointerEvents: 'none',
          filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.6))',
        }}
      />
      {/* Press Start + Version */}
      <div
        style={{
          position: 'absolute',
          bottom: 40,
          left: 0,
          right: 0,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 12,
          pointerEvents: 'none',
        }}
      >
        <div
          style={{
            fontSize: 20,
            fontFamily: 'system-ui, sans-serif',
            fontWeight: 600,
            color: blink ? '#ffcc00' : '#e6edf3',
            textShadow: '0 2px 4px rgba(0,0,0,0.8)',
            letterSpacing: '0.1em',
          }}
        >
          Press Start
        </div>
        <div
          style={{
            fontSize: 11,
            fontFamily: 'monospace',
            color: 'rgba(180,180,180,0.7)',
            textShadow: '0 1px 3px rgba(0,0,0,0.8)',
          }}
        >
          PSZ Godot v{VERSION}
        </div>
      </div>
    </div>
  );
}
