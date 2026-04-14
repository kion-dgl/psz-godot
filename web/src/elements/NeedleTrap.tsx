import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type NeedleTrapState = 'off' | 'on';

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_needle.glb');

export const needleTrapMeta: StoryMeta = {
  title: 'Needle Trap',
  description: 'Floor spike trap. Base is always visible. Spikes extend when active.',
  states: [
    { name: 'off', label: 'Off', description: 'Spikes retracted' },
    { name: 'on', label: 'On', description: 'Spikes extended, deals damage' },
  ],
  defaultState: 'off',
};

function isNeedleTexture(mat: THREE.Material): boolean {
  const m = mat as any;
  if (!m.map) return false;
  const src = m.map.image?.src || m.map.name || '';
  return src.includes('needle2');
}

export default function NeedleTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
}: ElementProps & { state?: NeedleTrapState }) {
  const { scene } = useGLTF(GLB_PATH);
  const cloned = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    cloned.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((mat) => {
        if (isNeedleTexture(mat)) {
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
