import { useMemo, useEffect, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import type { CatalogEntry } from './objectCatalog';
import { assetUrl } from '../utils/assets';
import { applyObjectTextures, detachSkinnedBind, textureFilename } from './materials';

interface ScrollingTexture {
  texture: THREE.Texture;
  x: number;
  y: number;
}

/**
 * Renders one catalog entry: load the GLB, force the PSZ mirrored-repeat
 * texture convention, optionally scroll named textures and spin the model.
 *
 * Everything that varies between catalog objects is data on the entry, so
 * there is one component here rather than 45 near-identical files.
 */
export function CatalogObject({
  entry,
  position = [0, 0, 0],
  rotation = [0, 0, 0],
  scale,
  state,
}: ElementProps & { entry: CatalogEntry; state?: string }) {
  const url = assetUrl(entry.glb);
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(), [scene]);
  const scrollingRef = useRef<ScrollingTexture[]>([]);
  const spinTimeRef = useRef(0);
  const groupRef = useRef<THREE.Group>(null);

  useEffect(() => {
    detachSkinnedBind(cloned);
    const [repeatX, repeatY] = entry.repeat ?? [1, 1];
    // Per-entry UV scale is the baseline; entry.textures can still override a
    // single texture on top of it.
    applyObjectTextures(cloned, entry.textures, { repeatX, repeatY });

    const scrollCfg = entry.scroll;
    if (!scrollCfg) {
      scrollingRef.current = [];
      return;
    }

    const scrolling: ScrollingTexture[] = [];
    cloned.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((mat) => {
        const map = (mat as THREE.MeshStandardMaterial).map;
        if (!map) return;
        const cfg = scrollCfg[textureFilename(map)];
        if (cfg) scrolling.push({ texture: map, x: cfg.x ?? 0, y: cfg.y ?? 0 });
      });
    });
    scrollingRef.current = scrolling;
  }, [cloned, entry.textures, entry.scroll]);

  useFrame((_, delta) => {
    scrollingRef.current.forEach(({ texture, x, y }) => {
      texture.offset.x += x * delta;
      texture.offset.y += y * delta;
      // Keep the offsets bounded so long sessions don't lose float precision.
      if (texture.offset.x > 10 || texture.offset.x < -10) texture.offset.x %= 10;
      if (texture.offset.y > 10 || texture.offset.y < -10) texture.offset.y %= 10;
    });

    if (entry.spin && groupRef.current) {
      spinTimeRef.current += delta;
      groupRef.current.rotation.y += delta * 2;
      groupRef.current.position.y = Math.sin(spinTimeRef.current * 3) * 0.1;
    }
  });

  // Destructible entries despawn their model in the `destroyed` state, matching
  // the hand-written Box / Wall components.
  if (state === 'destroyed') return null;

  return (
    <group ref={groupRef} position={position} rotation={rotation} scale={scale ?? entry.scale ?? 1}>
      <primitive object={cloned} />
    </group>
  );
}

/** Build the StoryMeta the storybook sidebar and state bar read. */
export function catalogMeta(entry: CatalogEntry): StoryMeta {
  const states = entry.states ?? [{ name: 'default', label: 'Default' }];
  return {
    title: entry.title,
    description: `${entry.description} — model \`${entry.model}\` (set ${entry.sourceSet}).`,
    states,
    defaultState: states[0].name,
  };
}

/** Wrap a catalog entry into the `{ state?: string }` component shape CATEGORIES expects. */
export function catalogComponent(entry: CatalogEntry): React.ComponentType<{ state?: string }> {
  const Component = ({ state }: { state?: string }) => <CatalogObject entry={entry} state={state} />;
  Component.displayName = `Catalog(${entry.id})`;
  return Component;
}

// Deliberately no preload pass here. The hand-written elements each preload
// their single GLB at module scope, which is fine for ~25 models; eagerly
// fetching all 45 catalog models on storybook open would be several MB of
// requests for art the user may never click. Suspense loads them on select.
