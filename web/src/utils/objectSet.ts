// objectSet — load a psz `assets/objects/<set>/` model set into a Three.js
// group, using the set's info.json manifest to know which GLBs to pull.
//
// The Godot repo keeps object sets flat: assets/objects/<set>/ holds every
// model's <name>.glb plus its PNG textures side by side, and an info.json
// whose `models` array lists the source `.imd` dir names (base == glb name).
// See scripts/tools/import_objects.py, which produced these dirs from the
// psz-asset-viewer checkout.
//
// Consumers (city-walk-mock teleporter, boss-room _z dressing) load a set,
// then position each named piece — the loader itself imposes no layout.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { assetUrl } from './assets';

export interface ObjectSetPiece {
  /** Model base name (glb without extension), e.g. 'o0s_warpcb'. */
  name: string;
  /** The loaded model root; add/position this. */
  object: THREE.Group;
}

export interface ObjectSet {
  setId: string;
  pieces: ObjectSetPiece[];
  /** Convenience lookup by base name. */
  byName: Record<string, THREE.Group>;
}

interface SetInfo {
  id?: string;
  models?: string[];
}

/** `o0s_warpcb.imd` -> `o0s_warpcb`. */
function imdToBase(imd: string): string {
  return imd.replace(/\.imd$/i, '');
}

/**
 * Wrap a loaded model in a pivot group whose origin is the model's
 * bottom-center (bbox center on x/z, bbox min on y). The GLBs keep the node
 * transforms they had in the original stage, so a piece's geometry can sit
 * far from its scene root; placing the root somewhere then moves the anchor,
 * not the visible mesh. Positioning the returned pivot puts the mesh's base
 * exactly there.
 */
export function wrapAtBaseCenter(object: THREE.Group): THREE.Group {
  const box = new THREE.Box3().setFromObject(object);
  const center = box.getCenter(new THREE.Vector3());
  const pivot = new THREE.Group();
  pivot.name = `${object.name}__pivot`;
  object.position.sub(new THREE.Vector3(center.x, box.min.y, center.z));
  pivot.add(object);
  return pivot;
}

/**
 * Set every texture map on a loaded object tree to mirrored wrapping on both
 * axes (THREE.MirroredRepeatWrapping). PSZ's warp / effect textures are
 * authored to tile mirror-symmetrically; GLTFLoader defaults to whatever the
 * glTF sampler declares (usually REPEAT/CLAMP), which seams these UVs.
 */
export function applyMirroredWrap(root: THREE.Object3D): void {
  root.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    for (const mat of mats) {
      for (const key of ['map', 'emissiveMap', 'normalMap', 'alphaMap'] as const) {
        const tex = (mat as THREE.MeshStandardMaterial | undefined)?.[key] as THREE.Texture | null;
        if (tex) {
          tex.wrapS = THREE.MirroredRepeatWrapping;
          tex.wrapT = THREE.MirroredRepeatWrapping;
          tex.needsUpdate = true;
        }
      }
    }
  });
}

/**
 * Fetch a set's info.json and load every listed model. Pieces load in
 * parallel; the returned array preserves manifest order. A single model
 * failing to load is logged and skipped rather than rejecting the whole set.
 */
export async function loadObjectSet(setId: string): Promise<ObjectSet> {
  const dir = `assets/objects/${setId}`;
  const info: SetInfo = await fetch(assetUrl(`${dir}/info.json`)).then((r) => {
    if (!r.ok) throw new Error(`${setId}/info.json → ${r.status}`);
    return r.json();
  });
  const names = (info.models ?? []).map(imdToBase);
  const loader = new GLTFLoader();

  const pieces = await Promise.all(
    names.map(
      (name) =>
        new Promise<ObjectSetPiece | null>((resolve) => {
          loader.load(
            assetUrl(`${dir}/${name}.glb`),
            (g) => {
              g.scene.name = name;
              resolve({ name, object: g.scene });
            },
            undefined,
            (e) => {
              console.warn(`objectSet ${setId}: ${name}.glb failed`, e);
              resolve(null);
            },
          );
        }),
    ),
  );

  const kept = pieces.filter((p): p is ObjectSetPiece => p !== null);
  const byName: Record<string, THREE.Group> = {};
  for (const p of kept) byName[p.name] = p.object;
  return { setId, pieces: kept, byName };
}
