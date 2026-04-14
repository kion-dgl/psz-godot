import { useMemo } from 'react';
import { useGLTF } from '@react-three/drei';
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

export default function NeedleTrap({
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
