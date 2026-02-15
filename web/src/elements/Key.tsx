import { useRef, useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type KeyState = 'available' | 'collected';

interface KeyProps extends ElementProps {
  state?: KeyState;
  keyId?: string;
  onCollect?: (keyId: string) => void;
}

// Story metadata for the storybook
export const keyMeta: StoryMeta = {
  title: 'Key',
  description: 'Pickup item that unlocks key-gates. Floats and rotates when available.',
  states: [
    { name: 'available', label: 'Available', description: 'Key can be picked up' },
    { name: 'collected', label: 'Collected', description: 'Key has been collected' },
  ],
  defaultState: 'available',
};

export default function Key({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'available',
  keyId = 'default',
  onCollect,
}: KeyProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_key.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);
  const timeRef = useRef(0);

  // Floating and spinning animation
  useFrame((_, delta) => {
    if (state !== 'available' || !groupRef.current) return;

    timeRef.current += delta;

    // Spin
    groupRef.current.rotation.y += delta * 2;

    // Bob up and down
    groupRef.current.position.y = position[1] + Math.sin(timeRef.current * 3) * 0.1;
  });

  // Apply visual state
  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            if (state === 'collected') {
              mat.transparent = true;
              mat.opacity = 0;
            } else {
              mat.transparent = false;
              mat.opacity = 1;
            }
            mat.needsUpdate = true;
          }
        });
      }
    });
  }, [clonedScene, state]);

  if (state === 'collected') return null;

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
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_key.glb'));
