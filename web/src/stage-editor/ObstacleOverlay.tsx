import { useRef, useMemo } from 'react';
import { useThree, useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ObstacleData, ObstacleType } from './types';

interface ObstacleOverlayProps {
  obstacles: ObstacleData[];
  selectedObstacleId: string | null;
  placementMode: boolean;
  placementType: ObstacleType;
  placementDimensions: {
    width: number;
    height: number;
    depth: number;
    radius: number;
    cylinderHeight: number;
    rotationY: number; // In degrees
  };
  onObstacleClick: (id: string) => void;
  onPlaceObstacle: (position: [number, number, number]) => void;
}

// Rendered obstacle (placed)
function ObstacleMesh({
  obstacle,
  selected,
  onClick,
}: {
  obstacle: ObstacleData;
  selected: boolean;
  onClick: () => void;
}) {
  const color = selected ? '#4a9eff' : (obstacle.type === 'box' ? '#6b5b95' : '#88b04b');

  // Calculate Y position (center of shape above ground + small offset to avoid z-fighting)
  const height = obstacle.type === 'box' ? (obstacle.height || 2) : (obstacle.cylinderHeight || 2);
  const yPos = height / 2 + 0.01; // Small Y offset

  // Render the obstacle mesh with semi-transparency
  if (obstacle.type === 'box') {
    return (
      <mesh
        position={[obstacle.position[0], yPos, obstacle.position[2]]}
        rotation={[obstacle.rotation[0], obstacle.rotation[1], obstacle.rotation[2]]}
        onClick={(e) => {
          e.stopPropagation();
          onClick();
        }}
      >
        <boxGeometry args={[obstacle.width || 2, obstacle.height || 2, obstacle.depth || 2]} />
        <meshStandardMaterial
          color={color}
          transparent
          opacity={selected ? 0.9 : 0.6}
        />
      </mesh>
    );
  }

  // Cylinder
  return (
    <mesh
      position={[obstacle.position[0], yPos, obstacle.position[2]]}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
    >
      <cylinderGeometry args={[obstacle.radius || 1, obstacle.radius || 1, obstacle.cylinderHeight || 2, 16]} />
      <meshStandardMaterial
        color={color}
        transparent
        opacity={selected ? 0.9 : 0.6}
      />
    </mesh>
  );
}

// Preview that follows the mouse
function PlacementPreview({
  type,
  dimensions,
}: {
  type: ObstacleType;
  dimensions: {
    width: number;
    height: number;
    depth: number;
    radius: number;
    cylinderHeight: number;
    rotationY: number;
  };
}) {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  // Convert degrees to radians for box rotation
  const rotationYRad = (dimensions.rotationY * Math.PI) / 180;

  useFrame(() => {
    if (!groupRef.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 0, intersection.z);
    }
  });

  const color = type === 'box' ? '#6b5b95' : '#88b04b';

  // Render preview based on type
  if (type === 'box') {
    return (
      <group ref={groupRef} rotation={[0, rotationYRad, 0]}>
        <mesh position={[0, dimensions.height / 2, 0]}>
          <boxGeometry args={[dimensions.width, dimensions.height, dimensions.depth]} />
          <meshStandardMaterial color={color} transparent opacity={0.4} />
      </mesh>
        <lineSegments position={[0, dimensions.height / 2, 0]}>
          <edgesGeometry args={[new THREE.BoxGeometry(dimensions.width, dimensions.height, dimensions.depth)]} />
          <lineBasicMaterial color={color} />
        </lineSegments>
      </group>
    );
  }

  // Cylinder preview
  return (
    <group ref={groupRef}>
      <mesh position={[0, dimensions.cylinderHeight / 2, 0]}>
        <cylinderGeometry args={[dimensions.radius, dimensions.radius, dimensions.cylinderHeight, 16]} />
        <meshStandardMaterial color={color} transparent opacity={0.4} />
      </mesh>
      <lineSegments position={[0, dimensions.cylinderHeight / 2, 0]}>
        <edgesGeometry args={[new THREE.CylinderGeometry(dimensions.radius, dimensions.radius, dimensions.cylinderHeight, 16)]} />
        <lineBasicMaterial color={color} />
      </lineSegments>
    </group>
  );
}

export default function ObstacleOverlay({
  obstacles,
  selectedObstacleId,
  placementMode,
  placementType,
  placementDimensions,
  onObstacleClick,
  onPlaceObstacle,
}: ObstacleOverlayProps) {
  const { camera, raycaster, pointer } = useThree();
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  const handleClick = () => {
    if (!placementMode) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      onPlaceObstacle([intersection.x, 0, intersection.z]);
    }
  };

  return (
    <group>
      {/* Ground plane for click detection in placement mode */}
      {placementMode && (
        <mesh
          rotation={[-Math.PI / 2, 0, 0]}
          position={[0, 0.01, 0]}
          onClick={handleClick}
        >
          <planeGeometry args={[200, 200]} />
          <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Existing obstacles */}
      {obstacles.map((obstacle) => (
        <ObstacleMesh
          key={obstacle.id}
          obstacle={obstacle}
          selected={obstacle.id === selectedObstacleId}
          onClick={() => onObstacleClick(obstacle.id)}
        />
      ))}

      {/* Placement preview */}
      {placementMode && (
        <PlacementPreview
          type={placementType}
          dimensions={placementDimensions}
        />
      )}
    </group>
  );
}
