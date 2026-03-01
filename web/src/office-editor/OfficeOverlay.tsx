import * as THREE from 'three';
import type { OfficeLayoutData, PlacementMode } from './types';

function DoorTriggerZone({ position, size }: { position: [number, number, number]; size: [number, number, number] }) {
  return (
    <mesh position={position}>
      <boxGeometry args={size} />
      <meshBasicMaterial color="#4488ff" transparent opacity={0.3} side={THREE.DoubleSide} />
    </mesh>
  );
}

function DoorTriggerWireframe({ position, size }: { position: [number, number, number]; size: [number, number, number] }) {
  return (
    <mesh position={position}>
      <boxGeometry args={size} />
      <meshBasicMaterial color="#4488ff" wireframe />
    </mesh>
  );
}

function SpawnMarker({ position, rotationY }: { position: [number, number, number]; rotationY: number }) {
  return (
    <group position={position} rotation={[0, rotationY, 0]}>
      {/* Cone pointing forward */}
      <mesh position={[0, 0.5, 0]} rotation={[Math.PI / 2, 0, 0]}>
        <coneGeometry args={[0.3, 0.8, 8]} />
        <meshBasicMaterial color="#44ff44" transparent opacity={0.7} />
      </mesh>
      {/* Direction arrow */}
      <mesh position={[0, 0.5, -0.6]}>
        <coneGeometry args={[0.15, 0.4, 8]} />
        <meshBasicMaterial color="#88ff88" />
      </mesh>
    </group>
  );
}

interface OfficeOverlayProps {
  layout: OfficeLayoutData;
  placementMode: PlacementMode;
}

export default function OfficeOverlay({ layout, placementMode }: OfficeOverlayProps) {
  return (
    <>
      <DoorTriggerZone position={layout.doorTrigger.position} size={layout.doorTrigger.size} />
      <DoorTriggerWireframe position={layout.doorTrigger.position} size={layout.doorTrigger.size} />
      <SpawnMarker position={layout.spawnPoint.position} rotationY={layout.spawnPoint.rotationY} />

      {/* Highlight ring around NPC when in npc placement mode */}
      {placementMode === 'npc' && (
        <mesh position={layout.npcPosition} rotation={[-Math.PI / 2, 0, 0]}>
          <ringGeometry args={[0.6, 0.8, 32]} />
          <meshBasicMaterial color="#ffaa00" transparent opacity={0.6} />
        </mesh>
      )}
      {placementMode === 'door' && (
        <mesh position={layout.doorTrigger.position}>
          <boxGeometry args={layout.doorTrigger.size.map(s => s + 0.1) as unknown as [number, number, number]} />
          <meshBasicMaterial color="#ffaa00" wireframe />
        </mesh>
      )}
      {placementMode === 'spawn' && (
        <mesh position={layout.spawnPoint.position} rotation={[-Math.PI / 2, 0, 0]}>
          <ringGeometry args={[0.4, 0.6, 32]} />
          <meshBasicMaterial color="#ffaa00" transparent opacity={0.6} />
        </mesh>
      )}
    </>
  );
}
