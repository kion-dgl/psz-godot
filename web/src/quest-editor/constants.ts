/**
 * Stage constants — adapted from psz-sketch stage-editor/constants.ts
 * Asset paths use raw stage layout: /assets/stages/{subfolder}/{stageId}/lndmd/{stageId}-scene.glb
 */
import { assetUrl } from '../utils/assets';

export const STANDARD_SUFFIXES = [
  'ga1', 'ib1', 'ib2', 'ic1', 'ic3', 'lb1', 'lb3', 'lc1', 'lc2',
  'na1', 'nb2', 'nc2', 'sa1', 'tb3', 'tc3', 'td1', 'td2', 'xb2'
];

export interface StageAreaConfig {
  name: string;
  prefix: string;
  folder: string;  // Stage area folder name
}

/** Maps area key → stage folder */
export const STAGE_AREAS: Record<string, StageAreaConfig> = {
  valley:   { name: 'Gurhacia Valley',   prefix: 's01', folder: 'valley' },
  wetlands: { name: 'Ozette Wetlands',   prefix: 's02', folder: 'wetlands' },
  snowfield:{ name: 'Rioh Snowfield',    prefix: 's03', folder: 'snowfield' },
  makara:   { name: 'Makara Ruins',      prefix: 's04', folder: 'makara' },
  paru:     { name: 'Oblivion City Paru',prefix: 's05', folder: 'paru' },
  arca:     { name: 'Arca Plant',        prefix: 's06', folder: 'arca' },
  shrine:   { name: 'Dark Shrine',       prefix: 's07', folder: 'shrine' },
  tower:    { name: 'Eternal Tower',     prefix: 's08', folder: 'tower' },
};

/** Derive the assets/stages/ subfolder from a mapId and area folder */
export function getStageSubfolder(mapId: string, folder: string): string {
  if (mapId.length >= 4) return `${folder}_${mapId[3]}`;
  return folder;
}

/** Get the raw stage GLB path for a stage */
export function getGlbPath(areaKey: string, mapId: string): string {
  const area = STAGE_AREAS[areaKey];
  const folder = area?.folder ?? 'valley';
  const subfolder = getStageSubfolder(mapId, folder);
  return assetUrl(`/assets/stages/${subfolder}/${mapId}/lndmd/${mapId}-scene.glb`);
}

/** Get area key from a map ID (e.g., "s01a_ib1" → "valley") */
export function getAreaFromMapId(mapId: string): string | null {
  for (const [areaKey, area] of Object.entries(STAGE_AREAS)) {
    if (mapId.startsWith(area.prefix)) {
      return areaKey;
    }
  }
  return null;
}

/** Area key to Godot area ID mapping (for export) */
export const AREA_KEY_TO_ID: Record<string, string> = {
  valley: 'gurhacia',
  wetlands: 'ozette',
  snowfield: 'rioh',
  makara: 'makara',
  paru: 'paru',
  arca: 'arca',
  shrine: 'dark',
  tower: 'tower',
};
