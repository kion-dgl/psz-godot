// Area metadata: mapping between area slug, asset folder name, display
// name, and the area-number prefix used in stage IDs. Matches
// AREA_FOLDER in scripts/tools/quest_solver/solve_manhattan.ts so the
// asset URLs line up with what the publisher writes to R2 / the local
// /cdn proxy.

export interface AreaMeta {
  folder: string;
  display: string;
  areaNum: string;
}

export const AREA_META: Record<string, AreaMeta> = {
  city:      { folder: 'city',      display: 'Dairon City',        areaNum: '00' },
  valley:    { folder: 'valley',    display: 'Gurhacia Valley',    areaNum: '01' },
  wetlands:  { folder: 'wetlands',  display: 'Ozette Wetlands',    areaNum: '02' },
  snowfield: { folder: 'snowfield', display: 'Rioh Snowfield',     areaNum: '03' },
  makara:    { folder: 'makara',    display: 'Makara Ruins',       areaNum: '04' },
  paru:      { folder: 'paru',      display: 'Oblivion City Paru', areaNum: '05' },
  arca:      { folder: 'arca',      display: 'Arca Plant',         areaNum: '06' },
  shrine:    { folder: 'shrine',    display: 'Dark Shrine',        areaNum: '07' },
  tower:     { folder: 'tower',     display: 'Eternal Tower',      areaNum: '08' },
};

/** Reverse lookup: area number → area slug. */
export function areaNumToSlug(num: string): string | null {
  for (const [slug, meta] of Object.entries(AREA_META)) {
    if (meta.areaNum === num) return slug;
  }
  return null;
}
