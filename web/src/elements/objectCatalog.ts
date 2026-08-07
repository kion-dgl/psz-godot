import type { TextureOverrides } from './materials';

/**
 * Catalog of PSZ field objects that exist as converted models but have no
 * hand-written element component (no gameplay behaviour to model yet).
 *
 * Ported from the psz-asset-viewer object browser
 * (https://dashgl.github.io/psz-asset-viewer/objects/). That viewer exposes
 * 52 object *sets* holding 951 model instances, but only 104 of those are
 * unique by content hash — every `o0c_*` "common" object is byte-identical
 * across all nine fields, so a set-by-set port would have been ~9x redundant.
 * This catalog is the deduplicated remainder: one entry per genuinely distinct
 * model + texture pair.
 *
 * Two kinds of duplication survive deliberately, because the models really do
 * differ:
 *   - Per-field art: `oNN_cont` / `oNN_wall` / `oNN_wallptcl` are a different
 *     mesh and texture in every field, so each field gets its own entry.
 *   - `o0s_warpb` / `o0s_warpm` / `o0s_warps` ship a second variant in the
 *     `special_n` set with different meshes AND different textures that reuse
 *     the same filenames (`o0s_1_fwarp2.png` is not the same image in the two
 *     sets) — hence the separate `special_n/` asset directory.
 *
 * Objects already covered by a component in ./index.ts are intentionally
 * absent here; see StorybookViewer's CATEGORIES for the merged list.
 */

/** Human-readable field names, keyed by the scene number in the model prefix. */
export const FIELD_NAMES: Record<string, string> = {
  '00': 'City',
  '01': 'Gurhacia Valley',
  '02': 'Ozette Wetlands',
  '03': 'Rioh Snowfield',
  '04': 'Makara Ruins',
  '05': 'Oblivion City Paru',
  '06': 'Arca Plant',
  '07': 'Dark Shrine',
  '08': 'Eternal Tower',
};

export interface CatalogState {
  name: string;
  label: string;
  description?: string;
}

export interface CatalogEntry {
  /** Storybook element id (kebab-case, unique across hand-written elements too). */
  id: string;
  title: string;
  description: string;
  /** Sidebar grouping. Reuses the existing category names where one fits. */
  category: string;
  /** Repo-relative asset path; resolved through assetUrl() at render time. */
  glb: string;
  /** Source model basename in the PSZ archives, for traceability back to the viewer. */
  model: string;
  /** Viewer object set the model was taken from. */
  sourceSet: string;
  /**
   * Preview scale, default 1 = the model's authored size.
   *
   * Left at 1 for almost everything on purpose: the hand-written elements all
   * render at true scale, so keeping it means the storybook shows real relative
   * size (a wall really is ~6x a box). Only set where the authored size is
   * unusable against the fixed preview camera — the ~20-unit compasses and clay
   * trap, the 126-unit sky backdrop, and the sub-unit critters and bullet.
   *
   * Requires detachSkinnedBind(): every object GLB is a SkinnedMesh, and
   * three's default attached bind mode cancels ancestor scale out entirely.
   */
  scale?: number;
  /**
   * UV scale applied to every texture on the model, default [1, 1].
   *
   * The box and wall families are the exception: `scripts/3d/elements/box.gd`
   * and `wall.gd` are the only two Godot elements that call
   * `GameElement._setup_mirror_textures()`, which binds the mirror_repeat
   * shader at `uv_scale = Vector2(2, 2)`. Their UVs run [-0.25, 1.0], so at
   * 1x the crate/wall panel motif stretches across the whole face and reads
   * as smeared bands; at 2x it tiles the way the game draws it. Mirroring the
   * game's value here is what makes a storybook box look like an in-game box.
   */
  repeat?: [number, number];
  /** Slow Y-spin, for pickups and floating props. */
  spin?: boolean;
  /** Texture filename → scroll speed, for animated warp surfaces. */
  scroll?: Record<string, { x?: number; y?: number }>;
  /** Per-texture wrap/repeat exceptions to the mirrored-repeat default. */
  textures?: TextureOverrides;
  states?: CatalogState[];
  /**
   * Per-state texture overrides, layered on top of `textures`. Used where a
   * state is expressed by shifting the sheet rather than by geometry — the
   * heal pad's used/unused frames are the same mesh at ±0.5 offsetX.
   */
  stateTextures?: Record<string, TextureOverrides>;
  /**
   * Texture filenames whose material is hidden in the named state. Mirrors what
   * the hand-written NeedleTrap does for `o0c_1_needle2`: the trap's second
   * sheet is the "armed" overlay and is simply not drawn when off.
   */
  stateHiddenTextures?: Record<string, string[]>;
  /**
   * Child-mesh indices drawn in the named state, for models that ship variants
   * as sibling primitives rather than separate files. The treasure box is two
   * 100-vertex primitives sharing one material — lid-on and lid-off — and
   * renders both at once unless a state picks one.
   */
  stateMeshes?: Record<string, number[]>;
  /**
   * Per-state skin-joint rotation in DEGREES, keyed by bone name. Some objects
   * express their state through the rig rather than through geometry or UVs —
   * the treasure box lid is the `huta` joint, and the GLB ships no animation
   * clip, so the open angle lives here.
   */
  stateBones?: Record<string, Record<string, [number, number, number]>>;
  /**
   * Milliseconds to ease texture offsets when the state changes, instead of
   * snapping. The heal pad reads as a pad draining rather than a hard cut.
   */
  stateTransitionMs?: number;
}

const DESTRUCTIBLE: CatalogState[] = [
  { name: 'intact', label: 'Intact' },
  { name: 'destroyed', label: 'Destroyed', description: 'Model is despawned' },
];

/** Per-field destructible container (`oNN_cont`) — the "box" every field re-skins. */
function boxEntry(scene: string, dir: string, set: string): CatalogEntry {
  const field = FIELD_NAMES[scene];
  return {
    id: `box-${dir}`,
    title: `Box (${field})`,
    description: `Destructible container, ${field} variant. Same role as the Valley box but a distinct mesh and texture.`,
    category: 'Containers',
    glb: `/assets/objects/${dir}/o${scene}_cont.glb`,
    model: `o${scene}_cont`,
    sourceSet: set,
    repeat: [2, 2],
    states: DESTRUCTIBLE,
  };
}

/** Per-field destructible wall (`oNN_wall`). */
function wallEntry(scene: string, dir: string, set: string): CatalogEntry {
  const field = FIELD_NAMES[scene];
  return {
    id: `wall-${dir}`,
    title: `Wall (${field})`,
    description: `Destructible wall obstacle, ${field} variant.`,
    category: 'Walls',
    glb: `/assets/objects/${dir}/o${scene}_wall.glb`,
    model: `o${scene}_wall`,
    sourceSet: set,
    repeat: [2, 2],
    states: DESTRUCTIBLE,
  };
}

/**
 * Per-field wall debris (`oNN_wallptcl`). These are the break-apart particle
 * shards spawned when the matching wall is destroyed — they use the field's
 * `ff_wall_oNN.png` sheet rather than the wall's own texture.
 */
function wallDebrisEntry(scene: string, dir: string, set: string): CatalogEntry {
  const field = FIELD_NAMES[scene];
  return {
    id: `wall-debris-${dir}`,
    title: `Wall Debris (${field})`,
    description: `Break-apart shards for the ${field} wall. Uses the field's ff_wall_o${scene} particle sheet.`,
    category: 'Walls',
    glb: `/assets/objects/${dir}/o${scene}_wallptcl.glb`,
    model: `o${scene}_wallptcl`,
    sourceSet: set,
  };
}

const FIELD_DIRS: { scene: string; dir: string; set: string; needsBoxAndWall: boolean }[] = [
  { scene: '01', dir: 'valley', set: '01_o01a', needsBoxAndWall: false }, // Box + Wall are hand-written
  { scene: '02', dir: 'wetlands', set: '02_o02a', needsBoxAndWall: true },
  { scene: '03', dir: 'snowfield', set: '03_o03a', needsBoxAndWall: true },
  { scene: '04', dir: 'makara', set: '04_o04a', needsBoxAndWall: true },
  { scene: '05', dir: 'paru', set: '05_o05a', needsBoxAndWall: true },
  { scene: '06', dir: 'arca', set: '06_o06a', needsBoxAndWall: true },
  { scene: '07', dir: 'shrine', set: '07_o07a', needsBoxAndWall: true },
];

const FIELD_ENTRIES: CatalogEntry[] = FIELD_DIRS.flatMap(({ scene, dir, set, needsBoxAndWall }) => [
  // Valley's box/wall already have hand-written components with real state logic.
  ...(needsBoxAndWall ? [boxEntry(scene, dir, set), wallEntry(scene, dir, set)] : []),
  wallDebrisEntry(scene, dir, set),
]);

export const OBJECT_CATALOG: CatalogEntry[] = [
  ...FIELD_ENTRIES,

  // Eternal Tower reuses one container across all eight floors and ships no
  // wall/wallptcl pair — the tower's rooms are sealed rather than walled off.
  {
    id: 'box-tower',
    title: 'Box (Eternal Tower)',
    description:
      'Destructible container, Eternal Tower variant. Shared by all eight tower floor sets (08_o080–08_o087) and the extra set. The tower has no destructible wall.',
    category: 'Containers',
    glb: '/assets/objects/tower/o08_cont.glb',
    model: 'o08_cont',
    sourceSet: '08_o080',
    repeat: [2, 2],
    states: DESTRUCTIBLE,
  },
  {
    id: 'treasure-box',
    title: 'Treasure Box',
    description:
      'Field-independent treasure chest. Unlike the per-field box this is one shared model in every set that has it. The lid is a SKIN JOINT named `huta` (Japanese for lid), not separate geometry — the two primitives are the same 100-vertex shell. Opening the chest means rotating that bone; there is no animation clip in the GLB, so the angle is set here.',
    category: 'Containers',
    glb: '/assets/objects/valley/o0c_trebox.glb',
    model: 'o0c_trebox',
    sourceSet: '01_o01a',
    states: [
      { name: 'closed', label: 'Closed', description: 'Lid down' },
      { name: 'open', label: 'Open', description: 'Lid hinged back' },
    ],
    stateBones: {
      closed: { huta: [0, 0, 0] },
      open: { huta: [-100, 0, 0] },
    },
  },

  // --- Traps and hazards -------------------------------------------------
  {
    id: 'bomb-container',
    title: 'Bomb Container',
    description: 'Explosive barrel. Breaking it damages whatever is nearby rather than dropping loot.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_bombcont.glb',
    model: 'o0c_bombcont',
    sourceSet: '01_o01a',
    states: DESTRUCTIBLE,
  },
  {
    id: 'gun-trap-1',
    title: 'Gun Trap (Type 1)',
    description: 'Wall-mounted turret trap. Fires the bullet model below.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_gun01.glb',
    model: 'o0c_gun01',
    sourceSet: '01_o01a',
  },
  {
    id: 'gun-trap-2',
    title: 'Gun Trap (Type 2)',
    description: 'Second turret trap variant, distinct mesh and texture from type 1.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_gun02.glb',
    model: 'o0c_gun02',
    sourceSet: '01_o01a',
  },
  {
    id: 'turret-bullet',
    title: 'Turret Bullet',
    description:
      'Projectile fired by the gun traps. Untextured — the only object model in the set with no image at all, so it renders as flat vertex-coloured geometry.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_bullet01.glb',
    model: 'o0c_bullet01',
    sourceSet: '01_o01a',
    scale: 4,
  },
  {
    id: 'poison-trap',
    title: 'Poison Trap',
    description:
      'Floor gas trap. Two-primitive model like the needle trap: o0c_1_poisonm is the always-visible base and o0c_1_poisonm2 is the armed gas overlay, drawn only when on.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_poisonm.glb',
    model: 'o0c_poisonm',
    sourceSet: '01_o01a',
    states: [
      { name: 'off', label: 'Off', description: 'Gas retracted' },
      { name: 'on', label: 'On', description: 'Gas venting, deals damage' },
    ],
    stateHiddenTextures: { off: ['o0c_1_poisonm2.png'] },
    // Same UV setup as the needle trap: base flat at 1x, armed overlay offset
    // slightly and tiled 2x across the strip.
    textures: {
      'o0c_1_poisonm.png': { offsetX: 0, offsetY: 0, repeatX: 1, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
      'o0c_1_poisonm2.png': { offsetX: -0.17, offsetY: -0.18, repeatX: 2, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'clay-trap',
    title: 'Clay Trap',
    description:
      'Large trap volume — roughly 21 units across, wall-sized rather than prop-sized, so it is scaled down to fit the preview. Textured from the shared o0s_*_trapc sheet rather than any field palette, so it looks identical everywhere it appears. Exact gameplay role not yet confirmed against the DS build.',
    category: 'Traps',
    glb: '/assets/objects/valley/o0c_clay1.glb',
    model: 'o0c_clay1',
    sourceSet: '01_o01a',
    scale: 0.12,
    repeat: [2, 1],
    states: DESTRUCTIBLE,
  },

  // --- Warps -------------------------------------------------------------
  {
    id: 'boss-warp',
    title: 'Boss Warp',
    description:
      'Third warp type alongside the start and area warps. Shares the start warp\'s scrolling o0s_1_swarp3 surface over its own o0s_0_bwarp1 base.',
    category: 'Warps',
    glb: '/assets/objects/special_z/o0s_warpb.glb',
    model: 'o0s_warpb',
    sourceSet: 'special_z',
    scroll: { 'o0s_1_swarp3.png': { y: -1.35 } },
  },
  {
    id: 'start-warp-n',
    title: 'Start Warp (Variant N)',
    description:
      'The special_n set ships its own start warp: different mesh, and a different image behind the same o0s_0_swarp1 filename plus an o0s_1_swarp2 surface the other sets never use. Compare against Start Warp.',
    category: 'Warps',
    glb: '/assets/objects/special_n/o0s_warps.glb',
    model: 'o0s_warps',
    sourceSet: 'special_n',
    scroll: { 'o0s_1_swarp2.png': { y: 0.6 } },
    textures: {
      'o0s_1_swarp2.png': { offsetX: 0, offsetY: -4.84, wrapS: 'mirror', wrapT: 'mirror' },
      'o0s_0_swarp1.png': { offsetX: 0, offsetY: 0, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'area-warp-n',
    title: 'Area Warp (Variant N)',
    description:
      'special_n area warp. Not a duplicate of the standard warps despite looking similar: the mesh differs and its o0s_1_fwarp2.png is a different image from the identically-named texture in every other special set — the reason these live in their own asset directory.',
    category: 'Warps',
    glb: '/assets/objects/special_n/o0s_warpm.glb',
    model: 'o0s_warpm',
    sourceSet: 'special_n',
    scroll: { 'o0s_1_fwarp2.png': { x: -0.5 } },
    textures: {
      'o0s_1_fwarp2.png': { offsetX: -3.08, offsetY: 0 },
      'o0s_0_fwarp1.png': { offsetX: 0, offsetY: 0, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'boss-warp-n',
    title: 'Boss Warp (Variant N)',
    description: 'special_n boss warp, with its own o0s_1_bwarp2 surface in place of the shared swarp3.',
    category: 'Warps',
    glb: '/assets/objects/special_n/o0s_warpb.glb',
    model: 'o0s_warpb',
    sourceSet: 'special_n',
    scroll: { 'o0s_1_bwarp2.png': { y: -1.35 } },
  },
  {
    id: 'arena-warp',
    title: 'Arena Warp',
    description: 'Warp used by the arena / event sets (special_e, special_r2, special_r4).',
    category: 'Warps',
    glb: '/assets/objects/special_z/o0c_warparena1.glb',
    model: 'o0c_warparena1',
    sourceSet: 'special_e',
    scroll: { 'o0c_1_warpa3.png': { y: -0.6 } },
  },
  {
    id: 'return-warp',
    title: 'Return Waypoint',
    description:
      'Waypoint marker carrying a home icon — the exit pad that sends the player back to the City. Grouped with the other indicators rather than the warps because it reads as a marker, not a transition. Appears in special_e, special_sg and special_z.',
    category: 'Indicators',
    glb: '/assets/objects/special_z/o0c_return.glb',
    model: 'o0c_return',
    sourceSet: 'special_e',
  },
  {
    id: 'city-warp-a',
    title: 'City Warp (A)',
    description: 'City teleporter, cwarp1a/cwarp2a texture set.',
    category: 'Warps',
    glb: '/assets/objects/special_c3/o0s_warpcn.glb',
    model: 'o0s_warpcn',
    sourceSet: 'special_c3',
    scroll: { 'o0s_1_cwarp2a.png': { x: -0.5 } },
    textures: {
      'o0s_1_cwarp2a.png': { offsetX: -2.68, offsetY: 5.31, repeatX: 1, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
      'o0s_1_cwarp1a2.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'city-warp-b',
    title: 'City Warp (B)',
    description: 'City teleporter, cwarp1b/cwarp2b texture set.',
    category: 'Warps',
    glb: '/assets/objects/special_c3/o0s_warpch.glb',
    model: 'o0s_warpch',
    sourceSet: 'special_c3',
    scroll: { 'o0s_1_cwarp2b.png': { x: -0.5 } },
    textures: {
      'o0s_1_cwarp2b.png': { offsetX: -2.68, offsetY: 5.31, repeatX: 1, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
      'o0s_1_cwarp1b2.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'city-warp-c',
    title: 'City Warp (C)',
    description: 'City teleporter, cwarp1c/cwarp2c texture set.',
    category: 'Warps',
    glb: '/assets/objects/special_c3/o0s_warpcv.glb',
    model: 'o0s_warpcv',
    sourceSet: 'special_c3',
    scroll: { 'o0s_1_cwarp2c.png': { x: -0.5 } },
    textures: {
      'o0s_1_cwarp2c.png': { offsetX: -2.68, offsetY: 5.31, repeatX: 1, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
      'o0s_1_cwarp1c2.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },
  {
    id: 'city-warp-absorb',
    title: 'City Warp (Absorb)',
    description:
      'Fourth city teleporter. The odd one out — it uses the o0c_1_wabs1 / wabs2 pair instead of the cwarp sheets the other three share.',
    category: 'Warps',
    glb: '/assets/objects/special_c3/o0s_warpcb.glb',
    model: 'o0s_warpcb',
    sourceSet: 'special_c3',
    scroll: { 'o0c_1_wabs2.png': { y: 0.4 } },
    textures: {
      'o0c_1_wabs2.png': { offsetX: 0, offsetY: 2.48, repeatX: 1, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
      'o0c_1_wabs1.png': { offsetX: 0, offsetY: 0, repeatX: 2, repeatY: 1, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },

  // --- City props --------------------------------------------------------
  {
    id: 'city-compass',
    title: 'City Compass',
    description:
      'Large gold ornamental prop from the City backdrop, ~21 units across (scaled down for the preview). Two textures, s00_1_back02 / back03. "Compass" is the archive model name, not a confirmed in-game role.',
    category: 'City Props',
    glb: '/assets/objects/special_c3/o00_compass.glb',
    model: 'o00_compass',
    sourceSet: 'special_c3',
    textures: {
      's00_1_back03.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
      's00_1_back02.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
    },
    scale: 0.12,
  },
  {
    id: 'city-compass-ring',
    title: 'City Compass (Ring)',
    description:
      'Companion ring overlay, same ~20-unit footprint as o00_compass and drawn from the o0c_2_line01 line sheet.',
    category: 'City Props',
    glb: '/assets/objects/special_c3/o00_compass2.glb',
    model: 'o00_compass2',
    sourceSet: 'special_c3',
    scale: 0.12,
  },
  {
    id: 'city-ring-marker',
    title: 'City Ring Marker',
    description: 'Ring marker prop from the City set (s00_1_ring1 texture).',
    category: 'City Props',
    glb: '/assets/objects/special_z/o0c_ruller01.glb',
    model: 'o0c_ruller01',
    sourceSet: 'special_c1',
    textures: {
      's00_1_ring1.png': { offsetX: 0, offsetY: 1, repeatX: 2, repeatY: 2, wrapS: 'mirror', wrapT: 'mirror' },
    },
  },

  // --- Ambient life ------------------------------------------------------
  {
    id: 'ambient-bird',
    title: 'Bird',
    description: 'Ambient flying bird (ob_pigeon texture). Appears in four of the special sets.',
    category: 'Ambient',
    glb: '/assets/objects/special_z/o0c_bird.glb',
    model: 'o0c_bird',
    sourceSet: 'special_05z',
  },
  {
    id: 'ambient-butterfly',
    title: 'Butterfly',
    description: 'Ambient butterfly, used in the City and special_sg sets.',
    category: 'Ambient',
    glb: '/assets/objects/special_z/o0c_butterfly.glb',
    model: 'o0c_butterfly',
    sourceSet: 'special_c1',
    scale: 4,
  },
  {
    id: 'ambient-dragonfly',
    title: 'Dragonfly',
    description: 'Ambient dragonfly, special_sg only.',
    category: 'Ambient',
    glb: '/assets/objects/special_z/o0c_dragonfly.glb',
    model: 'o0c_dragonfly',
    sourceSet: 'special_sg',
    scale: 4,
  },

  // --- Misc --------------------------------------------------------------
  {
    id: 'heal-pad',
    title: 'Heal Pad',
    description:
      'Healing floor pad. Present in nine of the fourteen special sets. Used and unused are the same mesh — the sheet holds both frames side by side and the state shifts offsetX by half.',
    category: 'Pickups',
    glb: '/assets/objects/special_z/o0c_healhp.glb',
    model: 'o0c_healhp',
    sourceSet: 'special_02z',
    states: [
      { name: 'unused', label: 'Unused', description: 'Pad is charged and can still heal' },
      { name: 'used', label: 'Used', description: 'Pad has been spent' },
    ],
    stateTextures: {
      unused: { 'o0c_0_healhp.png': { offsetX: 0.5 } },
      used: { 'o0c_0_healhp.png': { offsetX: -0.5 } },
    },
    stateTransitionMs: 450,
  },
  {
    id: 'z-sky-wetlands',
    title: 'Z-Sky Backdrop (Wetlands)',
    description:
      'Distant skybox/backdrop geometry for the Ozette Wetlands z-set. Eight textures, all s02_* stage art rather than object art — it is scenery packed into the object archive. Scaled down heavily to fit the preview.',
    category: 'Scenery',
    glb: '/assets/objects/special_z/o0s_zsky.glb',
    model: 'o0s_zsky',
    sourceSet: 'special_02z',
    scale: 0.02,
  },
];

/** Sidebar order for catalog-contributed categories not already in CATEGORIES. */
export const CATALOG_CATEGORY_ORDER = [
  'Containers',
  'Walls',
  'Traps',
  'Warps',
  'Pickups',
  'City Props',
  'Ambient',
  'Scenery',
];
