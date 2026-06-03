// FloorMeshEditor — click-to-pick vertex editor for a stage's -floor.glb.
//
// Use case: seal hairline cracks in the floor mesh that the runtime collision
// raycast drops into (causing autopilot stuck-walks). Pick a triangle, pick
// one of its 3 vertices, edit X/Z (Y stays put — these are floor verts), save.
// The save POST goes through the vite-plugin-floor-mesh-patch middleware,
// which patches the GLB binary in place on disk.
//
// URL: /psz-godot/#/floor-mesh-editor?stage=<id>&marker=x,z[;x,z;…]
//   - stage:  required. e.g. s02a_ga1
//   - marker: optional. Same syntax as the stage-editor — pins magenta posts.

import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

// Stage ID → assets/stages subfolder (matches web/src/stage-editor/constants.ts)
const AREA_FOLDER: Record<string, string> = {
  '00': 'city', '01': 'valley', '02': 'wetlands', '03': 'snowfield',
  '04': 'makara', '05': 'paru', '06': 'arca', '07': 'shrine', '08': 'tower',
};
function floorGlbUrl(stageId: string): string | null {
  const m = stageId.match(/^s(\d{2})([a-z])_/);
  if (!m) return null;
  const folder = AREA_FOLDER[m[1]];
  if (!folder) return null;
  return assetUrl(`assets/stages/${folder}_${m[2]}/${stageId}/lndmd/${stageId}-floor.glb`);
}

// --- In-browser GLB parser (adapted from scripts/tools/quest_solver/lib/glb.ts) ---
interface Prim {
  meshName: string;
  positions: Float32Array; // [x0,y0,z0, x1,y1,z1, ...]
  indices: Uint32Array | null;
}
async function fetchAndParseGlb(url: string): Promise<{ prims: Prim[] }> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  const buf = await res.arrayBuffer();
  const view = new DataView(buf);
  if (view.getUint32(0, true) !== 0x46546c67) throw new Error('not GLB');
  const jsonLen = view.getUint32(12, true);
  const jsonStr = new TextDecoder().decode(new Uint8Array(buf, 20, jsonLen));
  const json = JSON.parse(jsonStr);
  const padding = (4 - (jsonLen % 4)) % 4;
  const binStart = 20 + jsonLen + padding + 8;
  const binBuf = new Uint8Array(buf, binStart);
  const binView = new DataView(binBuf.buffer, binBuf.byteOffset, binBuf.byteLength);

  const prims: Prim[] = [];
  for (const mesh of json.meshes ?? []) {
    for (const prim of mesh.primitives ?? []) {
      const posIdx = prim.attributes?.POSITION;
      if (posIdx == null) continue;
      const posAcc = json.accessors[posIdx];
      const posBv = json.bufferViews[posAcc.bufferView];
      const posOffset = (posBv.byteOffset ?? 0) + (posAcc.byteOffset ?? 0);
      const stride = posBv.byteStride ?? 12;
      const positions = new Float32Array(posAcc.count * 3);
      for (let i = 0; i < posAcc.count; i++) {
        positions[i * 3 + 0] = binView.getFloat32(posOffset + i * stride + 0, true);
        positions[i * 3 + 1] = binView.getFloat32(posOffset + i * stride + 4, true);
        positions[i * 3 + 2] = binView.getFloat32(posOffset + i * stride + 8, true);
      }
      let indices: Uint32Array | null = null;
      if (prim.indices != null) {
        const acc = json.accessors[prim.indices];
        const bv = json.bufferViews[acc.bufferView];
        const off = (bv.byteOffset ?? 0) + (acc.byteOffset ?? 0);
        indices = new Uint32Array(acc.count);
        if (acc.componentType === 5123) { // UNSIGNED_SHORT
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint16(off + i * 2, true);
        } else if (acc.componentType === 5125) { // UNSIGNED_INT
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint32(off + i * 4, true);
        } else if (acc.componentType === 5121) { // UNSIGNED_BYTE
          for (let i = 0; i < acc.count; i++) indices[i] = binView.getUint8(off + i);
        } else {
          throw new Error(`unsupported index componentType ${acc.componentType}`);
        }
      }
      prims.push({ meshName: mesh.name ?? '', positions, indices });
    }
  }
  return { prims };
}

interface VertexSelection {
  primIdx: number;
  vertexIdx: number; // index into positions array (NOT triangle-local)
  x: number;
  y: number;
  z: number;
}

export default function FloorMeshEditor() {
  const [searchParams] = useSearchParams();
  const stageId = searchParams.get('stage') ?? '';
  const markerParam = searchParams.get('marker') ?? '';
  const markers: { x: number; z: number }[] = markerParam
    ? markerParam
        .split(';')
        .map((p) => p.split(',').map(parseFloat))
        .filter((p) => p.length === 2 && !isNaN(p[0]) && !isNaN(p[1]))
        .map(([x, z]) => ({ x, z }))
    : [];

  const mountRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const meshGroupRef = useRef<THREE.Group | null>(null);
  const vertexMarkerRef = useRef<THREE.Mesh | null>(null);
  const primsRef = useRef<Prim[]>([]);
  // Per-rendered-mesh metadata so we can map (mesh, triangleIdx) → (primIdx, vertexIdxs)
  const meshMetaRef = useRef<{ primIdx: number; triVerts: number[][] }[]>([]);

  const [status, setStatus] = useState<string>('loading...');
  const [selection, setSelection] = useState<VertexSelection | null>(null);
  const [pickedTri, setPickedTri] = useState<{ primIdx: number; verts: VertexSelection[] } | null>(null);
  const [editX, setEditX] = useState<string>('');
  const [editZ, setEditZ] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [saveLog, setSaveLog] = useState<string[]>([]);

  // Init Three scene
  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth;
    const h = el.clientHeight;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    sceneRef.current = scene;
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 500);
    camera.position.set(0, 30, 30);
    cameraRef.current = camera;
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    rendererRef.current = renderer;
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(20, 50, 20);
    scene.add(dir);

    meshGroupRef.current = new THREE.Group();
    scene.add(meshGroupRef.current);

    // Selected-vertex marker (added/repositioned on selection)
    const markerGeom = new THREE.SphereGeometry(0.3, 16, 12);
    const markerMat = new THREE.MeshBasicMaterial({ color: 0xff2266 });
    const vmark = new THREE.Mesh(markerGeom, markerMat);
    vmark.visible = false;
    scene.add(vmark);
    vertexMarkerRef.current = vmark;

    // URL markers — same magenta posts as the stage-editor's CoordMarkerOverlay
    for (const m of markers) {
      const g = new THREE.Group();
      g.position.set(m.x, 0, m.z);
      const post = new THREE.Mesh(
        new THREE.CylinderGeometry(0.15, 0.15, 10, 12),
        new THREE.MeshBasicMaterial({ color: 0xec4899 }),
      );
      post.position.y = 5;
      g.add(post);
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.8, 1.2, 24),
        new THREE.MeshBasicMaterial({ color: 0xec4899, side: THREE.DoubleSide }),
      );
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.05;
      g.add(ring);
      scene.add(g);
    }

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
      const nw = mountRef.current.clientWidth;
      const nh = mountRef.current.clientHeight;
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [markerParam]);

  // Load + render the floor GLB
  useEffect(() => {
    if (!stageId) {
      setStatus('no stage in URL — add ?stage=<id>');
      return;
    }
    const url = floorGlbUrl(stageId);
    if (!url) {
      setStatus(`could not derive floor GLB path for stage ${stageId}`);
      return;
    }
    let cancelled = false;
    setStatus(`loading ${url}…`);
    (async () => {
      try {
        const { prims } = await fetchAndParseGlb(url);
        if (cancelled) return;
        primsRef.current = prims;
        renderMesh(prims);
        const totalTris = prims.reduce((s, p) => s + (p.indices ? p.indices.length / 3 : p.positions.length / 9), 0);
        const totalVerts = prims.reduce((s, p) => s + p.positions.length / 3, 0);
        setStatus(`${prims.length} primitives · ${totalTris} tris · ${totalVerts} verts`);
      } catch (err) {
        setStatus(`load failed: ${(err as Error).message}`);
      }
    })();
    return () => { cancelled = true; };
  }, [stageId]);

  function renderMesh(prims: Prim[]) {
    const g = meshGroupRef.current;
    if (!g) return;
    while (g.children.length) {
      const c = g.children.pop()!;
      if (c instanceof THREE.Mesh) c.geometry.dispose();
    }
    meshMetaRef.current = [];
    const camera = cameraRef.current!;
    const box = new THREE.Box3();
    const tmp = new THREE.Vector3();

    for (let pi = 0; pi < prims.length; pi++) {
      const prim = prims[pi];
      // Build a non-indexed BufferGeometry so each rendered triangle maps
      // cleanly to a row in the geometry — Three's raycaster gives us
      // `faceIndex`, which we then map to (primIdx, [vertA, vertB, vertC]).
      const triCount = prim.indices ? prim.indices.length / 3 : prim.positions.length / 9;
      const flat = new Float32Array(triCount * 9);
      const triVerts: number[][] = [];
      for (let t = 0; t < triCount; t++) {
        const i0 = prim.indices ? prim.indices[t * 3 + 0] : t * 3 + 0;
        const i1 = prim.indices ? prim.indices[t * 3 + 1] : t * 3 + 1;
        const i2 = prim.indices ? prim.indices[t * 3 + 2] : t * 3 + 2;
        flat[t * 9 + 0] = prim.positions[i0 * 3 + 0];
        flat[t * 9 + 1] = prim.positions[i0 * 3 + 1];
        flat[t * 9 + 2] = prim.positions[i0 * 3 + 2];
        flat[t * 9 + 3] = prim.positions[i1 * 3 + 0];
        flat[t * 9 + 4] = prim.positions[i1 * 3 + 1];
        flat[t * 9 + 5] = prim.positions[i1 * 3 + 2];
        flat[t * 9 + 6] = prim.positions[i2 * 3 + 0];
        flat[t * 9 + 7] = prim.positions[i2 * 3 + 1];
        flat[t * 9 + 8] = prim.positions[i2 * 3 + 2];
        triVerts.push([i0, i1, i2]);
        tmp.set(flat[t * 9 + 0], flat[t * 9 + 1], flat[t * 9 + 2]); box.expandByPoint(tmp);
        tmp.set(flat[t * 9 + 3], flat[t * 9 + 4], flat[t * 9 + 5]); box.expandByPoint(tmp);
        tmp.set(flat[t * 9 + 6], flat[t * 9 + 7], flat[t * 9 + 8]); box.expandByPoint(tmp);
      }
      const geom = new THREE.BufferGeometry();
      geom.setAttribute('position', new THREE.BufferAttribute(flat, 3));
      geom.computeVertexNormals();
      const mat = new THREE.MeshStandardMaterial({
        color: 0x6b7280,
        side: THREE.DoubleSide,
        flatShading: true,
        wireframe: false,
      });
      const mesh = new THREE.Mesh(geom, mat);
      g.add(mesh);
      // Also a wireframe overlay so triangle edges are obvious
      const wireMat = new THREE.LineBasicMaterial({ color: 0x10b981, transparent: true, opacity: 0.6 });
      const wireGeom = new THREE.WireframeGeometry(geom);
      const wire = new THREE.LineSegments(wireGeom, wireMat);
      g.add(wire);
      meshMetaRef.current.push({ primIdx: pi, triVerts });
      // Dots at every unique vertex (small spheres)
      const seen = new Set<number>();
      const dotGeom = new THREE.SphereGeometry(0.08, 6, 4);
      const dotMat = new THREE.MeshBasicMaterial({ color: 0xfde047 });
      for (const tv of triVerts) {
        for (const vi of tv) {
          if (seen.has(vi)) continue;
          seen.add(vi);
          const dot = new THREE.Mesh(dotGeom, dotMat);
          dot.position.set(
            prim.positions[vi * 3 + 0],
            prim.positions[vi * 3 + 1] + 0.05,
            prim.positions[vi * 3 + 2],
          );
          g.add(dot);
        }
      }
    }

    // Frame the camera
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const span = Math.max(size.x, size.z) || 10;
    camera.position.set(center.x, center.y + span * 1.2, center.z + span * 0.6);
    camera.lookAt(center);
  }

  // Click → pick triangle → list 3 vertices for tap-to-edit
  useEffect(() => {
    const renderer = rendererRef.current;
    const camera = cameraRef.current;
    const group = meshGroupRef.current;
    if (!renderer || !camera || !group) return;
    const dom = renderer.domElement;
    const onPointer = (ev: PointerEvent) => {
      const rect = dom.getBoundingClientRect();
      const mouse = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      const raycaster = new THREE.Raycaster();
      raycaster.setFromCamera(mouse, camera);
      // Only intersect mesh children (skip the wireframe LineSegments + dots)
      const meshChildren: THREE.Mesh[] = [];
      group.children.forEach((c, i) => {
        // Layout (per primitive): mesh, wireframe, dots[]
        // The mesh is the first object pushed per prim; identify by name not set,
        // so just use instanceof.
        if (c instanceof THREE.Mesh && (c.geometry as THREE.BufferGeometry).attributes.position.itemSize === 3 && !(c.material instanceof THREE.MeshBasicMaterial)) {
          meshChildren.push(c);
        }
      });
      const hits = raycaster.intersectObjects(meshChildren, false);
      if (hits.length === 0) {
        setPickedTri(null);
        return;
      }
      const hit = hits[0];
      const meshIdx = meshChildren.indexOf(hit.object as THREE.Mesh);
      const meta = meshMetaRef.current[meshIdx];
      const faceIdx = hit.faceIndex ?? 0;
      const verts = meta.triVerts[faceIdx];
      const prim = primsRef.current[meta.primIdx];
      const vs: VertexSelection[] = verts.map((vi) => ({
        primIdx: meta.primIdx,
        vertexIdx: vi,
        x: prim.positions[vi * 3 + 0],
        y: prim.positions[vi * 3 + 1],
        z: prim.positions[vi * 3 + 2],
      }));
      setPickedTri({ primIdx: meta.primIdx, verts: vs });
    };
    dom.addEventListener('pointerdown', onPointer);
    return () => dom.removeEventListener('pointerdown', onPointer);
  }, [stageId]);

  // Highlight the selected vertex
  useEffect(() => {
    const m = vertexMarkerRef.current;
    if (!m) return;
    if (selection) {
      m.position.set(selection.x, selection.y + 0.1, selection.z);
      m.visible = true;
      setEditX(selection.x.toFixed(4));
      setEditZ(selection.z.toFixed(4));
    } else {
      m.visible = false;
    }
  }, [selection]);

  async function reset() {
    if (!stageId) return;
    if (!confirm(`Restore ${stageId}-floor.glb to git HEAD? All unstaged edits will be lost.`)) return;
    try {
      const res = await fetch('/api/floor-mesh/reset', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ stageId }),
      });
      const text = await res.text();
      setSaveLog((l) => [`${new Date().toLocaleTimeString()} reset ${res.status} ${text}`, ...l].slice(0, 6));
      if (res.ok) {
        // Reload the GLB from disk + redraw
        const url = floorGlbUrl(stageId);
        if (url) {
          const { prims } = await fetchAndParseGlb(url + '?t=' + Date.now());
          primsRef.current = prims;
          renderMesh(prims);
        }
        setSelection(null);
        setPickedTri(null);
      }
    } catch (err) {
      setSaveLog((l) => [`${new Date().toLocaleTimeString()} reset ERR ${(err as Error).message}`, ...l].slice(0, 6));
    }
  }

  async function save() {
    if (!selection) return;
    const nx = parseFloat(editX);
    const nz = parseFloat(editZ);
    if (isNaN(nx) || isNaN(nz)) return;
    setSaving(true);
    try {
      const res = await fetch('/api/floor-mesh/patch-vertex', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          stageId,
          primIdx: selection.primIdx,
          vertexIdx: selection.vertexIdx,
          x: nx,
          y: selection.y, // keep Y
          z: nz,
        }),
      });
      const text = await res.text();
      setSaveLog((l) => [`${new Date().toLocaleTimeString()} ${res.status} ${text}`, ...l].slice(0, 6));
      if (res.ok) {
        // Update in-memory positions + re-render
        const prim = primsRef.current[selection.primIdx];
        prim.positions[selection.vertexIdx * 3 + 0] = nx;
        prim.positions[selection.vertexIdx * 3 + 2] = nz;
        renderMesh(primsRef.current);
        const nextSel = { ...selection, x: nx, z: nz };
        setSelection(nextSel);
        setPickedTri(null);
      }
    } catch (err) {
      setSaveLog((l) => [`${new Date().toLocaleTimeString()} ERR ${(err as Error).message}`, ...l].slice(0, 6));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0e1a', color: '#e6edf3' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, background: 'rgba(0,0,0,0.6)', padding: '6px 10px', borderRadius: 4, fontSize: 12 }}>
          {stageId || '(no stage)'} · {status}
        </div>
      </div>
      <aside style={{ width: 340, flexShrink: 0, padding: 16, background: '#161b22', borderLeft: '1px solid #30363d', overflowY: 'auto' }}>
        <h2 style={{ margin: '0 0 8px', fontSize: 16 }}>Floor mesh editor</h2>
        <p style={{ margin: '0 0 12px', fontSize: 12, color: '#8b949e' }}>
          Tap a triangle, tap a vertex, edit X/Z, Save. Y stays put.
          Changes write back to the GLB on disk via Vite middleware.
        </p>
        <button
          onClick={reset}
          style={{ width: '100%', padding: '6px 10px', marginBottom: 12, background: '#3b1717', color: '#fca5a5', border: '1px solid #7f1d1d', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}
        >
          ↺ reset {stageId || 'stage'} to git HEAD
        </button>

        {!pickedTri && !selection && (
          <p style={{ fontSize: 13, color: '#8b949e' }}>Tap a triangle to begin.</p>
        )}

        {pickedTri && (
          <div style={{ marginBottom: 16 }}>
            <div style={{ fontSize: 12, color: '#8b949e', marginBottom: 6 }}>
              Picked triangle (prim {pickedTri.primIdx}):
            </div>
            {pickedTri.verts.map((v, i) => (
              <button
                key={i}
                onClick={() => setSelection(v)}
                style={{
                  display: 'block', width: '100%', textAlign: 'left',
                  padding: '8px 10px', marginBottom: 4,
                  background: selection && selection.vertexIdx === v.vertexIdx ? '#1f6feb' : '#21262d',
                  color: '#e6edf3', border: 'none', borderRadius: 4,
                  fontFamily: 'monospace', fontSize: 12, cursor: 'pointer',
                }}
              >
                v{v.vertexIdx}: ({v.x.toFixed(3)}, {v.y.toFixed(3)}, {v.z.toFixed(3)})
              </button>
            ))}
          </div>
        )}

        {selection && (
          <div style={{ padding: 12, background: '#21262d', borderRadius: 4 }}>
            <div style={{ fontSize: 12, color: '#8b949e', marginBottom: 8 }}>
              Editing prim {selection.primIdx}, vertex {selection.vertexIdx}
              <br />
              <span style={{ fontSize: 11 }}>Y locked at {selection.y.toFixed(4)}</span>
            </div>
            <label style={{ display: 'block', fontSize: 12, marginBottom: 4 }}>X</label>
            <input
              type="number"
              step="0.001"
              value={editX}
              onChange={(e) => setEditX(e.target.value)}
              style={{ width: '100%', padding: '6px 8px', marginBottom: 8, background: '#0d1117', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, fontFamily: 'monospace' }}
            />
            <label style={{ display: 'block', fontSize: 12, marginBottom: 4 }}>Z</label>
            <input
              type="number"
              step="0.001"
              value={editZ}
              onChange={(e) => setEditZ(e.target.value)}
              style={{ width: '100%', padding: '6px 8px', marginBottom: 8, background: '#0d1117', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, fontFamily: 'monospace' }}
            />
            <button
              onClick={save}
              disabled={saving}
              style={{ width: '100%', padding: '8px 12px', background: saving ? '#30363d' : '#238636', color: '#fff', border: 'none', borderRadius: 4, fontSize: 13, cursor: saving ? 'wait' : 'pointer' }}
            >
              {saving ? 'saving…' : 'save vertex'}
            </button>
            <button
              onClick={() => { setSelection(null); setPickedTri(null); }}
              style={{ width: '100%', padding: '6px 12px', marginTop: 6, background: 'transparent', color: '#8b949e', border: '1px solid #30363d', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}
            >
              cancel
            </button>
          </div>
        )}

        {saveLog.length > 0 && (
          <div style={{ marginTop: 16 }}>
            <div style={{ fontSize: 11, color: '#8b949e', marginBottom: 4 }}>save log:</div>
            <pre style={{ background: '#0d1117', padding: 8, borderRadius: 4, fontSize: 11, maxHeight: 140, overflow: 'auto' }}>
{saveLog.join('\n')}
            </pre>
          </div>
        )}
      </aside>
    </div>
  );
}
