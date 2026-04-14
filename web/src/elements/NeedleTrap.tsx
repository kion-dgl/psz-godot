import { useMemo, useEffect } from 'react';
import { useGLTF } from '@react-three/drei';
import * as THREE from 'three';
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

const TEXTURE_CONFIG: Record<string, { offsetX: number; offsetY: number; wrapS: THREE.Wrapping; wrapT: THREE.Wrapping }> = {
  'o0c_1_needle': { offsetX: 0.00, offsetY: 0.00, wrapS: THREE.MirroredRepeatWrapping, wrapT: THREE.MirroredRepeatWrapping },
  'o0c_1_needle2': { offsetX: -0.17, offsetY: -0.18, wrapS: THREE.MirroredRepeatWrapping, wrapT: THREE.MirroredRepeatWrapping },
};

function getTexId(mat: THREE.Material): string | null {
  const m = mat as any;
  if (!m.map) return null;
  const src: string = m.map.image?.src || m.map.name || '';
  if (src.includes('needle2')) return 'o0c_1_needle2';
  if (src.includes('needle')) return 'o0c_1_needle';
  return null;
}

export default function NeedleTrap({
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale = 1,
  state = 'off',
}: ElementProps & { state?: NeedleTrapState }) {
  const { scene } = useGLTF(GLB_PATH);
  const cloned = useMemo(() => scene.clone(), [scene]);

  useEffect(() => {
    cloned.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((mat) => {
        const texId = getTexId(mat);
        if (!texId) return;
        const cfg = TEXTURE_CONFIG[texId];
        if (cfg && mat.map) {
          mat.map.offset.set(cfg.offsetX, cfg.offsetY);
          mat.map.wrapS = cfg.wrapS;
          mat.map.wrapT = cfg.wrapT;
          mat.map.needsUpdate = true;
        }
        if (texId === 'o0c_1_needle2') {
          mat.visible = state === 'on';
        }
      });
    });
  }, [cloned, state]);

  return (
    <group position={position} rotation={rotation} scale={scale}>
      <primitive object={cloned} />
    </group>
  );
}

useGLTF.preload(GLB_PATH);
