/**
 * Boss behavior sim (spec /states/bosses, DRAFT) — the runnable form of the
 * boss_arenas.json v2 tables, dragon-first. Implements the shared skeleton:
 *
 *   INTRO → ACTIVE ⇄ ATTACKING, ACTIVE → RELOCATE (flight cycle) → ACTIVE,
 *   damage break → PUNISH → ACTIVE, HP 0 → DEAD
 *
 * Attack selection and the melee hit shape are the enemy room's normative
 * functions (spec: boss tables reuse /mechanics/enemy-attacks — same rules,
 * not a parallel model). Chain timeline per the spec: every clip before the
 * last is pure telegraph; windup_frac / damage_end_frac apply to the release
 * clip. beam_sweep approximates the sweep as a wide arc ticked during the
 * window (0.4 s between ticks).
 *
 * Pure state machine: no three.js, no DOM — clip durations come in through
 * the input, animation/damage go out as events. Unit-tested directly.
 */
import { arcHitTest, selectAttack, type Vec2 } from '../enemy-room/fsm';
import type { ResolvedBoss, ResolvedBossAttack } from './types';

export type BossStateName = 'intro' | 'active' | 'attacking' | 'relocate' | 'punish' | 'dead';

export const PLAYER_RADIUS = 0.4;
export const MELEE_STOP_RANGE = 3.5;
export const BEAM_TICK_INTERVAL = 0.4;
export const FLY_CONTACT_RANGE = 2.0;
export const FLY_PASS_OVERSHOOT = 12.0;
export const CLIMB_TIME = 1.0;
export const LAND_TIME = 0.8;
/** Fallback duration when a clip token doesn't resolve (enemy model's attack_fallback_duration). */
export const FALLBACK_CLIP_DURATION = 0.8;

export type BossEvent =
  | { type: 'anim'; tokens: string[]; loop: boolean }
  | { type: 'player-hit'; damage: number; via: string }
  | { type: 'state'; state: BossStateName }
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
}

interface FlightState {
  mode: 'climb' | 'pass' | 'land';
  target: Vec2;
  passesLeft: number;
  hitThisPass: boolean;
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
  current: CurrentAttack | null;
  fly: FlightState | null;
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
    current: null,
    fly: null,
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

function playOnce(sim: BossSim, tokens: string[], events: BossEvent[]) {
  sim.loopToken = null;
  events.push({ type: 'anim', tokens, loop: false });
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

/** Attacks available in the current grounded phase (spec: omitted gate = all). */
function groundedAttacks(entry: ResolvedBoss): ResolvedBossAttack[] {
  const groundId = entry.phases[0]?.id;
  return entry.attacks.filter(
    (a) => a.kind !== 'fly_pass' && (!a.phases || (groundId !== undefined && a.phases.includes(groundId))),
  );
}

function flyPassAttack(entry: ResolvedBoss): ResolvedBossAttack | null {
  return entry.attacks.find((a) => a.kind === 'fly_pass') ?? null;
}

function beginAttack(sim: BossSim, entry: ResolvedBoss, atk: ResolvedBossAttack, input: BossSimInput, events: BossEvent[]) {
  const tokens = atk.chain ?? [atk.clip];
  // Chain timeline (spec /states/bosses): telegraph = everything before the
  // release clip; the timeline fractions apply to the release clip only.
  // lp tokens loop — the visual side loops them; the sim charges one rep
  // (draft simplification, noted in the panel).
  const telegraph = tokens.slice(0, -1).reduce((s, t) => s + dur(input, t), 0);
  const release = dur(input, tokens[tokens.length - 1]);
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
  };
  playOnce(sim, tokens, events);
  setState(sim, 'attacking', events);
}

function stepAttacking(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  const cur = sim.current;
  if (!cur) {
    setState(sim, 'active', events);
    return;
  }
  cur.t += input.dt;
  const inWindow = cur.t >= cur.windowStart && cur.t <= cur.windowEnd;
  const damage = entry.stats.attack_base * cur.atk.damage_mult;
  if (inWindow) {
    if (cur.atk.kind === 'beam_sweep') {
      cur.beamTick -= input.dt;
      if (cur.beamTick <= 0 && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach + cur.atk.max_range * 0.5)) {
        events.push({ type: 'player-hit', damage, via: cur.atk.id });
        cur.beamTick = BEAM_TICK_INTERVAL;
      }
    } else if (!cur.didHit && arcHitTest(sim.pos, cur.facing, input.player, PLAYER_RADIUS, cur.atk.hit_half_angle_deg, cur.atk.hit_reach)) {
      events.push({ type: 'player-hit', damage, via: cur.atk.id });
      cur.didHit = true;
    }
  }
  if (cur.t >= cur.total) {
    sim.current = null;
    sim.cooldown = entry.stats.attack_cooldown;
    setState(sim, 'active', events);
  }
}

function stepActive(sim: BossSim, entry: ResolvedBoss, input: BossSimInput, events: BossEvent[]) {
  sim.cooldown -= input.dt;

  // Flight cycle: interval elapsed + the table has a fly_pass attack.
  const pass = flyPassAttack(entry);
  if (pass && entry.fsm.flight_interval > 0) {
    sim.sinceFlight += input.dt;
    if (sim.sinceFlight >= entry.fsm.flight_interval) {
      sim.fly = { mode: 'climb', target: { ...input.player }, passesLeft: entry.fsm.flight_passes, hitThisPass: false };
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
    sim.pos.x += facing.x * entry.stats.move_speed * input.dt;
    sim.pos.z += facing.z * entry.stats.move_speed * input.dt;
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
  const climbSpeed = entry.fsm.hover_height / CLIMB_TIME;
  if (fly.mode === 'climb') {
    sim.alt = Math.min(entry.fsm.hover_height, sim.alt + climbSpeed * input.dt);
    if (sim.alt >= entry.fsm.hover_height) {
      fly.mode = 'pass';
      const dir = turnToward(sim, input.player, 1e9, 1);
      fly.target = { x: input.player.x + dir.x * FLY_PASS_OVERSHOOT, z: input.player.z + dir.z * FLY_PASS_OVERSHOOT };
      fly.hitThisPass = false;
      ensureLoop(sim, 'fly', events);
    }
    return;
  }
  if (fly.mode === 'pass') {
    const facing = turnToward(sim, fly.target, entry.stats.turn_speed_deg * 3, input.dt);
    const speed = entry.stats.move_speed * entry.fsm.fly_speed_mult;
    sim.pos.x += facing.x * speed * input.dt;
    sim.pos.z += facing.z * speed * input.dt;
    const pass = flyPassAttack(entry);
    if (pass && !fly.hitThisPass && distXZ(sim.pos, input.player) <= FLY_CONTACT_RANGE + PLAYER_RADIUS) {
      events.push({ type: 'player-hit', damage: entry.stats.attack_base * pass.damage_mult, via: pass.id });
      fly.hitThisPass = true;
    }
    if (distXZ(sim.pos, fly.target) < 1.5) {
      fly.passesLeft -= 1;
      if (fly.passesLeft > 0) {
        const dir = turnToward(sim, input.player, 1e9, 1);
        fly.target = { x: input.player.x + dir.x * FLY_PASS_OVERSHOOT, z: input.player.z + dir.z * FLY_PASS_OVERSHOOT };
        fly.hitThisPass = false;
      } else {
        fly.mode = 'land';
        playOnce(sim, ['gld2claw', 'claw2wat'], events);
      }
    }
    return;
  }
  // land
  sim.alt = Math.max(0, sim.alt - (entry.fsm.hover_height / LAND_TIME) * input.dt);
  if (sim.alt <= 0) {
    sim.fly = null;
    sim.sinceFlight = 0;
    sim.cooldown = entry.stats.attack_cooldown;
    setState(sim, 'active', events);
  }
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
        sim.cooldown = entry.stats.attack_cooldown;
        setState(sim, 'active', events);
      }
      break;
    }
    case 'dead':
      break;
  }
  return events;
}

/**
 * Player damage into the boss. Punish accumulation only while grounded and
 * fighting (draft: airborne passes don't build the break — note in the room).
 * Damage during PUNISH is multiplied (enemy model's recovery_vulnerable_mult).
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
