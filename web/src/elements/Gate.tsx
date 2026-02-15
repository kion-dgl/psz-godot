import { useMemo, useEffect, useRef } from 'react';
import { useGLTF, Box } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type GateState = 'closed' | 'open';

interface GateProps extends ElementProps {
  state?: GateState;
}

// Story metadata for the storybook
export const gateMeta: StoryMeta = {
  title: 'Gate',
  description: 'Blocks passage between stages. Opens when all enemies are defeated.',
  states: [
    { name: 'closed', label: 'Closed', description: 'Gate is blocking the path (laser visible)' },
    { name: 'open', label: 'Open', description: 'Gate is open (laser hidden)' },
  ],
  defaultState: 'closed',
};

// The laser/beam mesh that gets hidden when open
const LASER_MESH_NAME = 'o0c_gate_3';

// Laser scroll speed (units/sec on offset.x)
const LASER_SCROLL_SPEED = 0.40;

// Texture to use for all submeshes (rails + laser sheet)
const UNIFIED_TEXTURE_NAME = 'o0c_1_gate';
// Texture to replace (switch icon part — should use o0c_1_gate instead)
const REPLACED_TEXTURE_NAME = 'o0c_0_gatet';

export default function Gate({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'closed',
}: GateProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_gate.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const laserTexturesRef = useRef<THREE.Texture[]>([]);

  // Toggle laser mesh visibility, swap textures, collect laser refs
  useEffect(() => {
    const laserTextures: THREE.Texture[] = [];

    // First pass: find the o0c_1_gate texture
    let unifiedTexture: THREE.Texture | null = null;
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if ((mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) && mat.map) {
            if (mat.map.name?.includes(UNIFIED_TEXTURE_NAME)) {
              unifiedTexture = mat.map;
            }
          }
        });
      }
    });

    // Second pass: swap replaced texture, hide/show laser, collect refs
    clonedScene.traverse((child) => {
      if (child.name === LASER_MESH_NAME) {
        child.visible = state === 'closed';
      }

      if (child instanceof THREE.Mesh) {
        const isLaser = child.name === LASER_MESH_NAME;
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if ((mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) && mat.map) {
            // Make frame mesh gray to distinguish from laser
            if (mat.map.name?.includes(REPLACED_TEXTURE_NAME)) {
              mat.map = null;
              (mat as THREE.MeshStandardMaterial).color = new THREE.Color(0.5, 0.5, 0.5);
              mat.needsUpdate = true;
            }
            if (isLaser && mat.map) {
              laserTextures.push(mat.map);
            }
          }
        });
      }
    });
    laserTexturesRef.current = laserTextures;
  }, [clonedScene, state]);

  // Animate laser texture scroll on offset.x
  useFrame((_, delta) => {
    laserTexturesRef.current.forEach((tex) => {
      tex.offset.x -= LASER_SCROLL_SPEED * delta;
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
      {state === 'closed' && (
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
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_gate.glb'));
