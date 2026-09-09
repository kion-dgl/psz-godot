import { Suspense, useMemo, useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Grid } from '@react-three/drei';
import { useGLTF, useTexture } from '@react-three/drei';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import { applyObjectTextures, detachSkinnedBind, textureFilename } from '../elements/materials';

/**
 * FlapLab — a workbench for the ambient critters' FLAP MECHANIC (#644).
 *
 * The wing meshes bake four triangles — two at max y (wings raised), two at
 * min y (wings lowered) — over one shared texture sheet, and the beat is two
 * hand-tuned texture states (window offset + mirroring) toggled at the flap
 * rate. This page splits every triangle into its own tinted mesh so each
 * face is individually visible (warm = up-stroke faces 0/2, cool =
 * down-stroke faces 1/3, white = body), adds a solo-face mode to inspect one
 * face alone, and draws each face's UV triangle onto the sheet preview so
 * the sampling math is on screen. The stroke form tunes the two states; the
 * winning values transplant into ambient_critter.gd.
 */

interface ModelEntry {
  id: string;
  label: string;
  scale: number;
  /** Split per-triangle with stroke group colors (the wing quad models). */
  split?: boolean;
  /** Procedural two-wing model with a real hinge flap — ours, not the DS's. */
  built?: boolean;
  /** Sprite sheet + UV region for the built model: [u0, v0, u1, v1]. */
  builtUv?: [number, number, number, number];
}

const MODELS: ModelEntry[] = [
  { id: 'built_butterfly', label: 'Butterfly (BUILT — hinged flap)', scale: 8,
    built: true, builtUv: [0, 0, 0.5, 1] },
  { id: 'o0c_butterfly', label: 'Butterfly (o0c_butterfly GLB)', scale: 8, split: true },
  { id: 'o0c_dragonfly', label: 'Dragonfly (o0c_dragonfly GLB)', scale: 8, split: true },
  { id: 'o0c_bird', label: 'Bird (o0c_bird — jointed rig)', scale: 4 },
];

const MECHANICS = ['moveFaces', 'uvTune', 'strokes', 'quadSwap', 'none', 'squeezeX', 'squashY', 'seeSaw', 'pitch', 'yaw'] as const;
const FACINGS = ['off', 'yaw', 'full'] as const;
const STROKE_VIEWS = ['toggle', 'up', 'down'] as const;

type Mechanic = (typeof MECHANICS)[number];
type Facing = (typeof FACINGS)[number];
type StrokeView = (typeof STROKE_VIEWS)[number];

/** One wing pose's texture state: window offset plus axis mirroring. */
interface Stroke {
  offsetX: number;
  offsetY: number;
  mirrorU: boolean;
  flipV: boolean;
}

interface Params {
  mechanic: Mechanic;
  facing: Facing;
  amplitude: number;
  flapHz: number;
  strokeUp: Stroke;
  strokeDown: Stroke;
  strokeView: StrokeView;
  uvTune: Stroke; // static window state — no flap, both quads drawn
  solo: string; // 'all' | face index | 'body'
  tintFaces: boolean;
  bob: number;
  driftRadius: number;
  driftSpeed: number;
  playing: boolean;
}

const DEFAULT_STROKE_UP: Stroke = { offsetX: 0, offsetY: 0, mirrorU: false, flipV: false };
// X snaps to halves: with mirrored-repeat wrap (period 2), offset 1 flips
// the window into its mirrored version — the clean pose change. 0.5 only
// straddles the sheet's half boundary.
const DEFAULT_STROKE_DOWN: Stroke = { offsetX: 1, offsetY: 0, mirrorU: false, flipV: false };

const DEFAULT_PARAMS: Params = {
  mechanic: 'squashY',
  facing: 'off',
  amplitude: 0.45,
  flapHz: 6,
  strokeUp: DEFAULT_STROKE_UP,
  strokeDown: DEFAULT_STROKE_DOWN,
  strokeView: 'toggle',
  uvTune: DEFAULT_STROKE_UP,
  solo: 'all',
  tintFaces: false,
  bob: 0.12,
  driftRadius: 0.35,
  driftSpeed: 0.4,
  playing: true,
};

// Quad A (tris 0,1) and quad B (tris 2,3) are the two crossed planes of
// the X; each carries the full texture and the flap flips between them.
const QUAD_A_TINT = 0xff5050;
const QUAD_B_TINT = 0x50ff88;
const BODY_TINT = 0xffffff;
const QUAD_A_HEX = '#ff5050';
const QUAD_B_HEX = '#50ff88';
const BODY_HEX = '#eeeeee';

interface Face {
  mesh: THREE.Mesh;
  tri: number;
  quad: number; // 0 = quad A (tris 0,1), 1 = quad B (tris 2,3), -1 = body
  group: 'a' | 'b' | 'body';
  uvs: [number, number][];
}

interface Sheet {
  name: string;
  url: string;
  width: number;
  height: number;
}

interface Loaded {
  root: THREE.Object3D;
  textures: THREE.Texture[];
  sheets: Sheet[];
  faces: Face[];
}

function bitmapToUrl(img: THREE.Texture['image']): { url: string; w: number; h: number } {
  if (typeof HTMLImageElement !== 'undefined' && img instanceof HTMLImageElement) {
    return { url: img.src, w: img.naturalWidth, h: img.naturalHeight };
  }
  const w = (img as ImageBitmap).width ?? 0;
  const h = (img as ImageBitmap).height ?? 0;
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  canvas.getContext('2d')?.drawImage(img as ImageBitmap, 0, 0);
  return { url: canvas.toDataURL(), w, h };
}

/**
 * Split an indexed mesh into one mesh per triangle, tinted by stroke group:
 * tris {0,2} are the max-y pair (up), {1,3} the min-y pair (down), the rest
 * body. Every face mesh shares the source texture instance, so texture
 * offset/repeat drives them together.
 */
function splitFaces(mesh: THREE.Mesh, tint: boolean): Face[] {
  const geo = mesh.geometry;
  const index = geo.getIndex();
  if (!index) return [];
  const pos = geo.getAttribute('position') as THREE.BufferAttribute;
  const uv = geo.getAttribute('uv') as THREE.BufferAttribute;
  const baseMat = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
  const faces: Face[] = [];
  for (let t = 0; t * 3 + 2 < index.count; t++) {
    const vs = [index.getX(t * 3), index.getX(t * 3 + 1), index.getX(t * 3 + 2)];
    const fg = new THREE.BufferGeometry();
    const fp: number[] = [];
    const fu: number[] = [];
    const uvs: [number, number][] = [];
    for (const v of vs) {
      fp.push(pos.getX(v), pos.getY(v), pos.getZ(v));
      fu.push(uv.getX(v), uv.getY(v));
      uvs.push([uv.getX(v), uv.getY(v)]);
    }
    fg.setAttribute('position', new THREE.Float32BufferAttribute(fp, 3));
    fg.setAttribute('uv', new THREE.Float32BufferAttribute(fu, 2));
    fg.computeVertexNormals();
    const quad = t <= 3 ? Math.floor(t / 2) : -1;
    const group = quad === 0 ? 'a' : quad === 1 ? 'b' : 'body';
    // The clone shares the source's texture instance, so texture offset /
    // repeat drives every face together.
    const mat = (baseMat as THREE.Material).clone() as THREE.MeshBasicMaterial;
    if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
      if (tint) mat.color.setHex(group === 'a' ? QUAD_A_TINT : group === 'b' ? QUAD_B_TINT : BODY_TINT);
      mat.side = THREE.DoubleSide;
      mat.needsUpdate = true;
    }
    const faceMesh = new THREE.Mesh(fg, mat);
    // Standalone triangles carry the source mesh's own local transform; the
    // mesh stays in its parent so ancestor transforms still apply.
    faceMesh.position.copy(mesh.position);
    faceMesh.quaternion.copy(mesh.quaternion);
    faceMesh.scale.copy(mesh.scale);
    mesh.parent?.add(faceMesh);
    const outline = new THREE.LineSegments(
      new THREE.EdgesGeometry(fg, 1),
      new THREE.LineBasicMaterial({
        color: group === 'a' ? QUAD_A_TINT : group === 'b' ? QUAD_B_TINT : 0xff2222,
      }),
    );
    faceMesh.add(outline);
    faces.push({ mesh: faceMesh, tri: t, quad, group, uvs });
  }
  mesh.visible = false;
  return faces;
}

function useCritter(model: string, tint: boolean): Loaded {
  const { scene } = useGLTF(assetUrl(`/assets/objects/special_z/${model}.glb`));
  return useMemo(() => {
    const root = scene.clone(true);
    const textures = applyObjectTextures(root);
    detachSkinnedBind(root);
    // DS sprites are double-sided: the two pose quads' tilts are baked into
    // the vertices with OPPOSITE normals, so single-sided culling eats half
    // of each pose depending on view angle.
    root.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const mats = Array.isArray(child.material) ? child.material : [child.material];
        for (const mat of mats) {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            mat.side = THREE.DoubleSide;
            mat.needsUpdate = true;
          }
        }
      }
    });
    const faces: Face[] = [];
    if (MODELS.find((m) => m.id === model)?.split) {
      let first: THREE.Mesh | null = null;
      root.traverse((child) => {
        if (!first && child instanceof THREE.Mesh) first = child;
      });
      if (first) faces.push(...splitFaces(first, tint));
    }
    const seen = new Set<string>();
    const sheets: Sheet[] = [];
    for (const tex of textures) {
      const name = textureFilename(tex);
      if (seen.has(name)) continue;
      seen.add(name);
      const { url, w, h } = bitmapToUrl(tex.image);
      sheets.push({ name, url, width: w, height: h });
    }
    return { root, textures, sheets, faces };
  }, [scene, tint]);
}

/**
 * The BUILT butterfly: instead of reconstructing the DS texture trick, use
 * the sprite the way it wants to be used. The sheet's left half is one
 * whole butterfly (top-down, body on the centreline); each wing is a quad
 * sampling its half of that sprite, hinged at the centreline, folding
 * symmetrically toward the camera. The flap is a rotation — correct by
 * construction.
 */
function BuiltCritter({ uv, params, scale }: {
  uv: [number, number, number, number]; params: Params; scale: number;
}) {
  const group = useRef<THREE.Group>(null);
  const hinge = useRef<THREE.Group>(null);
  const leftWing = useRef<THREE.Mesh>(null);
  const rightWing = useRef<THREE.Mesh>(null);
  const t = useRef(0);
  const texture = useTexture(assetUrl('/assets/objects/special_z/o0c_1_fly1.png'));
  useMemo(() => {
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    texture.needsUpdate = true;
  }, [texture]);

  // Sprite region: [u0, v0, u1, v1]; the centreline splits it into wings.
  const [u0, v0, u1, v1] = uv;
  const midU = (u0 + u1) / 2;
  const wingWidth = 0.24;
  const wingHeight = 0.30;

  const wings = useMemo(() => {
    const mkWing = (side: 'left' | 'right') => {
      const geo = new THREE.PlaneGeometry(wingWidth, wingHeight, 1, 1);
      // Pivot at the inner (hinge) edge.
      geo.translate(side === 'left' ? wingWidth / 2 : -wingWidth / 2, 0, 0);
      const uva = geo.getAttribute('uv') as THREE.BufferAttribute;
      for (let i = 0; i < uva.count; i++) {
        const u = uva.getX(i); // 0..1 across the wing, 0 at the hinge side
        const v = v0 + uva.getY(i) * (v1 - v0);
        uva.setXY(i, side === 'left'
          ? midU - u * (midU - u0)
          : midU + u * (u1 - midU), v);
      }
      uva.needsUpdate = true;
      return geo;
    };
    return { left: mkWing('left'), right: mkWing('right') };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [u0, v0, u1, v1]);

  useFrame((state, delta) => {
    if (params.playing) t.current += delta;
    const flapAngle = THREE.MathUtils.degToRad(80) * params.amplitude
      * (0.5 + 0.5 * Math.sin(t.current * params.flapHz * Math.PI * 2));
    if (leftWing.current) leftWing.current.rotation.y = flapAngle;
    if (rightWing.current) rightWing.current.rotation.y = -flapAngle;
    if (group.current) {
      const g = group.current;
      g.position.x = params.driftRadius * Math.sin(t.current * params.driftSpeed);
      g.position.z = params.driftRadius * 0.7 * Math.sin(t.current * params.driftSpeed * 0.618 + 2);
      g.position.y = params.bob * Math.sin(t.current * 2 * Math.PI * 0.9);
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
    void hinge;
  });

  const mat = (
    <meshBasicMaterial
      map={texture} transparent alphaTest={0.5} side={THREE.DoubleSide}
      color={0xffffff}
    />
  );
  return (
    <group ref={group} position={[0, 1, 0]} scale={scale}>
      <group ref={hinge}>
        <mesh ref={leftWing} geometry={wings.left}>{mat}</mesh>
        <mesh ref={rightWing} geometry={wings.right}>{mat}</mesh>
      </group>
    </group>
  );
}

function Critter({ model, scale, params }: { model: string; scale: number; params: Params }) {
  const group = useRef<THREE.Group>(null);
  const t = useRef(0);
  const loaded = useCritter(model, params.tintFaces);
  const meshTarget = useMemo(() => loaded.root.children[0] ?? loaded.root, [loaded]);

  useFrame((state, delta) => {
    if (params.playing) t.current += delta;
    const time = t.current;
    const phase = time * params.flapHz * Math.PI * 2;
    const flap = 0.5 + 0.5 * Math.sin(phase);

    if (params.mechanic === 'moveFaces') {
      // Texture parked at identity (the pose that read correctly) and the
      // FACES move: the real wing triangles fold around the body axis.
      for (const tex of loaded.textures) {
        tex.offset.set(0, 0);
        tex.repeat.set(1, 1);
      }
      const fold = THREE.MathUtils.degToRad(80) * params.amplitude * flap;
      for (const face of loaded.faces) {
        if (face.group === 'a') face.mesh.rotation.y = fold;
        else if (face.group === 'b') face.mesh.rotation.y = -fold;
        else face.mesh.rotation.y = 0;
      }
    } else {
      for (const face of loaded.faces) face.mesh.rotation.y = 0;
    }

    if (params.mechanic === 'uvTune') {
      // Static tuning: both quads drawn, no flap — just the shared window.
      const s = params.uvTune;
      for (const tex of loaded.textures) {
        tex.offset.set(s.offsetX, s.offsetY);
        tex.repeat.set(s.mirrorU ? -1 : 1, s.flipV ? -1 : 1);
      }
    } else if (params.mechanic === 'quadSwap') {
      // The X read: each quad carries the FULL texture at identity, and the
      // flap flips which crossed plane is visible.
      for (const tex of loaded.textures) {
        tex.offset.set(0, 0);
        tex.repeat.set(1, 1);
      }
    } else if (params.mechanic === 'strokes') {
      const up = params.strokeView === 'toggle'
        ? Math.floor(time * params.flapHz) % 2 === 0
        : params.strokeView === 'up';
      const s = up ? params.strokeUp : params.strokeDown;
      for (const tex of loaded.textures) {
        tex.offset.set(s.offsetX, s.offsetY);
        tex.repeat.set(s.mirrorU ? -1 : 1, s.flipV ? -1 : 1);
      }
    } else {
      for (const tex of loaded.textures) {
        tex.offset.set(0, 0);
        tex.repeat.set(1, 1);
      }
    }

    // Solo-face inspection plus the quad flip: with no solo face selected,
    // quadSwap shows only the current half of the X.
    const quadUp = Math.floor(time * params.flapHz) % 2;
    for (const face of loaded.faces) {
      const soloed = params.solo !== 'all'
        && (params.solo === String(face.tri)
          || (params.solo === 'body' && face.group === 'body'));
      if (soloed) {
        face.mesh.visible = true;
      } else if (params.solo === 'all' && params.mechanic === 'quadSwap') {
        face.mesh.visible = face.quad === quadUp || face.group === 'body';
      } else if (params.solo === 'all') {
        face.mesh.visible = true;
      }
      void quadUp;
    }

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
  });

  return (
    <group ref={group} position={[0, 1, 0]} scale={scale}>
      <primitive object={loaded.root} />
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
      {label}: <strong>{value.toFixed(3)}</strong>
      <input
        type="range" min={min} max={max} step={step} value={value}
        style={{ width: '100%' }}
        onChange={(e) => onChange(parseFloat(e.target.value))}
      />
    </label>
  );
}

function BuiltTexturePanel() {
  const W = 200;
  const [size, setSize] = useState<[number, number]>([0, 0]);
  return (
    <>
      <h3 style={{ marginBottom: 4 }}>Sprite sheet</h3>
      <p style={{ margin: '0 0 8px', fontSize: 12 }}>
        built wings: <span style={{ color: QUAD_A_HEX }}>left = U 0..0.25</span>{' '}
        <span style={{ color: QUAD_B_HEX }}>right = U 0.25..0.5</span> — split at the
        body centreline; the flap is the hinge rotation, not the sheet.
      </p>
      <figure style={{ margin: 0, width: W }}>
        {/* Plain DOM img — R3F texture hooks cannot run outside the Canvas. */}
        <img
          src={assetUrl('/assets/objects/special_z/o0c_1_fly1.png')} alt="sprite sheet"
          onLoad={(e) => {
            const img = e.currentTarget;
            setSize([img.naturalWidth, img.naturalHeight]);
          }}
          style={{ width: W, height: 'auto', imageRendering: 'pixelated', background: '#101014', border: '1px solid #444', display: 'block' }}
        />
        <figcaption style={{ fontSize: 11 }}>
          o0c_1_fly1.png{size[0] ? ` — ${size[0]}×${size[1]}` : ''}
        </figcaption>
      </figure>
    </>
  );
}

function GltfTexturePanel({ model }: { model: string }) {
  const loaded = useCritter(model, true);
  const W = 200;
  return (
    <>
      <h3 style={{ marginBottom: 4 }}>Texture sheets + face UVs</h3>
      <p style={{ margin: '0 0 8px', fontSize: 12 }}>
        <span style={{ color: QUAD_A_HEX }}>■ quad A (tris 0,1)</span>{' '}
        <span style={{ color: QUAD_B_HEX }}>■ quad B (tris 2,3)</span>{' '}
        <span style={{ color: BODY_HEX }}>■ body</span> — the two crossed planes of the X
      </p>
      {loaded.sheets.map((sheet) => (
        <figure key={sheet.name} style={{ margin: '0 0 12px', position: 'relative', width: W }}>
          <img
            src={sheet.url} alt={sheet.name}
            style={{ width: W, height: 'auto', imageRendering: 'pixelated', background: '#101014', border: '1px solid #444', display: 'block' }}
          />
          <svg
            width={W} height={W * sheet.height / sheet.width}
            viewBox="0 0 1 1" preserveAspectRatio="none"
            style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}
          >
            {loaded.faces.map((face) => {
              const color = face.group === 'a' ? QUAD_A_HEX : face.group === 'b' ? QUAD_B_HEX : BODY_HEX;
              const pts = face.uvs.map(([u, v]) => `${(u % 1 + 1) % 1},${1 - v}`).join(' ');
              return <polygon key={face.tri} points={pts} fill="none" stroke={color} strokeWidth={0.02} />;
            })}
          </svg>
          <figcaption style={{ fontSize: 11 }}>
            {sheet.name} — {sheet.width}×{sheet.height}
          </figcaption>
        </figure>
      ))}
    </>
  );
}

export default function FlapLab() {
  const [modelId, setModelId] = useState<string>('o0c_butterfly');
  const [params, setParams] = useState<Params>(DEFAULT_PARAMS);
  const model = MODELS.find((m) => m.id === modelId) ?? MODELS[0];
  const split = !!model.split;
  const set = <K extends keyof Params>(key: K, value: Params[K]) =>
    setParams((p) => ({ ...p, [key]: value }));
  const soloOptions = split
    ? ['all', '0', '1', '2', '3', ...(modelId === 'o0c_dragonfly' ? ['body'] : [])]
    : ['all'];

  return (
    <div style={{ padding: 16 }}>
      <h2 style={{ marginTop: 0 }}>Flap Lab — ambient critter flap mechanic (#644)</h2>
      <p style={{ maxWidth: 720 }}>
        The wing mesh is an X: two rects (<span style={{ color: QUAD_A_HEX }}>RED quad A =
        tris 0,1</span>, <span style={{ color: QUAD_B_HEX }}>GREEN quad B = tris 2,3</span>),
        both drawn at once, plus a body. <strong>uvTune</strong> (default) is static: no
        flap, both wings up, dial the shared texture window until each quad samples right.
        Solo mode isolates one face; the UV overlay on the sheet below tracks it. Once the
        resting window is right, the flap is the window toggle to build.
      </p>
      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        <div style={{ width: 640, height: 480, border: '1px solid #444' }}>
          <Canvas camera={{ position: [2.5, 2, 3.5], fov: 45 }}>
            <color attach="background" args={['#202028']} />
            <ambientLight intensity={2} />
            <Suspense fallback={null}>
              {model.built && model.builtUv ? (
                <BuiltCritter uv={model.builtUv} params={params} scale={model.scale} />
              ) : (
                <Critter model={model.id} scale={model.scale} params={params} />
              )}
            </Suspense>
            <mesh position={[0, 0.005, 0]} rotation={[-Math.PI / 2, 0, 0]}>
              <planeGeometry args={[1, 1]} />
              <meshBasicMaterial color="#666" transparent opacity={0.35} />
            </mesh>
            <Grid args={[8, 8]} cellColor="#3a3a44" sectionColor="#555" infiniteGrid />
            <OrbitControls target={[0, 1, 0]} />
          </Canvas>
        </div>
        <div style={{ width: 300 }}>
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
          <label style={{ display: 'block', marginBottom: 8 }}>
            Solo face{' '}
            <select value={params.solo} onChange={(e) => set('solo', e.target.value)}>
              {soloOptions.map((s) => <option key={s}>{s}</option>)}
            </select>
          </label>
          <label style={{ display: 'block', marginBottom: 8, fontSize: 12 }}>
            <input type="checkbox" checked={params.tintFaces}
              onChange={(e) => set('tintFaces', e.target.checked)} /> tint faces by stroke group
          </label>
          <Slider label="Flap speed (Hz)" value={params.flapHz}
            min={0.5} max={20} step={0.5} onChange={(v) => set('flapHz', v)} />
          <Slider label={model.built || params.mechanic === 'moveFaces'
            ? 'Fold angle (0..80°)' : 'Amplitude (geometric mechanics)'} value={params.amplitude}
            min={0} max={1} step={0.01} onChange={(v) => set('amplitude', v)} />

          {params.mechanic === 'uvTune' && !model.built && (
            <div style={{ borderTop: '1px solid #444', marginTop: 8, paddingTop: 8 }}>
              <p style={{ margin: '0 0 6px', fontSize: 12 }}>
                Both quads drawn, no flap — dial the shared texture window.
              </p>
              <Slider label="offset X" value={params.uvTune.offsetX}
                min={0} max={1} step={1}
                onChange={(v) => setParams((p) => ({ ...p, uvTune: { ...p.uvTune, offsetX: v } }))} />
              <Slider label="offset Y" value={params.uvTune.offsetY}
                min={-1} max={1} step={0.0625}
                onChange={(v) => setParams((p) => ({ ...p, uvTune: { ...p.uvTune, offsetY: v } }))} />
              <label style={{ display: 'inline-block', marginRight: 10, fontSize: 12 }}>
                <input type="checkbox" checked={params.uvTune.mirrorU}
                  onChange={(e) => setParams((p) => ({ ...p, uvTune: { ...p.uvTune, mirrorU: e.target.checked } }))} /> mirror U
              </label>
              <label style={{ display: 'inline-block', fontSize: 12 }}>
                <input type="checkbox" checked={params.uvTune.flipV}
                  onChange={(e) => setParams((p) => ({ ...p, uvTune: { ...p.uvTune, flipV: e.target.checked } }))} /> flip V
              </label>
            </div>
          )}

          {params.mechanic === 'strokes' && !model.built && (
            <div style={{ borderTop: '1px solid #444', marginTop: 8, paddingTop: 8 }}>
              <label style={{ display: 'block', marginBottom: 8 }}>
                Show stroke{' '}
                <select value={params.strokeView}
                  onChange={(e) => set('strokeView', e.target.value as StrokeView)}>
                  {STROKE_VIEWS.map((v) => <option key={v}>{v}</option>)}
                </select>
              </label>
              {(['up', 'down'] as const).map((which) => {
                const stroke = which === 'up' ? params.strokeUp : params.strokeDown;
                const patch = (p: Partial<Stroke>) =>
                  setParams((prev) => ({
                    ...prev,
                    [which === 'up' ? 'strokeUp' : 'strokeDown']: { ...stroke, ...p },
                  }));
                return (
                  <fieldset key={which} style={{ marginBottom: 8, borderColor: '#444' }}>
                    <legend style={{ color: which === 'up' ? QUAD_A_HEX : QUAD_B_HEX }}>
                      {which === 'up' ? 'Up stroke (wings raised)' : 'Down stroke (wings lowered)'}
                    </legend>
                    <Slider label="offset X" value={stroke.offsetX}
                      min={0} max={1} step={1} onChange={(v) => patch({ offsetX: v })} />
                    <Slider label="offset Y" value={stroke.offsetY}
                      min={-1} max={1} step={0.0625} onChange={(v) => patch({ offsetY: v })} />
                    <label style={{ display: 'inline-block', marginRight: 10, fontSize: 12 }}>
                      <input type="checkbox" checked={stroke.mirrorU}
                        onChange={(e) => patch({ mirrorU: e.target.checked })} /> mirror U
                    </label>
                    <label style={{ display: 'inline-block', fontSize: 12 }}>
                      <input type="checkbox" checked={stroke.flipV}
                        onChange={(e) => patch({ flipV: e.target.checked })} /> flip V
                    </label>
                  </fieldset>
                );
              })}
            </div>
          )}

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

          <Suspense fallback={null}>
            {model.built ? <BuiltTexturePanel /> : <GltfTexturePanel model={model.id} />}
          </Suspense>
        </div>
      </div>
    </div>
  );
}
