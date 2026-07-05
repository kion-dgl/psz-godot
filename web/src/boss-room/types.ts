/**
 * Boss room data — mirror of data/boss_arenas.json (#493).
 *
 * Bosses are arena-bound: the room loads the boss rig inside its own stage
 * geometry (visual `_m.glb` + baked `-floor.glb` collider, same world frame
 * as Godot — see city-walk-mock). Snake_case is kept so an edited config
 * round-trips to the data file with plain JSON.stringify.
 */
import { assetUrl } from '../utils/assets';

export interface ArenaDef {
  area: string; // assets/stages/<area>/ subfolder, e.g. "valley_z"
  label: string;
  skybox?: boolean;
  unassigned?: boolean; // no boss currently spawns here (quest data)
  note?: string;
}

export interface BossDef {
  model_id: string; // assets/enemies/<model_id>/<model_id>.glb
  arena: string; // default arena stage_id — the tool can load any
  quest_source: string; // quest whose boss segment spawns this boss
  model_scale: number;
  note?: string;
  clip_notes: Record<string, string>;
}

export interface BossArenaConfig {
  schema_version: number;
  arenas: Record<string, ArenaDef>;
  bosses: Record<string, BossDef>;
}

export async function loadBossConfig(): Promise<BossArenaConfig> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/boss_arenas.json`);
  if (!res.ok) throw new Error(`boss_arenas.json: HTTP ${res.status}`);
  return res.json();
}

/** Roster names come from data/enemies.json like the enemy room. */
export interface RosterEntry {
  id: string;
  name: string;
  is_boss?: boolean;
}

export async function loadRoster(): Promise<Map<string, RosterEntry>> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/enemies.json`);
  if (!res.ok) throw new Error(`enemies.json: HTTP ${res.status}`);
  const list: RosterEntry[] = await res.json();
  return new Map(list.map((e) => [e.id, e]));
}

export function arenaModelUrl(stageId: string, arena: ArenaDef): string {
  return assetUrl(`assets/stages/${arena.area}/${stageId}/lndmd/${stageId}_m.glb`);
}

export function arenaFloorUrl(stageId: string, arena: ArenaDef): string {
  return assetUrl(`assets/stages/${arena.area}/${stageId}/lndmd/${stageId}-floor.glb`);
}

export function arenaSkyboxUrl(stageId: string, arena: ArenaDef): string | null {
  if (!arena.skybox) return null;
  return assetUrl(`assets/stages/${arena.area}/${stageId}/lndmd/skybox/o0s_zsky.glb`);
}

/**
 * Group clip tokens into st/lp/ed segment families (#493: segmented clips are
 * first-class for bosses — the robot's whole kit is `atk_dl_lp` pieces, the
 * mother's laser/swing/headbutt and falz's thr/rad/dif all chain st→lp→ed).
 * A family is any shared prefix that has ≥2 of the st/lp/ed suffixes.
 * Suffix spellings seen in the boss rigs: `st`, `lp`, `end`/`ed`.
 */
export interface SegmentFamily {
  prefix: string;
  st?: string;
  lp?: string;
  ed?: string;
}

const SEGMENT_SUFFIXES: Array<[RegExp, keyof Omit<SegmentFamily, 'prefix'>]> = [
  [/(?:_?st)$/, 'st'],
  [/(?:_?lp)$/, 'lp'],
  [/(?:_?end|_?ed)$/, 'ed'],
];

export function segmentFamilies(clipNames: string[]): SegmentFamily[] {
  const families = new Map<string, SegmentFamily>();
  for (const name of clipNames) {
    for (const [re, slot] of SEGMENT_SUFFIXES) {
      const m = name.match(re);
      if (!m) continue;
      const prefix = name.slice(0, name.length - m[0].length);
      if (!prefix) continue;
      const fam = families.get(prefix) ?? { prefix };
      fam[slot] = name;
      families.set(prefix, fam);
      break;
    }
  }
  return [...families.values()]
    .filter((f) => [f.st, f.lp, f.ed].filter(Boolean).length >= 2)
    .sort((a, b) => a.prefix.localeCompare(b.prefix));
}
