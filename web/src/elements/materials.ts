import * as THREE from 'three';

/**
 * Shared texture setup for PSZ object GLBs.
 *
 * The DS source data stores per-material wrap flags, but the .imd → glTF
 * converter writes a glTF `sampler` per material and defaults most of them to
 * REPEAT (74 of the 122 samplers across the object set). That default is wrong
 * for this art: PSZ authored nearly every object texture to mirror on both
 * axes, and rendering them with plain REPEAT shows a seam wherever a UV runs
 * past 1.0 — most visibly on wall/fence/gate strips.
 *
 * So mirrored-repeat is the default here and per-texture exceptions are opt-in,
 * which matches what the hand-written elements (Box, Wall, StartWarp, …) each
 * do inline today.
 */
export type WrapMode = 'mirror' | 'repeat' | 'clamp';

export interface TextureOverride {
  wrapS?: WrapMode;
  wrapT?: WrapMode;
  repeatX?: number;
  repeatY?: number;
  offsetX?: number;
  offsetY?: number;
}

/** Per-texture overrides, keyed by the texture's source filename (no path). */
export type TextureOverrides = Record<string, TextureOverride>;

export function threeWrap(mode: WrapMode): THREE.Wrapping {
  if (mode === 'repeat') return THREE.RepeatWrapping;
  if (mode === 'clamp') return THREE.ClampToEdgeWrapping;
  return THREE.MirroredRepeatWrapping;
}

/** Best-effort source filename for a texture, matching StorybookViewer's inspector. */
export function textureFilename(texture: THREE.Texture): string {
  const named = texture.name || (texture.image as { src?: string } | null)?.src || '';
  if (!named) return 'unknown';
  return named.split('/').pop() as string;
}

type MappedMaterial = THREE.MeshStandardMaterial | THREE.MeshBasicMaterial;

function isMappedMaterial(mat: THREE.Material): mat is MappedMaterial {
  return mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial;
}

/**
 * Walk a loaded scene and normalise every diffuse map to mirrored-repeat,
 * applying any per-filename overrides on top. Returns the textures it touched
 * so callers can animate them (warp scroll, etc.) without re-traversing.
 */
export function applyObjectTextures(
  root: THREE.Object3D,
  overrides: TextureOverrides = {},
  defaults: TextureOverride = {},
): THREE.Texture[] {
  const touched: THREE.Texture[] = [];

  root.traverse((child) => {
    if (!(child instanceof THREE.Mesh)) return;
    const materials = Array.isArray(child.material) ? child.material : [child.material];

    materials.forEach((mat) => {
      if (!isMappedMaterial(mat)) return;
      const map = mat.map;
      if (map) {
        const cfg = { ...defaults, ...(overrides[textureFilename(map)] ?? {}) };
        map.wrapS = threeWrap(cfg.wrapS ?? 'mirror');
        map.wrapT = threeWrap(cfg.wrapT ?? 'mirror');
        map.repeat.set(cfg.repeatX ?? 1, cfg.repeatY ?? 1);
        map.offset.set(cfg.offsetX ?? 0, cfg.offsetY ?? 0);
        map.needsUpdate = true;
        touched.push(map);
      }
      mat.needsUpdate = true;
    });
  });

  return touched;
}

/**
 * Make a parent-group `scale` actually affect the model.
 *
 * Every PSZ object GLB is exported as a SkinnedMesh (all 117 of them carry a
 * `skins` array, even one-bone static props like the sky backdrop). three's
 * default `AttachedBindMode` recomputes `bindMatrixInverse` from the mesh's
 * world matrix every frame, so any scale on an ancestor gets inverted out of
 * the skinning result and then re-applied by the model-view matrix — the two
 * cancel and the model renders at its authored size no matter what scale you
 * set. Switching to detached bind mode freezes `bindMatrixInverse` at its bind
 * value so the ancestor transform survives.
 *
 * Safe for this art because the bind pose is identity on these props; it is
 * not a general-purpose fix for animated skinned characters.
 */
export function detachSkinnedBind(root: THREE.Object3D): void {
  root.traverse((child) => {
    if ((child as THREE.SkinnedMesh).isSkinnedMesh) {
      (child as THREE.SkinnedMesh).bindMode = THREE.DetachedBindMode;
    }
  });
}

/** Collect the diffuse maps whose filename contains a substring, for scroll animation. */
export function findTextures(root: THREE.Object3D, filenameSubstring: string): THREE.Texture[] {
  const found: THREE.Texture[] = [];
  root.traverse((child) => {
    if (!(child instanceof THREE.Mesh)) return;
    const materials = Array.isArray(child.material) ? child.material : [child.material];
    materials.forEach((mat) => {
      if (!isMappedMaterial(mat) || !mat.map) return;
      if (textureFilename(mat.map).includes(filenameSubstring)) found.push(mat.map);
    });
  });
  return found;
}
