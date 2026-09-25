/**
 * City Lab — shared types and the city stage table.
 *
 * One tool view for the custom city maps (web #/city-lab): click-around
 * reference, a malformed-triangle audit for the market, and an authored
 * lighting workbench for the guild counter (#656). Values live in Godot
 * units everywhere so anything tuned here pastes straight into the game.
 */

export type CityLabMode = 'inspect' | 'triangles' | 'lighting';

export type Vec3 = [number, number, number];

export interface StageModelDef {
  /** Repo-relative GLB path, resolved through assetUrl(). */
  path: string;
  label: string;
}

export interface StageMarkerDef {
  pos: Vec3;
  label: string;
  color: string;
}

export interface StageDef {
  id: string;
  label: string;
  models: StageModelDef[];
  /** Optional hand-authored floor collider rendered as a wireframe overlay. */
  floorPath?: string;
  /** Reference anchors (NPCs, spawns) worth seeing while placing lights. */
  markers?: StageMarkerDef[];
  /**
   * Whether the COLOR_0 vertex bake participates in the material. The
   * counter controller disables it in Godot ("SA2 baked too dark" —
   * _override_vertex_colors(false)); the other city maps keep it.
   */
  vertexColors: boolean;
  /** Lighting-mode starting rig, mirrored from the scene .tscn files. */
  sceneRig: {
    ambientColor: Vec3;
    ambientEnergy: number;
    /** Weak directional fill; the city scenes carry one at ~0.3. */
    sunEnergy: number;
  };
  /**
   * Godot stage id used as the city-lights sidecar filename. Only set for
   * stages whose lighting is (or will be) data-authored.
   */
  lightStageId?: string;
  /**
   * Where the "export fixed GLB" write-back lands (dev server only).
   * Only the market has a lineage re-export today (dairon2 → dairon3).
   */
  exportPath?: string;
}

export const STAGES: StageDef[] = [
  {
    // What the game renders (city_market.tscn instances dairon3).
    id: 'market',
    label: 'Market (dairon3 — the shipped build)',
    models: [
      { path: 'assets/stages/city_e/market/dairon3.glb', label: 'dairon3' },
      { path: 'assets/stages/city_e/market/wall_extension.glb', label: 'wall_extension' },
    ],
    vertexColors: true,
    sceneRig: { ambientColor: [0.95, 0.85, 0.7], ambientEnergy: 1.6, sunEnergy: 0.3 },
  },
  {
    // The source asset — kept for before/after audit comparison
    // (spike slivers, stripe faces, the dark cent5 quad).
    id: 'market-source',
    label: 'Market (dairon2 — source, pre-fix)',
    models: [
      { path: 'assets/stages/city_e/market/dairon2.glb', label: 'dairon2' },
      { path: 'assets/stages/city_e/market/wall_extension.glb', label: 'wall_extension' },
    ],
    vertexColors: true,
    sceneRig: { ambientColor: [0.95, 0.85, 0.7], ambientEnergy: 1.6, sunEnergy: 0.3 },
    exportPath: 'assets/stages/city_e/market/dairon3.glb',
  },
  {
    id: 'counter',
    label: 'Guild Counter (s00e_sa2)',
    models: [{ path: 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb', label: 's00e_sa2_m' }],
    floorPath: 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2-floor.glb',
    markers: [
      { pos: [-7.86, -10.67, 111.39], label: 'Guild Counter NPC', color: '#ffd24a' },
      { pos: [-10.53, -10.67, 114.15], label: 'Storage NPC', color: '#7fd4ff' },
      { pos: [0.05, -5.08, 60.96], label: 'Warp pad', color: '#c58cff' },
    ],
    vertexColors: false,
    sceneRig: { ambientColor: [0.9, 0.88, 0.82], ambientEnergy: 1.5, sunEnergy: 0.3 },
    lightStageId: 's00e_sa2',
  },
  {
    id: 'office',
    label: "Principal's Office (s00e_office)",
    models: [{ path: 'assets/stages/city_e/s00e_office/lndmd/s00e_office_m.glb', label: 'office' }],
    vertexColors: true,
    sceneRig: { ambientColor: [0.804, 0.69, 0.533], ambientEnergy: 0.55, sunEnergy: 0.35 },
  },
  {
    id: 'underground',
    label: 'Underground (s00e_sa4)',
    models: [{ path: 'assets/stages/city_e/s00e_sa4/lndmd/s00e_sa4_m.glb', label: 's00e_sa4_m' }],
    vertexColors: true,
    sceneRig: { ambientColor: [0.32, 0.35, 0.42], ambientEnergy: 1.0, sunEnergy: 0.0 },
  },
];

export function stageById(id: string): StageDef {
  return STAGES.find((s) => s.id === id) ?? STAGES[0];
}

/* ------------------------------------------------------------------ */
/* Triangle audit                                                      */
/* ------------------------------------------------------------------ */

export type IssueClass = 'nonfinite' | 'zero-area' | 'duplicate-vertex' | 'uv-degenerate' | 'sliver';

export interface TriangleIssue {
  /** `${meshName}#${faceIndex}` */
  key: string;
  meshName: string;
  faceIndex: number;
  cls: IssueClass;
  /** 3 = nonfinite, 2 = zero-area / duplicate vertex, 1 = sliver. */
  severity: number;
  v0: Vec3;
  v1: Vec3;
  v2: Vec3;
  centroid: Vec3;
  /** World-space area in m² (0 for nonfinite). */
  area: number;
  /** longestEdge² / (4·√3·area): 1 = equilateral, huge = sliver. */
  aspect: number;
}

export interface AuditStats {
  meshes: number;
  faces: number;
  issues: number;
  byClass: Record<IssueClass, number>;
}

/* ------------------------------------------------------------------ */
/* Authored lights                                                     */
/* ------------------------------------------------------------------ */

export interface LightSpec {
  id: string;
  name: string;
  pos: Vec3;
  /** Linear 0..1 RGB — written straight into Godot's Color(r, g, b). */
  color: Vec3;
  /** Godot OmniLight3D.light_energy — multiplies, 1:1 into three intensity. */
  energy: number;
  /** Godot omni_range — hard cutoff distance (three: light.distance). */
  range: number;
  /**
   * Godot omni_attenuation — 2.0 is true inverse-square, 1.0 is the
   * flattened falloff the placed-light convention uses (three: decay).
   */
  attenuation: number;
  shadows: boolean;
}

export interface AmbientSpec {
  color: Vec3;
  energy: number;
}

export interface LightsDoc {
  stage: string;
  ambient: AmbientSpec;
  lights: LightSpec[];
}
