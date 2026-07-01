// FloorColliderBuilder — build a stage's -floor.glb collision mesh by selecting
// triangles from the visual model, by material and/or one triangle at a time.
//
// Why: the runtime floor collider is a trimesh (MapCollisionBuilder in Godot
// runs create_trimesh_shape on the -floor.glb and keeps top faces). For a flat
// room a box collider works, but a room with a slope (e.g. the merged
// teleporter + guild counter, s00e_sa1) needs a collider that follows the art.
// The stage-editor's auto floor pick is Y-proximity based and can't separate a
// ramp from walls/props — so this tool gives manual control: toggle whole
// materials (floor03, floor4, …) and paint individual triangles, then export
// just those as the -floor.glb.
//
// URL: /psz-godot/#/floor-collider-builder?glb=<url>&stage=<id>&out=<repo-path>
//   - glb:   optional. Explicit source model URL. Otherwise derived from stage.
//   - stage: optional. e.g. s00e_sa1 → loads its visual _m.glb, exports -floor.glb.
//   - out:   optional. Override the export path (repo-relative -floor.glb).
// A local file picker also loads any .glb directly (for models not yet in assets).

import { useEffect, useRef, useState, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { assetUrl } from '../utils/assets';

const AREA_FOLDER: Record<string, string> = {
  '00': 'city', '01': 'valley', '02': 'wetlands', '03': 'snowfield',
  '04': 'makara', '05': 'paru', '06': 'arca', '07': 'shrine', '08': 'tower',
};
function stageFolder(stageId: string): string | null {
  const m = stageId.match(/^s(\d{2})([a-z])_/);
  if (!m) return null;
  const folder = AREA_FOLDER[m[1]];
  if (!folder) return null;
  return `${folder}_${m[2]}`;
}
function visualGlbUrl(stageId: string): string | null {
  const folder = stageFolder(stageId);
  if (!folder) return null;
  return assetUrl(`assets/stages/${folder}/${stageId}/lndmd/${stageId}_m.glb`);
}
function defaultOutPath(stageId: string): string | null {
  const folder = stageFolder(stageId);
  if (!folder) return null;
  return `assets/stages/${folder}/${stageId}/lndmd/${stageId}-floor.glb`;
}
// Derive a sibling -floor.glb repo path from a loaded model's URL/path, e.g.
// .../assets/stages/city_e/market/dairon2.glb → assets/stages/city_e/market/dairon2-floor.glb
function outPathFromGlb(glb: string): string {
  const idx = glb.indexOf('assets/stages/');
  const rel = idx >= 0 ? glb.slice(idx) : glb;
  return rel.replace(/\.glb$/i, '').replace(/_m$/, '') + '-floor.glb';
}

// --- In-browser GLB parser (positions + indices + material name per primitive).
// Adapted from FloorMeshEditor; extended to carry material info so the UI can
// group triangles by material.
interface Prim {
  meshName: string;
  materialIdx: number;
  materialName: string;
  positions: Float32Array; // [x0,y0,z0, ...]
  indices: Uint32Array | null;
  triCount: number;
}
// Local TRS/matrix of a glTF node as a THREE.Matrix4.
function nodeLocalMatrix(n: any): THREE.Matrix4 {
  const m = new THREE.Matrix4();
  if (n.matrix) {
    m.fromArray(n.matrix); // glTF matrices are column-major — matches fromArray
    return m;
  }
  const t = n.translation ?? [0, 0, 0];
  const r = n.rotation ?? [0, 0, 0, 1];
  const s = n.scale ?? [1, 1, 1];
  m.compose(
    new THREE.Vector3(t[0], t[1], t[2]),
    new THREE.Quaternion(r[0], r[1], r[2], r[3]),
    new THREE.Vector3(s[0], s[1], s[2]),
  );
  return m;
}

async function parseGlb(buf: ArrayBuffer): Promise<Prim[]> {
  const view = new DataView(buf);
  if (view.getUint32(0, true) !== 0x46546c67) throw new Error('not a GLB');
  const jsonLen = view.getUint32(12, true);
  const jsonStr = new TextDecoder().decode(new Uint8Array(buf, 20, jsonLen));
  const json = JSON.parse(jsonStr);
  const padding = (4 - (jsonLen % 4)) % 4;
  const binStart = 20 + jsonLen + padding + 8;
  const binBuf = new Uint8Array(buf, binStart);
  const binView = new DataView(binBuf.buffer, binBuf.byteOffset, binBuf.byteLength);
  const materials = json.materials ?? [];
  const nodes = json.nodes ?? [];

  // Compose each node's WORLD matrix by walking the scene graph from its roots,
  // so vertices come out in the same frame Godot places the instanced model
  // (Godot applies the GLB root node's transform — e.g. this model's root
  // offset — to the visual mesh).
  const worldMat: (THREE.Matrix4 | null)[] = nodes.map(() => null);
  const visit = (idx: number, parent: THREE.Matrix4) => {
    const w = new THREE.Matrix4().multiplyMatrices(parent, nodeLocalMatrix(nodes[idx]));
    worldMat[idx] = w;
    for (const c of nodes[idx].children ?? []) visit(c, w);
  };
  const scene = json.scenes?.[json.scene ?? 0];
  for (const r of scene?.nodes ?? []) visit(r, new THREE.Matrix4());

  const v = new THREE.Vector3();
  const prims: Prim[] = [];
  // Iterate NODES (not meshes) so each instance gets its own world transform.
  for (let ni = 0; ni < nodes.length; ni++) {
    const node = nodes[ni];
    if (node.mesh == null) continue;
    const wm = worldMat[ni] ?? new THREE.Matrix4();
    const mesh = json.meshes[node.mesh];
    for (const prim of mesh.primitives ?? []) {
      const posIdx = prim.attributes?.POSITION;
      if (posIdx == null) continue;
      const posAcc = json.accessors[posIdx];
      const posBv = json.bufferViews[posAcc.bufferView];
      const posOffset = (posBv.byteOffset ?? 0) + (posAcc.byteOffset ?? 0);
      const stride = posBv.byteStride ?? 12;
      const positions = new Float32Array(posAcc.count * 3);
      for (let i = 0; i < posAcc.count; i++) {
        v.set(
          binView.getFloat32(posOffset + i * stride + 0, true),
          binView.getFloat32(posOffset + i * stride + 4, true),
          binView.getFloat32(posOffset + i * stride + 8, true),
        ).applyMatrix4(wm); // bake node world transform
        positions[i * 3 + 0] = v.x;
        positions[i * 3 + 1] = v.y;
        positions[i * 3 + 2] = v.z;
      }
      let indices: Uint32Array | null = null;
      if (prim.indices != null) {
        const acc = json.accessors[prim.indices];
        const bv = json.bufferViews[acc.bufferView];
        const off = (bv.byteOffset ?? 0) + (acc.byteOffset ?? 0);
        indices = new Uint32Array(acc.count);
        if (acc.componentType === 5123) {
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint16(off + i * 2, true);
        } else if (acc.componentType === 5125) {
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint32(off + i * 4, true);
        } else if (acc.componentType === 5121) {
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint8(off + i);
        } else {
          throw new Error(`unsupported index componentType ${acc.componentType}`);
        }
      }
      const matIdx = prim.material ?? -1;
      const materialName = matIdx >= 0 ? (materials[matIdx]?.name ?? `material_${matIdx}`) : '(no material)';
      const triCount = indices ? indices.length / 3 : positions.length / 9;
      prims.push({ meshName: mesh.name ?? '', materialIdx: matIdx, materialName, positions, indices, triCount });
    }
  }
  return prims;
}

// Flatten a primitive into per-triangle world positions: triCount * 9 floats.
function flatTriangles(prim: Prim): Float32Array {
  const flat = new Float32Array(prim.triCount * 9);
  for (let t = 0; t < prim.triCount; t++) {
    const i0 = prim.indices ? prim.indices[t * 3 + 0] : t * 3 + 0;
    const i1 = prim.indices ? prim.indices[t * 3 + 1] : t * 3 + 1;
    const i2 = prim.indices ? prim.indices[t * 3 + 2] : t * 3 + 2;
    for (let k = 0; k < 3; k++) {
      flat[t * 9 + 0 + k] = prim.positions[i0 * 3 + k];
      flat[t * 9 + 3 + k] = prim.positions[i1 * 3 + k];
      flat[t * 9 + 6 + k] = prim.positions[i2 * 3 + k];
    }
  }
  return flat;
}

const KEY = (pi: number, ti: number) => `${pi}:${ti}`;
const COLOR_UNSEL = new THREE.Color(0x55606e);
const COLOR_SEL = new THREE.Color(0x22e06a);
type Mode = 'orbit' | 'paint' | 'erase' | 'probe';

// --- Floor classification ----------------------------------------------------
// Each primitive (one material) is classified from its name + geometry so the
// tool can pre-select the likely walkable surface and colour the rest for
// context. The user confirms/edits; this is only a starting suggestion.
type Cls = 'floor' | 'slope' | 'wall' | 'water' | 'prop';

interface PrimStats {
  cls: Cls;
  horizFrac: number; // fraction of triangles that are near-horizontal (|ny|>0.5)
  yMin: number;
  yMax: number;
}

// Per-class colours: base (unselected) tints so the 3D reads structurally.
// Selected floor triangles always override to bright green.
const CLS_BASE: Record<Cls, THREE.Color> = {
  floor: new THREE.Color(0x4a5a44),
  slope: new THREE.Color(0x5a5236),
  wall: new THREE.Color(0x3a3f4a),
  water: new THREE.Color(0x1d3a5a),
  prop: new THREE.Color(0x4a3f4a),
};
const CLS_LABEL: Record<Cls, string> = {
  floor: 'FLOOR', slope: 'SLOPE', wall: 'wall', water: 'water', prop: 'prop',
};

const FLOOR_RE = /floor|ground|groud|kaidan|tile|road|path/i;
const WALL_RE = /wall|doorset|kabe|fence|roof|yane/i;
const WATER_RE = /mizu|wave|water|umi/i;

function classify(name: string, st: { horizFrac: number; yMin: number; yMax: number }): Cls {
  const span = st.yMax - st.yMin;
  if (WATER_RE.test(name)) return 'water';
  // kaidan = stairs/ramp; a named slope or a mostly-horizontal surface that
  // also climbs a meaningful vertical span.
  if (/kaidan|slope|ramp|stair/i.test(name)) return 'slope';
  if (FLOOR_RE.test(name) && st.horizFrac >= 0.4 && span > 2.0) return 'slope';
  if (st.horizFrac >= 0.8 && (FLOOR_RE.test(name) || span < 0.8)) return 'floor';
  if (st.horizFrac < 0.15 && (span > 5.0 || WALL_RE.test(name))) return 'wall';
  return 'prop';
}

// Compute geometry stats + classification for one primitive from its flat
// triangle soup (9 floats/tri). Normals are translation-invariant, so the
// model's root offset doesn't affect horizontal detection.
function computeStats(materialName: string, flat: Float32Array): PrimStats {
  const n = flat.length / 9;
  let horiz = 0, yMin = Infinity, yMax = -Infinity;
  for (let t = 0; t < n; t++) {
    const ax = flat[t * 9], ay = flat[t * 9 + 1], az = flat[t * 9 + 2];
    const bx = flat[t * 9 + 3], by = flat[t * 9 + 4], bz = flat[t * 9 + 5];
    const cx = flat[t * 9 + 6], cy = flat[t * 9 + 7], cz = flat[t * 9 + 8];
    const ux = bx - ax, uy = by - ay, uz = bz - az;
    const vx = cx - ax, vy = cy - ay, vz = cz - az;
    const ny = uz * vx - ux * vz; // y-component of (u × v)
    const len = Math.hypot(uy * vz - uz * vy, ny, ux * vy - uy * vx) || 1;
    if (Math.abs(ny / len) > 0.5) horiz++;
    yMin = Math.min(yMin, ay, by, cy);
    yMax = Math.max(yMax, ay, by, cy);
  }
  const horizFrac = n ? horiz / n : 0;
  const cls = classify(materialName, { horizFrac, yMin, yMax });
  return { cls, horizFrac, yMin, yMax };
}

// floor + slope are the walkable surface → pre-selected.
const WALKABLE: Cls[] = ['floor', 'slope'];

interface MatGroup {
  primIdx: number;
  materialName: string;
  triCount: number;
  cls: Cls;
  horizPct: number;
}

export default function FloorColliderBuilder() {
  const [searchParams] = useSearchParams();
  const stageId = searchParams.get('stage') ?? '';
  const glbParam = searchParams.get('glb') ?? '';
  const outParam = searchParams.get('out') ?? '';
  const outPath = outParam
    || (glbParam ? outPathFromGlb(glbParam) : '')
    || (stageId ? defaultOutPath(stageId) : '')
    || '';

  const mountRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const controlsRef = useRef<OrbitControls | null>(null);
  const groupRef = useRef<THREE.Group | null>(null);
  const primsRef = useRef<Prim[]>([]);
  const flatRef = useRef<Float32Array[]>([]);       // per-prim flat triangles
  const meshesRef = useRef<THREE.Mesh[]>([]);        // per-prim render mesh
  const colorAttrRef = useRef<THREE.BufferAttribute[]>([]); // per-prim color attr
  const statsRef = useRef<PrimStats[]>([]);          // per-prim classification + geometry stats
  const selRef = useRef<Set<string>>(new Set());     // live selection (ref, for handlers)
  const modeRef = useRef<Mode>('orbit');

  const [status, setStatus] = useState('Load a model to begin.');
  const [groups, setGroups] = useState<MatGroup[]>([]);
  const [selCount, setSelCount] = useState(0);
  const [mode, setMode] = useState<Mode>('orbit');
  const [busy, setBusy] = useState(false);
  const [log, setLog] = useState<string[]>([]);
  const [probe, setProbe] = useState<[number, number, number] | null>(null);
  const [cutY, setCutY] = useState('-11');

  const pushLog = (s: string) =>
    setLog((l) => [`${new Date().toLocaleTimeString()} ${s}`, ...l].slice(0, 8));

  useEffect(() => { modeRef.current = mode; }, [mode]);
  useEffect(() => {
    // Orbit and probe both allow camera drag; paint/erase lock it for dragging.
    if (controlsRef.current) controlsRef.current.enabled = mode === 'orbit' || mode === 'probe';
  }, [mode]);

  // ---- Three scene init ----
  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    sceneRef.current = scene;
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 2000);
    camera.position.set(0, 40, 40);
    cameraRef.current = camera;
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    rendererRef.current = renderer;
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controlsRef.current = controls;
    scene.add(new THREE.AmbientLight(0xffffff, 0.85));
    const dir = new THREE.DirectionalLight(0xffffff, 0.5);
    dir.position.set(20, 60, 20);
    scene.add(dir);
    const grid = new THREE.GridHelper(120, 24, 0x2a3346, 0x18202e);
    scene.add(grid);
    const g = new THREE.Group();
    scene.add(g);
    groupRef.current = g;

    let cancelled = false;
    const animate = () => {
      if (cancelled) return;
      controls.update();
      renderer.render(scene, camera);
      requestAnimationFrame(animate);
    };
    animate();
    const onResize = () => {
      if (!mountRef.current) return;
      const nw = mountRef.current.clientWidth, nh = mountRef.current.clientHeight;
      renderer.setSize(nw, nh);
      camera.aspect = nw / nh;
      camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', onResize);
    return () => {
      cancelled = true;
      window.removeEventListener('resize', onResize);
      controls.dispose();
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
  }, []);

  // ---- Build render meshes from parsed prims ----
  const buildMeshes = useCallback((prims: Prim[]) => {
    const g = groupRef.current;
    const camera = cameraRef.current;
    if (!g || !camera) return;
    while (g.children.length) {
      const c = g.children.pop()!;
      if (c instanceof THREE.Mesh) c.geometry.dispose();
    }
    meshesRef.current = [];
    colorAttrRef.current = [];
    flatRef.current = [];
    statsRef.current = [];
    selRef.current = new Set();
    setSelCount(0);

    const box = new THREE.Box3();
    const tmp = new THREE.Vector3();
    for (let pi = 0; pi < prims.length; pi++) {
      const flat = flatTriangles(prims[pi]);
      flatRef.current.push(flat);
      statsRef.current.push(computeStats(prims[pi].materialName, flat));
      const geom = new THREE.BufferGeometry();
      geom.setAttribute('position', new THREE.BufferAttribute(flat, 3));
      const colors = new Float32Array(flat.length);
      const colAttr = new THREE.BufferAttribute(colors, 3);
      geom.setAttribute('color', colAttr);
      geom.computeVertexNormals();
      colorAttrRef.current.push(colAttr);
      const mat = new THREE.MeshStandardMaterial({
        vertexColors: true, side: THREE.DoubleSide, flatShading: true, roughness: 0.95,
      });
      const mesh = new THREE.Mesh(geom, mat);
      mesh.userData.primIdx = pi;
      g.add(mesh);
      meshesRef.current.push(mesh);
      for (let i = 0; i < flat.length; i += 3) {
        tmp.set(flat[i], flat[i + 1], flat[i + 2]);
        box.expandByPoint(tmp);
      }
    }
    // Pre-select the suggested walkable surface (floor + slope), then colour all.
    for (let pi = 0; pi < prims.length; pi++) {
      if (WALKABLE.includes(statsRef.current[pi].cls)) {
        for (let t = 0; t < prims[pi].triCount; t++) selRef.current.add(KEY(pi, t));
      }
      refreshColors(pi);
    }
    setSelCount(selRef.current.size);
    // Frame the camera on the model.
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const span = Math.max(size.x, size.z) || 20;
    camera.position.set(center.x, center.y + span * 1.1, center.z + span * 0.8);
    camera.lookAt(center);
    if (controlsRef.current) {
      controlsRef.current.target.copy(center);
      controlsRef.current.update();
    }
  }, []);

  // Rewrite the color attribute of one prim from the current selection.
  // Unselected triangles take their class tint so the model reads structurally.
  function refreshColors(pi: number) {
    const attr = colorAttrRef.current[pi];
    const prim = primsRef.current[pi];
    if (!attr || !prim) return;
    const base = CLS_BASE[statsRef.current[pi]?.cls ?? 'prop'] ?? COLOR_UNSEL;
    for (let t = 0; t < prim.triCount; t++) {
      const c = selRef.current.has(KEY(pi, t)) ? COLOR_SEL : base;
      for (let v = 0; v < 3; v++) {
        attr.setXYZ(t * 3 + v, c.r, c.g, c.b);
      }
    }
    attr.needsUpdate = true;
  }

  // ---- Selection mutators ----
  const setSelected = useCallback((pi: number, ti: number, on: boolean) => {
    const k = KEY(pi, ti);
    const has = selRef.current.has(k);
    if (on && !has) selRef.current.add(k);
    else if (!on && has) selRef.current.delete(k);
    else return;
    refreshColors(pi);
    setSelCount(selRef.current.size);
  }, []);

  const toggleMaterial = useCallback((pi: number, on: boolean) => {
    const prim = primsRef.current[pi];
    if (!prim) return;
    for (let t = 0; t < prim.triCount; t++) {
      const k = KEY(pi, t);
      if (on) selRef.current.add(k); else selRef.current.delete(k);
    }
    refreshColors(pi);
    setSelCount(selRef.current.size);
  }, []);

  const clearAll = useCallback(() => {
    selRef.current = new Set();
    for (let pi = 0; pi < primsRef.current.length; pi++) refreshColors(pi);
    setSelCount(0);
  }, []);

  // Keep only the top-most selected triangle layer at each XZ location. The
  // model stacks floor/terrain/water surfaces; a floor collider wants just the
  // walkable top, so this drops lower selected triangles that sit under a higher
  // one (which is what makes the player sink onto below-floor terrain).
  const keepTopSurface = useCallback(() => {
    const CELL = 1.5;     // XZ bin size
    const TOL = 1.2;      // keep triangles within this of the cell's top Y
    const topY = new Map<string, number>();
    const triInfo: { pi: number; ti: number; cell: string; y: number }[] = [];
    for (const k of selRef.current) {
      const [pi, ti] = k.split(':').map(Number);
      const f = flatRef.current[pi];
      const cx = (f[ti * 9] + f[ti * 9 + 3] + f[ti * 9 + 6]) / 3;
      const cy = (f[ti * 9 + 1] + f[ti * 9 + 4] + f[ti * 9 + 7]) / 3;
      const cz = (f[ti * 9 + 2] + f[ti * 9 + 5] + f[ti * 9 + 8]) / 3;
      const cell = `${Math.round(cx / CELL)}:${Math.round(cz / CELL)}`;
      triInfo.push({ pi, ti, cell, y: cy });
      topY.set(cell, Math.max(topY.get(cell) ?? -Infinity, cy));
    }
    const touched = new Set<number>();
    for (const t of triInfo) {
      if (t.y < (topY.get(t.cell) ?? -Infinity) - TOL) {
        selRef.current.delete(KEY(t.pi, t.ti));
        touched.add(t.pi);
      }
    }
    for (const pi of touched) refreshColors(pi);
    setSelCount(selRef.current.size);
  }, []);

  // Deselect every selected triangle whose centroid Y is below a cutoff. The
  // walkable floor is the top layer, so one cut strips the terrain/water/
  // undersides beneath it (which trap the player's capsule). Use probe mode to
  // read the floor Y, then cut a bit below it.
  const deselectBelowY = useCallback((cut: number) => {
    const touched = new Set<number>();
    for (const k of [...selRef.current]) {
      const [pi, ti] = k.split(':').map(Number);
      const f = flatRef.current[pi];
      const cy = (f[ti * 9 + 1] + f[ti * 9 + 4] + f[ti * 9 + 7]) / 3;
      if (cy < cut) {
        selRef.current.delete(k);
        touched.add(pi);
      }
    }
    for (const pi of touched) refreshColors(pi);
    setSelCount(selRef.current.size);
  }, []);

  // Re-apply the auto-suggestion: select every triangle of floor/slope-classed
  // materials, clearing any manual edits.
  const applySuggestion = useCallback(() => {
    selRef.current = new Set();
    for (let pi = 0; pi < primsRef.current.length; pi++) {
      if (WALKABLE.includes(statsRef.current[pi]?.cls)) {
        for (let t = 0; t < primsRef.current[pi].triCount; t++) selRef.current.add(KEY(pi, t));
      }
      refreshColors(pi);
    }
    setSelCount(selRef.current.size);
  }, []);

  // ---- Pointer interaction (raycast pick / paint) ----
  useEffect(() => {
    const renderer = rendererRef.current;
    const camera = cameraRef.current;
    if (!renderer || !camera) return;
    const dom = renderer.domElement;
    const ray = new THREE.Raycaster();
    let down = false;
    let moved = false;
    let downX = 0, downY = 0;

    const pick = (ev: PointerEvent): { pi: number; ti: number; point: THREE.Vector3 } | null => {
      const rect = dom.getBoundingClientRect();
      const m = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      ray.setFromCamera(m, camera);
      const hits = ray.intersectObjects(meshesRef.current, false);
      if (!hits.length) return null;
      const h = hits[0];
      const pi = (h.object as THREE.Mesh).userData.primIdx as number;
      const ti = h.faceIndex ?? 0;
      return { pi, ti, point: h.point };
    };

    const onDown = (ev: PointerEvent) => {
      down = true; moved = false; downX = ev.clientX; downY = ev.clientY;
      if (modeRef.current === 'paint' || modeRef.current === 'erase') {
        const hit = pick(ev);
        if (hit) setSelected(hit.pi, hit.ti, modeRef.current === 'paint');
      }
    };
    const onMove = (ev: PointerEvent) => {
      if (!down) return;
      if (Math.abs(ev.clientX - downX) > 3 || Math.abs(ev.clientY - downY) > 3) moved = true;
      if (modeRef.current === 'paint' || modeRef.current === 'erase') {
        const hit = pick(ev);
        if (hit) setSelected(hit.pi, hit.ti, modeRef.current === 'paint');
      }
    };
    const onUp = (ev: PointerEvent) => {
      if (down && !moved && modeRef.current === 'orbit') {
        // A click in orbit mode toggles a single triangle (shift = whole material).
        const hit = pick(ev);
        if (hit) {
          if (ev.shiftKey) {
            const allSel = isMaterialFullySelected(hit.pi);
            toggleMaterial(hit.pi, !allSel);
          } else {
            setSelected(hit.pi, hit.ti, !selRef.current.has(KEY(hit.pi, hit.ti)));
          }
        }
      } else if (down && !moved && modeRef.current === 'probe') {
        // Probe: read the world coordinate under the cursor (Godot-frame, since
        // node transforms are baked) so it can be pasted as an NPC/warp/spawn pos.
        const hit = pick(ev);
        if (hit) setProbe([hit.point.x, hit.point.y, hit.point.z]);
      }
      down = false;
    };
    dom.addEventListener('pointerdown', onDown);
    dom.addEventListener('pointermove', onMove);
    dom.addEventListener('pointerup', onUp);
    return () => {
      dom.removeEventListener('pointerdown', onDown);
      dom.removeEventListener('pointermove', onMove);
      dom.removeEventListener('pointerup', onUp);
    };
  }, [setSelected, toggleMaterial]);

  function isMaterialFullySelected(pi: number): boolean {
    const prim = primsRef.current[pi];
    if (!prim || prim.triCount === 0) return false;
    for (let t = 0; t < prim.triCount; t++) {
      if (!selRef.current.has(KEY(pi, t))) return false;
    }
    return true;
  }

  // ---- Loading ----
  const loadFromBuffer = useCallback(async (buf: ArrayBuffer, label: string) => {
    try {
      setStatus(`parsing ${label}…`);
      const prims = await parseGlb(buf);
      primsRef.current = prims;
      buildMeshes(prims);
      const st = statsRef.current;
      setGroups(prims.map((p, i) => ({
        primIdx: i, materialName: p.materialName, triCount: p.triCount,
        cls: st[i]?.cls ?? 'prop', horizPct: Math.round((st[i]?.horizFrac ?? 0) * 100),
      })));
      const tris = prims.reduce((s, p) => s + p.triCount, 0);
      const suggested = prims.filter((_, i) => WALKABLE.includes(st[i]?.cls)).length;
      setStatus(`${label} · ${prims.length} primitives · ${tris} tris · suggested ${suggested} walkable materials`);
      pushLog(`loaded ${label} — pre-selected floor+slope`);
    } catch (err) {
      setStatus(`load failed: ${(err as Error).message}`);
    }
  }, [buildMeshes]);

  const loadFromUrl = useCallback(async (url: string) => {
    setStatus(`fetching ${url}…`);
    try {
      // Cache-bust so re-loading after the asset changes on disk gets fresh bytes.
      const bust = url + (url.includes('?') ? '&' : '?') + 'cb=' + Date.now();
      const res = await fetch(bust);
      if (!res.ok) throw new Error(`${res.status}`);
      await loadFromBuffer(await res.arrayBuffer(), url.split('/').pop() ?? url);
    } catch (err) {
      setStatus(`fetch failed: ${(err as Error).message}`);
    }
  }, [loadFromBuffer]);

  // Auto-load from URL params.
  useEffect(() => {
    const url = glbParam || (stageId ? visualGlbUrl(stageId) : '');
    if (url) loadFromUrl(url);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [glbParam, stageId]);

  const onFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    if (!f) return;
    f.arrayBuffer().then((b) => loadFromBuffer(b, f.name));
  };

  // ---- Export ----
  const buildColliderMesh = (): THREE.Mesh | null => {
    const out: number[] = [];
    for (let pi = 0; pi < flatRef.current.length; pi++) {
      const flat = flatRef.current[pi];
      const prim = primsRef.current[pi];
      for (let t = 0; t < prim.triCount; t++) {
        if (!selRef.current.has(KEY(pi, t))) continue;
        for (let k = 0; k < 9; k++) out.push(flat[t * 9 + k]);
      }
    }
    if (!out.length) return null;
    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(new Float32Array(out), 3));
    geom.computeVertexNormals();
    const mesh = new THREE.Mesh(geom, new THREE.MeshStandardMaterial({ side: THREE.DoubleSide }));
    mesh.name = 'floor_collision';
    return mesh;
  };

  const exportGlb = async (): Promise<ArrayBuffer | null> => {
    const mesh = buildColliderMesh();
    if (!mesh) { setStatus('nothing selected to export'); return null; }
    const exporter = new GLTFExporter();
    return await new Promise<ArrayBuffer>((resolve, reject) => {
      exporter.parse(mesh, (result) => resolve(result as ArrayBuffer),
        (err) => reject(err), { binary: true });
    });
  };

  const saveToRepo = async () => {
    if (!outPath) { setStatus('no output path — add ?stage= or ?out='); return; }
    setBusy(true);
    try {
      const glb = await exportGlb();
      if (!glb) return;
      const res = await fetch(`/api/collider/export?path=${encodeURIComponent(outPath)}`, {
        method: 'POST',
        headers: { 'content-type': 'model/gltf-binary' },
        body: glb,
      });
      const text = await res.text();
      pushLog(`save ${res.status} ${text}`);
      setStatus(res.ok ? `saved → ${outPath}` : `save failed: ${text}`);
    } catch (err) {
      pushLog(`save ERR ${(err as Error).message}`);
    } finally {
      setBusy(false);
    }
  };

  const downloadGlb = async () => {
    setBusy(true);
    try {
      const glb = await exportGlb();
      if (!glb) return;
      const blob = new Blob([glb], { type: 'model/gltf-binary' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = outPath ? outPath.split('/').pop()! : 'floor.glb';
      a.click();
      URL.revokeObjectURL(a.href);
      pushLog(`downloaded ${a.download}`);
    } finally {
      setBusy(false);
    }
  };

  const resetRepo = async () => {
    if (!outPath) return;
    if (!confirm(`Restore ${outPath} to git HEAD (or delete if new)?`)) return;
    try {
      const res = await fetch('/api/collider/reset', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ path: outPath }),
      });
      pushLog(`reset ${res.status} ${await res.text()}`);
    } catch (err) {
      pushLog(`reset ERR ${(err as Error).message}`);
    }
  };

  const btn = (bg: string): React.CSSProperties => ({
    width: '100%', padding: '8px 10px', marginBottom: 8, background: bg,
    color: '#fff', border: 'none', borderRadius: 4, fontSize: 13,
    cursor: busy ? 'wait' : 'pointer',
  });

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0e1a', color: '#e6edf3' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, background: 'rgba(0,0,0,0.6)', padding: '6px 10px', borderRadius: 4, fontSize: 12 }}>
          {status}
        </div>
        <div style={{ position: 'absolute', bottom: 8, left: 8, display: 'flex', gap: 6, alignItems: 'center' }}>
          {(['orbit', 'paint', 'erase', 'probe'] as Mode[]).map((m) => (
            <button key={m} onClick={() => setMode(m)}
              style={{
                padding: '5px 12px', borderRadius: 4, fontSize: 12, cursor: 'pointer',
                border: '1px solid #30363d',
                background: mode === m ? '#1f6feb' : '#21262d',
                color: mode === m ? '#fff' : '#aaa',
              }}>
              {m}
            </button>
          ))}
          {mode === 'probe' && (
            <span style={{ marginLeft: 8, fontSize: 12, color: '#8b949e' }}>
              click a spot → world coord (Godot frame)
            </span>
          )}
        </div>
        {probe && (
          <div style={{ position: 'absolute', top: 8, right: 8, background: 'rgba(0,0,0,0.75)', padding: '8px 10px', borderRadius: 4, fontSize: 12, fontFamily: 'monospace' }}>
            <div style={{ color: '#8b949e', marginBottom: 4 }}>probed position (Godot world):</div>
            <div style={{ color: '#22e06a' }}>
              Vector3({probe[0].toFixed(2)}, {probe[1].toFixed(2)}, {probe[2].toFixed(2)})
            </div>
            <button
              onClick={() => navigator.clipboard?.writeText(`Vector3(${probe[0].toFixed(2)}, ${probe[1].toFixed(2)}, ${probe[2].toFixed(2)})`)}
              style={{ marginTop: 6, padding: '3px 8px', fontSize: 11, background: '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, cursor: 'pointer' }}
            >copy</button>
          </div>
        )}
      </div>

      <aside style={{ width: 320, flexShrink: 0, padding: 16, background: '#161b22', borderLeft: '1px solid #30363d', overflowY: 'auto' }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16 }}>Floor collider builder</h2>
        <p style={{ margin: '0 0 10px', fontSize: 12, color: '#8b949e' }}>
          Orbit mode: click a triangle to toggle, shift-click toggles its whole
          material. Paint/Erase: drag to add/remove triangles. Selected = green.
        </p>

        <label style={{ display: 'block', fontSize: 12, marginBottom: 4, color: '#8b949e' }}>
          Load .glb (local file)
        </label>
        <input type="file" accept=".glb" onChange={onFile}
          style={{ width: '100%', marginBottom: 10, fontSize: 12 }} />

        <div style={{ fontSize: 11, color: '#8b949e', marginBottom: 4 }}>
          export → <code style={{ color: '#79c0ff' }}>{outPath || '(set ?stage= or ?out=)'}</code>
        </div>
        <div style={{ fontSize: 12, marginBottom: 10 }}>
          selected: <b style={{ color: '#22e06a' }}>{selCount}</b> tris
        </div>

        <button onClick={saveToRepo} disabled={busy || !outPath} style={btn(busy ? '#30363d' : '#238636')}>
          {busy ? 'working…' : '💾 save to repo'}
        </button>
        <button onClick={downloadGlb} disabled={busy} style={btn('#21262d')}>⬇ download .glb</button>
        <button onClick={applySuggestion} style={btn('#1f3a5a')}>✨ auto-suggest floor+slope</button>
        <button onClick={keepTopSurface} style={btn('#1f3a5a')}>⬆ keep top surface only</button>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 8 }}>
          <button onClick={() => deselectBelowY(parseFloat(cutY))} style={{ ...btn('#1f3a5a'), width: 'auto', flex: 1, marginBottom: 0 }}>
            ✂ deselect below Y
          </button>
          <input type="number" step="0.5" value={cutY} onChange={(e) => setCutY(e.target.value)}
            style={{ width: 70, padding: '6px 8px', background: '#0d1117', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, fontFamily: 'monospace', fontSize: 12 }} />
        </div>
        <button onClick={clearAll} style={btn('#21262d')}>clear selection</button>
        <button onClick={resetRepo} style={{ ...btn('#3b1717'), color: '#fca5a5', border: '1px solid #7f1d1d' }}>
          ↺ reset file to git HEAD
        </button>

        <h3 style={{ fontSize: 13, margin: '14px 0 6px', color: '#8b949e' }}>
          Materials <span style={{ fontWeight: 400, fontSize: 11 }}>· green = suggested walkable</span>
        </h3>
        {groups.length === 0 && <p style={{ fontSize: 12, color: '#8b949e' }}>(load a model)</p>}
        {groups.map((g) => {
          const badge: Record<Cls, string> = {
            floor: '#4a8a44', slope: '#a08020', wall: '#5a5f6a', water: '#2d6aaa', prop: '#7a5f8a',
          };
          return (
            <div key={g.primIdx} style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
              <span title={CLS_LABEL[g.cls]} style={{
                fontSize: 9, fontWeight: 700, color: '#fff', background: badge[g.cls],
                borderRadius: 3, padding: '2px 4px', minWidth: 40, textAlign: 'center',
              }}>{CLS_LABEL[g.cls]}</span>
              <button onClick={() => toggleMaterial(g.primIdx, !isMaterialFullySelected(g.primIdx))}
                style={{
                  flex: 1, textAlign: 'left', padding: '6px 8px', background: '#21262d',
                  color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4,
                  fontFamily: 'monospace', fontSize: 11, cursor: 'pointer',
                }}>
                {g.materialName}
              </button>
              <span style={{ fontSize: 10, color: '#8b949e', minWidth: 58, textAlign: 'right' }}>
                {g.triCount}t · {g.horizPct}%⊥
              </span>
            </div>
          );
        })}

        {log.length > 0 && (
          <pre style={{ marginTop: 14, background: '#0d1117', padding: 8, borderRadius: 4, fontSize: 10, maxHeight: 140, overflow: 'auto' }}>
            {log.join('\n')}
          </pre>
        )}
      </aside>
    </div>
  );
}
