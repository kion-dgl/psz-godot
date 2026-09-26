/**
 * Lighting rig — the Godot↔three bridge for authored city lights.
 *
 * The mapping is deliberately 1:1 so numbers tuned here transfer:
 *
 *   OmniLight3D.light_energy   → PointLight.intensity   (both plain
 *                                multipliers — no physical units)
 *   omni_range                 → PointLight.distance    (hard cutoff)
 *   omni_attenuation           → PointLight.decay       (2 = inverse
 *                                square in both; 1 = the flattened falloff
 *                                the placed-light convention uses)
 *   ambient COLOR source       → AmbientLight           (flat albedo fill)
 *
 * Absolute pool brightness may still read slightly different between the
 * engines' falloff curves; placement, color and relative falloff carry,
 * and the final read happens in the Godot scene boot.
 *
 * The unlit base mirrors what the DS exports are: KHR_materials_unlit,
 * final color = texture × COLOR_0 (MeshBasic + vertexColors). The lit
 * view uses Lambert — the closest analogue of Godot's per-vertex shaded
 * StandardMaterial3D the city materials actually run on.
 */

import * as THREE from 'three';
import type { LightSpec, StageDef, Vec3 } from './types';

/** city_area_base._add_interior_lights defaults (the warm interior preset). */
export const PRESET_INTERIOR = {
  color: [1.0, 0.95, 0.88] as Vec3,
  energy: 2.0,
  range: 15.0,
  attenuation: 1.0,
  shadows: false,
};

/** mesh_utils.place_post_lights — the lantern/post pool convention. */
export const PRESET_POOL = {
  color: [1.0, 0.7, 0.3] as Vec3,
  energy: 5.0,
  range: 11.0,
  attenuation: 1.0,
  shadows: true,
};

let lightSeq = 0;

export function newLight(preset: typeof PRESET_INTERIOR | typeof PRESET_POOL): LightSpec {
  lightSeq += 1;
  return {
    id: `L${Date.now().toString(36)}-${lightSeq}`,
    name: `Light ${lightSeq}`,
    pos: [0, 0, 0],
    color: [...preset.color] as Vec3,
    energy: preset.energy,
    range: preset.range,
    attenuation: preset.attenuation,
    shadows: preset.shadows,
  };
}

/** The live 7-omni row from city_counter_controller (the A in the A/B):
 *  warm omnis every 6 m down the hallway, floating at y=4 — roughly 14.7 m
 *  above the real floor (−10.67). Kept verbatim so the replacement has an
 *  honest before. */
export function legacyCounterLights(): LightSpec[] {
  return [-18, -12, -6, 0, 6, 12, 18].map((z, i) => ({
    id: `legacy-${i}`,
    name: `InteriorLight_${i}`,
    pos: [0, 4, z] as Vec3,
    color: [1.0, 0.95, 0.88] as Vec3,
    energy: 2.0,
    range: 15.0,
    attenuation: 1.0,
    shadows: false,
  }));
}

export interface ThreeLightProps {
  color: THREE.Color;
  intensity: number;
  distance: number;
  decay: number;
}

export function threePointLightProps(spec: LightSpec): ThreeLightProps {
  return {
    color: new THREE.Color(spec.color[0], spec.color[1], spec.color[2]),
    intensity: spec.energy,
    distance: spec.range,
    decay: spec.attenuation,
  };
}

export function vec3ToColor(v: Vec3): THREE.Color {
  return new THREE.Color(v[0], v[1], v[2]);
}

/**
 * Outlier-robust stage bounds. dairon2 ships six stray vertices shot to
 * y = −1e9 (the spike triangles the audit flags); Box3.setFromObject on
 * the whole stage would span a billion units and any auto-fit camera
 * lands sub-pixel. Nothing in the game exceeds ~600 units (the market's
 * panorama skirt is the largest at ~400), so when the whole-stage box
 * blows past FRAME_CAP only the absurd boxes are dropped — a legit
 * ground plane sitting 200× above the tile-size median still frames.
 */
export const FRAME_CAP = 2000;

export function robustStageBox(root: THREE.Object3D): THREE.Box3 {
  root.updateMatrixWorld(true);
  const entries: { box: THREE.Box3; size: number }[] = [];
  root.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (!mesh.isMesh || !mesh.visible) return;
    const box = new THREE.Box3().setFromObject(mesh);
    if (box.isEmpty()) return;
    entries.push({ box, size: box.getSize(new THREE.Vector3()).length() });
  });
  const full = new THREE.Box3();
  for (const e of entries) full.union(e.box);
  if (entries.length === 0 || full.getSize(new THREE.Vector3()).length() <= FRAME_CAP) {
    return full;
  }
  // Poisoned stage: drop only boxes on the order of the poison itself.
  const limit = Math.max(FRAME_CAP, full.getSize(new THREE.Vector3()).length() * 0.5);
  const out = new THREE.Box3();
  const kept = entries.filter((e) => e.size <= limit);
  for (const e of kept.length > 0 ? kept : entries) out.union(e.box);
  return out;
}

/**
 * Swap materials on a prepared stage node for the requested view.
 * `bake` is the reference target (COLOR_0 × texture, what the DS shipped —
 * always renders the GL's own vertex colors regardless of the def flag);
 * `lit` is the authored-lighting workbench and honors the def's
 * vertexColors flag, mirroring the game's per-stage override.
 * Source material NAME is preserved — the inspector and any name-based
 * lookups key off it.
 */
export function applyViewMaterials(
  node: THREE.Object3D,
  view: 'bake' | 'lit',
  vertexColors: boolean,
): void {
  node.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (!mesh.isMesh || !mesh.material) return;
    const src = mesh.material as THREE.MeshBasicMaterial;
    const shared = {
      map: src.map ?? null,
      name: src.name,
      vertexColors,
      alphaTest: src.alphaTest,
      transparent: src.transparent,
      side: THREE.DoubleSide,
      color: 0xffffff,
    };
    if (view === 'bake') {
      mesh.material = new THREE.MeshBasicMaterial({ ...shared, fog: false });
    } else {
      // The GLBs ship no NORMAL (unlit exports) — compute once, like
      // LightingLab and SmoothNormals.ensure do in Godot.
      if (!mesh.geometry.attributes.normal) mesh.geometry.computeVertexNormals();
      mesh.material = new THREE.MeshLambertMaterial({ ...shared });
    }
  });
}
