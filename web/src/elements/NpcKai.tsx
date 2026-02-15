import { useRef, useMemo } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type NpcKaiState = 'idle';

interface NpcKaiProps extends ElementProps {
  state?: NpcKaiState;
}

export const npcKaiMeta: StoryMeta = {
  title: 'Kai',
  description: 'Story NPC. A veteran hunter who mentors the player in Quest 1.',
  states: [
    { name: 'idle', label: 'Idle', description: 'Standing pose' },
  ],
  defaultState: 'idle',
};

const MODEL_PATH = assetUrl('/assets/npcs/kai/pc_a01_000.glb');
const TEXTURE_PATH = assetUrl('/assets/npcs/kai/pc_a01_000.png');

export default function NpcKai({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
}: NpcKaiProps) {
  const { scene } = useGLTF(MODEL_PATH);
  const groupRef = useRef<THREE.Group>(null);

  const texture = useMemo(() => {
    const loader = new THREE.TextureLoader();
    const tex = loader.load(TEXTURE_PATH);
    tex.flipY = false;
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);

  const clonedModel = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        if (mesh.material) {
          const mat = (mesh.material as THREE.MeshStandardMaterial).clone();
          mat.map = texture;
          mat.needsUpdate = true;
          mesh.material = mat;
        }
      }
    });
    return clone;
  }, [scene, texture]);

  return (
    <group
      ref={groupRef}
      position={position}
      rotation={rotation}
      scale={scale}
    >
      <primitive object={clonedModel} />
    </group>
  );
}

useGLTF.preload(MODEL_PATH);
