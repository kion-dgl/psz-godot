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

/** Draft phase of a boss fight (v2). Order matters; the first phase is the opener. */
export interface BossPhase {
  id: string;
  label: string;
  /** Phase entered when HP fraction drops to this (omitted = non-HP trigger; see note). */
  hp_frac?: number;
  /** Modifier phases (enrage): movement speed multiplier while entered. */
  speed_mult?: number;
  /** Modifier phases (enrage): attack-cooldown multiplier while entered (<1 = more aggressive). */
  cooldown_mult?: number;
  note?: string;
}

/**
 * Draft boss attack (v2) — reuses the /mechanics/enemy-attacks timeline model
 * (unset numeric fields default per that spec's `defaults`). Boss-only
 * extensions: `chain` (explicit clip-token sequence — tokens ending in `lp`
 * loop), `phases` (availability gate), `anchor` (named arena anchor the
 * attack is bound to), and the boss `kind` values beam_sweep / aoe_burst /
 * grab / fly_pass / spout on top of the enemy kinds.
 */
export interface BossAttackDef {
  id: string;
  /** Representative clip token (suffix-matched against the rig, `*_<token>`). */
  clip: string;
  /** Full token sequence played in order; tokens ending in `lp` repeat lp-loops times. */
  chain?: string[];
  kind?: string;
  /** Phase ids this attack is available in (omitted = all phases). */
  phases?: string[];
  /** Named anchor (from BossDef.anchors) the attack is bound to / aimed from. */
  anchor?: string;
  weight?: number;
  min_range?: number;
  max_range?: number;
  windup_frac?: number;
  damage_end_frac?: number;
  hit_half_angle_deg?: number;
  hit_reach?: number;
  damage_mult?: number;
  /** A hit also shoves the player this many units along the boss's facing (wing flap). */
  knockback?: number;
  /** Loop count for `lp` chain tokens — for projectile volleys, one shot per rep (fireball ×3). */
  lp_loops?: number;
  /** kind: lob — impact points around the target; kind: projectile — shots fanned across the spread (falz's diffusion). */
  split?: number;
  /** kind: grab — clip played when damaging the boss cancels the hold (octo diablo's eatcnc). */
  cancel_clip?: string;
  /** Gem caster (Chaos Sorcerer): the gem color that triggers this attack. */
  gem?: GemColor;
  note?: string;
}

/** Chaos Sorcerer gem colors → spell school: purple dark, red fire, blue ice, green heal. */
export type GemColor = 'purple' | 'red' | 'blue' | 'green';
export const GEM_COLORS: GemColor[] = ['purple', 'red', 'blue', 'green'];
/** Render tint per gem (hex). */
export const GEM_HEX: Record<GemColor, number> = {
  purple: 0xa855f7,
  red: 0xef4444,
  blue: 0x3b82f6,
  green: 0x22c55e,
};

/** Arena-anchored named position (authored with the room's click tool). */
export interface BossAnchor {
  name: string;
  pos: [number, number, number];
  note?: string;
}

/** Draft sim tuning (v2) — drives the room's behavior sim, not observed truth. */
export interface BossStats {
  hp: number;
  move_speed: number;
  attack_cooldown: number;
  attack_base: number;
  turn_speed_deg: number;
}

export interface BossFsmParams {
  /** Fight-opening threat display clip token ('' = none, straight to active). */
  intro_clip: string;
  /** Locomotion loop while chasing/loafing (reyburn wlk1; humilias move; falz walk). */
  walk_clip: string;
  /** Grounded idle loop (humilias wat1). */
  idle_clip: string;
  /** Rooted emplacement (octo diablo): never walks; faces the target and attacks from the bands. */
  stationary: boolean;
  /** Chaos Sorcerer: hovers at this fixed height above the floor (0 = grounded). Distinct from the flyer hover_height. */
  hover_hold: number;
  /** Gem caster (Chaos Sorcerer): holds two gems; each attack is chosen by a held gem, consumed, then a new gem refills the empty slot. */
  gem_caster: boolean;
  /** Gem caster: seconds after a gem is spent before a new one spawns in the empty slot. */
  gem_respawn_delay: number;
  /** Gem caster: telegraph window — seconds both gems are visible after a refill before the next cast. */
  gem_cast_delay: number;
  /** Chaos Sorcerer: seconds between cancel-cast teleport repositions (0 = never). */
  teleport_interval: number;
  /** Teleport reposition radius around the arena origin. */
  teleport_radius: number;
  /** What RELOCATE looks like: the dragon's flight cycle or the octopus's submerge-swim. */
  relocate_kind: 'flight' | 'submerge';
  /** Damage into the boss is ignored while relocating (submerged octopus). */
  relocate_untargetable: boolean;
  /** relocate_kind submerge: how far below the floor the boss sinks. */
  submerge_depth: number;
  /** Seconds of grounded ACTIVE time before a flight cycle (0 = never; needs a flight-phase attack). */
  flight_interval: number;
  /** Airborne attack repetitions per flight (reyburn: sky fireballs fired before landing). */
  flight_attacks: number;
  hover_height: number;
  /** Relocation travel speed (× move_speed) — flight and submerged swim alike. */
  fly_speed_mult: number;
  /** Post-attack disengage walk (the enemy model's loafing): duration range in seconds. */
  loaf_duration_min: number;
  loaf_duration_max: number;
  /** Attacks since surfacing/resting that trigger the fatigue punish (0 = no fatigue). */
  fatigue_attacks: number;
  /** Fatigue punish length; the punish clip LOOPS for it (0 = play punish_clip once, its duration). */
  punish_duration: number;
  /** Damage accumulated in ground phases that triggers the knockdown punish window (0 = no break). */
  punish_break_damage: number;
  /** Damage multiplier while the punish reaction plays (enemy model's recovery_vulnerable_mult). */
  punish_vulnerable_mult: number;
  /** Clip token for the punish reaction (reyburn: dmg1; octo diablo: wattir; humilias: fallwat). */
  punish_clip: string;
  /** Knockdown chain (humilias): one-shot entry clip before the punish loop ('' = none). */
  punish_start_clip: string;
  /** Knockdown chain (humilias): one-shot recovery clip after the punish window ('' = none). */
  punish_end_clip: string;
  /** relocate_kind submerge: locomotion loop while relocating (octopus float; falz swm). */
  relocate_loop_clip: string;
}

export const DEFAULT_BOSS_STATS: BossStats = {
  hp: 300,
  move_speed: 4.0,
  attack_cooldown: 2.5,
  attack_base: 12,
  turn_speed_deg: 120,
};

export const DEFAULT_BOSS_FSM: BossFsmParams = {
  intro_clip: 'tht',
  walk_clip: 'wlk1',
  idle_clip: 'wat',
  stationary: false,
  hover_hold: 0,
  gem_caster: false,
  gem_respawn_delay: 2.5,
  gem_cast_delay: 1.5,
  teleport_interval: 0,
  teleport_radius: 10,
  relocate_kind: 'flight',
  relocate_untargetable: false,
  submerge_depth: 3,
  flight_interval: 0,
  flight_attacks: 1,
  hover_height: 8,
  fly_speed_mult: 2.5,
  loaf_duration_min: 2.5,
  loaf_duration_max: 4.0,
  fatigue_attacks: 0,
  punish_duration: 0,
  punish_break_damage: 60,
  punish_vulnerable_mult: 2.0,
  punish_clip: 'dmg1',
  punish_start_clip: '',
  punish_end_clip: '',
  relocate_loop_clip: 'float',
};

/** Mirrors the enemy DEFAULT_ATTACK (spec: unset boss fields take the enemy defaults). */
export const DEFAULT_BOSS_ATTACK = {
  windup_frac: 0.35,
  damage_end_frac: 0.6,
  hit_half_angle_deg: 45.0,
  hit_reach: 2.0,
  damage_mult: 1.0,
  weight: 1.0,
  min_range: 0.0,
  max_range: 999.0,
};

/** BossAttackDef with every numeric field applied — what the sim runs. */
export type ResolvedBossAttack = BossAttackDef & typeof DEFAULT_BOSS_ATTACK;

export interface ResolvedBoss {
  stats: BossStats;
  fsm: BossFsmParams;
  phases: BossPhase[];
  attacks: ResolvedBossAttack[];
  /** Authored arena anchors — submerge relocation targets (surfacing spots). */
  anchors: BossAnchor[];
}

export function resolveBoss(def: BossDef): ResolvedBoss {
  return {
    stats: { ...DEFAULT_BOSS_STATS, ...(def.stats ?? {}) },
    fsm: { ...DEFAULT_BOSS_FSM, ...(def.fsm ?? {}) },
    phases: def.phases ?? [],
    attacks: (def.attacks ?? []).map((a) => ({ ...DEFAULT_BOSS_ATTACK, ...a })),
    anchors: def.anchors ?? [],
  };
}

/**
 * A selectable rig in the form picker. Two shapes:
 * - composite boss (heaven's mother): a regular roster enemy the fight cycles through.
 * - split boss (chaos & mobius at Paru): a PART rig of a parent enemy — set
 *   `part_of` and the room loads assets/enemies/<part_of>/parts/<model_id>/.
 */
export interface BossForm {
  roster_id: string;
  model_id: string;
  label: string;
  /** When set, model_id is a part under this parent enemy (the robot's split halves). */
  part_of?: string;
}

export interface BossDef {
  model_id: string; // assets/enemies/<model_id>/<model_id>.glb (forms[0] for composite bosses)
  arena: string; // default arena stage_id — the tool can load any
  quest_source: string; // quest whose boss segment spawns this boss
  model_scale: number;
  /** Composite boss (heaven's mother): the fight cycles these roster enemies as its phases. */
  forms?: BossForm[];
  /** PSO stand-in whose rig is on R2 but not yet in the game pack — skip the asset_tree assertion. */
  pack_pending?: boolean;
  note?: string;
  phases?: BossPhase[];
  attacks?: BossAttackDef[];
  /**
   * Authored boss position in the DEFAULT arena frame (humilias stands at
   * the broken stage edge, not the arena center). Omitted = the room settles
   * the boss at the floor-collider center. The room's "move boss" click +
   * config export author this.
   */
  spawn_pos?: [number, number, number];
  /** Positions in the boss's DEFAULT arena frame — meaningless in an override arena. */
  anchors?: BossAnchor[];
  /**
   * Multi-part boss pieces (assets/enemies/<model_id>/parts/<name>/<name>.glb,
   * imported via import_objects.py parts). Rendered with the body; a part
   * carrying the body's clip names plays them in sync (octopus tentacles,
   * mother faces), a static part just rides the group (dragon horn).
   * The object form places INSTANCES of one part around the body — the
   * octopus's four tentacles are the same z_002_tt rig cloned four times,
   * positioned/rotated in the boss's local frame (+z = facing).
   */
  parts?: BossPartDef[];
  /** Visual y offset for the whole boss group — sinks the octopus to the waterline. */
  model_offset_y?: number;
  /** Draft sim tuning knobs (partial — defaults below fill the rest). */
  stats?: Partial<BossStats>;
  fsm?: Partial<BossFsmParams>;
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

/** One placed copy of a part, in the boss's local frame (+z = facing). */
export interface BossPartInstance {
  pos: [number, number, number];
  /** Turn around the up axis (degrees) — point the part outward. */
  yaw_deg?: number;
  /** Tilt (degrees, negative = nose up) — bend a tentacle up out of the water. */
  pitch_deg?: number;
  /**
   * Spline-poser control points (#508), boss-local frame — ≥2 points
   * (emergence → apex → tip). When set, the curve — not pos/yaw/pitch —
   * places the piece: bones pose along the Catmull-Rom fit per the
   * /states/bosses parts contract (see curvePose.ts).
   */
  curve?: [number, number, number][];
}

export type BossPartDef = string | { part: string; instances?: BossPartInstance[] };

export const partName = (p: BossPartDef): string => (typeof p === 'string' ? p : p.part);
export const partInstances = (p: BossPartDef): BossPartInstance[] =>
  typeof p === 'string' ? [{ pos: [0, 0, 0] }] : (p.instances ?? [{ pos: [0, 0, 0] }]);

export function bossPartUrl(modelId: string, part: string): string {
  return assetUrl(`assets/enemies/${modelId}/parts/${part}/${part}.glb`);
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
 * Resolve a clip token against the rig's actual clip names, in the
 * /mechanics/enemy-attacks order: exact match, then `*_<token>` suffix.
 * The underscore in the suffix rule keeps short tokens honest (`wat` must
 * not match `claw2wat`). Returns null when nothing resolves.
 */
export function resolveClipToken(clipNames: string[], token: string): string | null {
  if (clipNames.includes(token)) return token;
  return clipNames.find((n) => n.endsWith(`_${token}`)) ?? null;
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
