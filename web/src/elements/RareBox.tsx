import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type RareBoxState = 'intact' | 'destroyed';

interface RareBoxProps extends ElementProps {
  state?: RareBoxState;
}

// Story metadata for the storybook
export const rareBoxMeta: StoryMeta = {
  title: 'Rare Box',
  description: 'Container that drops valuable items. Model varies by field. (Valley variant)',
  states: [
    { name: 'intact', label: 'Intact', description: 'Rare box can be destroyed' },
    { name: 'destroyed', label: 'Destroyed', description: 'Rare box has been destroyed' },
  ],
  defaultState: 'intact',
};

export default function RareBox({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'intact',
}: RareBoxProps) {
  // Valley variant (o0c_recont)
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_recont.glb'));
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
              mat.map.offset.set(0, 1);
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

useGLTF.preload(assetUrl('/assets/objects/valley/o0c_recont.glb'));
