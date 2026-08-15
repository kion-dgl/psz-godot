import { useRef, useMemo, useCallback } from 'react';
import { useGLTF, Html } from '@react-three/drei';
import { useThree, useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import { assetUrl } from '../utils/assets';
import type { PortalData, GateDirection, PreviewModel, SpawnPointData } from './types';
import { rotateDirection } from '../quest-editor/hooks/useStageConfigs';
import type { Direction } from '../quest-editor/types';
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
  label?: string;
  compassLabel?: string;
  portalId?: string;
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

// Compass rose at origin showing N/S/E/W directions
// Base axes: North = -Z, South = +Z, East = +X, West = -X
// When previewRotation > 0, labels rotate CW (e.g. at 90°: N→+X, E→+Z, S→-X, W→-Z)
function CompassRose({ previewRotation = 0 }: { previewRotation?: number }) {
  const armLength = 4;
  const armThickness = 0.15;

  // Physical axis positions (fixed, don't rotate)
  const axisPositions: [number, number, number][] = [
    [0, 0, -(armLength + 1.5)],  // -Z
    [0, 0, armLength + 1.5],     // +Z
    [armLength + 1.5, 0, 0],     // +X
    [-(armLength + 1.5), 0, 0],  // -X
  ];

  // Base direction labels at each axis position (rotation=0)
  const baseLabels: Direction[] = ['north', 'south', 'east', 'west'];
  const colors: Record<Direction, string> = { north: '#44ff44', south: '#ff4444', east: '#4488ff', west: '#ffaa00' };
  const shortNames: Record<Direction, string> = { north: 'N', south: 'S', east: 'E', west: 'W' };

  // Apply rotation: at each physical position, show which direction maps there
  // rotateDirection('north', 90) = 'east', meaning north label moves to where east was (+X)
  // So for each axis position, we need the INVERSE: which original dir rotates TO this position's base dir
  // Inverse of CW rotation by R is CW rotation by (360-R)
  const inverseRotation = (360 - previewRotation) % 360;
  const directions = baseLabels.map((baseDir, i) => {
    const rotatedLabel = rotateDirection(baseDir, inverseRotation);
    return {
      label: `${shortNames[rotatedLabel]}`,
      pos: axisPositions[i],
      color: colors[rotatedLabel],
    };
  });

  return (
    <group position={[0, 0.5, 0]}>
      {/* Center marker */}
      <mesh>
        <sphereGeometry args={[0.4, 16, 16]} />
        <meshBasicMaterial color="#ffffff" />
      </mesh>

      {/* N/S arm (-Z / +Z) */}
      <mesh position={[0, 0, 0]}>
        <boxGeometry args={[armThickness, armThickness, armLength * 2]} />
        <meshBasicMaterial color="#44ff44" />
      </mesh>
      {/* Arrow tip north (-Z) */}
      <mesh position={[0, 0, -armLength]} rotation={[Math.PI / 2, 0, 0]}>
        <coneGeometry args={[0.4, 0.8, 8]} />
        <meshBasicMaterial color="#44ff44" />
      </mesh>

      {/* E/W arm (-X / +X) */}
      <mesh position={[0, 0, 0]}>
        <boxGeometry args={[armLength * 2, armThickness, armThickness]} />
        <meshBasicMaterial color="#4488ff" />
      </mesh>
      {/* Arrow tip east (+X) */}
      <mesh position={[armLength, 0, 0]} rotation={[0, 0, -Math.PI / 2]}>
        <coneGeometry args={[0.4, 0.8, 8]} />
        <meshBasicMaterial color="#4488ff" />
      </mesh>

      {/* Labels */}
      {directions.map(({ label, pos, color }) => (
        <Html key={label} position={pos} center style={{ pointerEvents: 'none' }}>
          <div style={{
            background: 'rgba(0,0,0,0.85)',
            color,
            padding: '2px 6px',
            borderRadius: '3px',
            fontSize: '12px',
            fontFamily: 'monospace',
            fontWeight: 'bold',
            whiteSpace: 'nowrap',
            border: `1px solid ${color}`,
          }}>
            {label}
          </div>
        </Html>
      ))}
    </group>
  );
}

// Floating label above a portal showing direction, compass label, and truncated ID
function PortalLabel({ position, label, compassLabel, portalId }: { position: [number, number, number]; label?: string; compassLabel?: string; portalId?: string }) {
  if (!label && !compassLabel && !portalId) return null;
  const dir = label?.toUpperCase() || '';
  const compass = compassLabel ? ` [${compassLabel}]` : '';
  const idSuffix = portalId ? portalId.slice(-6) : '';

  return (
    <Html position={[position[0], position[1] + 5, position[2]]} center style={{ pointerEvents: 'none' }}>
      <div style={{
        background: 'rgba(0,0,0,0.8)',
        color: '#fff',
        padding: '3px 6px',
        borderRadius: '3px',
        fontSize: '11px',
        whiteSpace: 'nowrap',
        fontFamily: 'monospace',
        lineHeight: '1.3',
        textAlign: 'center',
        border: '1px solid #555',
      }}>
        <div style={{ fontWeight: 'bold' }}>{dir}{compass}</div>
        {idSuffix && <div style={{ fontSize: '9px', color: '#aaa' }}>...{idSuffix}</div>}
      </div>
    </Html>
  );
}

function GatePreview({ position, rotation, opacity = 1, selected, onClick, label, compassLabel, portalId }: Omit<PortalModelProps, 'modelType'>) {
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
      <PortalLabel position={position} label={label} compassLabel={compassLabel} portalId={portalId} />
    </group>
  );
}

function WarpPreview({ position, rotation, opacity = 1, selected, onClick, label, compassLabel, portalId }: Omit<PortalModelProps, 'modelType'>) {
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
      <PortalLabel position={position} label={label} compassLabel={compassLabel} portalId={portalId} />
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
  previewRotation?: number; // degrees (0/90/180/270) for compass + label rotation
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
  previewRotation = 0,
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
      {/* Compass rose at origin */}
      <CompassRose previewRotation={previewRotation} />

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
      {portals.map((portal) => {
        const rotatedDir = previewRotation > 0
          ? rotateDirection(portal.direction as Direction, previewRotation)
          : portal.direction;
        return (
          <PortalModel
            key={portal.id}
            // The GATE goes at the measured doorway when we have one — the same
            // split the runtime makes (portal_gate_manager._compute_portal_from_config).
            // `position` still drives spawn and trigger, so the markers inside
            // PortalModel stay where navigation expects them.
            position={(portal as { gatePosition?: [number, number, number] }).gatePosition ?? portal.position}
            rotation={getPortalRotation(portal)}
            modelType={previewModel}
            opacity={1}
            selected={portal.id === selectedPortalId}
            onClick={() => onPortalClick(portal.id)}
            label={previewRotation > 0 ? `${portal.direction}→${rotatedDir}` : portal.direction}
            compassLabel={portal.compass_label}
            portalId={portal.id}
          />
        );
      })}

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
