import { Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { Canvas, useThree, type ThreeEvent } from '@react-three/fiber';
import { Html, OrbitControls, TransformControls, useGLTF } from '@react-three/drei';
import { clone as skeletonClone } from 'three/examples/jsm/utils/SkeletonUtils.js';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import { STAGES, type CityLabMode, type LightSpec, type StageDef, type TriangleIssue, type Vec3 } from './types';
import { applyViewMaterials, threePointLightProps, vec3ToColor } from './lightingRig';

export interface FacePick {
  meshName: string;
  nodePath: string;
  materialName: string;
  /** Original (pre-filter) face index. */
  faceIndex: number;
  v0: Vec3;
  v1: Vec3;
  v2: Vec3;
  point: Vec3;
}

/** Every GLB the four stages reference, loaded once. Calling useGLTF a
 *  FIXED number of times (never per current-stage) keeps the hook count
 *  stable across stage switches — the union is ~2.4 MB, acceptable for a
 *  dev tool. */
const ALL_MODEL_PATHS = STAGES.flatMap((s) => [
  ...s.models.map((m) => m.path),
  ...(s.floorPath ? [s.floorPath] : []),
]);
type GltfCache = Record<string, THREE.Object3D>;

function useCityGltfs(onCache?: (cache: GltfCache) => void): GltfCache {
  // useGLTF's returned objects are stable per path, so spreading the
  // scenes as deps keeps this memo stable across renders — the cache (and
  // everything derived from it, like the cloned stage root) must not be
  // rebuilt on every panel keystroke.
  const loadedScenes = ALL_MODEL_PATHS.map((p) => useGLTF(assetUrl(p)).scene);
  const cache = useMemo(() => {
    const c: GltfCache = {};
    ALL_MODEL_PATHS.forEach((p, i) => {
      c[p] = loadedScenes[i];
    });
    return c;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...loadedScenes]);
  useEffect(() => {
    onCache?.(cache);
  }, [cache, onCache]);
  return cache;
}

interface StageModelsProps {
  def: StageDef;
  gltfs: GltfCache;
  mode: CityLabMode;
  /** Original face indexes marked for deletion, per mesh name. */
  markedFaces: Map<string, Set<number>>;
  onPick: (pick: FacePick | null, worldPoint?: Vec3) => void;
  onRootReady: (root: THREE.Object3D | null) => void;
}

/** Load + prepare the current city map. The GLTF cache is shared across
 *  tools, so the scene and every geometry are cloned before any in-place
 *  mutation (face filtering, material swaps) — LightingLab discipline. */
function StageModels({ def, gltfs, mode, markedFaces, onPick, onRootReady }: StageModelsProps) {
  const origIndices = useRef<Map<string, THREE.BufferAttribute>>(new Map());

  const root = useMemo(() => {
    const container = new THREE.Group();
    container.name = `city-lab-${def.id}`;
    for (const m of def.models) {
      const node = skeletonClone(gltfs[m.path]);
      node.traverse((child) => {
        const mesh = child as THREE.Mesh;
        if (mesh.isMesh) mesh.geometry = mesh.geometry.clone();
      });
      container.add(node);
    }
    return container;
    // Rebuild only when the stage changes — mode/marks are applied in
    // the effects below, not by rebuilding.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [def.id, gltfs]);

  // Materials per mode: bake (unlit reference) for inspect/triangles,
  // lit (Lambert) for the lighting workbench.
  useEffect(() => {
    applyViewMaterials(root, mode === 'lighting' ? 'lit' : 'bake', def.vertexColors);
    const lit = mode === 'lighting';
    root.traverse((child) => {
      const mesh = child as THREE.Mesh;
      if (!mesh.isMesh) return;
      mesh.castShadow = lit;
      mesh.receiveShadow = lit;
    });
    root.updateMatrixWorld(true);
    onRootReady(root);
  }, [root, mode, def.vertexColors, onRootReady]);

  // Apply/clear the marked-face deletion filter (MarketCanvas pattern):
  // stash the original index buffer once, rewrite from it thereafter.
  useEffect(() => {
    root.updateMatrixWorld(true);
    root.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh) || !obj.geometry.index) return;
      if (!origIndices.current.has(obj.uuid)) {
        origIndices.current.set(obj.uuid, obj.geometry.index.clone() as THREE.BufferAttribute);
      }
      const orig = origIndices.current.get(obj.uuid)!;
      const removeSet = markedFaces.get(obj.name);
      if (!removeSet || removeSet.size === 0) {
        obj.geometry.setIndex(orig);
        return;
      }
      const total = orig.count / 3;
      const keep: number[] = [];
      for (let face = 0; face < total; face++) {
        if (removeSet.has(face)) continue;
        keep.push(orig.getX(face * 3), orig.getX(face * 3 + 1), orig.getX(face * 3 + 2));
      }
      obj.geometry.setIndex(keep);
    });
  }, [root, markedFaces]);

  const handleClick = (e: ThreeEvent<MouseEvent>) => {
    e.stopPropagation();
    const hit = e.intersections[0];
    if (!hit) return;
    const worldPoint: Vec3 = [hit.point.x, hit.point.y, hit.point.z];
    let target: THREE.Object3D | null = hit.object;
    while (target && !(target instanceof THREE.Mesh)) target = target.parent;
    if (!(target instanceof THREE.Mesh) || hit.faceIndex == null) {
      onPick(null, worldPoint);
      return;
    }
    if (!target.geometry.index) {
      onPick(null, worldPoint);
      return;
    }

    // Map the clicked (possibly filtered) face back to its ORIGINAL index
    // so audit issues and marks stay stable across deletions.
    const current = target.geometry.index;
    const a = current.getX(hit.faceIndex * 3);
    const b = current.getX(hit.faceIndex * 3 + 1);
    const c = current.getX(hit.faceIndex * 3 + 2);
    const orig = origIndices.current.get(target.uuid) ?? current;
    let origFace = -1;
    for (let face = 0; face < orig.count / 3; face++) {
      if (orig.getX(face * 3) === a && orig.getX(face * 3 + 1) === b && orig.getX(face * 3 + 2) === c) {
        origFace = face;
        break;
      }
    }
    if (origFace < 0) {
      onPick(null, worldPoint);
      return;
    }

    const attr = target.geometry.attributes.position as THREE.BufferAttribute;
    const matrix = target.matrixWorld;
    const world = (i: number): Vec3 => {
      const v = new THREE.Vector3().fromBufferAttribute(attr, i).applyMatrix4(matrix);
      return [v.x, v.y, v.z];
    };
    const mat = target.material as THREE.Material | undefined;
    onPick(
      {
        meshName: target.name,
        nodePath: target.name,
        materialName: mat?.name || '(unnamed)',
        faceIndex: origFace,
        v0: world(a),
        v1: world(b),
        v2: world(c),
        point: worldPoint,
      },
      worldPoint,
    );
  };

  return <primitive object={root} onClick={handleClick} />;
}

/** Red/amber overlay of every audit issue triangle (world space). Never
 *  raycasts — picking must reach the mesh under the highlight. */
function IssueOverlay({ issues }: { issues: TriangleIssue[] }) {
  const geometry = useMemo(() => {
    const n = issues.length;
    const pos = new Float32Array(n * 9);
    const col = new Float32Array(n * 9);
    const color = new THREE.Color();
    issues.forEach((iss, i) => {
      const vs = [iss.v0, iss.v1, iss.v2];
      // Nonfinite coords can't render — clamp to the centroid so the
      // marker still shows where the corruption lives.
      const safe = vs.map((v) =>
        v.map((c) => (Number.isFinite(c) ? c : iss.centroid[vs.indexOf(v)] ?? 0)) as Vec3,
      );
      for (let k = 0; k < 3; k++) pos.set(safe[k], i * 9 + k * 3);
      color.set(iss.severity >= 3 ? '#ff2222' : iss.severity === 2 ? '#ff8800' : '#ffcc00');
      for (let k = 0; k < 3; k++) col.set([color.r, color.g, color.b], i * 9 + k * 3);
    });
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    return g;
  }, [issues]);

  if (issues.length === 0) return null;
  return (
    <mesh geometry={geometry} renderOrder={998} raycast={() => null}>
      <meshBasicMaterial
        vertexColors
        side={THREE.DoubleSide}
        depthTest={false}
        transparent
        opacity={0.85}
        toneMapped={false}
      />
    </mesh>
  );
}

/** A pulsing ring around the focused issue centroid (list ⇄ scene). */
function FocusMarker({ target }: { target: Vec3 }) {
  const ref = useRef<THREE.Mesh>(null);
  useEffect(() => {
    const mesh = ref.current;
    if (!mesh) return;
    let t = 0;
    let raf = 0;
    const tick = () => {
      t += 0.05;
      mesh.scale.setScalar(1 + 0.35 * Math.sin(t * 4));
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);
  return (
    <mesh ref={ref} position={target} renderOrder={999} raycast={() => null}>
      <torusGeometry args={[0.6, 0.12, 8, 24]} />
      <meshBasicMaterial color="#00e5ff" depthTest={false} transparent toneMapped={false} />
    </mesh>
  );
}

interface LightRigProps {
  lights: LightSpec[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onMove: (id: string, pos: Vec3) => void;
  ambientColor: Vec3;
  ambientEnergy: number;
  sunEnergy: number;
}

function LightRig({ lights, selectedId, onSelect, onMove, ambientColor, ambientEnergy, sunEnergy }: LightRigProps) {
  return (
    <>
      <ambientLight color={vec3ToColor(ambientColor)} intensity={ambientEnergy} />
      {sunEnergy > 0 && <directionalLight position={[10, 20, 10]} intensity={sunEnergy} />}
      {lights.map((spec) => (
        <LightNode
          key={spec.id}
          spec={spec}
          selected={spec.id === selectedId}
          onSelect={() => onSelect(spec.id)}
          onMove={(pos) => onMove(spec.id, pos)}
        />
      ))}
    </>
  );
}

function LightNode({
  spec,
  selected,
  onSelect,
  onMove,
}: {
  spec: LightSpec;
  selected: boolean;
  onSelect: () => void;
  onMove: (pos: Vec3) => void;
}) {
  const [node, setNode] = useState<THREE.Group | null>(null);
  const props = threePointLightProps(spec);

  // Numeric panel edits push into the group when they diverge (the
  // PlaceableCart feedback-loop guard).
  useEffect(() => {
    if (!node) return;
    const [x, y, z] = spec.pos;
    if (
      Math.abs(node.position.x - x) > 1e-4 ||
      Math.abs(node.position.y - y) > 1e-4 ||
      Math.abs(node.position.z - z) > 1e-4
    ) {
      node.position.set(x, y, z);
    }
  }, [spec.pos, node]);

  return (
    <>
      <group
        ref={setNode}
        position={spec.pos}
        onClick={(e) => {
          e.stopPropagation();
          onSelect();
        }}
      >
        <pointLight
          color={props.color}
          intensity={props.intensity}
          distance={props.distance}
          decay={props.decay}
          castShadow={spec.shadows}
          shadow-mapSize={[512, 512]}
        />
        <mesh>
          <sphereGeometry args={[0.25, 12, 12]} />
          <meshBasicMaterial color={props.color} toneMapped={false} />
        </mesh>
        {selected && (
          <mesh raycast={() => null}>
            <sphereGeometry args={[Math.max(spec.range, 0.5), 16, 12]} />
            <meshBasicMaterial color="#3ad0ff" wireframe transparent opacity={0.08} />
          </mesh>
        )}
        <Html center distanceFactor={30} style={{ pointerEvents: 'none' }}>
          <div
            style={{
              color: selected ? '#3ad0ff' : '#ffe9a0',
              fontSize: 11,
              fontFamily: 'monospace',
              textShadow: '0 0 4px #000',
              whiteSpace: 'nowrap',
            }}
          >
            {spec.name}
          </div>
        </Html>
      </group>
      {selected && node && (
        <TransformControls
          object={node}
          mode="translate"
          onObjectChange={() => onMove([node.position.x, node.position.y, node.position.z])}
        />
      )}
    </>
  );
}

/** The hand-authored floor collider as a teal wireframe (walk surface
 *  reference while placing lights). */
function FloorWire({ scene }: { scene: THREE.Object3D }) {
  const cloned = useMemo(() => {
    const node = skeletonClone(scene);
    node.traverse((child) => {
      const mesh = child as THREE.Mesh;
      if (mesh.isMesh) {
        mesh.material = new THREE.MeshBasicMaterial({
          color: '#37e0c8',
          wireframe: true,
          transparent: true,
          opacity: 0.25,
        });
      }
    });
    return node;
  }, [scene]);
  return <primitive object={cloned} raycast={() => null} />;
}

function Markers({ def }: { def: StageDef }) {
  return (
    <>
      {(def.markers ?? []).map((m) => (
        <group key={m.label} position={m.pos}>
          <mesh raycast={() => null}>
            <octahedronGeometry args={[0.45]} />
            <meshBasicMaterial color={m.color} toneMapped={false} />
          </mesh>
          <Html center distanceFactor={40} style={{ pointerEvents: 'none' }}>
            <div
              style={{
                color: m.color,
                fontSize: 11,
                fontFamily: 'monospace',
                textShadow: '0 0 4px #000',
                whiteSpace: 'nowrap',
              }}
            >
              {m.label}
            </div>
          </Html>
        </group>
      ))}
    </>
  );
}

/** Frame the freshly loaded stage once per stage change. */
function FitCamera({ watchKey, rootRef }: { watchKey: string; rootRef: React.RefObject<THREE.Object3D | null> }) {
  const camera = useThree((s) => s.camera);
  const controls = useThree((s) => s.controls) as { target: THREE.Vector3; update: () => void } | null;
  useEffect(() => {
    const root = rootRef.current;
    if (!root || !controls) return;
    const box = new THREE.Box3().setFromObject(root);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const radius = Math.max(size.length() / 2, 1);
    const dir = new THREE.Vector3(0.7, 0.5, 0.9).normalize();
    camera.position.copy(center.clone().add(dir.multiplyScalar(radius * 2.2)));
    camera.near = Math.max(radius / 500, 0.01);
    camera.far = radius * 60;
    camera.updateProjectionMatrix();
    controls.target.copy(center);
    controls.update();
  }, [watchKey, camera, controls, rootRef]);
  return null;
}

export interface CityLabCanvasProps {
  def: StageDef;
  mode: CityLabMode;
  markedFaces: Map<string, Set<number>>;
  issues: TriangleIssue[];
  focus: Vec3 | null;
  lights: LightSpec[];
  selectedLightId: string | null;
  ambientColor: Vec3;
  ambientEnergy: number;
  sunEnergy: number;
  onPick: (pick: FacePick | null, worldPoint?: Vec3) => void;
  onSelectLight: (id: string) => void;
  onMoveLight: (id: string, pos: Vec3) => void;
  onRootReady: (root: THREE.Object3D | null) => void;
  /** Receives the pristine (un-mutated) GLTF scenes — the audit walks
   *  these so face indexes stay stable regardless of deletion marks. */
  onGltfsReady?: (cache: Record<string, THREE.Object3D>) => void;
}

export default function CityLabCanvas(props: CityLabCanvasProps) {
  const {
    def, mode, markedFaces, issues, focus, lights, selectedLightId,
    ambientColor, ambientEnergy, sunEnergy,
    onPick, onSelectLight, onMoveLight, onRootReady, onGltfsReady,
  } = props;
  const rootRef = useRef<THREE.Object3D | null>(null);
  const gltfs = useCityGltfs(onGltfsReady);
  const handleRootReady = (root: THREE.Object3D | null) => {
    rootRef.current = root;
    onRootReady(root);
  };

  return (
    <Canvas
      shadows
      camera={{ position: [12, 8, 12], fov: 50, near: 0.1, far: 800 }}
      style={{ background: '#15162e' }}
    >
      <Suspense fallback={null}>
        <StageModels
          def={def}
          gltfs={gltfs}
          mode={mode}
          markedFaces={markedFaces}
          onPick={onPick}
          onRootReady={handleRootReady}
        />
        {def.floorPath && gltfs[def.floorPath] && <FloorWire scene={gltfs[def.floorPath]} />}
        {mode === 'triangles' && <IssueOverlay issues={issues} />}
        {mode === 'lighting' && (
          <LightRig
            lights={lights}
            selectedId={selectedLightId}
            onSelect={onSelectLight}
            onMove={onMoveLight}
            ambientColor={ambientColor}
            ambientEnergy={ambientEnergy}
            sunEnergy={sunEnergy}
          />
        )}
        <Markers def={def} />
      </Suspense>
      {focus && <FocusMarker target={focus} />}
      {mode !== 'lighting' && <gridHelper args={[40, 40, 0x444466, 0x2a2a44]} />}
      <axesHelper args={[2]} />
      <OrbitControls makeDefault />
      <FitCamera watchKey={`${def.id}:${mode}`} rootRef={rootRef} />
    </Canvas>
  );
}
