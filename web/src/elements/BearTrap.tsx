import { useMemo } from 'react';
import { useGLTF } from '@react-three/drei';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type BearTrapState = 'open' | 'closed';

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_torabasami.glb');

export const bearTrapMeta: StoryMeta = {
  title: 'Bear Trap',
  description: 'Floor bear trap. Container always visible. Lasers active when armed.',
  states: [
    { name: 'open', label: 'Open', description: 'Armed, lasers active' },
    { name: 'closed', label: 'Closed', description: 'Triggered, shut' },
  ],
  defaultState: 'open',
};

export default function BearTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
}: ElementProps) {
  const { scene } = useGLTF(GLB_PATH);
  const cloned = useMemo(() => scene.clone(), [scene]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={cloned} />
    </group>
  );
}

useGLTF.preload(GLB_PATH);
