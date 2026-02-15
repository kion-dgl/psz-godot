import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type SwitchState = 'off' | 'on';

interface InteractSwitchProps extends ElementProps {
  state?: SwitchState;
  onActivate?: () => void;
}

// Story metadata for the storybook
export const interactSwitchMeta: StoryMeta = {
  title: 'Interact Switch',
  description: 'Player-activated switch that disables fences. Requires interaction to toggle.',
  states: [
    { name: 'off', label: 'Off', description: 'Switch has not been activated' },
    { name: 'on', label: 'On', description: 'Switch has been activated' },
  ],
  defaultState: 'off',
};

export default function InteractSwitch({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
  onActivate,
}: InteractSwitchProps) {
  // switchs = standing switch (player interacts)
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_switchs.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  // Apply visual state and texture settings
  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            // Apply texture settings
            if (mat.map) {
              mat.map.wrapS = THREE.MirroredRepeatWrapping;
              mat.map.repeat.x = 2.0;
              mat.map.offset.y = state === 'off' ? 0.5 : 0;
              mat.map.needsUpdate = true;
            }

            if (mat instanceof THREE.MeshStandardMaterial) {
              if (state === 'on') {
                mat.emissive = new THREE.Color(0x00ff00);
                mat.emissiveIntensity = 0.3;
              } else {
                mat.emissive = new THREE.Color(0x000000);
                mat.emissiveIntensity = 0;
              }
            }
            mat.needsUpdate = true;
          }
        });
      }
    });
  }, [clonedScene, state]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

// Preload the model
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_switchs.glb'));
