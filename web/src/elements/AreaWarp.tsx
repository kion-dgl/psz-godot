import { useMemo, useEffect, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type AreaWarpState = 'active' | 'inactive';

interface AreaWarpProps extends ElementProps {
  state?: AreaWarpState;
}

// Story metadata for the storybook
export const areaWarpMeta: StoryMeta = {
  title: 'Area Warp',
  description: 'Warp gate to the next area. Players pass through this to advance to the next section.',
  states: [
    { name: 'active', label: 'Active', description: 'Warp gate is active and usable' },
    { name: 'inactive', label: 'Inactive', description: 'Warp gate is inactive' },
  ],
  defaultState: 'active',
};

// Animated warp surface texture
const WARP_TEXTURE_NAME = 'o0s_1_fwarp2';
const WARP_SCROLL_SPEED = 1.35;

export default function AreaWarp({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'active',
}: AreaWarpProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/special/o0s_warpm.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const warpTexturesRef = useRef<THREE.Texture[]>([]);

  // Apply texture settings and state-based effects
  useEffect(() => {
    const warpTextures: THREE.Texture[] = [];
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            if (mat.map) {
              mat.map.wrapS = THREE.MirroredRepeatWrapping;
              mat.map.wrapT = THREE.MirroredRepeatWrapping;

              if (mat.map.name?.includes(WARP_TEXTURE_NAME)) {
                // Animated warp surface — offsetY depends on state
                mat.map.offset.set(0, state === 'active' ? 1.34 : 0);
                mat.map.needsUpdate = true;
                warpTextures.push(mat.map);
              } else {
                mat.map.needsUpdate = true;
              }
            }
            // Dim the material when inactive
            if (state === 'inactive') {
              mat.opacity = 0.5;
              mat.transparent = true;
            } else {
              mat.opacity = 1;
              mat.transparent = false;
            }
            mat.needsUpdate = true;
          }
        });
      }
    });
    warpTexturesRef.current = warpTextures;
  }, [clonedScene, state]);

  // Animate warp texture scroll on offset.x
  useFrame((_, delta) => {
    warpTexturesRef.current.forEach((tex) => {
      tex.offset.x -= WARP_SCROLL_SPEED * delta;
      if (tex.offset.x < -10) tex.offset.x += 10;
    });
  });

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(assetUrl('/assets/objects/special/o0s_warpm.glb'));
