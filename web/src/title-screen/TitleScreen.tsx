import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

const CANVAS_W = 1280;
const CANVAS_H = 720;

const ASSET_BASE = '/psz-godot/assets/title';
const GLB_PATH = `${ASSET_BASE}/scene.glb`;
const BG_PATH = `${ASSET_BASE}/background.png`;

const TEXTURE_SLOTS: Record<string, string> = {
  none: '',
  clouds: `${ASSET_BASE}/clouds.png`,
  beam: `${ASSET_BASE}/beam.png`,
  waves: `${ASSET_BASE}/waves.png`,
};

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

export default function TitleScreen() {
  const hostRef = useRef<HTMLDivElement>(null);
  const objectsRef = useRef<Map<string, THREE.Object3D>>(new Map());
  const materialsRef = useRef<Map<string, THREE.MeshBasicMaterial>>(new Map());
  const texCacheRef = useRef<Map<string, THREE.Texture>>(new Map());
  const scrollSpeedsRef = useRef<Map<string, { x: number; y: number }>>(new Map());
  const [nodes, setNodes] = useState<NodeMeta[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [cameraZ, setCameraZ] = useState(140);
  const [fov, setFov] = useState(45);
  const [bgVisible, setBgVisible] = useState(true);
  const [showHelpers, setShowHelpers] = useState(true);
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
    scene.background = new THREE.Color(0x000010);

    const camera = new THREE.PerspectiveCamera(fov, CANVAS_W / CANVAS_H, 0.1, 1000);
    camera.position.set(0, 0, cameraZ);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(CANVAS_W, CANVAS_H);
    renderer.setPixelRatio(1);
    host.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 1.0));

    const helpers = new THREE.Group();
    helpers.add(new THREE.AxesHelper(1));
    helpers.add(new THREE.GridHelper(4, 8, 0x444466, 0x222244));
    scene.add(helpers);

    // Background plane sits in the scene at the back, sized for 16:9.
    // Initial size (240 × 135) roughly matches the GLB Y extent (135) scaled out to 16:9.
    const BG_W = 240;
    const BG_H = BG_W * (9 / 16);
    const bgGeo = new THREE.PlaneGeometry(BG_W, BG_H);
    const bgMat = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      side: THREE.DoubleSide,
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

    const loader = new THREE.TextureLoader();
    loader.load(BG_PATH, (tex) => {
      tex.colorSpace = THREE.SRGBColorSpace;
      bgMat.map = tex;
      bgMat.needsUpdate = true;
    });

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
    gltf.load(GLB_PATH, (res) => {
      const root = res.scene;
      scene.add(root);
      if (sceneRefs.current) sceneRefs.current.root = root;

      const collected: NodeMeta[] = [];
      const walk = (obj: THREE.Object3D, depth: number) => {
        objectsRef.current.set(obj.uuid, obj);

        let hasMesh = false;
        if ((obj as THREE.Mesh).isMesh) {
          hasMesh = true;
          const mesh = obj as THREE.Mesh;
          const orig = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
          const origMap = (orig as THREE.MeshStandardMaterial | undefined)?.map ?? null;
          const hasVertexColors = !!mesh.geometry.getAttribute('color');
          if (origMap) {
            origMap.wrapS = THREE.RepeatWrapping;
            origMap.wrapT = THREE.RepeatWrapping;
            origMap.needsUpdate = true;
          }
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
          scrollX: 0,
          scrollY: 0,
        });

        obj.children.forEach((c) => walk(c, depth + 1));
      };
      walk(root, 0);
      setNodes([bgNode, ...collected]);

      // Auto-frame: compute bbox and set camera to look at it from +Z
      const box = new THREE.Box3().setFromObject(root);
      const size = new THREE.Vector3();
      const center = new THREE.Vector3();
      box.getSize(size);
      box.getCenter(center);
      const maxDim = Math.max(size.x, size.y, size.z) || 1;
      const fitDist = (maxDim / 2) / Math.tan((fov * Math.PI) / 360);
      const z = center.z + fitDist * 2.2;
      camera.position.set(center.x, center.y, z);
      camera.lookAt(center);
      setCameraZ(+z.toFixed(2));
      setBboxInfo(
        `bbox: min(${box.min.x.toFixed(2)}, ${box.min.y.toFixed(2)}, ${box.min.z.toFixed(2)}) ` +
          `max(${box.max.x.toFixed(2)}, ${box.max.y.toFixed(2)}, ${box.max.z.toFixed(2)}) ` +
          `size(${size.x.toFixed(2)}, ${size.y.toFixed(2)}, ${size.z.toFixed(2)})`,
      );
      // Resize axes/grid to match model scale
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
    s.camera.position.z = cameraZ;
    s.camera.fov = fov;
    s.camera.updateProjectionMatrix();
  }, [cameraZ, fov]);

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
              style={{ width: 70, background: '#12122a', color: '#e0e0e0', border: '1px solid #2a2a4a', padding: '2px 4px', fontSize: 11 }}
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
