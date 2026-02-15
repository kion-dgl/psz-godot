import { useRef, useMemo } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type DropshipCrashState = 'crashed';

interface DropshipCrashProps extends ElementProps {
  state?: DropshipCrashState;
}

export const dropshipCrashMeta: StoryMeta = {
  title: 'Dropship Crash',
  description: 'Crashed dropship prop for Quest 1. Found at the Sarisa incident site.',
  states: [
    { name: 'crashed', label: 'Crashed', description: 'Wrecked on the ground' },
  ],
  defaultState: 'crashed',
};

const MODEL_PATH = assetUrl('/assets/objects/story/dropship_crash.glb');

export default function DropshipCrash({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
}: DropshipCrashProps) {
  const { scene } = useGLTF(MODEL_PATH);
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);

  return (
    <group
      ref={groupRef}
      position={position}
      rotation={rotation}
      scale={scale}
    >
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(MODEL_PATH);
