/**
 * Enemy-room schema — 1:1 TS mirror of data/enemy_attacks.json
 * (spec /mechanics/enemy-attacks). Field names stay snake_case so the
 * tool's export is a plain JSON.stringify of the same shape the Godot
 * loader (next PR) reads. Keep DEFAULTS in sync with
 * scripts/tools/gen_enemy_attacks.py.
 */

export interface AttackDef {
  id: string;
  /** Animation-name token as Godot's resolver consumes it (atk, atk2, atk_hi…) — NOT a full clip name. */
  clip: string;
  weight: number;
  min_range: number;
  max_range: number;
  /** Telegraph: [0, windup_frac) of the resolved clip deals no damage. */
  windup_frac: number;
  /** Damaging window is [windup_frac, damage_end_frac] of the clip. */
  damage_end_frac: number;
  hit_half_angle_deg: number;
  hit_reach: number;
  damage_mult: number;
}

export interface EnemyStats {
  move_speed: number;
  attack_range: number;
  attack_cooldown: number;
  detection_range: number;
  attack_base: number;
}

export interface FsmParams {
  walk_speed_mult: number;
  charge_range_mult: number;
  charge_speed_mult: number;
  loaf_duration_min: number;
  loaf_duration_max: number;
  hurt_duration: number;
  attack_fallback_duration: number;
}

export interface EnemyAttackEntry {
  stats: EnemyStats;
  fsm: Partial<FsmParams>;
  attacks: AttackDef[];
}

export interface EnemyAttackConfig {
  schema_version: number;
  defaults: { fsm: FsmParams; attack: Omit<AttackDef, 'id' | 'clip'> };
  enemies: Record<string, EnemyAttackEntry>;
}

/** Mirrors gen_enemy_attacks.py DEFAULTS / enemy_base.gd constants. */
export const DEFAULT_FSM: FsmParams = {
  walk_speed_mult: 0.5,
  charge_range_mult: 2.0,
  charge_speed_mult: 1.5,
  loaf_duration_min: 2.5,
  loaf_duration_max: 4.0,
  hurt_duration: 0.3,
  attack_fallback_duration: 0.8,
};

export const DEFAULT_ATTACK: Omit<AttackDef, 'id' | 'clip'> = {
  windup_frac: 0.35,
  damage_end_frac: 0.6,
  hit_half_angle_deg: 45.0,
  hit_reach: 2.0,
  damage_mult: 1.0,
  weight: 1.0,
  min_range: 0.0,
  max_range: 999.0,
};

export const DEFAULT_STATS: EnemyStats = {
  move_speed: 3.0,
  attack_range: 2.0,
  attack_cooldown: 1.5,
  detection_range: 15.0,
  attack_base: 10,
};

/** Entry with defaults applied — what the sim actually runs. */
export interface ResolvedEntry {
  stats: EnemyStats;
  fsm: FsmParams;
  attacks: AttackDef[];
}

export function resolveEntry(config: EnemyAttackConfig | null, enemyId: string): ResolvedEntry {
  const entry = config?.enemies?.[enemyId];
  const stats = { ...DEFAULT_STATS, ...(entry?.stats ?? {}) };
  const fsm = { ...DEFAULT_FSM, ...(config?.defaults?.fsm ?? {}), ...(entry?.fsm ?? {}) };
  const attacks = (entry?.attacks?.length ? entry.attacks : [defaultAttackFor(stats)]).map((a) => ({
    ...DEFAULT_ATTACK,
    ...(config?.defaults?.attack ?? {}),
    ...a,
  }));
  return { stats, fsm, attacks };
}

/** Spec: an enemy missing from the file falls back to one default attack — it never refuses to attack. */
export function defaultAttackFor(stats: EnemyStats): AttackDef {
  return { id: 'basic', clip: 'atk', ...DEFAULT_ATTACK, max_range: stats.attack_range };
}

export async function loadConfig(): Promise<EnemyAttackConfig> {
  const base = import.meta.env.BASE_URL || '/';
  const res = await fetch(`${base}data/enemy_attacks.json`);
  if (!res.ok) throw new Error(`enemy_attacks.json fetch failed: ${res.status}`);
  return res.json();
}

/** data/enemies.json roster row — maps roster id → display name + model id (GLB dir). */
export interface RosterEntry {
  id: string;
  name: string;
  model_id: string;
  element: string;
  locations: string[];
  is_rare: boolean;
  is_boss: boolean;
}

export async function loadRoster(): Promise<Map<string, RosterEntry>> {
  const base = import.meta.env.BASE_URL || '/';
  const res = await fetch(`${base}data/enemies.json`);
  if (!res.ok) throw new Error(`enemies.json fetch failed: ${res.status}`);
  const list: RosterEntry[] = await res.json();
  return new Map(list.map((e) => [e.id, e]));
}
