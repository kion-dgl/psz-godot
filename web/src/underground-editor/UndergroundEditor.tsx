import { useMemo, useState, useCallback, useEffect } from 'react';
import * as THREE from 'three';
import { Canvas, type ThreeEvent } from '@react-three/fiber';
import { OrbitControls, useGLTF, Grid } from '@react-three/drei';
import { assetUrl } from '../utils/assets';
import { copyText } from '../utils/clipboard';

// s00e_sa4 = the underground / sewer scene. The base stage only models what's
// visible from one camera angle, so the surrounding "void" needs to be filled
// in by parking de_roll_le tunnel / rock / water pieces around it. This editor
// lets you stage that placement and export the positions as JSON to apply on
// the Godot side.
const STAGE_BASE = 'assets/stages/city_e/s00e_sa4/lndmd/s00e_sa4_m.glb';
const DE_ROLL_LE_DIR = 'assets/stages/city_e/s00e_sa4/de_roll_le';

// Filenames committed to the repo. Hand-listed (cheaper than wiring a
// directory probe; the set is small and frozen).
const DE_ROLL_LE_PIECES = [
  'fe_boss02iwa1.nj.glb',
  'fe_boss02iwa2.nj.glb',
  'fe_boss02iwa3.nj.glb',
  'fe_crobj1.nj.glb',
  'fe_crobj2.nj.glb',
  'fe_crobj3.nj.glb',
  'fe_obj001_complex3.nj.glb',
  'fe_obj001_muzu.nj.glb',
  'fe_obj002_complex4.nj.glb',
  'fe_obj002_mizu.nj.glb',
  'fe_obj003_mizu.nj.glb',
  'fe_obj003_obj1_1.nj.glb',
  'fe_obj004_mizu.nj.glb',
  'fe_obj004_obj1.nj.glb',
  'fe_obj006_grid2.nj.glb',
  'fe_obj006_mizu.nj.glb',
  'fe_obj006_mizu1.nj.glb',
  'fe_obj007_cube18_3.nj.glb',
  'fe_obj007_mizu.nj.glb',
  'fe_obj008_cube18_3.nj.glb',
  'fe_obj008_mizu.nj.glb',
  'fe_obj010_start.nj.glb',
];

type Vec3 = [number, number, number];

type Placed = {
  id: string;
  file: string;
  pos: Vec3;
  rot: Vec3;
  scale: number;
};

const LS_KEY = 'underground-editor:placements:v1';

function loadFromStorage(): Placed[] {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed;
  } catch {
    /* ignore */
  }
  return [];
}

function saveToStorage(items: Placed[]) {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(items));
  } catch {
    /* ignore */
  }
}

// Display name strips the .nj.glb and the boring fe_ prefix.
function displayName(file: string): string {
  return file.replace(/^fe_/, '').replace(/\.nj\.glb$/, '');
}

// ── 3D primitives ─────────────────────────────────────────────────────

function StageMesh() {
  const { scene } = useGLTF(assetUrl(STAGE_BASE));
  // Clone once so multiple renders of this component don't reuse the same
  // material instance.
  const cloned = useMemo(() => scene.clone(), [scene]);
  return <primitive object={cloned} />;
}

function PlacedMesh({
  file,
  position,
  rotation,
  scale,
  onClick,
}: {
  file: string;
  position: Vec3;
  rotation: Vec3;
  scale: number;
  onClick: () => void;
}) {
  const { scene } = useGLTF(assetUrl(`${DE_ROLL_LE_DIR}/${file}`));
  // Each placed piece needs its own clone — sharing instances would mean
  // moving one moves them all.
  const cloned = useMemo(() => {
    const c = scene.clone();
    // These GLBs are exported as skinned meshes (bones + SkinnedMesh).
    // SkinnedMeshes don't always respect parent-group scale via the
    // shader's bone-matrix pipeline; baking the skin into static
    // geometry up-front guarantees the placement gizmo's parent scale
    // / rotation / position actually shows on screen.
    bakeSkinnedMeshes(c);
    return c;
  }, [scene]);

  const [groupNode, setGroupNode] = useState<THREE.Group | null>(null);

  // Apply transforms imperatively (market-editor pattern). Declarative
  // <group position={...}> props were silently dropped on subsequent
  // renders in this scene for reasons I couldn't isolate; .set() always
  // works.
  useEffect(() => {
    if (!groupNode) return;
    groupNode.position.set(position[0], position[1], position[2]);
    groupNode.rotation.set(rotation[0], rotation[1], rotation[2]);
    groupNode.scale.set(scale, scale, scale);
  }, [groupNode, position, rotation, scale]);

  return (
    <group
      ref={setGroupNode}
      onClick={(e: ThreeEvent<MouseEvent>) => {
        e.stopPropagation();
        onClick();
      }}
    >
      <primitive object={cloned} />
    </group>
  );
}

// Walk a cloned GLB scene and replace every SkinnedMesh with a regular
// THREE.Mesh whose geometry has the current pose baked into its vertex
// positions. SkinnedMeshes don't respect parent-group scale in THREE's
// shader pipeline (vertices come out of bone matrices, not the standard
// world-matrix path), so any wrapping <group> we put around them has no
// visible effect. After baking, the mesh is just static geometry that
// transforms normally. The de_roll_le pieces are scenery, not animated
// characters — losing the skeleton is the right tradeoff.
function bakeSkinnedMeshes(root: THREE.Object3D): void {
  root.updateMatrixWorld(true);
  // Vertex positions come out of getVertexPosition in WORLD space (of
  // the cloned scene at this moment). To keep the baked mesh at root
  // level we transform them back into root-local space so the cloned
  // scene's own root transform isn't double-applied at render time.
  const invRoot = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const tmp = new THREE.Vector3();
  const skinneds: THREE.SkinnedMesh[] = [];
  root.traverse((obj) => {
    if ((obj as THREE.SkinnedMesh).isSkinnedMesh) {
      skinneds.push(obj as THREE.SkinnedMesh);
    }
  });
  for (const skinned of skinneds) {
    skinned.skeleton.update();
    const bakedGeom = skinned.geometry.clone();
    const positions = bakedGeom.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < positions.count; i++) {
      // getVertexPosition handles bindMatrix / boneMatrices / weights for us.
      skinned.getVertexPosition(i, tmp);
      tmp.applyMatrix4(invRoot);
      positions.setXYZ(i, tmp.x, tmp.y, tmp.z);
    }
    positions.needsUpdate = true;
    bakedGeom.computeVertexNormals();
    // BufferGeometry.clone() carries over the source's boundingBox /
    // boundingSphere, which were sized to the un-baked rest-pose vertices.
    // Without recomputing, frustum culling can mis-cull the now-relocated
    // mesh and pop pieces in/out of view as the camera moves.
    bakedGeom.computeBoundingBox();
    bakedGeom.computeBoundingSphere();
    bakedGeom.deleteAttribute('skinIndex');
    bakedGeom.deleteAttribute('skinWeight');

    const mat = Array.isArray(skinned.material) ? skinned.material[0] : skinned.material;
    const baked = new THREE.Mesh(bakedGeom, mat);
    baked.name = skinned.name + '_baked';
    // Vertices are in root-local space, so the baked mesh sits at root
    // with identity transform.
    root.add(baked);
    if (skinned.parent) skinned.parent.remove(skinned);
  }
}

// All 3D content for the editor. No gizmos — placement is driven entirely
// by the numeric input panel on the right; clicking a piece in the viewport
// just selects it.
function SceneContents({
  placed,
  setSelectedId,
}: {
  placed: Placed[];
  setSelectedId: (id: string | null) => void;
}) {
  return (
    <>
      <ambientLight intensity={0.55} />
      <directionalLight position={[10, 18, 10]} intensity={0.8} />
      <directionalLight position={[-12, 8, -6]} intensity={0.35} />

      <Grid
        position={[0, 0, 0]}
        args={[200, 200]}
        cellSize={2}
        cellThickness={0.5}
        cellColor="#3a4a5a"
        sectionSize={20}
        sectionThickness={1}
        sectionColor="#5a6a82"
        fadeDistance={120}
        fadeStrength={1}
        infiniteGrid={false}
      />

      <StageMesh />

      {placed.map((p) => (
        <PlacedMesh
          key={p.id}
          file={p.file}
          position={p.pos}
          rotation={p.rot}
          scale={p.scale}
          onClick={() => setSelectedId(p.id)}
        />
      ))}

      <OrbitControls makeDefault enableDamping={false} />
    </>
  );
}

// ── Main component ────────────────────────────────────────────────────

export default function UndergroundEditor() {
  const [placed, setPlaced] = useState<Placed[]>(() => loadFromStorage());
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Auto-save on every change. Cheap (small JSON) and means refreshing the
  // page doesn't lose placements.
  useEffect(() => {
    saveToStorage(placed);
  }, [placed]);

  const addPiece = useCallback((file: string) => {
    const id = `${file}__${Date.now().toString(36)}`;
    // PSO/PSZ assets are authored at game-world scale which is much larger
    // than the editor's reference grid; default new pieces to 0.2 so they
    // sit closer to the stage's apparent size.
    const next: Placed = {
      id,
      file,
      pos: [0, 0, 0],
      rot: [0, 0, 0],
      scale: 0.2,
    };
    setPlaced((prev) => [...prev, next]);
    setSelectedId(id);
  }, []);

  const removePiece = useCallback((id: string) => {
    setPlaced((prev) => prev.filter((p) => p.id !== id));
    if (selectedId === id) setSelectedId(null);
  }, [selectedId]);

  const duplicatePiece = useCallback((id: string) => {
    setPlaced((prev) => {
      const src = prev.find((p) => p.id === id);
      if (!src) return prev;
      const dup: Placed = {
        ...src,
        id: `${src.file}__${Date.now().toString(36)}`,
        pos: [src.pos[0] + 1, src.pos[1], src.pos[2]],
      };
      return [...prev, dup];
    });
  }, []);

  // Used by the per-piece numeric inputs — patch one field of one piece.
  const patchPiece = useCallback((id: string, patch: Partial<Placed>) => {
    setPlaced((prev) => prev.map((p) => (p.id === id ? { ...p, ...patch } : p)));
  }, []);

  const [copied, setCopied] = useState(false);
  const copyJSON = useCallback(() => {
    const payload = placed.map((p) => ({
      file: p.file,
      pos: p.pos.map((n) => +n.toFixed(3)),
      rot: p.rot.map((n) => +n.toFixed(4)),
      scale: +p.scale.toFixed(3),
    }));
    const text = JSON.stringify(payload, null, 2);

    // Shared helper handles secure-context vs. textarea-fallback. The dev
    // server is served over plain HTTP via the Tailscale IP, so the
    // textarea path is what actually runs in practice.
    copyText(text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1500);
  }, [placed]);

  const clearAll = useCallback(() => {
    if (!window.confirm(`Clear all ${placed.length} placed pieces?`)) return;
    setPlaced([]);
    setSelectedId(null);
  }, [placed.length]);

  const selectedPiece = placed.find((p) => p.id === selectedId) || null;

  return (
    <div
      style={{
        display: 'flex',
        height: '100%',
        width: '100%',
        background: '#0a0a1a',
        color: '#e0e0e0',
        fontFamily: 'system-ui, sans-serif',
        fontSize: 13,
      }}
    >
      {/* Left: piece catalog */}
      <div
        style={{
          width: 220,
          borderRight: '1px solid #2a2a4a',
          display: 'flex',
          flexDirection: 'column',
          minHeight: 0,
        }}
      >
        <div
          style={{
            padding: '10px 12px',
            background: '#12122a',
            borderBottom: '1px solid #2a2a4a',
            fontWeight: 600,
            fontSize: 12,
            letterSpacing: '0.1em',
            textTransform: 'uppercase',
            color: '#88aaff',
          }}
        >
          De Roll Le pieces ({DE_ROLL_LE_PIECES.length})
        </div>
        <div style={{ overflow: 'auto', flex: 1, padding: 6 }}>
          {DE_ROLL_LE_PIECES.map((file) => (
            <button
              key={file}
              type="button"
              onClick={() => addPiece(file)}
              style={{
                display: 'block',
                width: '100%',
                textAlign: 'left',
                background: '#1a1a2e',
                color: '#cfd4e3',
                border: '1px solid #2a2a4a',
                borderRadius: 3,
                padding: '5px 8px',
                margin: '2px 0',
                fontSize: 11,
                cursor: 'pointer',
                fontFamily: '"Share Tech Mono", monospace',
              }}
            >
              + {displayName(file)}
            </button>
          ))}
        </div>
      </div>

      {/* Center: viewport + bottom toolbar */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
          <Canvas
            camera={{ position: [40, 30, 40], fov: 50, near: 0.1, far: 2000 }}
            style={{ background: '#11141d' }}
          >
            <SceneContents placed={placed} setSelectedId={setSelectedId} />
          </Canvas>
        </div>

        {/* Bottom toolbar */}
        <div
          style={{
            background: '#12122a',
            borderTop: '1px solid #2a2a4a',
            padding: '8px 12px',
            display: 'flex',
            alignItems: 'center',
            gap: 12,
          }}
        >
          <span style={{ color: '#888', fontSize: 11 }}>
            {placed.length} placed · {selectedId ? 'selected ' + (selectedPiece?.file ?? '') : 'none selected'}
          </span>
          <span style={{ flex: 1 }} />
          <button
            type="button"
            onClick={clearAll}
            disabled={placed.length === 0}
            style={{
              background: '#2a1a2a',
              color: placed.length === 0 ? '#555' : '#e88',
              border: '1px solid #4a2a3a',
              borderRadius: 3,
              padding: '4px 10px',
              fontSize: 11,
              cursor: placed.length === 0 ? 'default' : 'pointer',
            }}
          >
            Clear all
          </button>
          <button
            type="button"
            onClick={copyJSON}
            disabled={placed.length === 0}
            style={{
              background: '#1e3a8a',
              color: placed.length === 0 ? '#888' : '#fde047',
              border: '1px solid ' + (placed.length === 0 ? '#2a2a4a' : '#fde047'),
              borderRadius: 3,
              padding: '4px 10px',
              fontSize: 11,
              cursor: placed.length === 0 ? 'default' : 'pointer',
              fontWeight: 700,
            }}
          >
            {copied ? 'Copied!' : 'Copy JSON'}
          </button>
        </div>
      </div>

      {/* Right: placed list + selected detail */}
      <div
        style={{
          width: 280,
          borderLeft: '1px solid #2a2a4a',
          display: 'flex',
          flexDirection: 'column',
          minHeight: 0,
        }}
      >
        <div
          style={{
            padding: '10px 12px',
            background: '#12122a',
            borderBottom: '1px solid #2a2a4a',
            fontWeight: 600,
            fontSize: 12,
            letterSpacing: '0.1em',
            textTransform: 'uppercase',
            color: '#88aaff',
          }}
        >
          Placed ({placed.length})
        </div>
        <div style={{ overflow: 'auto', flex: 1, padding: 6 }}>
          {placed.map((p) => {
            const active = p.id === selectedId;
            return (
              <div
                key={p.id}
                style={{
                  background: active ? '#1f1f3f' : '#1a1a2e',
                  border: `1px solid ${active ? '#fde047' : '#2a2a4a'}`,
                  borderRadius: 3,
                  padding: '5px 8px',
                  margin: '2px 0',
                  cursor: 'pointer',
                  fontSize: 11,
                  fontFamily: '"Share Tech Mono", monospace',
                }}
                onClick={() => setSelectedId(p.id)}
              >
                <div style={{ color: active ? '#fde047' : '#cfd4e3' }}>
                  {displayName(p.file)}
                </div>
                <div style={{ color: '#788', fontSize: 10, marginTop: 2 }}>
                  pos {p.pos.map((n) => n.toFixed(1)).join(', ')}
                </div>
                <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      duplicatePiece(p.id);
                    }}
                    style={{
                      background: '#1e3a8a',
                      color: '#fde047',
                      border: 'none',
                      borderRadius: 2,
                      padding: '1px 6px',
                      fontSize: 10,
                      cursor: 'pointer',
                    }}
                  >
                    dup
                  </button>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      removePiece(p.id);
                    }}
                    style={{
                      background: '#3a1f2f',
                      color: '#e88',
                      border: 'none',
                      borderRadius: 2,
                      padding: '1px 6px',
                      fontSize: 10,
                      cursor: 'pointer',
                    }}
                  >
                    del
                  </button>
                </div>
              </div>
            );
          })}
          {placed.length === 0 && (
            <div style={{ padding: 12, fontSize: 11, color: '#666' }}>
              Pick a piece on the left to drop it in at the origin, then tune
              its position / rotation / scale below.
            </div>
          )}
        </div>

        {selectedPiece && (
          <SelectedDetail piece={selectedPiece} patch={patchPiece} />
        )}
      </div>
    </div>
  );
}

// ── Selected-piece editor ─────────────────────────────────────────────

function SelectedDetail({
  piece,
  patch,
}: {
  piece: Placed;
  patch: (id: string, p: Partial<Placed>) => void;
}) {
  // Rotation surfaces as DEGREES so 90° rotations are typed directly.
  // Internal state stays in radians (THREE convention).
  const degRot: Vec3 = [
    +(piece.rot[0] * 180 / Math.PI).toFixed(1),
    +(piece.rot[1] * 180 / Math.PI).toFixed(1),
    +(piece.rot[2] * 180 / Math.PI).toFixed(1),
  ];
  const setDeg = (i: 0 | 1 | 2, deg: number) => {
    const nextRot: Vec3 = [...piece.rot] as Vec3;
    nextRot[i] = deg * Math.PI / 180;
    patch(piece.id, { rot: nextRot });
  };
  const nudgeDeg = (i: 0 | 1 | 2, delta: number) => setDeg(i, degRot[i] + delta);

  return (
    <div
      style={{
        borderTop: '1px solid #2a2a4a',
        padding: '12px',
        fontSize: 11,
        fontFamily: '"Share Tech Mono", monospace',
        color: '#cfd4e3',
        background: '#10122a',
      }}
    >
      <div style={{ fontSize: 10, color: '#fde047', marginBottom: 8, letterSpacing: '0.1em' }}>
        SELECTED · {displayName(piece.file)}
      </div>

      {/* Position */}
      <FieldGroup label="Position">
        {(['x', 'y', 'z'] as const).map((axis, i) => (
          <NumInput
            key={axis}
            label={axis.toUpperCase()}
            value={piece.pos[i]}
            step={1}
            onChange={(v) => {
              const next: Vec3 = [...piece.pos] as Vec3;
              next[i] = v;
              patch(piece.id, { pos: next });
            }}
          />
        ))}
      </FieldGroup>

      {/* Rotation in degrees */}
      <FieldGroup label="Rotation (deg)">
        {(['x', 'y', 'z'] as const).map((axis, i) => (
          <div key={axis} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <NumInput
              label={axis.toUpperCase()}
              value={degRot[i]}
              step={15}
              onChange={(v) => setDeg(i as 0 | 1 | 2, v)}
              width={60}
            />
            <button
              type="button"
              onClick={() => nudgeDeg(i as 0 | 1 | 2, -90)}
              style={pillBtn}
            >
              −90
            </button>
            <button
              type="button"
              onClick={() => nudgeDeg(i as 0 | 1 | 2, 90)}
              style={pillBtn}
            >
              +90
            </button>
          </div>
        ))}
      </FieldGroup>

      {/* Scale */}
      <FieldGroup label="Scale (uniform)">
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <input
            type="range"
            min={0.01}
            max={3}
            step={0.01}
            value={piece.scale}
            onChange={(e) => patch(piece.id, { scale: +e.target.value })}
            style={{ flex: 1 }}
          />
          <NumInput
            label=""
            value={piece.scale}
            step={0.05}
            min={0.001}
            onChange={(v) => patch(piece.id, { scale: v })}
            width={66}
          />
        </div>
        <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
          {[0.1, 0.2, 0.5, 1, 2].map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => patch(piece.id, { scale: s })}
              style={pillBtn}
            >
              {s}
            </button>
          ))}
        </div>
      </FieldGroup>
    </div>
  );
}

const pillBtn: React.CSSProperties = {
  background: '#1e3a8a',
  color: '#fde047',
  border: '1px solid #2a2a4a',
  borderRadius: 3,
  padding: '2px 7px',
  fontSize: 10,
  cursor: 'pointer',
  fontFamily: 'inherit',
};

function FieldGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ fontSize: 9, color: '#788', letterSpacing: '0.12em', textTransform: 'uppercase', marginBottom: 4 }}>
        {label}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>{children}</div>
    </div>
  );
}

function NumInput({
  label,
  value,
  step,
  min,
  width,
  onChange,
}: {
  label: string;
  value: number;
  step: number;
  min?: number;
  width?: number;
  onChange: (v: number) => void;
}) {
  return (
    <label style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      {label && <span style={{ color: '#788', width: 12 }}>{label}</span>}
      <input
        type="number"
        step={step}
        min={min}
        value={value}
        onChange={(e) => {
          const v = parseFloat(e.target.value);
          if (!Number.isNaN(v)) onChange(v);
        }}
        style={{
          background: '#0c1330',
          color: '#e0e0e0',
          border: '1px solid #2a2a4a',
          borderRadius: 2,
          padding: '3px 5px',
          fontSize: 11,
          fontFamily: 'inherit',
          width: width ?? 70,
          boxSizing: 'border-box',
        }}
      />
    </label>
  );
}

// Pre-warm so picking a piece doesn't stutter the first time.
useGLTF.preload(assetUrl(STAGE_BASE));
DE_ROLL_LE_PIECES.forEach((f) => useGLTF.preload(assetUrl(`${DE_ROLL_LE_DIR}/${f}`)));
