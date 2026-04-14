import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import { assetUrl } from '../utils/assets';

export type NeedleTrapState = 'off' | 'on';

interface NeedleTrapProps extends ElementProps {
  state?: NeedleTrapState;
}

const GLB_PATH = assetUrl('/assets/objects/valley/o0c_needle.glb');
const TEX_OFF = assetUrl('/assets/objects/valley/o0c_1_needle.png');
const TEX_ON = assetUrl('/assets/objects/valley/o0c_1_needle2.png');

export const needleTrapMeta: StoryMeta = {
  title: 'Needle Trap',
  description: 'Floor spike trap. Damages players and enemies on contact when active. Texture swaps between gray (off) and orange (on).',
  states: [
    { name: 'off', label: 'Off', description: 'Retracted, safe to walk over' },
    { name: 'on', label: 'On', description: 'Extended, deals damage on contact' },
  ],
  defaultState: 'off',
};

export default function NeedleTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
}: NeedleTrapProps) {
  const { scene } = useGLTF(GLB_PATH);
  const clonedScene = useMemo(() => scene.clone(), [scene]);

  const texOff = useMemo(() => {
    const tex = new THREE.TextureLoader().load(TEX_OFF);
    tex.flipY = false;
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);

  const texOn = useMemo(() => {
    const tex = new THREE.TextureLoader().load(TEX_ON);
    tex.flipY = false;
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }, []);

  useEffect(() => {
    const activeTex = state === 'on' ? texOn : texOff;
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
  }, [clonedScene, state, texOff, texOn]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={clonedScene} />
    </group>
  );
}

useGLTF.preload(GLB_PATH);
