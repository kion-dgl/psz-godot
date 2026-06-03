// StageWaypointSpec — read-only viewer for a stage's floor + visual mesh +
// Manhattan grid + hand-authored waypoints. Waypoints are authored in the
// Vite editor (http://.../web/#/stage-editor) and stored in
// data/stage_configs/unified-stage-configs.json — this viewer just reads
// the latest copy so we don't duplicate editing UI.

import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import {
  buildNavGrid,
  loadGlbTriangles,
  filterFloorTriangles,
  type NavGrid,
} from './manhattan';

interface Waypoint {
  id: string;
  position: [number, number, number];
  kind?: string;
  label?: string;
}

interface Props {
  stageId: string;
  /** Floor.glb URL — fetched via the spec's /cdn proxy. */
  floorUrl: string;
  /** Visual mesh _m.glb URL — rendered translucent for spatial context. */
  visualUrl: string;
  /** Vite editor deep-link (for the "edit waypoints" button). */
  editorUrl: string;
  resolution?: number;
  clearance?: number;
}

const KIND_COLOR: Record<string, number> = {
  spawn: 0x22c55e,
  exit: 0x3b82f6,
  switch: 0xef4444,
  key_drop: 0xa855f7,
  telepipe: 0xf97316,
  via: 0x06b6d4,
  point: 0xfbbf24,
};

export default function StageWaypointSpec({
  stageId,
  floorUrl,
  visualUrl,
  editorUrl,
  resolution = 1.0,
  clearance = 2.0,
}: Props) {
  const mountRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const floorMeshRef = useRef<THREE.Mesh | null>(null);
  const visualMeshRef = useRef<THREE.Mesh | null>(null);
  const gridGroupRef = useRef<THREE.Group | null>(null);
  const wpGroupRef = useRef<THREE.Group | null>(null);
  const edgeGroupRef = useRef<THREE.Group | null>(null);

  const [showGrid, setShowGrid] = useState(true);
  const [showVisual, setShowVisual] = useState(true);
  const [showWaypoints, setShowWaypoints] = useState(true);
  const [waypoints, setWaypoints] = useState<Waypoint[]>([]);
  const [edges, setEdges] = useState<[string, string][]>([]);
  const [status, setStatus] = useState<string>('loading...');

  // Scene init — once per mount.
  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth;
    const h = el.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    sceneRef.current = scene;

    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 500);
    camera.position.set(0, 40, 40);
    camera.lookAt(0, 0, 0);
    cameraRef.current = camera;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    rendererRef.current = renderer;

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.1;

    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dir = new THREE.DirectionalLight(0xffffff, 0.7);
    dir.position.set(20, 50, 20);
    scene.add(dir);

    gridGroupRef.current = new THREE.Group();
    scene.add(gridGroupRef.current);
    wpGroupRef.current = new THREE.Group();
    scene.add(wpGroupRef.current);
    edgeGroupRef.current = new THREE.Group();
    scene.add(edgeGroupRef.current);

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
  }, []);

  // Load floor + visual + grid when stage changes.
  useEffect(() => {
    let cancelled = false;
    const scene = sceneRef.current;
    if (!scene) return;

    setStatus('loading floor + visual...');

    (async () => {
      // Floor.glb — used for the Manhattan grid + as the primary rendered
      // surface. Walkable iff a cell center sits on a floor triangle.
      let floorTris;
      try {
        floorTris = await loadGlbTriangles(floorUrl);
      } catch (err) {
        if (!cancelled) setStatus('floor load failed: ' + (err as Error).message);
        return;
      }
      if (cancelled) return;

      if (floorMeshRef.current) {
        scene.remove(floorMeshRef.current);
        floorMeshRef.current.geometry.dispose();
        floorMeshRef.current = null;
      }
      const floorGeom = new THREE.BufferGeometry();
      const fpos = new Float32Array(floorTris.length * 9);
      for (let i = 0; i < floorTris.length; i++) {
        const t = floorTris[i];
        fpos[i * 9 + 0] = t.x1; fpos[i * 9 + 1] = t.y1; fpos[i * 9 + 2] = t.z1;
        fpos[i * 9 + 3] = t.x2; fpos[i * 9 + 4] = t.y2; fpos[i * 9 + 5] = t.z2;
        fpos[i * 9 + 6] = t.x3; fpos[i * 9 + 7] = t.y3; fpos[i * 9 + 8] = t.z3;
      }
      floorGeom.setAttribute('position', new THREE.BufferAttribute(fpos, 3));
      floorGeom.computeVertexNormals();
      const floorMat = new THREE.MeshStandardMaterial({
        color: 0x6b7280,
        side: THREE.DoubleSide,
        flatShading: true,
      });
      const floorMesh = new THREE.Mesh(floorGeom, floorMat);
      scene.add(floorMesh);
      floorMeshRef.current = floorMesh;

      // Camera target = floor centroid; start from above + back so the
      // user sees the layout from a top-down-ish angle (waypoints + grid
      // are on Y≈0, so a steep down-angle keeps both visible without the
      // visual mesh occluding everything).
      const box = new THREE.Box3().setFromBufferAttribute(
        floorGeom.getAttribute('position') as THREE.BufferAttribute,
      );
      const center = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());
      const camera = cameraRef.current!;
      const span = Math.max(size.x, size.z);
      camera.position.set(center.x, center.y + span * 1.2, center.z + span * 0.6);
      camera.lookAt(center);

      // Manhattan grid from filtered floor triangles.
      const filtered = filterFloorTriangles(floorTris, {});
      const grid = buildNavGrid(filtered, { resolution, clearance });
      renderGrid(grid);

      // Visual mesh _m.glb — the actual stage geometry (walls, decoration,
      // textures). Keep the GLTF's original materials so the user sees the
      // real stage; lift transparency slightly so the waypoints +
      // Manhattan grid below stay visible.
      if (visualMeshRef.current) {
        scene.remove(visualMeshRef.current);
        visualMeshRef.current = null;
      }
      try {
        const loader = new GLTFLoader();
        const gltf = await new Promise<any>((resolve, reject) =>
          loader.load(visualUrl, resolve, undefined, reject),
        );
        if (cancelled) return;
        const visualRoot = gltf.scene;
        visualRoot.traverse((obj: any) => {
          if (obj.isMesh && obj.material) {
            const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
            for (const m of mats) {
              m.transparent = true;
              m.opacity = 0.45;
              // Many source materials carry alphaTest=0.5 from the GLB (used
              // for sprite-like texture cutouts). With opacity=0.45, that
              // cutoff would discard every fragment (final alpha 0.45 < 0.5)
              // and the mesh disappears entirely. Disable the cutoff so the
              // translucency works.
              m.alphaTest = 0;
              m.depthWrite = false;
              m.side = THREE.DoubleSide;
            }
          }
        });
        scene.add(visualRoot);
        visualMeshRef.current = visualRoot;
        visualRoot.visible = showVisualRef.current;
      } catch (err) {
        console.warn('visual mesh load failed (continuing without)', err);
      }

      if (!cancelled) {
        setStatus(`floor: ${floorTris.length} tris · grid ${grid.rows}×${grid.cols}`);
      }
    })();

    return () => { cancelled = true; };
  }, [floorUrl, visualUrl, resolution, clearance]);

  // Render waypoints + edges whenever they change.
  useEffect(() => {
    const wpg = wpGroupRef.current;
    const eg = edgeGroupRef.current;
    if (!wpg || !eg) return;
    while (wpg.children.length) {
      const c = wpg.children.pop()!;
      if (c instanceof THREE.Mesh) c.geometry.dispose();
    }
    while (eg.children.length) {
      const c = eg.children.pop()!;
      if (c instanceof THREE.Line) c.geometry.dispose();
    }
    const byId: Record<string, Waypoint> = {};
    for (const w of waypoints) byId[w.id] = w;
    for (const wp of waypoints) {
      const color = KIND_COLOR[wp.kind ?? 'point'] ?? 0xfbbf24;
      const geom = new THREE.SphereGeometry(0.55, 12, 8);
      const mat = new THREE.MeshBasicMaterial({ color });
      const sphere = new THREE.Mesh(geom, mat);
      sphere.position.set(wp.position[0], wp.position[1] + 0.6, wp.position[2]);
      wpg.add(sphere);
    }
    for (const [aid, bid] of edges) {
      const A = byId[aid];
      const B = byId[bid];
      if (!A || !B) continue;
      const pts = [
        new THREE.Vector3(A.position[0], A.position[1] + 0.4, A.position[2]),
        new THREE.Vector3(B.position[0], B.position[1] + 0.4, B.position[2]),
      ];
      const geom = new THREE.BufferGeometry().setFromPoints(pts);
      const mat = new THREE.LineBasicMaterial({ color: 0xfbbf24 });
      eg.add(new THREE.Line(geom, mat));
    }
    wpg.visible = showWaypoints;
    eg.visible = showWaypoints;
  }, [waypoints, edges, showWaypoints]);

  // Fetch waypoints from the live unified config. Goes through the spec's
  // /web proxy → editor's /psz-godot/data/... endpoint.
  useEffect(() => {
    let cancelled = false;
    fetch('/web/data/stage_configs/unified-stage-configs.json')
      .then((r) => r.json())
      .then((cfg) => {
        if (cancelled) return;
        const stage = cfg[stageId];
        if (!stage) {
          setWaypoints([]); setEdges([]);
          return;
        }
        setWaypoints((stage.waypoints ?? []) as Waypoint[]);
        setEdges((stage.waypointEdges ?? []) as [string, string][]);
      })
      .catch((err) => {
        if (!cancelled) console.warn('waypoint fetch failed', err);
      });
    return () => { cancelled = true; };
  }, [stageId]);

  // Toggle visibility on the existing groups (avoids tearing down geometry
  // each time).
  useEffect(() => {
    const g = gridGroupRef.current;
    if (g) g.visible = showGrid;
  }, [showGrid]);
  const showVisualRef = useRef(showVisual);
  useEffect(() => {
    showVisualRef.current = showVisual;
    const m = visualMeshRef.current;
    if (m) m.visible = showVisual;
  }, [showVisual]);
  useEffect(() => {
    const wpg = wpGroupRef.current;
    const eg = edgeGroupRef.current;
    if (wpg) wpg.visible = showWaypoints;
    if (eg) eg.visible = showWaypoints;
  }, [showWaypoints]);

  function renderGrid(grid: NavGrid) {
    const g = gridGroupRef.current;
    if (!g) return;
    while (g.children.length) {
      const c = g.children.pop()!;
      if (c instanceof THREE.Mesh) c.geometry.dispose();
    }
    const walkGeom = new THREE.BufferGeometry();
    const walkVerts: number[] = [];
    const half = grid.resolution / 2;
    for (let r = 0; r < grid.rows; r++) {
      for (let c = 0; c < grid.cols; c++) {
        if (grid.walkable[r * grid.cols + c] !== 1) continue;
        const wx = grid.minX + c * grid.resolution;
        const wz = grid.minZ + r * grid.resolution;
        walkVerts.push(
          wx - half, 0.05, wz - half,
          wx + half, 0.05, wz - half,
          wx + half, 0.05, wz + half,
          wx - half, 0.05, wz - half,
          wx + half, 0.05, wz + half,
          wx - half, 0.05, wz + half,
        );
      }
    }
    if (walkVerts.length > 0) {
      walkGeom.setAttribute('position', new THREE.Float32BufferAttribute(walkVerts, 3));
      const mat = new THREE.MeshBasicMaterial({
        color: 0x22c55e,
        transparent: true,
        opacity: 0.2,
        side: THREE.DoubleSide,
      });
      g.add(new THREE.Mesh(walkGeom, mat));
    }
  }

  return (
    <div className="stage-spec-root">
      <div className="toolbar">
        <label className="tool-toggle">
          <input type="checkbox" checked={showGrid} onChange={(e) => setShowGrid(e.target.checked)} />
          grid
        </label>
        <label className="tool-toggle">
          <input type="checkbox" checked={showVisual} onChange={(e) => setShowVisual(e.target.checked)} />
          visual mesh
        </label>
        <label className="tool-toggle">
          <input type="checkbox" checked={showWaypoints} onChange={(e) => setShowWaypoints(e.target.checked)} />
          waypoints ({waypoints.length})
        </label>
        <span className="status">{status}</span>
        <a className="tool-link" href={editorUrl} target="_blank" rel="noopener">
          ✎ edit waypoints →
        </a>
      </div>
      <div ref={mountRef} className="canvas-mount" />

      <style>{`
        .stage-spec-root {
          display: flex;
          flex-direction: column;
          height: 100%;
          background: #0a0e1a;
        }
        .toolbar {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 8px 12px;
          background: #161b22;
          border-bottom: 1px solid #30363d;
          flex-shrink: 0;
        }
        .tool-toggle {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 12px;
          color: #8b949e;
          cursor: pointer;
        }
        .status {
          margin-left: auto;
          font-size: 11px;
          color: #8b949e;
        }
        .tool-link {
          padding: 4px 10px;
          background: #1f6feb;
          color: #fff;
          border-radius: 4px;
          font-size: 12px;
          text-decoration: none;
        }
        .tool-link:hover { background: #388bfd; text-decoration: none; }
        .canvas-mount {
          flex: 1;
          position: relative;
          min-height: 0;
        }
      `}</style>
    </div>
  );
}
