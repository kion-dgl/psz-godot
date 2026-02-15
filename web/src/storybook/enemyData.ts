/**
 * Enemy Gallery Data — adapted for psz-godot asset layout.
 *
 * Enemy GLBs live at assets/enemies/{id}/{id}.glb (flat, no info.json).
 * Metadata (display names, elements, categories) is hardcoded here.
 */

import { assetUrl } from '../utils/assets';

export interface EnemyCategory {
  id: string;
  label: string;
  description: string;
}

export type EnemyElement = 'Native' | 'Beast' | 'Machine' | 'Dark';

export interface EnemyMetadata {
  displayName: string;
  element?: EnemyElement;
  location?: string;
  isRare?: boolean;
}

export const ENEMY_CATEGORIES: EnemyCategory[] = [
  { id: 'gurhacia', label: 'Gurhacia Valley', description: 'Forest and grassland enemies' },
  { id: 'rioh', label: 'Rioh Snowfield', description: 'Snow and ice enemies' },
  { id: 'ozette', label: 'Ozette Wetland', description: 'Swamp and water enemies' },
  { id: 'paru', label: 'Oblivion City Paru', description: 'Ruined city enemies' },
  { id: 'makara', label: 'Makara Ruins', description: 'Cave and ruins enemies' },
  { id: 'arca', label: 'Arca Plant', description: 'Machine enemies' },
  { id: 'dark', label: 'Dark Shrine', description: 'Dark element creatures' },
  { id: 'rare', label: 'Rare', description: 'Rare spawns (Rappies & Boomas)' },
];

const ENEMY_METADATA: Record<string, EnemyMetadata> = {
  // Gurhacia Valley
  snake: { displayName: 'Garapython', element: 'Native', location: 'Gurhacia Valley' },
  snake_rare: { displayName: 'Garahadan', element: 'Native', location: 'Gurhacia Valley', isRare: true },
  lizard: { displayName: 'Ghowl', element: 'Native', location: 'Gurhacia Valley' },
  hyena: { displayName: 'Grimble', element: 'Native', location: 'Gurhacia Valley' },
  hyena_rare: { displayName: 'Tormatible', element: 'Native', location: 'Gurhacia Valley', isRare: true },
  vulture: { displayName: 'Vulkure', element: 'Native', location: 'Gurhacia Valley' },
  lion: { displayName: 'Helion', element: 'Beast', location: 'Gurhacia Valley' },
  lion_rare: { displayName: 'Blaze Helion', element: 'Beast', location: 'Gurhacia Valley', isRare: true },
  // Rioh Snowfield
  wolf: { displayName: 'Reyhound', element: 'Native', location: 'Rioh Snowfield' },
  deer: { displayName: 'Stagg', element: 'Native', location: 'Rioh Snowfield' },
  rabbit: { displayName: 'Usanny', element: 'Native', location: 'Rioh Snowfield' },
  rabbit_rare: { displayName: 'Usanimere', element: 'Native', location: 'Rioh Snowfield', isRare: true },
  gorilla: { displayName: 'Hildegao', element: 'Beast', location: 'Rioh Snowfield' },
  gorilla_female: { displayName: 'Hildeghana', element: 'Beast', location: 'Rioh Snowfield' },
  gorilla_rare: { displayName: 'Hildegigas', element: 'Beast', location: 'Rioh Snowfield', isRare: true },
  // Ozette Wetland
  seal: { displayName: 'Hypao', element: 'Native', location: 'Ozette Wetland' },
  seal_rare: { displayName: 'Vespao', element: 'Native', location: 'Ozette Wetland', isRare: true },
  frog: { displayName: 'Porel', element: 'Native', location: 'Ozette Wetland' },
  frog_rare: { displayName: 'Pomarr', element: 'Native', location: 'Ozette Wetland', isRare: true },
  roc: { displayName: 'Pelcatraz', element: 'Beast', location: 'Ozette Wetland' },
  roc_rare: { displayName: 'Pelcatobur', element: 'Beast', location: 'Ozette Wetland', isRare: true },
  // Oblivion City Paru
  shrimp: { displayName: 'Bolix', element: 'Native', location: 'Oblivion City Paru' },
  shrimp_rare: { displayName: 'Goldix', element: 'Native', location: 'Oblivion City Paru', isRare: true },
  frog_bomb: { displayName: 'Pobomma', element: 'Native', location: 'Oblivion City Paru' },
  orangutan: { displayName: 'Froutang', element: 'Beast', location: 'Oblivion City Paru' },
  orangutan_rare: { displayName: 'Frunaked', element: 'Beast', location: 'Oblivion City Paru', isRare: true },
  quad: { displayName: 'Izhirak-S6', element: 'Machine', location: 'Oblivion City Paru' },
  quad_rare: { displayName: 'Azherowa-B2', element: 'Machine', location: 'Oblivion City Paru', isRare: true },
  // Makara Ruins
  bat: { displayName: 'Batt', element: 'Native', location: 'Makara Ruins' },
  bat_blue: { displayName: 'Bullbatt', element: 'Native', location: 'Makara Ruins' },
  tiger: { displayName: 'Kapantha', element: 'Native', location: 'Makara Ruins' },
  mole: { displayName: 'Rumole', element: 'Native', location: 'Makara Ruins' },
  armadillo: { displayName: 'Rohjade', element: 'Beast', location: 'Makara Ruins' },
  armadillo_rare: { displayName: 'Rohcrysta', element: 'Beast', location: 'Makara Ruins', isRare: true },
  // Arca Plant
  shooter: { displayName: 'Korse', element: 'Machine', location: 'Arca Plant' },
  shooter_leader: { displayName: 'Akorse', element: 'Machine', location: 'Arca Plant' },
  swordman: { displayName: 'Arkzein', element: 'Machine', location: 'Arca Plant' },
  swordman_rare: { displayName: 'Arkzein R', element: 'Machine', location: 'Arca Plant', isRare: true },
  board: { displayName: 'Finjer R', element: 'Machine', location: 'Arca Plant' },
  board_blue: { displayName: 'Finjer B', element: 'Machine', location: 'Arca Plant' },
  board_green: { displayName: 'Finjer G', element: 'Machine', location: 'Arca Plant' },
  // Dark Shrine
  circle: { displayName: 'Eulada', element: 'Dark', location: 'Dark Shrine' },
  circle_black: { displayName: 'Euladaveil', element: 'Dark', location: 'Dark Shrine' },
  lower: { displayName: 'Eulid', element: 'Dark', location: 'Dark Shrine' },
  lower_black: { displayName: 'Eulidveil', element: 'Dark', location: 'Dark Shrine' },
  leg: { displayName: 'Derreo', element: 'Dark', location: 'Dark Shrine' },
  leg_black: { displayName: 'Zerreo', element: 'Dark', location: 'Dark Shrine' },
  tank: { displayName: 'Phobos', element: 'Dark', location: 'Dark Shrine' },
  tank_rare: { displayName: 'Phobos Dyna', element: 'Dark', location: 'Dark Shrine', isRare: true },
  swordman_b: { displayName: 'Zaphobos', element: 'Dark', location: 'Dark Shrine' },
  swordman_rare_b: { displayName: 'Zaphobos Dyna', element: 'Dark', location: 'Dark Shrine', isRare: true },
  mother: { displayName: 'Mother Trinity', element: 'Dark', location: 'Dark Shrine' },
  mother_sword: { displayName: 'Blade Mother', element: 'Dark', location: 'Eternal Tower' },
  mother_gun: { displayName: 'Shot Mother', element: 'Dark', location: 'Eternal Tower' },
  mother_tech: { displayName: 'Force Mother', element: 'Native', location: 'Eternal Tower' },
  // Rare spawns
  booma: { displayName: 'Booma Origin', element: 'Native', location: 'Gurhacia Valley', isRare: true },
  jigobooma: { displayName: 'Gigobooma Origin', element: 'Native', location: 'Ozette Wetland', isRare: true },
  rappy: { displayName: 'Rappy', element: 'Native', location: 'Gurhacia Valley', isRare: true },
  rappy_blue: { displayName: 'Ar Rappy', element: 'Native', location: 'Oblivion City Paru', isRare: true },
  rappy_red: { displayName: 'Rab Rappy', element: 'Native', location: 'Arca Plant', isRare: true },
};

const ENEMY_CATEGORY_MAP: Record<string, string> = {
  snake: 'gurhacia', snake_rare: 'gurhacia', lizard: 'gurhacia',
  hyena: 'gurhacia', hyena_rare: 'gurhacia', vulture: 'gurhacia',
  lion: 'gurhacia', lion_rare: 'gurhacia',
  wolf: 'rioh', deer: 'rioh', rabbit: 'rioh', rabbit_rare: 'rioh',
  gorilla: 'rioh', gorilla_female: 'rioh', gorilla_rare: 'rioh',
  seal: 'ozette', seal_rare: 'ozette', frog: 'ozette', frog_rare: 'ozette',
  roc: 'ozette', roc_rare: 'ozette',
  shrimp: 'paru', shrimp_rare: 'paru', frog_bomb: 'paru',
  orangutan: 'paru', orangutan_rare: 'paru', quad: 'paru', quad_rare: 'paru',
  bat: 'makara', bat_blue: 'makara', tiger: 'makara', mole: 'makara',
  armadillo: 'makara', armadillo_rare: 'makara',
  shooter: 'arca', shooter_leader: 'arca', swordman: 'arca', swordman_rare: 'arca',
  board: 'arca', board_blue: 'arca', board_green: 'arca',
  circle: 'dark', circle_black: 'dark', lower: 'dark', lower_black: 'dark',
  leg: 'dark', leg_black: 'dark', tank: 'dark', tank_rare: 'dark',
  swordman_b: 'dark', swordman_rare_b: 'dark', mother: 'dark',
  mother_gun: 'dark', mother_sword: 'dark', mother_tech: 'dark',
  booma: 'rare', jigobooma: 'rare', rappy: 'rare', rappy_blue: 'rare', rappy_red: 'rare',
};

// 60 enemies imported into psz-godot (bosses excluded — multi-part models not imported)
export const ALL_ENEMY_IDS = [
  'armadillo', 'armadillo_rare', 'bat', 'bat_blue',
  'board', 'board_blue', 'board_green', 'booma',
  'circle', 'circle_black', 'deer',
  'frog', 'frog_bomb', 'frog_rare',
  'gorilla', 'gorilla_female', 'gorilla_rare',
  'hyena', 'hyena_rare', 'jigobooma',
  'leg', 'leg_black', 'lion', 'lion_rare', 'lizard',
  'lower', 'lower_black', 'mole',
  'mother', 'mother_gun', 'mother_sword', 'mother_tech',
  'orangutan', 'orangutan_rare',
  'quad', 'quad_rare',
  'rabbit', 'rabbit_rare', 'rappy', 'rappy_blue', 'rappy_red',
  'roc', 'roc_rare', 'seal', 'seal_rare',
  'shooter', 'shooter_leader',
  'shrimp', 'shrimp_rare',
  'snake', 'snake_rare',
  'swordman', 'swordman_b', 'swordman_rare', 'swordman_rare_b',
  'tank', 'tank_rare', 'tiger', 'vulture', 'wolf',
];

/** Animation source sharing — rare variants load animations from base model */
const ANIMATION_SOURCE_MAP: Record<string, string> = {
  gorilla_female: 'gorilla', frog_bomb: 'frog', bat_blue: 'bat',
  circle_black: 'circle', rappy_blue: 'rappy', rappy_red: 'rappy',
  lower_black: 'lower', leg_black: 'leg', hyena: 'hyena_rare',
};

/** GLB path for an enemy — uses psz-godot flat layout */
export function getEnemyGlbPath(enemyId: string): string {
  return assetUrl(`/assets/enemies/${enemyId}/${enemyId}.glb`);
}

export function getEnemyCategory(enemyId: string): EnemyCategory | null {
  const categoryId = ENEMY_CATEGORY_MAP[enemyId];
  return ENEMY_CATEGORIES.find(cat => cat.id === categoryId) || null;
}

export function getEnemyDisplayName(enemyId: string): string {
  const meta = ENEMY_METADATA[enemyId];
  if (meta) return meta.displayName;
  return enemyId.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

export function isEnemyBoss(enemyId: string): boolean {
  return enemyId.startsWith('boss_');
}

export function isEnemyRare(enemyId: string): boolean {
  return ENEMY_METADATA[enemyId]?.isRare ?? enemyId.endsWith('_rare');
}

export function getEnemyElement(enemyId: string): EnemyElement | null {
  return ENEMY_METADATA[enemyId]?.element || null;
}

/** Get the base enemy for animation sharing. Returns null if no sharing needed. */
export function getBaseEnemyId(enemyId: string): string | null {
  if (ANIMATION_SOURCE_MAP[enemyId]) {
    const baseId = ANIMATION_SOURCE_MAP[enemyId];
    if (ALL_ENEMY_IDS.includes(baseId)) return baseId;
  }
  if (enemyId.endsWith('_rare')) {
    const baseId = enemyId.replace(/_rare$/, '');
    if (ALL_ENEMY_IDS.includes(baseId)) return baseId;
  }
  return null;
}
