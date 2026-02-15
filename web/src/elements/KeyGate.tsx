import { useMemo, useEffect, useRef } from 'react';
import { useGLTF, Box } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type KeyGateState = 'closed' | 'open';

interface KeyGateProps extends ElementProps {
  state?: KeyGateState;
}

// Story metadata for the storybook
export const keyGateMeta: StoryMeta = {
  title: 'Key Gate',
  description: 'Blocks passage between stages. Requires a key to unlock.',
  states: [
    { name: 'closed', label: 'Closed', description: 'Gate is locked (laser visible)' },
    { name: 'open', label: 'Open', description: 'Gate is unlocked (laser hidden)' },
  ],
  defaultState: 'closed',
};

// The laser/beam mesh that gets hidden when open
const LASER_MESH_NAME = 'o0c_gatet_3';

// Laser scroll speed (units/sec on offset.x)
const LASER_SCROLL_SPEED = 0.40;


export default function KeyGate({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'closed',
}: KeyGateProps) {
  const { scene } = useGLTF(assetUrl('/assets/objects/valley/o0c_gatet.glb'));
  const clonedScene = useMemo(() => scene.clone(), [scene]);
  const laserTexturesRef = useRef<THREE.Texture[]>([]);

  // Toggle laser visibility, make frame gray, keep terminal texture
  useEffect(() => {
    const laserTextures: THREE.Texture[] = [];

    clonedScene.traverse((child) => {
      if (child.name === LASER_MESH_NAME) {
        child.visible = state === 'closed';
      }

      if (child instanceof THREE.Mesh) {
        const isLaser = child.name === LASER_MESH_NAME;
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (!(mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial)) return;
          if (!mat.map) return;

          if (!isLaser) {
            // Non-laser meshes → solid gray
            mat.map = null;
            (mat as THREE.MeshStandardMaterial).color = new THREE.Color(0.5, 0.5, 0.5);
            mat.needsUpdate = true;
          }

          if (isLaser && mat.map) {
            laserTextures.push(mat.map);
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
useGLTF.preload(assetUrl('/assets/objects/valley/o0c_gatet.glb'));
