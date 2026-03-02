import * as THREE from 'three';
import { Html } from '@react-three/drei';
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

const SLOT_COLORS: Record<string, string> = {
  pos_1: '#ffaa44',
  pos_2: '#ff66aa',
};

function NpcSlotMarker({ slotId, position, rotationY, active }: {
  slotId: string; position: [number, number, number]; rotationY: number; active: boolean;
}) {
  const color = SLOT_COLORS[slotId] || '#ffffff';
  return (
    <group position={position} rotation={[0, rotationY, 0]}>
      {/* Standing capsule */}
      <mesh position={[0, 0.7, 0]}>
        <capsuleGeometry args={[0.25, 0.8, 8, 16]} />
        <meshBasicMaterial color={color} transparent opacity={0.5} />
      </mesh>
      {/* Direction arrow */}
      <mesh position={[0, 0.3, -0.6]}>
        <coneGeometry args={[0.12, 0.3, 8]} />
        <meshBasicMaterial color={color} />
      </mesh>
      {/* Label */}
      <Html position={[0, 1.8, 0]} center style={{ pointerEvents: 'none' }}>
        <div style={{
          background: active ? '#ffaa00' : 'rgba(0,0,0,0.7)',
          color: active ? '#000' : color,
          padding: '1px 6px', borderRadius: 3,
          fontSize: 10, fontWeight: 600, whiteSpace: 'nowrap',
        }}>
          {slotId}
        </div>
      </Html>
      {/* Highlight ring when active */}
      {active && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.02, 0]}>
          <ringGeometry args={[0.5, 0.7, 32]} />
          <meshBasicMaterial color="#ffaa00" transparent opacity={0.6} />
        </mesh>
      )}
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

      {/* NPC position slots */}
      {Object.entries(layout.npcPositions).map(([slotId, slot]) => (
        <NpcSlotMarker
          key={slotId}
          slotId={slotId}
          position={slot.position}
          rotationY={slot.rotationY}
          active={placementMode === slotId}
        />
      ))}

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
