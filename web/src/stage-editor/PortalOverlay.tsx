import { useRef, useMemo, useCallback } from 'react';
import { useGLTF } from '@react-three/drei';
import { useThree, useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import { assetUrl } from '../utils/assets';
import type { PortalData, GateDirection, PreviewModel, SpawnPointData } from './types';
import { DIRECTION_ROTATIONS, getPortalRotation } from './types';

// Model paths — Godot asset layout
const GATE_MODEL_PATH = assetUrl('assets/objects/valley/o0c_gate.glb');
const WARP_MODEL_PATH = assetUrl('assets/objects/valley/o0s_warpm.glb');

interface PortalModelProps {
  position: [number, number, number];
  rotation: number; // effective rotation in radians
  modelType: PreviewModel;
  opacity?: number;
  selected?: boolean;
  onClick?: () => void;
}

// Spawn/trigger offset constants (matching ExportTab)
// Order from outside to inside: trigger -> spawn -> gate
const SPAWN_OUTSET = 3;   // Spawn behind the gate (outside)
const TRIGGER_OUTSET = 7; // Trigger further out, player hits it first
const GATE_WIDTH = 6.0;

// Compute spawn and trigger positions from gate position and rotation (radians)
function computeMarkerPositions(position: [number, number, number], rotation: number) {
  const [x, , z] = position;
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);

  return {
    // Spawn is outside the gate (player spawns behind gate)
    spawn: [x - sin * SPAWN_OUTSET, 1, z - cos * SPAWN_OUTSET] as [number, number, number],
    // Trigger is even further outside (player hits this first when entering)
    trigger: [x - sin * TRIGGER_OUTSET, 0, z - cos * TRIGGER_OUTSET] as [number, number, number],
    rotation,
  };
}

// Spawn point marker (sphere with ring and arrow)
function SpawnMarker({ position, rotation, color = "#00ff00" }: { position: [number, number, number]; rotation: number; color?: string }) {
  return (
    <group position={position}>
      <mesh>
        <sphereGeometry args={[0.8, 16, 16]} />
        <meshBasicMaterial color={color} transparent opacity={0.7} />
      </mesh>
      {/* Ring on ground */}
      <mesh rotation={[-Math.PI / 2, 0, 0]}>
        <ringGeometry args={[1, 1.3, 32]} />
        <meshBasicMaterial color={color} side={THREE.DoubleSide} />
      </mesh>
      {/* Direction arrow */}
      <group rotation={[0, rotation, 0]}>
        <mesh position={[0, 0.3, 1]}>
          <boxGeometry args={[0.2, 0.2, 1.5]} />
          <meshBasicMaterial color={color} />
        </mesh>
        <mesh position={[0, 0.3, 2]} rotation={[Math.PI / 2, 0, 0]}>
          <coneGeometry args={[0.4, 0.6, 8]} />
          <meshBasicMaterial color={color} />
        </mesh>
      </group>
    </group>
  );
}

// Trigger zone marker (orange box)
function TriggerMarker({ position, rotation }: { position: [number, number, number]; rotation: number }) {
  return (
    <group position={position} rotation={[0, rotation, 0]}>
      <mesh position={[0, 1.5, 0]}>
        <boxGeometry args={[GATE_WIDTH, 3, 2]} />
        <meshBasicMaterial color="#ff6600" transparent opacity={0.3} />
      </mesh>
      <lineSegments position={[0, 1.5, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(GATE_WIDTH, 3, 2)]} />
        <lineBasicMaterial color="#ff6600" />
      </lineSegments>
    </group>
  );
}

// Gate bounding box marker (cyan wireframe at gate position)
function GateBoundingBox({ position, rotation }: { position: [number, number, number]; rotation: number }) {
  const boxWidth = GATE_WIDTH;
  const boxHeight = 4;
  const boxDepth = 1;

  return (
    <group position={position} rotation={[0, rotation, 0]}>
      {/* Semi-transparent fill */}
      <mesh position={[0, boxHeight / 2, 0]}>
        <boxGeometry args={[boxWidth, boxHeight, boxDepth]} />
        <meshBasicMaterial color="#00ffff" transparent opacity={0.15} />
      </mesh>
      {/* Wireframe outline */}
      <lineSegments position={[0, boxHeight / 2, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(boxWidth, boxHeight, boxDepth)]} />
        <lineBasicMaterial color="#00ffff" linewidth={2} />
      </lineSegments>
    </group>
  );
}

function GatePreview({ position, rotation, opacity = 1, selected, onClick }: Omit<PortalModelProps, 'modelType'>) {
  const { scene } = useGLTF(GATE_MODEL_PATH);

  const clonedScene = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materials.forEach((mat) => {
          const material = mat as THREE.MeshStandardMaterial;
          material.transparent = true;
          material.opacity = opacity;
          material.needsUpdate = true;
        });
      }
    });
    return clone;
  }, [scene, opacity]);

  const markers = useMemo(() => computeMarkerPositions(position, rotation), [position, rotation]);

  return (
    <group>
      <group
        position={position}
        rotation={[0, rotation, 0]}
        onClick={(e) => {
          e.stopPropagation();
          onClick?.();
        }}
      >
        <primitive object={clonedScene} />
        {selected && (
          <mesh position={[0, 2, 0]}>
            <sphereGeometry args={[0.3]} />
            <meshBasicMaterial color="#4a9eff" />
          </mesh>
        )}
      </group>
      <GateBoundingBox position={position} rotation={rotation} />
      <SpawnMarker position={markers.spawn} rotation={markers.rotation} />
      <TriggerMarker position={markers.trigger} rotation={markers.rotation} />
    </group>
  );
}

function WarpPreview({ position, rotation, opacity = 1, selected, onClick }: Omit<PortalModelProps, 'modelType'>) {
  const { scene } = useGLTF(WARP_MODEL_PATH);

  const clonedScene = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materials.forEach((mat) => {
          const material = mat as THREE.MeshStandardMaterial;
          material.transparent = true;
          material.opacity = opacity;
          material.needsUpdate = true;
        });
      }
    });
    return clone;
  }, [scene, opacity]);

  const markers = useMemo(() => computeMarkerPositions(position, rotation), [position, rotation]);

  return (
    <group>
      <group
        position={position}
        rotation={[0, rotation, 0]}
        onClick={(e) => {
          e.stopPropagation();
          onClick?.();
        }}
      >
        <primitive object={clonedScene} />
        {selected && (
          <mesh position={[0, 2, 0]}>
            <sphereGeometry args={[0.3]} />
            <meshBasicMaterial color="#4a9eff" />
          </mesh>
        )}
      </group>
      <GateBoundingBox position={position} rotation={rotation} />
      <SpawnMarker position={markers.spawn} rotation={markers.rotation} />
      <TriggerMarker position={markers.trigger} rotation={markers.rotation} />
    </group>
  );
}

function PortalModel({ modelType, ...props }: PortalModelProps) {
  if (modelType === 'Gate') {
    return <GatePreview {...props} />;
  }
  return <WarpPreview {...props} />;
}

interface PortalOverlayProps {
  portals: PortalData[];
  selectedPortalId: string | null;
  placementMode: boolean;
  placementDirection: GateDirection;
  placementRotationOffset: number; // degrees
  previewModel: PreviewModel;
  onPortalClick: (id: string) => void;
  onPlacePortal: (position: [number, number, number]) => void;
  onUpdatePortalPosition?: (id: string, position: [number, number, number]) => void;
  defaultSpawn?: SpawnPointData;
  spawnPlacementMode?: boolean;
  onPlaceDefaultSpawn?: (position: [number, number, number]) => void;
}

// Spawn marker for placement preview (semi-transparent)
function SpawnMarkerPreview({ localOffset }: { localOffset: [number, number, number] }) {
  return (
    <group position={localOffset}>
      <mesh>
        <sphereGeometry args={[0.8, 16, 16]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.4} />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]}>
        <ringGeometry args={[1, 1.3, 32]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.4} side={THREE.DoubleSide} />
      </mesh>
      <mesh position={[0, 0.3, 1]}>
        <boxGeometry args={[0.2, 0.2, 1.5]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.5} />
      </mesh>
      <mesh position={[0, 0.3, 2]} rotation={[Math.PI / 2, 0, 0]}>
        <coneGeometry args={[0.4, 0.6, 8]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.5} />
      </mesh>
    </group>
  );
}

// Trigger marker for placement preview (semi-transparent)
function TriggerMarkerPreview({ localOffset }: { localOffset: [number, number, number] }) {
  return (
    <group position={localOffset}>
      <mesh position={[0, 1.5, 0]}>
        <boxGeometry args={[GATE_WIDTH, 3, 2]} />
        <meshBasicMaterial color="#ff6600" transparent opacity={0.2} />
      </mesh>
      <lineSegments position={[0, 1.5, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(GATE_WIDTH, 3, 2)]} />
        <lineBasicMaterial color="#ff6600" transparent opacity={0.5} />
      </lineSegments>
    </group>
  );
}

// Gate bounding box for placement preview (semi-transparent)
function GateBoundingBoxPreview() {
  const boxWidth = GATE_WIDTH;
  const boxHeight = 4;
  const boxDepth = 1;

  return (
    <group>
      <mesh position={[0, boxHeight / 2, 0]}>
        <boxGeometry args={[boxWidth, boxHeight, boxDepth]} />
        <meshBasicMaterial color="#00ffff" transparent opacity={0.1} />
      </mesh>
      <lineSegments position={[0, boxHeight / 2, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(boxWidth, boxHeight, boxDepth)]} />
        <lineBasicMaterial color="#00ffff" transparent opacity={0.5} />
      </lineSegments>
    </group>
  );
}

// Separate component for the preview that follows the mouse
function PlacementPreview({
  rotation,
  modelType
}: {
  rotation: number; // effective rotation in radians
  modelType: PreviewModel;
}) {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  useFrame(() => {
    if (!groupRef.current) return;

    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 0, intersection.z);
    }
  });

  const spawnLocalOffset: [number, number, number] = [0, 1, -SPAWN_OUTSET];
  const triggerLocalOffset: [number, number, number] = [0, 0, -TRIGGER_OUTSET];

  return (
    <group ref={groupRef} rotation={[0, rotation, 0]}>
      {modelType === 'Gate' ? (
        <GatePreviewStatic opacity={0.5} />
      ) : (
        <WarpPreviewStatic opacity={0.5} />
      )}
      <GateBoundingBoxPreview />
      <SpawnMarkerPreview localOffset={spawnLocalOffset} />
      <TriggerMarkerPreview localOffset={triggerLocalOffset} />
    </group>
  );
}

// Spawn-only placement preview (follows mouse, shows just the spawn marker)
function SpawnPlacementPreview({ direction }: { direction: GateDirection }) {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  useFrame(() => {
    if (!groupRef.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 0, intersection.z);
    }
  });

  const rotation = DIRECTION_ROTATIONS[direction];

  return (
    <group ref={groupRef}>
      <SpawnMarker position={[0, 1, 0]} rotation={rotation} color="#ffff00" />
    </group>
  );
}

// Static preview components that don't need position (position is on parent group)
function GatePreviewStatic({ opacity }: { opacity: number }) {
  const { scene } = useGLTF(GATE_MODEL_PATH);

  const clonedScene = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materials.forEach((mat) => {
          const material = mat as THREE.MeshStandardMaterial;
          material.transparent = true;
          material.opacity = opacity;
          material.needsUpdate = true;
        });
      }
    });
    return clone;
  }, [scene, opacity]);

  return <primitive object={clonedScene} />;
}

function WarpPreviewStatic({ opacity }: { opacity: number }) {
  const { scene } = useGLTF(WARP_MODEL_PATH);

  const clonedScene = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materials.forEach((mat) => {
          const material = mat as THREE.MeshStandardMaterial;
          material.transparent = true;
          material.opacity = opacity;
          material.needsUpdate = true;
        });
      }
    });
    return clone;
  }, [scene, opacity]);

  return <primitive object={clonedScene} />;
}

export default function PortalOverlay({
  portals,
  selectedPortalId,
  placementMode,
  placementDirection,
  placementRotationOffset,
  previewModel,
  onPortalClick,
  onPlacePortal,
  onUpdatePortalPosition,
  defaultSpawn,
  spawnPlacementMode,
  onPlaceDefaultSpawn,
}: PortalOverlayProps) {
  const { camera, raycaster, pointer } = useThree();
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  const anyPlacementMode = placementMode || spawnPlacementMode;

  // Handle click to place - get position from raycaster at click time
  const handleCanvasClick = useCallback(() => {
    raycaster.setFromCamera(pointer, camera);
    if (!raycaster.ray.intersectPlane(groundPlane, intersection)) return;

    if (placementMode) {
      onPlacePortal([intersection.x, 0, intersection.z]);
    } else if (spawnPlacementMode && onPlaceDefaultSpawn) {
      onPlaceDefaultSpawn([intersection.x, 0, intersection.z]);
    }
  }, [placementMode, spawnPlacementMode, raycaster, pointer, camera, groundPlane, intersection, onPlacePortal, onPlaceDefaultSpawn]);

  return (
    <group>
      {/* Ground plane for click detection in placement mode */}
      {anyPlacementMode && (
        <mesh
          rotation={[-Math.PI / 2, 0, 0]}
          position={[0, 0.01, 0]}
          onClick={handleCanvasClick}
        >
          <planeGeometry args={[200, 200]} />
          <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Existing portals */}
      {portals.map((portal) => (
        <PortalModel
          key={portal.id}
          position={portal.position}
          rotation={getPortalRotation(portal)}
          modelType={previewModel}
          opacity={1}
          selected={portal.id === selectedPortalId}
          onClick={() => onPortalClick(portal.id)}
        />
      ))}

      {/* Default spawn marker (yellow) */}
      {defaultSpawn && (
        <SpawnMarker position={defaultSpawn.position} rotation={DIRECTION_ROTATIONS[defaultSpawn.direction]} color="#ffff00" />
      )}

      {/* Preview portal when in placement mode - follows mouse */}
      {placementMode && (
        <PlacementPreview
          rotation={DIRECTION_ROTATIONS[placementDirection] + (placementRotationOffset * Math.PI) / 180}
          modelType={previewModel}
        />
      )}

      {/* Preview spawn marker when in spawn placement mode */}
      {spawnPlacementMode && (
        <SpawnPlacementPreview direction={placementDirection} />
      )}
    </group>
  );
}

// Preload models
useGLTF.preload(GATE_MODEL_PATH);
useGLTF.preload(WARP_MODEL_PATH);
