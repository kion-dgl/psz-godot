import { useMemo, useEffect, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { ElementProps, StoryMeta } from './types';
import type { CatalogEntry } from './objectCatalog';
import { assetUrl } from '../utils/assets';
import { applyObjectTextures, detachSkinnedBind, textureFilename } from './materials';

interface TextureTransition {
  texture: THREE.Texture;
  fromX: number;
  toX: number;
  fromY: number;
  toY: number;
  elapsed: number;
  duration: number;
}

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
  animate = true,
}: ElementProps & { entry: CatalogEntry; state?: string; animate?: boolean }) {
  const url = assetUrl(entry.glb);
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(), [scene]);
  const scrollingRef = useRef<ScrollingTexture[]>([]);
  const spinTimeRef = useRef(0);
  const transitionRef = useRef<TextureTransition[]>([]);
  const firstApply = useRef(true);
  const groupRef = useRef<THREE.Group>(null);

  useEffect(() => {
    detachSkinnedBind(cloned);
    const [repeatX, repeatY] = entry.repeat ?? [1, 1];

    // Snapshot offsets before the state's overrides land, so a transition can
    // replay the move instead of the sheet jumping between frames.
    const before = new Map<THREE.Texture, { x: number; y: number }>();
    if (entry.stateTransitionMs) {
      cloned.traverse((child) => {
        if (!(child instanceof THREE.Mesh)) return;
        const mats = Array.isArray(child.material) ? child.material : [child.material];
        mats.forEach((mat) => {
          const map = (mat as THREE.MeshStandardMaterial).map;
          if (map) before.set(map, { x: map.offset.x, y: map.offset.y });
        });
      });
    }

    // Per-entry UV scale is the baseline; entry.textures can still override a
    // single texture on top of it, and the current state's overrides win last.
    const stateOverrides = (state && entry.stateTextures?.[state]) || {};
    applyObjectTextures(cloned, { ...entry.textures, ...stateOverrides }, { repeatX, repeatY });

    // Rewind anything that moved and hand it to the frame loop to ease in.
    if (entry.stateTransitionMs && !firstApply.current) {
      const moves: TextureTransition[] = [];
      before.forEach((from, tex) => {
        if (from.x === tex.offset.x && from.y === tex.offset.y) return;
        moves.push({
          texture: tex,
          fromX: from.x,
          toX: tex.offset.x,
          fromY: from.y,
          toY: tex.offset.y,
          elapsed: 0,
          duration: entry.stateTransitionMs! / 1000,
        });
        tex.offset.set(from.x, from.y);
      });
      transitionRef.current = moves;
    }
    firstApply.current = false;

    // State-driven visibility: hide the materials this state doesn't draw, and
    // pick which sibling primitive is shown for models that ship variants.
    const hidden = new Set((state && entry.stateHiddenTextures?.[state]) || []);
    const visibleMeshes = state ? entry.stateMeshes?.[state] : undefined;
    let meshIndex = 0;
    cloned.traverse((child) => {
      if (!(child instanceof THREE.Mesh)) return;
      const idx = meshIndex++;
      if (visibleMeshes) child.visible = visibleMeshes.includes(idx);
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((mat) => {
        const map = (mat as THREE.MeshStandardMaterial).map;
        if (map) mat.visible = !hidden.has(textureFilename(map));
      });
    });

    // Rig-driven state: pose named joints. Degrees in the data because the
    // authored angles are read off a model viewer, not computed.
    const bones = (state && entry.stateBones?.[state]) || null;
    if (bones) {
      cloned.traverse((child) => {
        const pose = bones[child.name];
        if (!pose) return;
        child.rotation.set(
          THREE.MathUtils.degToRad(pose[0]),
          THREE.MathUtils.degToRad(pose[1]),
          THREE.MathUtils.degToRad(pose[2]),
        );
      });
    }

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
  }, [cloned, entry, state]);

  useFrame((_, delta) => {
    // State transitions play regardless of `animate`: the host disables the
    // continuous scroll so its panel owns the offset, but a used/unused change
    // should still be visible as a move rather than a jump.
    if (transitionRef.current.length) {
      transitionRef.current = transitionRef.current.filter((tr) => {
        tr.elapsed += delta;
        const k = Math.min(1, tr.elapsed / tr.duration);
        // Smoothstep so the pad eases out rather than stopping dead.
        const e = k * k * (3 - 2 * k);
        tr.texture.offset.set(
          THREE.MathUtils.lerp(tr.fromX, tr.toX, e),
          THREE.MathUtils.lerp(tr.fromY, tr.toY, e),
        );
        return k < 1;
      });
    }

    // The storybook drives texture.offset itself (TextureAnimator) so the
    // scroll controls in its panel are authoritative. Both writing the same
    // offset every frame means panel edits are immediately overwritten by the
    // authored value and the sliders appear to do nothing — so the host opts
    // out of the built-in animation while it is tuning.
    if (!animate) return;

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
