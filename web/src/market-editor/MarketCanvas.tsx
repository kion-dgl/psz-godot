import { Canvas, type ThreeEvent } from '@react-three/fiber';
import { OrbitControls, TransformControls, useGLTF } from '@react-three/drei';
import { Suspense, useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import type { CartId, CartTransform, FaceMark, Mode, TransformMode } from './types';

const MARKET_PATH = 'assets/stages/city_e/s00e_sa1/lndmd/s00e_sa1_m.glb';
const CART_PATH = 'assets/stages/city_e/market/weapon_shop/weapon_shop_cart.glb';
const ITEM_CART_PATH = 'assets/stages/city_e/market/item_shop/item_cart.glb';

interface MarketModelProps {
  mode: Mode;
  markedMeshes: Set<string>;
  markedFaces: Map<string, FaceMark>;
  onMeshPick: (name: string) => void;
  onFacePick: (mark: FaceMark) => void;
  onSceneReady?: (scene: THREE.Object3D) => void;
}

function vec3FromAttr(
  attr: THREE.BufferAttribute | THREE.InterleavedBufferAttribute,
  i: number,
  matrixWorld: THREE.Matrix4
): [number, number, number] {
  const v = new THREE.Vector3().fromBufferAttribute(attr, i).applyMatrix4(matrixWorld);
  return [v.x, v.y, v.z];
}

function MarketModel({ mode, markedMeshes, markedFaces, onMeshPick, onFacePick, onSceneReady }: MarketModelProps) {
  const { scene } = useGLTF(assetUrl(MARKET_PATH));
  const origIndices = useRef<Map<string, THREE.BufferAttribute>>(new Map());

  // Surface the loaded scene up to the editor so the side-panel
  // "Download GLB" button can pass it to the GLTFExporter. The scene
  // reference is the same object we're mutating with face filters and
  // visibility, so the exporter sees the live state.
  useEffect(() => {
    if (onSceneReady) onSceneReady(scene);
  }, [scene, onSceneReady]);

  useEffect(() => {
    scene.updateMatrixWorld(true);
    const facesByMesh = new Map<string, Set<number>>();
    for (const m of markedFaces.values()) {
      let set = facesByMesh.get(m.meshName);
      if (!set) {
        set = new Set();
        facesByMesh.set(m.meshName, set);
      }
      set.add(m.faceIndex);
    }
    scene.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh)) return;
      if (!origIndices.current.has(obj.uuid) && obj.geometry.index) {
        origIndices.current.set(obj.uuid, obj.geometry.index.clone() as THREE.BufferAttribute);
      }
      const orig = origIndices.current.get(obj.uuid);
      if (markedMeshes.has(obj.name)) {
        obj.visible = false;
        if (orig) obj.geometry.setIndex(orig);
        return;
      }
      obj.visible = true;
      if (!orig) return;
      const removeSet = facesByMesh.get(obj.name);
      if (!removeSet || removeSet.size === 0) {
        obj.geometry.setIndex(orig);
        return;
      }
      const total = orig.count / 3;
      const newIdx: number[] = new Array(Math.max(0, (total - removeSet.size) * 3));
      let w = 0;
      for (let f = 0; f < total; f++) {
        if (removeSet.has(f)) continue;
        newIdx[w++] = orig.getX(f * 3);
        newIdx[w++] = orig.getX(f * 3 + 1);
        newIdx[w++] = orig.getX(f * 3 + 2);
      }
      obj.geometry.setIndex(newIdx);
    });
  }, [scene, markedMeshes, markedFaces]);

  const handleClick = (e: ThreeEvent<MouseEvent>) => {
    // Mesh/Face picks are only meaningful in their own modes — in Place
    // mode the click is reserved for OrbitControls / TransformControls
    // gizmo interaction.
    if (mode === 'place') return;
    e.stopPropagation();
    const hit = e.intersections[0];
    if (!hit) return;
    let target: THREE.Object3D | null = hit.object;
    while (target && !(target instanceof THREE.Mesh)) {
      target = target.parent;
    }
    if (!(target instanceof THREE.Mesh)) return;

    if (mode === 'mesh') {
      onMeshPick(target.name);
      return;
    }
    if (hit.faceIndex == null) return;
    const currentIdx = target.geometry.index;
    if (!currentIdx) return;
    const a = currentIdx.getX(hit.faceIndex * 3);
    const b = currentIdx.getX(hit.faceIndex * 3 + 1);
    const c = currentIdx.getX(hit.faceIndex * 3 + 2);
    const orig = origIndices.current.get(target.uuid);
    if (!orig) return;
    let origFace = -1;
    const total = orig.count / 3;
    for (let f = 0; f < total; f++) {
      if (
        orig.getX(f * 3) === a &&
        orig.getX(f * 3 + 1) === b &&
        orig.getX(f * 3 + 2) === c
      ) {
        origFace = f;
        break;
      }
    }
    if (origFace < 0) return;
    const posAttr = target.geometry.attributes.position as
      | THREE.BufferAttribute
      | THREE.InterleavedBufferAttribute;
    onFacePick({
      meshName: target.name,
      faceIndex: origFace,
      v0: vec3FromAttr(posAttr, a, target.matrixWorld),
      v1: vec3FromAttr(posAttr, b, target.matrixWorld),
      v2: vec3FromAttr(posAttr, c, target.matrixWorld),
    });
  };

  return <primitive object={scene} onClick={handleClick} />;
}

interface PlaceableCartProps {
  path: string;
  transform: CartTransform;
  transformMode: TransformMode;
  onChange: (t: CartTransform) => void;
  /** Only the selected cart shows the TransformControls gizmo so drags
   *  hit exactly one cart at a time, even when both render. */
  selected: boolean;
}

/** Loads a cart GLB and attaches a transform gizmo when selected. The
 *  group ref drives the Object3D position/rot/scale, so the gizmo
 *  manipulates them directly and we read them back in onObjectChange.
 *  Initialized once from `transform` on mount; subsequent prop changes
 *  (e.g. numeric input edits in the side panel) are applied via
 *  useEffect below. Two PlaceableCart instances render in 'place'
 *  mode (weapon + item) using distinct `path`s — useGLTF caches by
 *  path so each instance loads its own scene. */
function PlaceableCart({ path, transform, transformMode, onChange, selected }: PlaceableCartProps) {
  const { scene } = useGLTF(assetUrl(path));
  const [groupNode, setGroupNode] = useState<THREE.Group | null>(null);

  // Set the initial transform once the group mounts.
  useEffect(() => {
    if (!groupNode) return;
    groupNode.position.set(transform.pos[0], transform.pos[1], transform.pos[2]);
    groupNode.rotation.set(transform.rot[0], transform.rot[1], transform.rot[2]);
    groupNode.scale.set(transform.scale[0], transform.scale[1], transform.scale[2]);
  }, [groupNode]);

  // External numeric edits (typed in the side panel) push to the group
  // when they diverge from the live transform. The threshold guard
  // prevents a feedback loop when this effect runs after onObjectChange
  // sync'd state — re-setting the same value would still fire
  // TransformControls' "objectChange" event in three-stdlib.
  useEffect(() => {
    if (!groupNode) return;
    if (
      Math.abs(groupNode.position.x - transform.pos[0]) > 1e-5 ||
      Math.abs(groupNode.position.y - transform.pos[1]) > 1e-5 ||
      Math.abs(groupNode.position.z - transform.pos[2]) > 1e-5
    ) {
      groupNode.position.set(transform.pos[0], transform.pos[1], transform.pos[2]);
    }
    if (
      Math.abs(groupNode.rotation.x - transform.rot[0]) > 1e-5 ||
      Math.abs(groupNode.rotation.y - transform.rot[1]) > 1e-5 ||
      Math.abs(groupNode.rotation.z - transform.rot[2]) > 1e-5
    ) {
      groupNode.rotation.set(transform.rot[0], transform.rot[1], transform.rot[2]);
    }
    if (
      Math.abs(groupNode.scale.x - transform.scale[0]) > 1e-5 ||
      Math.abs(groupNode.scale.y - transform.scale[1]) > 1e-5 ||
      Math.abs(groupNode.scale.z - transform.scale[2]) > 1e-5
    ) {
      groupNode.scale.set(transform.scale[0], transform.scale[1], transform.scale[2]);
    }
  }, [transform, groupNode]);

  const handleObjectChange = () => {
    if (!groupNode) return;
    onChange({
      pos: [groupNode.position.x, groupNode.position.y, groupNode.position.z],
      rot: [groupNode.rotation.x, groupNode.rotation.y, groupNode.rotation.z],
      scale: [groupNode.scale.x, groupNode.scale.y, groupNode.scale.z],
    });
  };

  return (
    <>
      <group ref={setGroupNode}>
        <primitive object={scene} />
      </group>
      {selected && groupNode && (
        <TransformControls
          object={groupNode}
          mode={transformMode}
          onObjectChange={handleObjectChange}
        />
      )}
    </>
  );
}

interface MarketCanvasProps {
  mode: Mode;
  markedMeshes: Set<string>;
  markedFaces: Map<string, FaceMark>;
  onMeshPick: (name: string) => void;
  onFacePick: (mark: FaceMark) => void;
  cartTransform: CartTransform;
  itemCartTransform: CartTransform;
  selectedCart: CartId;
  transformMode: TransformMode;
  onCartChange: (t: CartTransform) => void;
  onItemCartChange: (t: CartTransform) => void;
  onSceneReady?: (scene: THREE.Object3D) => void;
}

export default function MarketCanvas({
  mode,
  markedMeshes,
  markedFaces,
  onMeshPick,
  onFacePick,
  cartTransform,
  itemCartTransform,
  selectedCart,
  transformMode,
  onCartChange,
  onItemCartChange,
  onSceneReady,
}: MarketCanvasProps) {
  return (
    <Canvas
      camera={{ position: [12, 8, 12], fov: 50, near: 0.1, far: 500 }}
      style={{ background: '#15162e' }}
    >
      <ambientLight intensity={0.6} />
      <directionalLight position={[10, 20, 10]} intensity={0.8} />
      <Suspense fallback={null}>
        <MarketModel
          mode={mode}
          markedMeshes={markedMeshes}
          markedFaces={markedFaces}
          onMeshPick={onMeshPick}
          onFacePick={onFacePick}
          onSceneReady={onSceneReady}
        />
        {mode === 'place' && (
          <>
            <PlaceableCart
              path={CART_PATH}
              transform={cartTransform}
              transformMode={transformMode}
              onChange={onCartChange}
              selected={selectedCart === 'weapon'}
            />
            <PlaceableCart
              path={ITEM_CART_PATH}
              transform={itemCartTransform}
              transformMode={transformMode}
              onChange={onItemCartChange}
              selected={selectedCart === 'item'}
            />
          </>
        )}
      </Suspense>
      <gridHelper args={[40, 40, 0x444466, 0x2a2a44]} />
      <axesHelper args={[2]} />
      <OrbitControls makeDefault />
    </Canvas>
  );
}

useGLTF.preload(assetUrl(MARKET_PATH));
useGLTF.preload(assetUrl(CART_PATH));
useGLTF.preload(assetUrl(ITEM_CART_PATH));
