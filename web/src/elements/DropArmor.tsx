import { useMemo, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type DropArmorState = 'available' | 'collected';

interface DropArmorProps extends ElementProps {
  state?: DropArmorState;
}

// Story metadata for the storybook
export const dropArmorMeta: StoryMeta = {
  title: 'Drop: Armor',
  description: 'Armor/protector drop. Floats and rotates when available.',
  states: [
    { name: 'available', label: 'Available', description: 'Armor can be picked up' },
    { name: 'collected', label: 'Collected', description: 'Armor has been collected' },
  ],
  defaultState: 'available',
};

export default function DropArmor({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'available',
}: DropArmorProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_droppr.glb'));
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

useGLTF.preload(assetUrl('/assets/objects/valley/o0c_droppr.glb'));
