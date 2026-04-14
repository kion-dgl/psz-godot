import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type BearTrapState = 'open' | 'closed';

interface BearTrapProps extends ElementProps {
  state?: BearTrapState;
}

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_torabasami.glb');
const TEX_OPEN = assetUrl('/assets/objects/valley/o0c_1_tora1.png');
const TEX_CLOSED = assetUrl('/assets/objects/valley/o0c_1_tora2.png');

export const bearTrapMeta: StoryMeta = {
  title: 'Bear Trap',
  description: 'Floor bear trap. Snaps shut when stepped on. One-shot trigger that deals damage.',
  states: [
    { name: 'open', label: 'Open', description: 'Armed, waiting for contact' },
    { name: 'closed', label: 'Closed', description: 'Triggered, snapped shut' },
  ],
  defaultState: 'open',
};

export default function BearTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'open',
}: BearTrapProps) {
  const { scene } = useGLTF(GLB_PATH);
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  const texOpen = useMemo(() => {
    const tex = new THREE.TextureLoader().load(TEX_OPEN);
    tex.flipY = false;
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);

  const texClosed = useMemo(() => {
    const tex = new THREE.TextureLoader().load(TEX_CLOSED);
    tex.flipY = false;
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);

  useEffect(() => {
    const activeTex = state === 'closed' ? texClosed : texOpen;
    clonedScene.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((mat) => {
          if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
            mat.map = activeTex;
            mat.needsUpdate = true;
          }
        });
      }
    });
  }, [clonedScene, state, texOpen, texClosed]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(GLB_PATH);
