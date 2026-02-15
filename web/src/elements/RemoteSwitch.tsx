import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type RemoteSwitchState = 'off' | 'on';

interface RemoteSwitchProps extends ElementProps {
  state?: RemoteSwitchState;
  onActivate?: () => void;
}

// Story metadata for the storybook
export const remoteSwitchMeta: StoryMeta = {
  title: 'Remote Switch',
  description: 'Interactive switch used to disarm traps or trigger remote mechanisms.',
  states: [
    { name: 'off', label: 'Off', description: 'Switch has not been activated' },
    { name: 'on', label: 'On', description: 'Switch has been activated' },
  ],
  defaultState: 'off',
};

// Texture that changes based on state
const STATE_TEXTURE_NAME = 'o0c_1_rmsw2';

export default function RemoteSwitch({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
  onActivate,
}: RemoteSwitchProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_remswitch.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  // Apply visual state based on texture offset
  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            if (mat.map && mat.map.name?.includes(STATE_TEXTURE_NAME)) {
              mat.map.offset.y = state === 'on' ? 0.5 : 0;
              mat.map.needsUpdate = true;
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
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_remswitch.glb'));
