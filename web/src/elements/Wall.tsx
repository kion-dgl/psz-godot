import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type WallState = 'intact' | 'destroyed';

interface WallProps extends ElementProps {
  state?: WallState;
}

// Story metadata for the storybook
export const wallMeta: StoryMeta = {
  title: 'Wall',
  description: 'Destructible wall obstacle. Model varies by field. (Valley variant)',
  states: [
    { name: 'intact', label: 'Intact', description: 'Wall blocks passage' },
    { name: 'destroyed', label: 'Destroyed', description: 'Wall has been destroyed' },
  ],
  defaultState: 'intact',
};

export default function Wall({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'intact',
}: WallProps) {
  // Valley variant (o01_wall)
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o01_wall.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  // Apply texture settings
  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            if (mat.map) {
              mat.map.wrapS = THREE.MirroredRepeatWrapping;
              mat.map.wrapT = THREE.MirroredRepeatWrapping;
              mat.map.repeat.set(2, 2);
              mat.map.offset.set(0, 0);
              mat.map.needsUpdate = true;
            }
            mat.needsUpdate = true;
          }
        });
      }
    });
  }, [clonedScene]);

  if (state === 'destroyed') return null;

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(assetUrl('/assets/objects/valley/o01_wall.glb'));
