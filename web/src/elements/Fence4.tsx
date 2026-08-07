import { useMemo, useEffect, useRef } from 'react';
import { useGLTF, Box } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';
import { applyFenceTextureConfig, type FenceTextureSetup } from './Fence';

export type Fence4State = 'active' | 'disabled';

interface Fence4Props extends ElementProps {
  state?: Fence4State;
}

// Story metadata for the storybook
export const fence4Meta: StoryMeta = {
  title: 'Fence (4-sided)',
  description: 'Four-sided fence that blocks access from all directions. Disabled by interact switches.',
  states: [
    { name: 'active', label: 'Active', description: 'Fence is blocking access (laser visible)' },
    { name: 'disabled', label: 'Disabled', description: 'Fence has been deactivated (laser hidden, poles remain)' },
  ],
  defaultState: 'active',
};

// The laser texture - meshes with this texture are hidden when disabled
const LASER_TEXTURE_NAME = 'o0c_1_fence2';
const LASER_SCROLL_SPEED = 0.25;

/**
 * Same texture pair as the straight fence, different UV placement: the laser
 * sits at offsetX +2.57 here rather than -4.09. repeatY 2 is what splits the
 * single laser quad into the two beams the original draws.
 */
const FENCE4_TEXTURE_CONFIG: Record<string, FenceTextureSetup> = {
  'o0c_1_fence2': {
    offsetX: 2.57,
    offsetY: 1.11,
    repeatX: 1.0,
    repeatY: 2.0,
    wrapS: THREE.RepeatWrapping,
    wrapT: THREE.MirroredRepeatWrapping,
  },
  'o0c_0_fence1': {
    offsetX: 0.5,
    offsetY: 0.0,
    repeatX: 1.0,
    repeatY: 1.0,
    wrapS: THREE.RepeatWrapping,
    wrapT: THREE.RepeatWrapping,
  },
};

export default function Fence4({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'active',
}: Fence4Props) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_fence4.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const laserTexturesRef = useRef<THREE.Texture[]>([]);

  // Hide laser mesh when disabled, keep poles visible, collect laser textures
  useEffect(() => {
    applyFenceTextureConfig(clonedScene, FENCE4_TEXTURE_CONFIG);
    const laserTextures: THREE.Texture[] = [];
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];

        // Check if this mesh has the laser texture
        const hasLaserTexture = materials.some((mat) => {
          if ((mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) && mat.map) {
            return mat.map.name?.includes(LASER_TEXTURE_NAME);
          }
          return false;
        });

        // Hide laser meshes when disabled, collect textures for scroll
        if (hasLaserTexture) {
          child.visible = state === 'active';
          materials.forEach((mat) => {
            if ((mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) && mat.map) {
              if (mat.map.name?.includes(LASER_TEXTURE_NAME)) {
                laserTextures.push(mat.map);
              }
            }
          });
        }
      }
    });
    laserTexturesRef.current = laserTextures;
  }, [clonedScene, state]);

  // Animate laser texture scroll on offset.x
  useFrame((_, delta) => {
    laserTexturesRef.current.forEach((tex) => {
      tex.offset.x += LASER_SCROLL_SPEED * delta;
      if (tex.offset.x > 10) tex.offset.x -= 10;
      if (tex.offset.x < -10) tex.offset.x += 10;
    });
  });

  // Calculate bounding box for collision indicator
  const bounds = useMemo(() => {
    const box = new THREE.Box3().setFromObject(clonedScene);
    const size = new THREE.Vector3();
    const center = new THREE.Vector3();
    box.getSize(size);
    box.getCenter(center);
    return { size, center };
  }, [clonedScene]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
      {state === 'active' && (
        <Box
          args={[bounds.size.x, bounds.size.y, bounds.size.z]}
          position={[bounds.center.x, bounds.center.y, bounds.center.z]}
        >
          <meshBasicMaterial color="yellow" wireframe />
        </Box>
      )}
    </group>
  );
}

// Preload the model
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_fence4.glb'));
