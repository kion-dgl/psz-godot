import { assetUrl } from '../../utils/assets';

export const CLASS_TO_PC_PREFIX: Record<string, string> = {
  humar: 'pc_00', humarl: 'pc_01', ramar: 'pc_02', ramarl: 'pc_03',
  fomar: 'pc_04', fomarl: 'pc_05', hunewm: 'pc_06', hunewearl: 'pc_07',
  fonewm: 'pc_08', fonewearl: 'pc_09', hucast: 'pc_10', hucaseal: 'pc_11',
  racast: 'pc_12', racaseal: 'pc_13',
};

export const GENDER_MAP: Record<string, 'm' | 'w'> = {
  humar: 'm', humarl: 'w', ramar: 'm', ramarl: 'w',
  fomar: 'm', fomarl: 'w', hunewm: 'm', hunewearl: 'w',
  fonewm: 'm', fonewearl: 'w', hucast: 'm', hucaseal: 'w',
  racast: 'm', racaseal: 'w',
};

export const HEAD_VARIATIONS = 4;

export const HAIR_COLORS = ['Blonde', 'Brown', 'Black'];
export const SKIN_TONES = ['Light', 'Medium', 'Dark'];
export const BODY_COLORS = ['Red', 'Blue', 'Green', 'Blue & Red', 'Black & Red'];

export const CAST_LABELS = { head: 'Head Parts', hair: 'Body Color A', body: 'Body Color B', skin: 'Body Color C' };
export const HUMAN_LABELS = { head: 'Head Type', hair: 'Hair Color', body: 'Costume Color', skin: 'Skin Tone' };

/** Class character art path */
export function getClassArtPath(classId: string): string {
  // Map class IDs to image filenames (some have different naming)
  const FILE_MAP: Record<string, string> = {
    hucast: 'hucast', hucaseal: 'hucasteal',
    racast: 'racast', racaseal: 'racasteal',
  };
  const filename = FILE_MAP[classId] || classId;
  return assetUrl(`/assets/images/${filename}.png`);
}

/**
 * Model GLB path for a given class + head variation.
 * Directory: pc_XYZ where XY = class prefix digits, Z = variation (0-3)
 * File: pc_XYZ_000.glb
 */
export function getModelPath(classId: string, variationIndex: number): string {
  const prefix = CLASS_TO_PC_PREFIX[classId] || 'pc_00';
  const variation = `${prefix}${variationIndex}`;
  return assetUrl(`assets/player/${variation}/${variation}_000.glb`);
}

/**
 * Texture PNG path for a given class + head variation + color choices.
 * Texture index = hair*100 + skin*10 + body, zero-padded to 3 digits.
 */
export function getTexturePath(
  classId: string,
  variationIndex: number,
  hairIndex: number,
  skinIndex: number,
  bodyIndex: number,
): string {
  const prefix = CLASS_TO_PC_PREFIX[classId] || 'pc_00';
  const variation = `${prefix}${variationIndex}`;
  const textureIndex = hairIndex * 100 + skinIndex * 10 + bodyIndex;
  const padded = String(textureIndex).padStart(3, '0');
  return assetUrl(`assets/player/${variation}/textures/${variation}_${padded}.png`);
}

/**
 * Idle animation GLB — saver has the idle (`pmsa_wait` / `pwsa_wait`).
 */
export function getIdleAnimationPath(classId: string): string {
  const gender = GENDER_MAP[classId] || 'm';
  return assetUrl(`assets/player/animations/saver_${gender}.glb`);
}
