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
import type { BossPhase, ResolvedBoss, ResolvedBossAttack } from './types';

export type BossStateName = 'intro' | 'active' | 'attacking' | 'relocate' | 'punish' | 'dead';

export const PLAYER_RADIUS = 0.4;
export const MELEE_STOP_RANGE = 3.5;
export const BEAM_TICK_INTERVAL = 0.4;
export const CHARGE_SPEED_MULT = 2.0;
export const CHARGE_STOP_RANGE = 2.0;
export const PROJECTILE_SPEED = 12.0;
export const PROJECTILE_RADIUS = 0.5;
export const PROJECTILE_LIFE = 4.0;
export const LOB_FLIGHT_TIME = 1.2;
export const LOB_SPLIT_RADIUS = 3.0;
export const FLY_AWAY_DIST = 15.0;
export const CLIMB_TIME = 1.0;
export const LAND_TIME = 0.8;
/** Fallback duration when a clip token doesn't resolve (enemy model's attack_fallback_duration). */
export const FALLBACK_CLIP_DURATION = 0.8;

export type BossEvent =
  | { type: 'anim'; tokens: string[]; loop: boolean; lpLoops?: number }
  | { type: 'player-hit'; damage: number; via: string; knockback?: Vec2 }
  | { type: 'state'; state: BossStateName }
  | { type: 'enrage' }
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
  mode: 'climb' | 'away' | 'return' | 'land';
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
  enraged: boolean;
  current: CurrentAttack | null;
  fly: FlightState | null;
  projectiles: SimProjectile[];
  lobs: SimLob[];
  /** Token of the loop clip currently requested (dedupes anim events). */
  loopToken: string | null;
  introDone: boolean;
}

export function makeBossSim(entry: ResolvedBoss, pos: Vec2, yaw: number): BossSim {
  return {
    state: 'intro',
    stateT: 0,
    pos: { ...pos },
    alt: 0,
    yaw,
    hp: entry.stats.hp,
    maxHp: entry.stats.hp,
    cooldown: 1.0, // grace before the first attack
    sinceFlight: 0,
    punishAccum: 0,
    enraged: false,
    current: null,
    fly: null,
    projectiles: [],
    lobs: [],
    loopToken: null,
    introDone: false,
  };
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
  // player's position at that moment.
  while (cur.shotTimes.length > 0 && cur.t >= cur.shotTimes[0]) {
    cur.shotTimes.shift();
    const dx = input.player.x - sim.pos.x;
    const dz = input.player.z - sim.pos.z;
    const d = Math.hypot(dx, dz) || 1;
    sim.projectiles.push({ pos: { ...sim.pos }, dir: { x: dx / d, z: dz / d }, age: 0, damage, via: cur.atk.id });
  }

  const inWindow = cur.t >= cur.windowStart && cur.t <= cur.windowEnd;
  if (inWindow && cur.atk.kind !== 'projectile') {
    if (cur.atk.kind === 'beam_sweep') {
      cur.beamTick -= input.dt;
      if (cur.beamTick <= 0 && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach + cur.atk.max_range * 0.5)) {
        events.push(hitEvent(cur.atk, damage, cur.facing));
        cur.beamTick = BEAM_TICK_INTERVAL;
      }
    } else if (!cur.didHit && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach)) {
      events.push(hitEvent(cur.atk, damage, cur.facing));
      cur.didHit = true;
    }
  }
  if (cur.t >= cur.total) {
    sim.current = null;
    sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
    setState(sim, 'active', events);
  }
}

function stepActive(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  sim.cooldown -= input.dt;

  // Flight cycle: interval elapsed + the table has flight-phase attacks.
  const hasFlight = entry.attacks.some((a) => a.phases?.includes('flight'));
  if (hasFlight && entry.fsm.flight_interval > 0) {
    sim.sinceFlight += input.dt;
    if (sim.sinceFlight >= entry.fsm.flight_interval) {
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

  if (dist > MELEE_STOP_RANGE) {
    const speed = entry.stats.move_speed * mods(sim, entry).speed;
    sim.pos.x += facing.x * speed * input.dt;
    sim.pos.z += facing.z * speed * input.dt;
    ensureLoop(sim, 'wlk1', events);
  } else {
    ensureLoop(sim, 'wat', events);
  }
}

function stepRelocate(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const fly = sim.fly;
  if (!fly) {
    setState(sim, 'active', events);
    return;
  }
  const flySpeed = entry.stats.move_speed * entry.fsm.fly_speed_mult * mods(sim, entry).speed;
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
      if (!sim.introDone) {
        sim.introDone = true;
        playOnce(sim, ['tht'], events);
      }
      if (sim.stateT >= dur(input, 'tht')) setState(sim, 'active', events);
      break;
    }
    case 'active':
      stepActive(sim, entry, input, events);
      break;
    case 'attacking':
      stepAttacking(sim, entry, input, events);
      break;
    case 'relocate':
      stepRelocate(sim, entry, input, events);
      break;
    case 'punish': {
      if (sim.stateT >= dur(input, entry.fsm.punish_clip)) {
        sim.punishAccum = 0;
        sim.cooldown = entry.stats.attack_cooldown * mods(sim, entry).cooldown;
        setState(sim, 'active', events);
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
  const phase = enragePhase(entry);
  if (!sim.enraged && phase?.hp_frac !== undefined && sim.hp / sim.maxHp <= phase.hp_frac) {
    sim.enraged = true;
    events.push({ type: 'enrage' });
    // The growl replaces the current grounded animation; airborne it only tints.
    if (sim.state === 'active') playOnce(sim, ['tht'], events);
  }
  if ((sim.state === 'active' || sim.state === 'attacking') && entry.fsm.punish_break_damage > 0) {
    sim.punishAccum += amount;
    if (sim.punishAccum >= entry.fsm.punish_break_damage) {
      sim.current = null;
      playOnce(sim, [entry.fsm.punish_clip], events);
      setState(sim, 'punish', events);
    }
  }
  return events;
}
