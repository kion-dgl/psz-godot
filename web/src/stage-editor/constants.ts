import { assetUrl } from '../utils/assets';
import type { StageAreaConfig } from './types';

// Standard map suffixes used across most stages
export const STANDARD_SUFFIXES = [
  'ga1', 'ib1', 'ib2', 'ic1', 'ic3', 'lb1', 'lb3', 'lc1', 'lc2',
  'na1', 'nb2', 'nc2', 'sa1', 'tb3', 'tc3', 'td1', 'td2', 'xb2'
];

// Generate maps for a stage prefix (e.g., 's01' for valley)
export function generateStageMaps(prefix: string, variants: string[] = ['a', 'b', 'e', 'z']): Record<string, string[]> {
  const result: Record<string, string[]> = {};
  for (const variant of variants) {
    if (variant === 'e') {
      result[variant] = [`${prefix}e_ia1`];
    } else if (variant === 'z') {
      result[variant] = [`${prefix}z_na1`];
    } else {
      result[variant] = STANDARD_SUFFIXES.map(suffix => `${prefix}${variant}_${suffix}`);
    }
  }
  return result;
}

// Tower has a different structure
const TOWER_MAPS: Record<string, string[]> = {
  '0': ['s080_sa0'],
  '1': ['s081_ga1', 's081_sa1', 's081_ib1', 's081_lb1'],
  '2': ['s082_ga1', 's082_sa1', 's082_ib1', 's082_lb1'],
  '3': ['s083_ga1', 's083_sa1', 's083_ib1', 's083_lb1'],
  '4': ['s084_ga1', 's084_sa1', 's084_ib1', 's084_lb1'],
  '5': ['s085_ga1', 's085_sa1', 's085_ib1', 's085_lb1'],
  '6': ['s086_ga1', 's086_sa1', 's086_ib1', 's086_lb1'],
  '7': ['s087_na1'],
  'e': ['s08e_ib1'],
};

// Shrine has extra boss map
const SHRINE_Z_MAPS = ['s07z_na1', 's07z_na2'];

// City has a different map structure
const CITY_MAPS: Record<string, string[]> = {
  a: ['s00a_nr1', 's00a_nr2', 's00a_nr3', 's00a_nr4', 's00a_nr5', 's00a_nr6'],
  e: ['s00e_sa1', 's00e_sa2', 's00e_sa3', 's00e_sa4'],
};

export const STAGE_AREAS: Record<string, StageAreaConfig> = {
  city: {
    name: 'Dairon City',
    prefix: 's00',
    folder: 'city',
    maps: CITY_MAPS,
  },
  valley: {
    name: 'Gurhacia Valley',
    prefix: 's01',
    folder: 'valley',
    maps: generateStageMaps('s01'),
  },
  wetlands: {
    name: 'Ozette Wetlands',
    prefix: 's02',
    folder: 'wetlands',
    maps: generateStageMaps('s02'),
  },
  snowfield: {
    name: 'Rioh Snowfield',
    prefix: 's03',
    folder: 'snowfield',
    maps: generateStageMaps('s03'),
  },
  makara: {
    name: 'Makara Ruins',
    prefix: 's04',
    folder: 'makara',
    maps: generateStageMaps('s04'),
  },
  paru: {
    name: 'Oblivion City Paru',
    prefix: 's05',
    folder: 'paru',
    maps: generateStageMaps('s05'),
  },
  arca: {
    name: 'Arca Plant',
    prefix: 's06',
    folder: 'arca',
    maps: generateStageMaps('s06'),
  },
  shrine: {
    name: 'Dark Shrine',
    prefix: 's07',
    folder: 'shrine',
    maps: {
      ...generateStageMaps('s07', ['a', 'b', 'e']),
      z: SHRINE_Z_MAPS,
    },
  },
  tower: {
    name: 'Eternal Tower',
    prefix: 's08',
    folder: 'tower',
    maps: TOWER_MAPS,
  },
};

// Get all maps for a given area
export function getAllMapsForArea(areaKey: string): string[] {
  const area = STAGE_AREAS[areaKey];
  if (!area) return [];
  return Object.values(area.maps).flat();
}

// Get area key from map ID
export function getAreaFromMapId(mapId: string): string | null {
  for (const [areaKey, area] of Object.entries(STAGE_AREAS)) {
    if (mapId.startsWith(area.prefix)) {
      return areaKey;
    }
  }
  return null;
}

// Derive the assets/stages/ subfolder from a mapId and area folder.
// e.g. mapId="s01a_ga1", folder="valley" → "valley_a"
export function getStageSubfolder(mapId: string, folder: string): string {
  if (mapId.length >= 4) return `${folder}_${mapId[3]}`;
  return folder;
}

// Get GLB path for a map — uses raw stage layout via assetUrl()
export function getGlbPath(areaKey: string, mapId: string): string {
  const area = STAGE_AREAS[areaKey];
  const folder = area?.folder ?? 'valley';
  const subfolder = getStageSubfolder(mapId, folder);
  return assetUrl(`assets/stages/${subfolder}/${mapId}/lndmd/${mapId}-scene.glb`);
}

// Calculate portal positions based on edge, offset along edge, and grid settings
export function calculatePortalPositions(
  edge: 'north' | 'south' | 'east' | 'west',
  offsetAlongEdge: number,
  gridSize: number,
  gridOffset: [number, number]
): { gate: [number, number, number]; spawn: [number, number, number]; trigger: [number, number, number]; rotation: number } {
  const halfSize = gridSize / 2;
  const spawnInset = 3;
  const triggerOutset = 2;
  const y = 1;

  switch (edge) {
    case 'north':
      return {
        gate: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] - halfSize],
        spawn: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] - halfSize + spawnInset],
        trigger: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] - halfSize - triggerOutset],
        rotation: 0,
      };
    case 'south':
      return {
        gate: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] + halfSize],
        spawn: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] + halfSize - spawnInset],
        trigger: [gridOffset[0] + offsetAlongEdge, y, gridOffset[1] + halfSize + triggerOutset],
        rotation: Math.PI,
      };
    case 'east':
      return {
        gate: [gridOffset[0] + halfSize, y, gridOffset[1] + offsetAlongEdge],
        spawn: [gridOffset[0] + halfSize - spawnInset, y, gridOffset[1] + offsetAlongEdge],
        trigger: [gridOffset[0] + halfSize + triggerOutset, y, gridOffset[1] + offsetAlongEdge],
        rotation: -Math.PI / 2,
      };
    case 'west':
      return {
        gate: [gridOffset[0] - halfSize, y, gridOffset[1] + offsetAlongEdge],
        spawn: [gridOffset[0] - halfSize + spawnInset, y, gridOffset[1] + offsetAlongEdge],
        trigger: [gridOffset[0] - halfSize - triggerOutset, y, gridOffset[1] + offsetAlongEdge],
        rotation: Math.PI / 2,
      };
  }
}

// Get gate rotation for visual display
export function getGateRotation(edge: 'north' | 'south' | 'east' | 'west'): number {
  switch (edge) {
    case 'north': return Math.PI;
    case 'south': return 0;
    case 'east': return Math.PI / 2;
    case 'west': return -Math.PI / 2;
  }
}
