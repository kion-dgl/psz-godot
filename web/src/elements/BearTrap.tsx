import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type BearTrapState = 'off' | 'on';

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_torabasami.glb');

export const bearTrapMeta: StoryMeta = {
  title: 'Bear Trap',
  description: 'Floor bear trap. Container always visible. Prongs active when armed.',
  states: [
    { name: 'off', label: 'Off', description: 'Triggered, prongs hidden' },
    { name: 'on', label: 'On', description: 'Armed, prongs visible' },
  ],
  defaultState: 'off',
};

function isTora1(mat: THREE.Material): boolean {
  const m = mat as any;
  if (!m.map) return false;
  const src: string = m.map.image?.src || m.map.name || '';
  return src.includes('tora1');
}

export default function BearTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
}: ElementProps & { state?: BearTrapState }) {
  const { scene } = useGLTF(GLB_PATH);
  const cloned = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    cloned.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((mat) => {
        if (isTora1(mat)) {
          mat.visible = state === 'on';
        }
      });
    });
  }, [cloned, state]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={cloned} />
    </group>
  );
}

useGLTF.preload(GLB_PATH);
