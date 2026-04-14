import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type NeedleTrapState = 'off' | 'on';

interface NeedleTrapProps extends ElementProps {
  state?: NeedleTrapState;
}

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_needle.glb');

export const needleTrapMeta: StoryMeta = {
  title: 'Needle Trap',
  description: 'Floor spike trap. Base is always visible. Spikes extend when active, dealing damage on contact.',
  states: [
    { name: 'off', label: 'Off', description: 'Spikes retracted, safe to walk over' },
    { name: 'on', label: 'On', description: 'Spikes extended, deals damage' },
  ],
  defaultState: 'off',
};

export default function NeedleTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
}: NeedleTrapProps) {
  const { scene } = useGLTF(GLB_PATH);
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh && child.geometry) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat, idx) => {
          if (idx === 1) {
            mat.visible = state === 'on';
            mat.opacity = state === 'on' ? 1.0 : 0.0;
            mat.transparent = state !== 'on';
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

useGLTF.preload(GLB_PATH);
