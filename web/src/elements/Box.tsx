import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type BoxState = 'intact' | 'destroyed';

interface BoxProps extends ElementProps {
  state?: BoxState;
}

// Story metadata for the storybook
export const boxMeta: StoryMeta = {
  title: 'Box',
  description: 'Destructible container. Model varies by field. (Valley variant)',
  states: [
    { name: 'intact', label: 'Intact', description: 'Box can be destroyed' },
    { name: 'destroyed', label: 'Destroyed', description: 'Box has been destroyed' },
  ],
  defaultState: 'intact',
};

export default function Box({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'intact',
}: BoxProps) {
  // Valley variant (o01_cont)
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o01_cont.glb'));
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

useGLTF.preload(assetUrl('/assets/objects/valley/o01_cont.glb'));
