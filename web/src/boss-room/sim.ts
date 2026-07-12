/**
 * Boss behavior sim (spec /states/bosses, DRAFT) — the runnable form of the
 * boss_arenas.json v2 tables, dragon-first. Implements the shared skeleton:
 *
 *   INTRO → ACTIVE ⇄ ATTACKING, ACTIVE → RELOCATE (flight cycle) → ACTIVE,
 *   damage break → PUNISH → ACTIVE, HP 0 → DEAD
 *
 * plus the observed Reyburn patterns: melee arcs (bite / tail swipe), the
 * wing-flap knockback, the war-cry blast circle, a standing fireball volley
 * (one projectile per lp rep), the rush-bite charge, the fly-away → landing
 * slam cycle with the sky cluster-fireball, and the low-HP enrage modifier
 * (growl + red edges + speed/cooldown multipliers from the enrage phase).
 *
 * Attack selection and the arc hit shape are the enemy room's normative
 * functions (spec: boss tables reuse /mechanics/enemy-attacks — same rules,
 * not a parallel model). Chain timeline per the spec: every clip before the
 * last is pure telegraph; windup_frac / damage_end_frac apply to the release
 * clip; lp tokens repeat lp_loops times.
 *
 * Pure state machine: no three.js, no DOM — clip durations come in through
 * the input, animation/damage go out as events. Unit-tested directly.
 */
import { arcHitTest, selectAttack, type Vec2 } from '../enemy-room/fsm';
import { GEM_COLORS, type BossPhase, type GemColor, type ResolvedBoss, type ResolvedBossAttack } from './types';

export type BossStateName = 'intro' | 'active' | 'attacking' | 'loaf' | 'relocate' | 'punish' | 'dead';

export const PLAYER_RADIUS = 0.4;
export const MELEE_STOP_RANGE = 3.5;
/** Post-attack disengage walk speed (× move_speed) — the enemy model's loaf. */
export const LOAF_SPEED_MULT = 0.6;
/** Max random deviation from straight-away for the loaf direction (radians). */
export const LOAF_SPREAD = (2 * Math.PI) / 3;
export const LOAF_CURVE_MAX = 0.4; // rad/s drift of the loaf path (gentle arc, never a curl-back)
export const BEAM_TICK_INTERVAL = 0.4;
export const CHARGE_SPEED_MULT = 2.0;
export const CHARGE_STOP_RANGE = 2.0;
export const PROJECTILE_SPEED = 12.0;
export const PROJECTILE_RADIUS = 0.5;
export const PROJECTILE_LIFE = 4.0;
/** kind: projectile with split — half-spread of the fan (dark falz's diffusion). */
export const PROJECTILE_FAN_DEG = 25.0;
export const LOB_FLIGHT_TIME = 1.2;
export const LOB_SPLIT_RADIUS = 3.0;
export const FLY_AWAY_DIST = 15.0;
export const CLIMB_TIME = 1.0;
export const LAND_TIME = 0.8;
export const SINK_TIME = 1.0;
/** kind: grab — damage tick cadence and per-tick fraction of the attack's damage. */
export const GRAB_TICK_INTERVAL = 0.6;
export const GRAB_TICK_FRAC = 0.4;
/** Submerge relocation fallback (no authored anchors): resurface this far from the player. */
export const RELOCATE_FALLBACK_RADIUS = 10.0;
/** Fallback duration when a clip token doesn't resolve (enemy model's attack_fallback_duration). */
export const FALLBACK_CLIP_DURATION = 0.8;

export type BossEvent =
  | { type: 'anim'; tokens: string[]; loop: boolean; lpLoops?: number }
  | { type: 'player-hit'; damage: number; via: string; knockback?: Vec2 }
  | { type: 'state'; state: BossStateName }
  | { type: 'enrage' }
  | { type: 'boss-heal'; amount: number }
  | { type: 'teleport' }
  | { type: 'died' };

export interface BossSimInput {
  dt: number;
  player: Vec2;
  /** Resolved clip duration for a token, or null when the rig has no match. */
  clipDur: (token: string) => number | null;
  rng: () => number;
}

interface CurrentAttack {
  atk: ResolvedBossAttack;
  t: number;
  windowStart: number;
  windowEnd: number;
  total: number;
  facing: Vec2;
  didHit: boolean;
  beamTick: number;
  /** kind: projectile — remaining firing times (one shot per lp rep). */
  shotTimes: number[];
}

export interface SimProjectile {
  pos: Vec2;
  dir: Vec2;
  age: number;
  damage: number;
  via: string;
}

export interface SimLob {
  target: Vec2;
  t: number;
  split: number;
  reach: number;
  damage: number;
  via: string;
}

interface FlightState {
  mode: 'climb' | 'away' | 'return' | 'land' | 'sink' | 'swim' | 'rise';
  target: Vec2;
  attacksLeft: number;
}

export interface BossSim {
  state: BossStateName;
  stateT: number;
  pos: Vec2;
  /** Altitude offset above the floor (flight); 0 while grounded. */
  alt: number;
  yaw: number;
  hp: number;
  maxHp: number;
  cooldown: number;
  sinceFlight: number;
  punishAccum: number;
  /** Attacks since last rest (surfacing / fatigue punish) — drives the fatigue trigger. */
  attacksSinceRest: number;
  punishCause: 'break' | 'fatigue' | null;
  /** Knockdown chain progress (humilias: fall → fallwat loop → stdup). */
  punishPhase: 'start' | 'loop' | 'end' | null;
  enraged: boolean;
  /** Loaf (post-attack disengage): time left, walk direction, curve drift. */
  loafT: number;
  loafDir: Vec2;
  loafCurve: number;
  current: CurrentAttack | null;
  fly: FlightState | null;
  projectiles: SimProjectile[];
  lobs: SimLob[];
  /** Gem caster (Chaos Sorcerer): the two held gems (null = empty slot). */
  gems: [GemColor | null, GemColor | null];
  gemRespawnT: number;
  sinceTeleport: number;
  /** Gem caster: the gem currently being cast — spins in front, then vanishes at release. */
  castingGem: GemColor | null;
  /** Token of the loop clip currently requested (dedupes anim events). */
  loopToken: string | null;
  introDone: boolean;
}

export function makeBossSim(entry: ResolvedBoss, pos: Vec2, yaw: number, rng: () => number = Math.random): BossSim {
  // Gem caster opens with two distinct gems from the colors its attacks use.
  let gems: [GemColor | null, GemColor | null] = [null, null];
  if (entry.fsm.gem_caster) {
    const pool = gemPool(entry);
    const first = pickFrom(pool, rng);
    const second = pickFrom(pool.filter((c) => c !== first), rng);
    gems = [first, second];
  }
  return {
    state: 'intro',
    stateT: 0,
    pos: { ...pos },
    alt: entry.fsm.hover_hold ?? 0, // gem caster / hoverers start aloft
    yaw,
    hp: entry.stats.hp,
    maxHp: entry.stats.hp,
    cooldown: 1.0, // grace before the first attack
    sinceFlight: 0,
    punishAccum: 0,
    attacksSinceRest: 0,
    punishCause: null,
    punishPhase: null,
    enraged: false,
    loafT: 0,
    loafDir: { x: 0, z: 1 },
    loafCurve: 0,
    current: null,
    fly: null,
    projectiles: [],
    lobs: [],
    gems,
    gemRespawnT: 0,
    sinceTeleport: 0,
    castingGem: null,
    loopToken: null,
    introDone: false,
  };
}

/** Gem colors the boss's attacks actually use (so refills stay in-kit). */
function gemPool(entry: ResolvedBoss): GemColor[] {
  const used = new Set<GemColor>();
  for (const a of entry.attacks) if (a.gem) used.add(a.gem);
  return used.size ? [...used] : GEM_COLORS;
}

function pickFrom<T>(arr: T[], rng: () => number): T {
  return arr[Math.min(arr.length - 1, Math.floor(rng() * arr.length))];
}

const dur = (input: BossSimInput, token: string) => input.clipDur(token) ?? FALLBACK_CLIP_DURATION;

function ensureLoop(sim: BossSim, token: string, events: BossEvent[]) {
  if (sim.loopToken === token) return;
  sim.loopToken = token;
  events.push({ type: 'anim', tokens: [token], loop: true });
}

function playOnce(sim: BossSim, tokens: string[], events: BossEvent[], lpLoops?: number) {
  sim.loopToken = null;
  events.push({ type: 'anim', tokens, loop: false, ...(lpLoops !== undefined ? { lpLoops } : {}) });
}

function setState(sim: BossSim, state: BossStateName, events: BossEvent[]) {
  sim.state = state;
  sim.stateT = 0;
  events.push({ type: 'state', state });
}

/** Yaw toward a target, capped by turn speed. Returns the facing vector. */
function turnToward(sim: BossSim, target: Vec2, turnSpeedDeg: number, dt: number): Vec2 {
  const dx = target.x - sim.pos.x;
  const dz = target.z - sim.pos.z;
  if (dx * dx + dz * dz > 1e-9) {
    const desired = Math.atan2(dx, dz);
    let diff = desired - sim.yaw;
    while (diff > Math.PI) diff -= 2 * Math.PI;
    while (diff < -Math.PI) diff += 2 * Math.PI;
    const cap = (turnSpeedDeg * Math.PI / 180) * dt;
    sim.yaw += Math.abs(diff) <= cap ? diff : Math.sign(diff) * cap;
  }
  return { x: Math.sin(sim.yaw), z: Math.cos(sim.yaw) };
}

const distXZ = (a: Vec2, b: Vec2) => Math.hypot(a.x - b.x, a.z - b.z);

/** The modifier phase (enrage): any hp_frac phase carrying multipliers. */
export function enragePhase(entry: ResolvedBoss): BossPhase | null {
  return entry.phases.find((p) => p.hp_frac !== undefined && (p.speed_mult !== undefined || p.cooldown_mult !== undefined)) ?? null;
}

function mods(sim: BossSim, entry: ResolvedBoss): { speed: number; cooldown: number } {
  const phase = sim.enraged ? enragePhase(entry) : null;
  return { speed: phase?.speed_mult ?? 1, cooldown: phase?.cooldown_mult ?? 1 };
}

/** Attacks available in the current grounded phase (spec: omitted gate = all). */
function groundedAttacks(entry: ResolvedBoss): ResolvedBossAttack[] {
  const groundId = entry.phases[0]?.id;
  return entry.attacks.filter(
    (a) => (!a.phases || (groundId !== undefined && a.phases.includes(groundId))),
  );
}

function flightAttack(entry: ResolvedBoss, kind: string): ResolvedBossAttack | null {
  return entry.attacks.find((a) => a.kind === kind && a.phases?.includes('flight')) ?? null;
}

/** Chain expansion: lp tokens repeat lp_loops times. Returns per-piece durations. */
function chainTiming(atk: ResolvedBossAttack, input: BossSimInput): { telegraph: number; release: number; shotTimes: number[] } {
  const tokens = atk.chain ?? [atk.clip];
  const reps = atk.lp_loops ?? 1;
  let telegraph = 0;
  const shotTimes: number[] = [];
  for (const t of tokens.slice(0, -1)) {
    const d = dur(input, t);
    if (t.endsWith('lp')) {
      for (let i = 0; i < reps; i++) {
        telegraph += d;
        if (atk.kind === 'projectile') shotTimes.push(telegraph); // one shot per lp rep
      }
    } else {
      telegraph += d;
    }
  }
  const release = dur(input, tokens[tokens.length - 1]);
  // Projectile with no lp piece in the chain: single shot at the window open.
  if (atk.kind === 'projectile' && shotTimes.length === 0) shotTimes.push(telegraph + atk.windup_frac * release);
  return { telegraph, release, shotTimes };
}

function beginAttack(sim: BossSim, entry: ResolvedBoss, atk: ResolvedBossAttack, input: BossSimInput, events: BossEvent[]) {
  const tokens = atk.chain ?? [atk.clip];
  const { telegraph, release, shotTimes } = chainTiming(atk, input);
  const facing = turnToward(sim, input.player, 1e9, 1); // face the target at attack start, then lock
  sim.current = {
    atk,
    t: 0,
    windowStart: telegraph + atk.windup_frac * release,
    windowEnd: telegraph + atk.damage_end_frac * release,
    total: telegraph + release,
    facing,
    didHit: false,
    beamTick: 0,
    shotTimes,
  };
  playOnce(sim, tokens, events, atk.lp_loops);
  setState(sim, 'attacking', events);
}

function hitEvent(atk: ResolvedBossAttack, damage: number, facing: Vec2): BossEvent {
  return {
    type: 'player-hit',
    damage,
    via: atk.id,
    ...(atk.knockback ? { knockback: { x: facing.x * atk.knockback, z: facing.z * atk.knockback } } : {}),
  };
}

function stepAttacking(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const cur = sim.current;
  if (!cur) {
    setState(sim, 'active', events);
    return;
  }
  cur.t += input.dt;
  const damage = entry.stats.attack_base * cur.atk.damage_mult;

  // kind: charge — run along the locked facing during the telegraph (the
  // rush), stopping short of the player; the release clip is the bite.
  if (cur.atk.kind === 'charge' && cur.t < cur.windowStart && distXZ(sim.pos, input.player) > CHARGE_STOP_RANGE) {
    const speed = entry.stats.move_speed * CHARGE_SPEED_MULT * mods(sim, entry).speed;
    sim.pos.x += cur.facing.x * speed * input.dt;
    sim.pos.z += cur.facing.z * speed * input.dt;
  }

  // kind: projectile — fire when t crosses each shot time, aimed at the
  // player's position at that moment. `split` fans the shot into that many
  // projectiles spread across ±PROJECTILE_FAN_DEG (dark falz's diffusion).
  while (cur.shotTimes.length > 0 && cur.t >= cur.shotTimes[0]) {
    cur.shotTimes.shift();
    const dx = input.player.x - sim.pos.x;
    const dz = input.player.z - sim.pos.z;
    const aim = Math.atan2(dx, dz);
    const split = cur.atk.split ?? 1;
    for (let i = 0; i < split; i++) {
      const a = aim + (split > 1 ? ((i / (split - 1)) - 0.5) * 2 * (PROJECTILE_FAN_DEG * Math.PI / 180) : 0);
      sim.projectiles.push({ pos: { ...sim.pos }, dir: { x: Math.sin(a), z: Math.cos(a) }, age: 0, damage, via: cur.atk.id });
    }
  }

  const inWindow = cur.t >= cur.windowStart && cur.t <= cur.windowEnd;
  // Gem caster: the casting gem vanishes as the spell releases (window open).
  if (sim.castingGem && cur.t >= cur.windowStart) sim.castingGem = null;
  if (inWindow && cur.atk.kind !== 'projectile') {
    if (cur.atk.kind === 'heal') {
      // Green gem (Chaos Sorcerer): self-heal once at the window open. Interrupting
      // is a follow-up (damaging mid-cast should cancel it); for now it lands.
      if (!cur.didHit) {
        cur.didHit = true;
        const amount = Math.round(sim.maxHp * (cur.atk.damage_mult >= 1 ? 0.15 : cur.atk.damage_mult));
        sim.hp = Math.min(sim.maxHp, sim.hp + amount);
        events.push({ type: 'boss-heal', amount });
      }
    } else if (cur.atk.kind === 'lob') {
      // Ground-fired lob (octo diablo's vomit): released once at window open,
      // aimed at the player's position at release.
      if (!cur.didHit) {
        cur.didHit = true;
        sim.lobs.push({
          target: { ...input.player },
          t: LOB_FLIGHT_TIME,
          split: cur.atk.split ?? 1,
          reach: cur.atk.hit_reach,
          damage,
          via: cur.atk.id,
        });
      }
    } else if (cur.atk.kind === 'beam_sweep' || cur.atk.kind === 'spout') {
      // Sustained jet: ticked wide arc (spout is the position-locked variant).
      cur.beamTick -= input.dt;
      if (cur.beamTick <= 0 && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach + cur.atk.max_range * 0.5)) {
        events.push(hitEvent(cur.atk, damage, cur.facing));
        cur.beamTick = BEAM_TICK_INTERVAL;
      }
    } else if (cur.atk.kind === 'grab') {
      // Hold: damage ticks while the player stays in reach; damaging the
      // boss during the hold cancels it (see damageBoss).
      cur.beamTick -= input.dt;
      if (cur.beamTick <= 0 && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach)) {
        events.push(hitEvent(cur.atk, damage * GRAB_TICK_FRAC, cur.facing));
        cur.beamTick = GRAB_TICK_INTERVAL;
      }
    } else if (!cur.didHit && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach)) {
      events.push(hitEvent(cur.atk, damage, cur.facing));
      cur.didHit = true;
    }
  }
  if (cur.t >= cur.total) {
    sim.current = null;
    sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
    endAttack(sim, entry, input, events);
  }
}

/** Attack resolved: count it toward fatigue, then rest (tired) or disengage. */
function endAttack(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  sim.attacksSinceRest += 1;
  if (entry.fsm.fatigue_attacks > 0 && sim.attacksSinceRest >= entry.fsm.fatigue_attacks) {
    beginPunish(sim, entry, 'fatigue', events);
    return;
  }
  // The gem caster doesn't loaf-walk — its post-cast cooldown IS the rest,
  // and the spent gem refills during it (see stepGemCaster).
  if (entry.fsm.gem_caster) {
    setState(sim, 'active', events);
    return;
  }
  beginLoaf(sim, entry, input, events);
}

/**
 * Punish entry — the spec's punish window, in all three observed shapes:
 * a one-shot reaction (reyburn's dmg1), a timed loop (octo diablo's wattir
 * tired idle), and the full knockdown chain (humilias: fall one-shot →
 * fallwat loop → stdup one-shot recovery).
 */
function beginPunish(sim: BossSim, entry: ResolvedBoss, cause: 'break' | 'fatigue', events: BossEvent[]) {
  sim.current = null;
  sim.punishCause = cause;
  if (entry.fsm.punish_start_clip !== '') {
    sim.punishPhase = 'start';
    playOnce(sim, [entry.fsm.punish_start_clip], events);
  } else {
    enterPunishLoop(sim, entry, events);
  }
  setState(sim, 'punish', events);
}

function enterPunishLoop(sim: BossSim, entry: ResolvedBoss, events: BossEvent[]) {
  sim.punishPhase = 'loop';
  if (entry.fsm.punish_duration > 0) {
    sim.loopToken = null;
    ensureLoop(sim, entry.fsm.punish_clip, events);
  } else {
    playOnce(sim, [entry.fsm.punish_clip], events);
  }
}

/** Chain boundaries in punish stateT time: [start end, loop end, total]. */
function punishTimes(entry: ResolvedBoss, input: BossSimInput): [number, number, number] {
  const startLen = entry.fsm.punish_start_clip !== '' ? dur(input, entry.fsm.punish_start_clip) : 0;
  const loopLen = entry.fsm.punish_duration > 0 ? entry.fsm.punish_duration : dur(input, entry.fsm.punish_clip);
  const endLen = entry.fsm.punish_end_clip !== '' ? dur(input, entry.fsm.punish_end_clip) : 0;
  return [startLen, startLen + loopLen, startLen + loopLen + endLen];
}

/**
 * Post-attack disengage (the enemy model's LOAFING, spec /states/enemies):
 * walk away from the player on a slowly curving path for a few seconds so
 * the fight breathes — without it the boss camps the player between
 * cooldowns and a downed player never gets to stand up. Enrage shortens it
 * via the phase's cooldown_mult (more aggressive = less breathing room).
 */
function beginLoaf(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const { loaf_duration_min: min, loaf_duration_max: max } = entry.fsm;
  sim.loafT = (min + input.rng() * Math.max(0, max - min)) * mods(sim, entry).cooldown;
  // Straight away from the player, deflected by a random spread.
  const dx = sim.pos.x - input.player.x;
  const dz = sim.pos.z - input.player.z;
  const away = Math.atan2(dx, dz) + (input.rng() - 0.5) * LOAF_SPREAD;
  sim.loafDir = { x: Math.sin(away), z: Math.cos(away) };
  sim.loafCurve = (input.rng() - 0.5) * 2 * LOAF_CURVE_MAX;
  setState(sim, 'loaf', events);
}

function stepLoaf(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  sim.cooldown -= input.dt; // cooldown keeps ticking while it wanders
  sim.loafT -= input.dt;
  if (sim.loafT <= 0) {
    setState(sim, 'active', events);
    return;
  }
  // A rooted boss can't walk off — its breathing room is a rest beat in place.
  if (entry.fsm.stationary) {
    ensureLoop(sim, entry.fsm.idle_clip, events);
    return;
  }
  // Curving drift, walking where it faces.
  const rot = sim.loafCurve * input.dt;
  const { x, z } = sim.loafDir;
  sim.loafDir = { x: x * Math.cos(rot) + z * Math.sin(rot), z: -x * Math.sin(rot) + z * Math.cos(rot) };
  sim.yaw = Math.atan2(sim.loafDir.x, sim.loafDir.z);
  const speed = entry.stats.move_speed * LOAF_SPEED_MULT * mods(sim, entry).speed;
  sim.pos.x += sim.loafDir.x * speed * input.dt;
  sim.pos.z += sim.loafDir.z * speed * input.dt;
  ensureLoop(sim, entry.fsm.walk_clip, events);
}

/** The attack for a held gem color (Chaos Sorcerer). */
function attackForGem(entry: ResolvedBoss, gem: GemColor): ResolvedBossAttack | undefined {
  return entry.attacks.find((a) => a.gem === gem);
}

/**
 * Chaos Sorcerer's turn (the resting/ready phase between casts): hover in
 * place, refill the spent gem during the cooldown, occasionally teleport, and
 * when the cooldown is up cast the spell of ONE of the two held gems. The two
 * gems telegraph the two possible next spells (the player can't tell which
 * fires). Casting sends its gem to the "casting" slot — it spins in front and
 * vanishes as the spell releases (see stepAttacking) — leaving one side gem;
 * a new gem then respawns during the cooldown to bring it back to two.
 */
function stepGemCaster(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  // Hold altitude and face the player without moving (mostly static).
  sim.alt = entry.fsm.hover_hold;
  turnToward(sim, input.player, entry.stats.turn_speed_deg, input.dt);
  ensureLoop(sim, entry.fsm.idle_clip, events);

  // Respawn phase: a slot is empty after a cast. Wait gem_respawn_delay, then
  // refill it (a color distinct from the held one) and START the telegraph
  // window before the next cast — so the two gems are BOTH visible for
  // gem_cast_delay seconds before the sorcerer picks one. The next-cast timer
  // only begins once the gem is back, never overlapping the respawn.
  if (sim.gems.includes(null)) {
    sim.gemRespawnT -= input.dt;
    if (sim.gemRespawnT <= 0) {
      const other = sim.gems.find(Boolean);
      const options = gemPool(entry).filter((c) => c !== other);
      const slot = sim.gems.indexOf(null);
      sim.gems[slot] = pickFrom(options.length ? options : gemPool(entry), input.rng);
      sim.cooldown = entry.fsm.gem_cast_delay; // telegraph window before casting
    }
  }

  // Teleport reposition on its own timer.
  if (entry.fsm.teleport_interval > 0) {
    sim.sinceTeleport += input.dt;
    if (sim.sinceTeleport >= entry.fsm.teleport_interval) {
      sim.sinceTeleport = 0;
      const a = input.rng() * 2 * Math.PI;
      const r = entry.fsm.teleport_radius * (0.4 + 0.6 * input.rng());
      sim.pos = { x: Math.cos(a) * r, z: Math.sin(a) * r };
      events.push({ type: 'teleport' });
    }
  }

  // Cast a held gem once the cooldown is up AND both gems are present (so the
  // two-option telegraph is shown before every cast). The chosen gem leaves
  // its side slot for the casting animation.
  const held = sim.gems.filter(Boolean) as GemColor[];
  if (sim.cooldown <= 0 && held.length >= 2) {
    // 50/50 coin flip: either held gem may fire — the player can't predict which.
    const gem = pickFrom(held, input.rng);
    const atk = attackForGem(entry, gem);
    if (atk) {
      sim.gems[sim.gems.indexOf(gem)] = null;
      sim.castingGem = gem;
      sim.gemRespawnT = entry.fsm.gem_respawn_delay;
      beginAttack(sim, entry, atk, input, events);
    }
  }
}

function stepActive(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  sim.cooldown -= input.dt;

  // Gem caster (Chaos Sorcerer): hovers, refills spent gems, teleports, and
  // selects its attack by a held gem rather than by range bands.
  if (entry.fsm.gem_caster) {
    stepGemCaster(sim, entry, input, events);
    return;
  }

  // Relocation cycle on the interval: the dragon's flight (needs its
  // flight-phase attacks) or a timer-driven submerge (dark falz's swim —
  // the octopus relocates via its fatigue cycle instead, interval 0).
  const hasFlight = entry.attacks.some((a) => a.phases?.includes('flight'));
  if (entry.fsm.flight_interval > 0 && (entry.fsm.relocate_kind === 'submerge' || hasFlight)) {
    sim.sinceFlight += input.dt;
    if (sim.sinceFlight >= entry.fsm.flight_interval) {
      if (entry.fsm.relocate_kind === 'submerge') {
        beginSubmerge(sim, entry, input, events);
        return;
      }
      const away = turnToward(sim, input.player, 1e9, 1);
      sim.fly = {
        mode: 'climb',
        target: { x: sim.pos.x - away.x * FLY_AWAY_DIST, z: sim.pos.z - away.z * FLY_AWAY_DIST },
        attacksLeft: entry.fsm.flight_attacks,
      };
      playOnce(sim, ['flst'], events);
      setState(sim, 'relocate', events);
      return;
    }
  }

  const dist = distXZ(sim.pos, input.player);
  const facing = turnToward(sim, input.player, entry.stats.turn_speed_deg, input.dt);

  // Spec trigger: cooldown ready AND some grounded attack's band contains dist.
  const attacks = groundedAttacks(entry);
  if (sim.cooldown <= 0 && attacks.some((a) => dist >= a.min_range && dist <= a.max_range)) {
    // selectAttack only reads weight/min_range/max_range; the boss `kind`
    // string is wider than the enemy AttackKind union, hence the cast.
    const atk = selectAttack(attacks as unknown as Parameters<typeof selectAttack>[0], dist, input.rng) as ResolvedBossAttack | null;
    if (atk) {
      beginAttack(sim, entry, atk, input, events);
      return;
    }
  }

  if (!entry.fsm.stationary && dist > MELEE_STOP_RANGE) {
    const speed = entry.stats.move_speed * mods(sim, entry).speed;
    sim.pos.x += facing.x * speed * input.dt;
    sim.pos.z += facing.z * speed * input.dt;
    ensureLoop(sim, entry.fsm.walk_clip, events);
  } else {
    ensureLoop(sim, entry.fsm.idle_clip, events);
  }
}

/**
 * Submerge relocation (octo diablo): sink below the floor, swim to the next
 * surfacing spot — an authored anchor when they exist, else a fallback point
 * around the player — and rise. Untargetable throughout when
 * relocate_untargetable is set.
 */
function beginSubmerge(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const spots = entry.anchors.filter((a) => distXZ({ x: a.pos[0], z: a.pos[2] }, sim.pos) > 2);
  let target: Vec2;
  if (spots.length > 0) {
    const pick = spots[Math.min(spots.length - 1, Math.floor(input.rng() * spots.length))];
    target = { x: pick.pos[0], z: pick.pos[2] };
  } else {
    const a = input.rng() * 2 * Math.PI;
    target = { x: input.player.x + Math.cos(a) * RELOCATE_FALLBACK_RADIUS, z: input.player.z + Math.sin(a) * RELOCATE_FALLBACK_RADIUS };
  }
  sim.fly = { mode: 'sink', target, attacksLeft: 0 };
  sim.sinceFlight = 0;
  sim.loopToken = null;
  ensureLoop(sim, entry.fsm.relocate_loop_clip, events);
  setState(sim, 'relocate', events);
}

function stepRelocate(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const fly = sim.fly;
  if (!fly) {
    setState(sim, 'active', events);
    return;
  }
  const flySpeed = entry.stats.move_speed * entry.fsm.fly_speed_mult * mods(sim, entry).speed;
  // — submerge-swim modes (octo diablo) —
  if (fly.mode === 'sink') {
    sim.alt = Math.max(-entry.fsm.submerge_depth, sim.alt - (entry.fsm.submerge_depth / SINK_TIME) * input.dt);
    if (sim.alt <= -entry.fsm.submerge_depth) fly.mode = 'swim';
    return;
  }
  if (fly.mode === 'swim') {
    const facing = turnToward(sim, fly.target, entry.stats.turn_speed_deg * 3, input.dt);
    sim.pos.x += facing.x * flySpeed * input.dt;
    sim.pos.z += facing.z * flySpeed * input.dt;
    if (distXZ(sim.pos, fly.target) < 1.5) fly.mode = 'rise';
    return;
  }
  if (fly.mode === 'rise') {
    sim.alt = Math.min(0, sim.alt + (entry.fsm.submerge_depth / SINK_TIME) * input.dt);
    if (sim.alt >= 0) {
      sim.fly = null;
      sim.attacksSinceRest = 0;
      sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
      sim.loopToken = null;
      ensureLoop(sim, entry.fsm.idle_clip, events);
      setState(sim, 'active', events);
    }
    return;
  }
  // — flight modes (reyburn) —
  if (fly.mode === 'climb') {
    sim.alt = Math.min(entry.fsm.hover_height, sim.alt + (entry.fsm.hover_height / CLIMB_TIME) * input.dt);
    if (sim.alt >= entry.fsm.hover_height) {
      fly.mode = 'away';
      ensureLoop(sim, 'fly', events);
    }
    return;
  }
  if (fly.mode === 'away') {
    const facing = turnToward(sim, fly.target, entry.stats.turn_speed_deg * 3, input.dt);
    sim.pos.x += facing.x * flySpeed * input.dt;
    sim.pos.z += facing.z * flySpeed * input.dt;
    if (distXZ(sim.pos, fly.target) < 2) {
      // The airborne attack (sky cluster-fireball) fires from the far point.
      const lob = flightAttack(entry, 'lob');
      if (lob && fly.attacksLeft > 0) {
        fly.attacksLeft -= 1;
        sim.lobs.push({
          target: { ...input.player },
          t: LOB_FLIGHT_TIME,
          split: lob.split ?? 1,
          reach: lob.hit_reach,
          damage: entry.stats.attack_base * lob.damage_mult,
          via: lob.id,
        });
        playOnce(sim, [lob.clip], events);
        sim.loopToken = null;
      }
      fly.mode = 'return';
    }
    return;
  }
  if (fly.mode === 'return') {
    const facing = turnToward(sim, input.player, entry.stats.turn_speed_deg * 3, input.dt);
    sim.pos.x += facing.x * flySpeed * input.dt;
    sim.pos.z += facing.z * flySpeed * input.dt;
    ensureLoop(sim, 'fly', events);
    if (distXZ(sim.pos, input.player) < 4) {
      fly.mode = 'land';
      playOnce(sim, ['gld2claw', 'claw2wat'], events);
    }
    return;
  }
  // land — touch down, then the landing slam circle.
  sim.alt = Math.max(0, sim.alt - (entry.fsm.hover_height / LAND_TIME) * input.dt);
  if (sim.alt <= 0) {
    const slam = flightAttack(entry, 'aoe_burst');
    if (slam && distXZ(sim.pos, input.player) <= slam.hit_reach + PLAYER_RADIUS) {
      events.push(hitEvent(slam, entry.stats.attack_base * slam.damage_mult, turnToward(sim, input.player, 1e9, 1)));
    }
    sim.fly = null;
    sim.sinceFlight = 0;
    sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
    setState(sim, 'active', events);
  }
}

/** Projectiles + lob payloads fly independently of the boss state. */
function stepOrdnance(sim: BossSim, input: BossSimInput, events: BossEvent[]) {
  for (let i = sim.projectiles.length - 1; i >= 0; i--) {
    const p = sim.projectiles[i];
    p.age += input.dt;
    p.pos.x += p.dir.x * PROJECTILE_SPEED * input.dt;
    p.pos.z += p.dir.z * PROJECTILE_SPEED * input.dt;
    if (distXZ(p.pos, input.player) <= PROJECTILE_RADIUS + PLAYER_RADIUS) {
      events.push({ type: 'player-hit', damage: p.damage, via: p.via });
      sim.projectiles.splice(i, 1);
    } else if (p.age > PROJECTILE_LIFE) {
      sim.projectiles.splice(i, 1);
    }
  }
  for (let i = sim.lobs.length - 1; i >= 0; i--) {
    const l = sim.lobs[i];
    l.t -= input.dt;
    if (l.t > 0) continue;
    // Impact: the payload splits into `split` parts around the target.
    for (const impact of lobImpacts(l)) {
      if (distXZ(impact, input.player) <= l.reach + PLAYER_RADIUS) {
        events.push({ type: 'player-hit', damage: l.damage, via: l.via });
        break; // one hit per lob, not per part
      }
    }
    sim.lobs.splice(i, 1);
  }
}

/** Impact points for a lob: the target plus (split-1) points on a ring around it. */
export function lobImpacts(l: Pick<SimLob, 'target' | 'split'>): Vec2[] {
  const points: Vec2[] = [{ ...l.target }];
  for (let i = 1; i < l.split; i++) {
    const a = (2 * Math.PI * i) / Math.max(1, l.split - 1);
    points.push({ x: l.target.x + Math.cos(a) * LOB_SPLIT_RADIUS, z: l.target.z + Math.sin(a) * LOB_SPLIT_RADIUS });
  }
  return points;
}

export function stepBoss(sim: BossSim, entry: ResolvedBoss, input: BossSimInput): BossEvent[] {
  const events: BossEvent[] = [];
  sim.stateT += input.dt;
  switch (sim.state) {
    case 'intro': {
      if (entry.fsm.intro_clip === '') {
        setState(sim, 'active', events);
        break;
      }
      if (!sim.introDone) {
        sim.introDone = true;
        playOnce(sim, [entry.fsm.intro_clip], events);
      }
      if (sim.stateT >= dur(input, entry.fsm.intro_clip)) setState(sim, 'active', events);
      break;
    }
    case 'active':
      stepActive(sim, entry, input, events);
      break;
    case 'attacking':
      stepAttacking(sim, entry, input, events);
      break;
    case 'loaf':
      stepLoaf(sim, entry, input, events);
      break;
    case 'relocate':
      stepRelocate(sim, entry, input, events);
      break;
    case 'punish': {
      const [startEnd, loopEnd, total] = punishTimes(entry, input);
      if (sim.punishPhase === 'start' && sim.stateT >= startEnd) {
        enterPunishLoop(sim, entry, events);
      } else if (sim.punishPhase === 'loop' && sim.stateT >= loopEnd && entry.fsm.punish_end_clip !== '') {
        sim.punishPhase = 'end';
        playOnce(sim, [entry.fsm.punish_end_clip], events);
      } else if (sim.stateT >= total) {
        const cause = sim.punishCause;
        sim.punishCause = null;
        sim.punishPhase = null;
        sim.punishAccum = 0;
        sim.attacksSinceRest = 0;
        sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
        // The octopus's tired window ends in a submerge-relocate, not a re-engage.
        if (cause === 'fatigue' && entry.fsm.relocate_kind === 'submerge') {
          beginSubmerge(sim, entry, input, events);
        } else {
          setState(sim, 'active', events);
        }
      }
      break;
    }
    case 'dead':
      return events; // ordnance dies with the boss
  }
  stepOrdnance(sim, input, events);
  return events;
}

/**
 * Player damage into the boss. Punish accumulation only while grounded and
 * fighting (draft: airborne passes don't build the break — note in the room).
 * Damage during PUNISH is multiplied (enemy model's recovery_vulnerable_mult).
 * Crossing the enrage phase's hp_frac growls, tints, and applies its
 * multipliers from then on.
 */
export function damageBoss(sim: BossSim, entry: ResolvedBoss, amount: number): BossEvent[] {
  const events: BossEvent[] = [];
  if (sim.state === 'dead') return events;
  // Submerged and untargetable: the hit simply doesn't land.
  if (sim.state === 'relocate' && entry.fsm.relocate_untargetable) return events;
  const mult = sim.state === 'punish' ? entry.fsm.punish_vulnerable_mult : 1;
  sim.hp = Math.max(0, sim.hp - amount * mult);
  if (sim.hp <= 0) {
    sim.current = null;
    sim.fly = null;
    sim.alt = 0;
    playOnce(sim, ['ded'], events);
    setState(sim, 'dead', events);
    events.push({ type: 'died' });
    return events;
  }
  // Grab hold: damaging the boss breaks the grip (octo diablo's *cnc clips).
  const cur = sim.current;
  if (sim.state === 'attacking' && cur?.atk.kind === 'grab' && cur.t >= cur.windowStart) {
    sim.current = null;
    sim.attacksSinceRest += 1;
    sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
    if (cur.atk.cancel_clip) playOnce(sim, [cur.atk.cancel_clip], events);
    setState(sim, 'active', events);
  }
  const phase = enragePhase(entry);
  if (!sim.enraged && phase?.hp_frac !== undefined && sim.hp / sim.maxHp <= phase.hp_frac) {
    sim.enraged = true;
    events.push({ type: 'enrage' });
    // The growl replaces the current grounded animation; airborne it only tints.
    if ((sim.state === 'active' || sim.state === 'loaf') && entry.fsm.intro_clip !== '') {
      playOnce(sim, [entry.fsm.intro_clip], events);
    }
  }
  if ((sim.state === 'active' || sim.state === 'attacking' || sim.state === 'loaf') && entry.fsm.punish_break_damage > 0) {
    sim.punishAccum += amount;
    if (sim.punishAccum >= entry.fsm.punish_break_damage) {
      beginPunish(sim, entry, 'break', events);
    }
  }
  return events;
}
