import { useMemo, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type DropItemState = 'available' | 'collected';

interface DropItemProps extends ElementProps {
  state?: DropItemState;
}

// Story metadata for the storybook
export const dropItemMeta: StoryMeta = {
  title: 'Drop: Item',
  description: 'Generic item drop. Floats and rotates when available.',
  states: [
    { name: 'available', label: 'Available', description: 'Item can be picked up' },
    { name: 'collected', label: 'Collected', description: 'Item has been collected' },
  ],
  defaultState: 'available',
};

export default function DropItem({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'available',
}: DropItemProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_dropit.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);
  const timeRef = useRef(0);

  // Floating and spinning animation
  useFrame((_, delta) => {
    if (state !== 'available' || !groupRef.current) return;

    timeRef.current += delta;
    groupRef.current.rotation.y += delta * 2;
    groupRef.current.position.y = position[1] + Math.sin(timeRef.current * 3) * 0.1;
  });

  if (state === 'collected') return null;

  return (
    <group ref={groupRef} position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(assetUrl('/assets/objects/valley/o0c_dropit.glb'));
