import { useRef, useMemo } from 'react';
import { useThree, useFrame } from '@react-three/fiber';
import { Line, Html } from '@react-three/drei';
import * as THREE from 'three';
import type { WaypointData, WaypointKind } from './types';

interface WaypointOverlayProps {
  waypoints: WaypointData[];
  edges: [string, string][];
  selectedId: string | null;
  placementMode: boolean;
  onPlace: (position: [number, number, number]) => void;
  onWaypointClick: (id: string) => void;
}

const KIND_COLORS: Record<WaypointKind, string> = {
  point: '#5ad1ff',
  gate: '#00ffff',
  spawn: '#44ff44',
  npc: '#ffd24a',
  exit: '#ff8c00',
};

const Y = 0.6; // lift markers + edge lines slightly above the floor

function WaypointMarker({
  wp,
  selected,
  interactive,
  onClick,
}: {
  wp: WaypointData;
  selected: boolean;
  interactive: boolean;
  onClick: () => void;
}) {
  const color = selected ? '#ffffff' : KIND_COLORS[wp.kind ?? 'point'];
  return (
    <group position={[wp.position[0], Y, wp.position[2]]}>
      <mesh
        onClick={interactive ? (e) => { e.stopPropagation(); onClick(); } : undefined}
      >
        <sphereGeometry args={[selected ? 0.9 : 0.6, 16, 16]} />
        <meshBasicMaterial color={color} />
      </mesh>
      {/* ground ring */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -Y + 0.05, 0]}>
        <ringGeometry args={[0.9, 1.15, 24]} />
        <meshBasicMaterial color={color} transparent opacity={0.5} side={THREE.DoubleSide} />
      </mesh>
      {(wp.label || wp.kind) && (
        <Html position={[0, 1.4, 0]} center style={{ pointerEvents: 'none' }}>
          <div style={{
            background: 'rgba(0,0,0,0.8)', color, padding: '1px 5px', borderRadius: 3,
            fontSize: 10, fontFamily: 'monospace', whiteSpace: 'nowrap', border: `1px solid ${color}`,
          }}>
            {wp.label || wp.kind}
          </div>
        </Html>
      )}
    </group>
  );
}

function PlacementPreview() {
  const { camera, raycaster, pointer } = useThree();
  const ref = useRef<THREE.Mesh>(null);
  const plane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const hit = useMemo(() => new THREE.Vector3(), []);
  useFrame(() => {
    if (!ref.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(plane, hit)) ref.current.position.set(hit.x, Y, hit.z);
  });
  return (
    <mesh ref={ref}>
      <sphereGeometry args={[0.6, 16, 16]} />
      <meshBasicMaterial color="#5ad1ff" transparent opacity={0.45} />
    </mesh>
  );
}

export default function WaypointOverlay({
  waypoints, edges, selectedId, placementMode, onPlace, onWaypointClick,
}: WaypointOverlayProps) {
  const { camera, raycaster, pointer } = useThree();
  const plane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const hit = useMemo(() => new THREE.Vector3(), []);

  const byId = useMemo(() => {
    const m = new Map<string, WaypointData>();
    waypoints.forEach((w) => m.set(w.id, w));
    return m;
  }, [waypoints]);

  const handlePlaceClick = () => {
    if (!placementMode) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(plane, hit)) onPlace([hit.x, 0, hit.z]);
  };

  return (
    <group>
      {/* Invisible ground plane catches clicks while placing */}
      {placementMode && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.02, 0]} onClick={handlePlaceClick}>
          <planeGeometry args={[400, 400]} />
          <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Dashed edges between connected waypoints */}
      {edges.map(([a, b], i) => {
        const wa = byId.get(a);
        const wb = byId.get(b);
        if (!wa || !wb) return null;
        return (
          <Line
            key={`${a}-${b}-${i}`}
            points={[[wa.position[0], Y, wa.position[2]], [wb.position[0], Y, wb.position[2]]]}
            color="#9ad6ff"
            lineWidth={2}
            dashed
            dashSize={0.8}
            gapSize={0.5}
          />
        );
      })}

      {waypoints.map((wp) => (
        <WaypointMarker
          key={wp.id}
          wp={wp}
          selected={wp.id === selectedId}
          interactive={!placementMode}
          onClick={() => onWaypointClick(wp.id)}
        />
      ))}

      {placementMode && <PlacementPreview />}
    </group>
  );
}
