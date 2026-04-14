import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type BearTrapState = 'open' | 'closed';

interface BearTrapProps extends ElementProps {
  state?: BearTrapState;
}

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_torabasami.glb');

export const bearTrapMeta: StoryMeta = {
  title: 'Bear Trap',
  description: 'Floor bear trap. Container is always visible. Lasers active when open (armed). Snaps shut on contact.',
  states: [
    { name: 'open', label: 'Open', description: 'Armed — lasers active, waiting for contact' },
    { name: 'closed', label: 'Closed', description: 'Triggered — lasers off, trap shut' },
  ],
  defaultState: 'open',
};

export default function BearTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'open',
}: BearTrapProps) {
  const { scene } = useGLTF(GLB_PATH);
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh && child.geometry) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat, idx) => {
          if (idx === 1) {
            mat.visible = state === 'open';
            mat.opacity = state === 'open' ? 1.0 : 0.0;
            mat.transparent = state !== 'open';
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
