/**
 * Quest Editor Types
 * Self-contained type definitions (no external stage/types dependency)
 */

// ============================================================================
// Inlined stage types (from psz-sketch systems/stage/types)
// ============================================================================

export type StageArea =
  | 'valley-a' | 'valley-b' | 'valley-e'
  | 'snowfield-a' | 'snowfield-b'
  | 'wetland-a' | 'wetland-b'
  | 'city-a' | 'city-b'
  | 'ruins-a' | 'ruins-b'
  | 'plant-a' | 'plant-b'
  | 'shrine-a' | 'shrine-b';

export interface StageConfig {
  gridSize: number;
  gridOffset: [number, number];
  gates: GateConfig[];
  spawnPoints: SpawnPoint[];
  triggers: GateTrigger[];
}

export interface GateConfig {
  edge: 'north' | 'south' | 'east' | 'west';
  x: number;
  z: number;
  scale: number;
  animated: boolean;
}

export interface SpawnPoint {
  position: [number, number, number];
  rotation: number;
  label: string;
}

export interface GateTrigger {
  position: [number, number, number];
  rotation: number;
  targetUrl: string;
  label: string;
}

/** Placeholder for per-cell content (future milestone) */
export interface StageContent {
  stageId: string;
  [key: string]: unknown;
}

// ============================================================================
// Directions (re-used from grid generation)
// ============================================================================

export type Direction = 'north' | 'south' | 'east' | 'west';

// ============================================================================
// Cell Roles
// ============================================================================

export type CellRole = 'transit' | 'guard' | 'puzzle' | 'cache' | 'landmark' | 'boss';

export const ROLE_COLORS: Record<CellRole, string> = {
  transit: '#666',
  guard: '#cc4444',
  puzzle: '#ccaa44',
  cache: '#44aa44',
  landmark: '#4488cc',
  boss: '#cc8844',
};

export const ROLE_LABELS: Record<CellRole, string> = {
  transit: 'Transit',
  guard: 'Guard',
  puzzle: 'Puzzle',
  cache: 'Cache',
  landmark: 'Landmark',
  boss: 'Boss',
};

// ============================================================================
// Cell Objects (placed in 3D stage)
// ============================================================================

export type CellObjectType = 'box' | 'rare_box' | 'enemy' | 'fence' | 'step_switch' | 'message' | 'story_prop' | 'dialog_trigger' | 'npc' | 'telepipe';

export interface CellObject {
  /** Unique ID within cell (e.g., "box_0", "enemy_1") */
  id: string;
  /** Object type */
  type: CellObjectType;
  /** Stage-local position [x, y, z] */
  position: [number, number, number];
  /** Y-axis rotation in degrees */
  rotation?: number;
  /** Enemy ID for type='enemy' */
  enemy_id?: string;
  /** Links switch-fence pairs with matching link_id */
  link_id?: string;
  /** Spawn wave number for type='enemy' (default 1) */
  wave?: number;
  /** Message text for type='message' */
  text?: string;
  /** GLB path for type='story_prop' (relative to project, e.g., "assets/objects/story/dropship_crash.glb") */
  prop_path?: string;
  /** NPC identifier for type='npc' (e.g., "sarisa", "kai") */
  npc_id?: string;
  /** Display name for type='npc' */
  npc_name?: string;
  /** Dialog pages for type='dialog_trigger' or type='npc' */
  dialog?: Array<{ speaker: string; text: string }>;
  /** Trigger identifier for type='dialog_trigger' (for one-shot tracking) */
  trigger_id?: string;
  /** Trigger collision box size [x, y, z] for type='dialog_trigger' (default [4, 3, 4]) */
  trigger_size?: [number, number, number];
  /** When to fire for type='dialog_trigger': 'enter' (default) or 'room_clear' */
  trigger_condition?: 'enter' | 'room_clear';
  /** Post-dialog actions for type='dialog_trigger': "complete_quest", "telepipe" */
  actions?: string[];
  /** Animation name to freeze on for type='npc' (e.g., "dam_h" for lying face down) */
  animation?: string;
  /** Frame to freeze on for type='npc' (used with animation) */
  animation_frame?: number;
  /** When to spawn for type='telepipe': 'immediate' (default) or 'room_clear' */
  spawn_condition?: 'immediate' | 'room_clear';
}

export const CELL_OBJECT_COLORS: Record<CellObjectType, string> = {
  box: '#aa6633',
  rare_box: '#ddaa33',
  enemy: '#cc4444',
  fence: '#4488cc',
  step_switch: '#44cc66',
  message: '#cc66ff',
  story_prop: '#cccc44',
  dialog_trigger: '#44cccc',
  npc: '#44cc44',
  telepipe: '#66aaff',
};

export const CELL_OBJECT_LABELS: Record<CellObjectType, string> = {
  box: 'Box',
  rare_box: 'Rare Box',
  enemy: 'Enemy',
  fence: 'Fence',
  step_switch: 'Switch',
  message: 'Message',
  story_prop: 'Story Prop',
  dialog_trigger: 'Dialog Trigger',
  npc: 'NPC',
  telepipe: 'Telepipe',
};

// ============================================================================
// Editor Grid Cell
// ============================================================================

export interface EditorGridCell {
  /** Stage ID with prefix (e.g., "s01a_ib1") */
  stageName: string;
  /** Rotation in degrees (0, 90, 180, 270). Only used for single-gate stages. */
  rotation?: number;
  /** Which gate direction is key-locked on this cell */
  lockedGate?: Direction;
  /** Cell role for visual and future content generation */
  role: CellRole;
  /** Whether this cell was manually placed (vs generated) */
  manual: boolean;
  /** Optional designer notes */
  notes?: string;
  /** Authored 3D position for key pickup [x, y, z] in stage-local coords */
  keyPosition?: [number, number, number];
  /** Placed objects (boxes, enemies, fences, switches) */
  objects?: CellObject[];
}

// ============================================================================
// Quest Section (one section of a multi-section quest)
// ============================================================================

export type SectionType = 'grid' | 'transition' | 'boss';

export interface QuestSection {
  type: SectionType;
  variant: string;
  gridSize: number;
  cells: Record<string, EditorGridCell>;
  startPos: string | null;
  endPos: string | null;
  keyLinks: Record<string, string>;
  /** Direction player enters from (transition/boss sections) */
  entryDirection?: Direction;
  /** Direction player exits to (transition/boss sections) */
  exitDirection?: Direction;
}

// ============================================================================
// Quest Project (top-level save state)
// ============================================================================

/** Tracks where a project was loaded from */
export type QuestProjectSource =
  | { type: 'new' }
  | { type: 'game'; filename: string }
  | { type: 'draft'; id: string };

export interface QuestProject {
  id: string;
  name: string;
  areaKey: string;
  variant: string;
  gridSize: number;
  cells: Record<string, EditorGridCell>;
  startPos: string | null;
  endPos: string | null;
  keyLinks: Record<string, string>;
  sections?: QuestSection[];
  metadata: QuestMetadata;
  cellContents: Record<string, StageContent>;
  lastModified: string;
  version: number;
  source?: QuestProjectSource;
}

export interface CityDialogScene {
  /** NPC who speaks (matches npc_id) */
  npc_id: string;
  /** Display name */
  npc_name: string;
  /** Dialog pages */
  dialog: Array<{ speaker: string; text: string }>;
}

export interface QuestMetadata {
  questName: string;
  description: string;
  companions?: string[];
  /** Dialog scenes that play in the city before entering the field */
  cityDialog?: CityDialogScene[];
}

export interface CompanionInfo {
  id: string;
  name: string;
}

export const AVAILABLE_COMPANIONS: CompanionInfo[] = [
  { id: 'kai', name: 'Kai' },
  { id: 'sarisa', name: 'Sarisa' },
];

// ============================================================================
// Validation
// ============================================================================

export interface ValidationIssue {
  severity: 'error' | 'warning' | 'info';
  message: string;
  cellPos?: string;
}

// ============================================================================
// Area config for the editor
// ============================================================================

export interface EditorAreaConfig {
  key: string;
  name: string;
  prefix: string;
  variants: string[];
  available: boolean;
}

export const EDITOR_AREAS: EditorAreaConfig[] = [
  { key: 'valley', name: 'Gurhacia Valley', prefix: 's01', variants: ['a', 'b'], available: true },
  { key: 'wetlands', name: 'Ozette Wetlands', prefix: 's02', variants: ['a', 'b'], available: true },
  { key: 'snowfield', name: 'Rioh Snowfield', prefix: 's03', variants: ['a', 'b'], available: true },
  { key: 'makara', name: 'Makara Ruins', prefix: 's04', variants: ['a', 'b'], available: true },
  { key: 'paru', name: 'Oblivion City Paru', prefix: 's05', variants: ['a', 'b'], available: true },
  { key: 'arca', name: 'Arca Plant', prefix: 's06', variants: ['a', 'b'], available: false },
  { key: 'shrine', name: 'Dark Shrine', prefix: 's07', variants: ['a', 'b'], available: false },
  { key: 'tower', name: 'Eternal Tower', prefix: 's08', variants: [], available: false },
];

// ============================================================================
// Factory
// ============================================================================

export function createDefaultProject(id?: string): QuestProject {
  return {
    id: id || crypto.randomUUID(),
    name: 'New Quest',
    areaKey: 'valley',
    variant: 'a',
    gridSize: 5,
    cells: {},
    startPos: null,
    endPos: null,
    keyLinks: {},
    metadata: {
      questName: '',
      description: '',
      companions: [],
    },
    cellContents: {},
    lastModified: new Date().toISOString(),
    version: 1,
  };
}

export function getProjectSections(project: QuestProject): QuestSection[] {
  if (project.sections && project.sections.length > 0) {
    return project.sections;
  }
  return [{
    type: 'grid',
    variant: project.variant,
    gridSize: project.gridSize,
    cells: project.cells,
    startPos: project.startPos,
    endPos: project.endPos,
    keyLinks: project.keyLinks,
  }];
}

export function getActiveSection(project: QuestProject, sectionIdx: number): QuestSection {
  const sections = getProjectSections(project);
  return sections[sectionIdx] || sections[0];
}

export function createSection(type: SectionType, variant: string, gridSize?: number): QuestSection {
  return {
    type,
    variant,
    gridSize: type === 'grid' ? (gridSize || 5) : 1,
    cells: {},
    startPos: null,
    endPos: null,
    keyLinks: {},
  };
}

export const SECTION_TYPE_LABELS: Record<SectionType, string> = {
  grid: 'Grid',
  transition: 'Transition',
  boss: 'Boss',
};

export const SECTION_VARIANT_SUGGESTIONS: Record<SectionType, string> = {
  grid: 'a',
  transition: 'e',
  boss: 'z',
};
