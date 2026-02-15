import { useMemo, useEffect, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type WaypointState = 'new' | 'unvisited' | 'visited';

interface WaypointProps extends ElementProps {
  state?: WaypointState;
  targetUrl?: string;
}

// Story metadata for the storybook
export const waypointMeta: StoryMeta = {
  title: 'Waypoint',
  description: 'Navigation indicator placed in load area triggers. Shows if destination has been visited.',
  states: [
    { name: 'new', label: 'New Area', description: 'Area has never been visited' },
    { name: 'unvisited', label: 'Unvisited', description: 'Area exists but not yet visited this run' },
    { name: 'visited', label: 'Visited', description: 'Player has already been to this area' },
  ],
  defaultState: 'unvisited',
};

// Texture offset X values for different states
// Based on o0c_point.imd texture analysis
const STATE_OFFSETS: Record<WaypointState, number> = {
  new: 0.00,
  unvisited: 0.12,
  visited: 0.40,
};

export default function Waypoint({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'unvisited',
  targetUrl,
}: WaypointProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_point.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);
  const timeRef = useRef(0);

  // Apply texture offset based on state
  useEffect(() => {
    const offsetX = STATE_OFFSETS[state];

    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if ((mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) && mat.map) {
            mat.map.offset.x = offsetX;
            mat.map.needsUpdate = true;
          }
        });
      }
    });
  }, [clonedScene, state]);

  // Gentle floating animation
  useFrame((_, delta) => {
    if (!groupRef.current) return;

    timeRef.current += delta;

    // Slow bob
    groupRef.current.position.y = position[1] + Math.sin(timeRef.current * 2) * 0.05;
  });

  return (
    <group
      ref={groupRef}
      position={position}
      rotation={rotation}
      scale={scale}
    >
      <primitive object={clonedScene} />
    </group>
  );
}

// Preload the model
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_point.glb'));
