import { useRef, useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type MessagePackState = 'available' | 'read';

interface MessagePackProps extends ElementProps {
  state?: MessagePackState;
}

// Story metadata for the storybook
export const messagePackMeta: StoryMeta = {
  title: 'Message Pack',
  description: 'Interactable message object. Press E to read a text message.',
  states: [
    { name: 'available', label: 'Available', description: 'Message can be read' },
    { name: 'read', label: 'Read', description: 'Message has been read' },
  ],
  defaultState: 'available',
};

export default function MessagePack({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'available',
}: MessagePackProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_mspack.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);
  const scrollTextureRef = useRef<THREE.Texture | null>(null);

  // Apply texture config + visual state
  useEffect(() => {
    scrollTextureRef.current = null;
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (!(mat instanceof THREE.MeshStandardMaterial) && !(mat instanceof THREE.MeshBasicMaterial)) return;

          if (mat.map) {
            const filename = mat.map.name?.split('/').pop() || '';

            if (filename.includes('o0c_0_mspack')) {
              mat.map.wrapS = THREE.MirroredRepeatWrapping;
              mat.map.wrapT = THREE.MirroredRepeatWrapping;
              mat.map.needsUpdate = true;
            } else if (filename.includes('o0c_1_mspack')) {
              mat.map.offset.set(0, 2.27);
              mat.map.needsUpdate = true;
              scrollTextureRef.current = mat.map;
            }
          }

          if (state === 'read') {
            mat.transparent = true;
            mat.opacity = 0.6;
          } else {
            mat.transparent = false;
            mat.opacity = 1;
          }
          mat.needsUpdate = true;
        });
      }
    });
  }, [clonedScene, state]);

  // Texture scroll animation
  useFrame((_, delta) => {
    if (scrollTextureRef.current) {
      scrollTextureRef.current.offset.y += 0.45 * delta;
    }
  });

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

// Preload the model
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_mspack.glb'));
