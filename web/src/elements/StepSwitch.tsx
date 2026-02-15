import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type StepSwitchState = 'off' | 'on';

interface StepSwitchProps extends ElementProps {
  state?: StepSwitchState;
  onStep?: () => void;
}

// Story metadata for the storybook
export const stepSwitchMeta: StoryMeta = {
  title: 'Step Switch',
  description: 'Floor pressure plate. Activates when player steps on it. Used for traps, lights, or debug triggers.',
  states: [
    { name: 'off', label: 'Off', description: 'Not stepped on' },
    { name: 'on', label: 'On', description: 'Currently pressed' },
  ],
  defaultState: 'off',
};

export default function StepSwitch({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
  onStep,
}: StepSwitchProps) {
  // switchf = floor pressure plate (player steps on)
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_switchf.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  // Apply visual state
  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            // Apply texture offset based on state
            if (mat.map) {
              mat.map.offset.x = state === 'off' ? 0.50 : 0;
              mat.map.needsUpdate = true;
            }

            if (mat instanceof THREE.MeshStandardMaterial) {
              if (state === 'on') {
                mat.emissive = new THREE.Color(0x44aaff);
                mat.emissiveIntensity = 0.5;
              } else {
                mat.emissive = new THREE.Color(0x000000);
                mat.emissiveIntensity = 0;
              }
            }
            mat.needsUpdate = true;
          }
        });

        // Pressed down visual
        if (state === 'on') {
          child.position.y = -0.02;
        } else {
          child.position.y = 0;
        }
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
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_switchf.glb'));
