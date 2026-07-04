/**
 * Enemy FSM simulation — pure TS port of scripts/3d/enemies/enemy_base.gd
 * (IDLE/CHASING/ATTACKING/LOAFING/HURT) plus the frame-tied attack model
 * from spec /mechanics/enemy-attacks. This module is the normative
 * reference the spec cites for attack selection (selectAttack) and the
 * hit shape (arcHitTest).
 *
 * Deliberate divergences from the Godot runtime (flat-arena sandbox):
 * no nav-mesh, no floor rays, no stuck detection, no status effects,
 * no DEAD state (the sandbox enemy is immortal; HURT is entered via an
 * explicit applyHurt call — the debug "Hit enemy" button).
 *
 * Zero three.js imports — unit-testable with a seeded rng.
 */

import type { AttackDef, ResolvedEntry } from './types';

export interface Vec2 {
  x: number;
  z: number;
}

export type EnemyStateName = 'idle' | 'chasing' | 'attacking' | 'loafing' | 'hurt';

export interface CurrentAttack {
  def: AttackDef;
  /** Timeline length: resolved clip duration, or fsm.attack_fallback_duration when no clip resolves. */
  duration: number;
  /** Resolved full clip name ('' = none resolved → fallback duration in use). */
  resolvedClip: string;
  /** Seconds into the attack. */
  t: number;
  /** Facing locked at attack start (spec: facing MUST be locked). */
  facing: Vec2;
  /** A hit or dodge has been resolved — no further tests this attack. */
  resolved: boolean;
  windowOpened: boolean;
  windowClosed: boolean;
}

export interface EnemySim {
  state: EnemyStateName;
  pos: Vec2;
  facing: Vec2;
  velocity: Vec2;
  attackCooldown: number;
  hurtTimer: number;
  wanderTimer: number;
  wanderDir: Vec2 | null; // null = paused
  loafTimer: number;
  loafDir: Vec2;
  loafCurveRate: number;
  currentAttack: CurrentAttack | null;
  /** Animation token the UI should play (wat/wlk/run/dmg or the attack clip token). */
  anim: string;
}

export interface SimInput {
  dt: number;
  playerPos: Vec2;
  playerRadius: number;
  /** True during dodge i-frames (player.gd:247 DODGE_IFRAME_DURATION 0.2s). */
  playerInvincible: boolean;
  /** Seedable random source in [0,1) — mulberry32 in tests, Math.random in the UI. */
  rng: () => number;
  /** Resolved clip duration in seconds for an attack token, null if the rig has no such clip. */
  clipDurationFor: (token: string) => number | null;
}

export type SimEvent =
  | { type: 'state_change'; from: EnemyStateName; to: EnemyStateName }
  | { type: 'attack_start'; attack: AttackDef; resolvedClip: string; duration: number }
  | { type: 'window_open'; attack: AttackDef }
  | { type: 'hit'; attack: AttackDef; damage: number }
  | { type: 'hit_dodged'; attack: AttackDef }
  | { type: 'window_close'; attack: AttackDef }
  | { type: 'attack_end'; attack: AttackDef };

// enemy_base.gd wander/loaf constants (not per-enemy data)
const WANDER_INTERVAL_MIN = 2.0;
const WANDER_INTERVAL_MAX = 5.0;
const WANDER_PAUSE_CHANCE = 0.3;
const WANDER_SPEED_MULT = 0.5;
const LOAF_SPEED_MULT = 0.5;
const LOAF_CURVE_RATE = 0.8;

export function makeSim(pos: Vec2 = { x: 0, z: 0 }): EnemySim {
  return {
    state: 'idle',
    pos: { ...pos },
    facing: { x: 0, z: 1 },
    velocity: { x: 0, z: 0 },
    attackCooldown: 0,
    hurtTimer: 0,
    wanderTimer: 0,
    wanderDir: null,
    loafTimer: 0,
    loafDir: { x: 0, z: 1 },
    loafCurveRate: LOAF_CURVE_RATE,
    currentAttack: null,
    anim: 'wat',
  };
}

const len = (v: Vec2) => Math.hypot(v.x, v.z);
const sub = (a: Vec2, b: Vec2): Vec2 => ({ x: a.x - b.x, z: a.z - b.z });
const norm = (v: Vec2): Vec2 => {
  const l = len(v);
  return l > 1e-6 ? { x: v.x / l, z: v.z / l } : { x: 0, z: 1 };
};
const rot = (v: Vec2, rad: number): Vec2 => ({
  x: v.x * Math.cos(rad) - v.z * Math.sin(rad),
  z: v.x * Math.sin(rad) + v.z * Math.cos(rad),
});

/**
 * Attack selection (spec /mechanics/enemy-attacks §selection):
 * candidates = attacks whose [min_range, max_range] contains dist;
 * weighted-random pick among candidates; empty candidate set → the
 * attack whose band is nearest to dist. Never null for non-empty input.
 */
export function selectAttack(attacks: AttackDef[], dist: number, rng: () => number): AttackDef | null {
  if (attacks.length === 0) return null;
  const candidates = attacks.filter((a) => dist >= a.min_range && dist <= a.max_range);
  if (candidates.length === 0) {
    let best = attacks[0];
    let bestGap = Infinity;
    for (const a of attacks) {
      const gap = dist < a.min_range ? a.min_range - dist : dist - a.max_range;
      if (gap < bestGap) {
        bestGap = gap;
        best = a;
      }
    }
    return best;
  }
  const total = candidates.reduce((s, a) => s + Math.max(a.weight, 0), 0);
  if (total <= 0) return candidates[0];
  let roll = rng() * total;
  for (const a of candidates) {
    roll -= Math.max(a.weight, 0);
    if (roll <= 0) return a;
  }
  return candidates[candidates.length - 1];
}

/**
 * Hit shape (spec /mechanics/enemy-attacks §hit-shape): flat arc, apex at
 * the enemy origin, facing locked at attack start; hits when XZ distance
 * ≤ reach + target radius AND the angle to the target ≤ half-angle.
 * Deliberately simpler than the player weapon cone (no apex pull-back,
 * no vertical bound).
 */
export function arcHitTest(
  enemyPos: Vec2,
  facing: Vec2,
  targetPos: Vec2,
  targetRadius: number,
  halfAngleDeg: number,
  reach: number,
): boolean {
  const to = sub(targetPos, enemyPos);
  const dist = len(to);
  if (dist > reach + targetRadius) return false;
  if (dist < 1e-6) return true; // standing inside the enemy
  const dir = norm(to);
  const dot = dir.x * facing.x + dir.z * facing.z;
  const angle = (Math.acos(Math.min(Math.max(dot, -1), 1)) * 180) / Math.PI;
  return angle <= halfAngleDeg + 1e-9; // epsilon: boundary is inclusive, acos jitters

}

/** External hurt (the sandbox "Hit enemy" button) — mirrors _on_hit_received's stagger path. */
export function applyHurt(sim: EnemySim, entry: ResolvedEntry): SimEvent[] {
  const events: SimEvent[] = [];
  if (sim.state === 'attacking' && sim.currentAttack) {
    events.push({ type: 'attack_end', attack: sim.currentAttack.def });
  }
  sim.currentAttack = null;
  changeState(sim, 'hurt', events);
  sim.hurtTimer = entry.fsm.hurt_duration;
  sim.velocity = { x: 0, z: 0 };
  sim.anim = 'dmg';
  return events;
}

function changeState(sim: EnemySim, to: EnemyStateName, events: SimEvent[]): void {
  if (sim.state === to) return;
  events.push({ type: 'state_change', from: sim.state, to });
  sim.state = to;
}

/** One simulation tick. Mutates sim; returns the events this tick produced. */
export function stepEnemy(sim: EnemySim, entry: ResolvedEntry, input: SimInput): SimEvent[] {
  const events: SimEvent[] = [];
  const { dt, playerPos, rng } = input;
  const dist = len(sub(playerPos, sim.pos));

  if (sim.attackCooldown > 0) sim.attackCooldown -= dt;

  switch (sim.state) {
    case 'idle': {
      if (dist <= entry.stats.detection_range) {
        changeState(sim, 'chasing', events);
        sim.anim = 'tht';
        break;
      }
      sim.wanderTimer -= dt;
      if (sim.wanderTimer <= 0) {
        sim.wanderTimer = WANDER_INTERVAL_MIN + rng() * (WANDER_INTERVAL_MAX - WANDER_INTERVAL_MIN);
        if (rng() < WANDER_PAUSE_CHANCE) {
          sim.wanderDir = null;
        } else {
          const angle = rng() * Math.PI * 2;
          sim.wanderDir = { x: Math.sin(angle), z: Math.cos(angle) };
        }
      }
      if (sim.wanderDir) {
        const speed = entry.stats.move_speed * WANDER_SPEED_MULT;
        sim.velocity = { x: sim.wanderDir.x * speed, z: sim.wanderDir.z * speed };
        sim.facing = { ...sim.wanderDir };
        sim.anim = 'wlk';
      } else {
        sim.velocity = { x: 0, z: 0 };
        sim.anim = 'wat';
      }
      break;
    }

    case 'chasing': {
      if (dist <= entry.stats.attack_range && sim.attackCooldown <= 0) {
        startAttack(sim, entry, input, dist, events);
        break;
      }
      const chargeRange = entry.stats.attack_range * entry.fsm.charge_range_mult;
      const charging = dist <= chargeRange;
      const speed =
        entry.stats.move_speed * (charging ? entry.fsm.charge_speed_mult : entry.fsm.walk_speed_mult);
      const dir = norm(sub(playerPos, sim.pos));
      sim.velocity = { x: dir.x * speed, z: dir.z * speed };
      sim.facing = dir;
      sim.anim = charging ? 'run' : 'wlk';
      break;
    }

    case 'attacking': {
      sim.velocity = { x: 0, z: 0 };
      const atk = sim.currentAttack;
      if (!atk) {
        // Shouldn't happen; recover like the #477 contract — never wedge.
        endAttack(sim, entry, events, rng);
        break;
      }
      atk.t += dt;
      const windowStart = atk.def.windup_frac * atk.duration;
      const windowEnd = atk.def.damage_end_frac * atk.duration;
      if (!atk.windowOpened && atk.t >= windowStart) {
        atk.windowOpened = true;
        events.push({ type: 'window_open', attack: atk.def });
      }
      // Damaging window: first arc pass resolves the hit — at most once per attack.
      if (atk.windowOpened && !atk.windowClosed && !atk.resolved && atk.t <= windowEnd) {
        const inArc = arcHitTest(
          sim.pos,
          atk.facing,
          playerPos,
          input.playerRadius,
          atk.def.hit_half_angle_deg,
          atk.def.hit_reach,
        );
        if (inArc) {
          atk.resolved = true;
          if (input.playerInvincible) {
            events.push({ type: 'hit_dodged', attack: atk.def });
          } else {
            const damage = Math.round(entry.stats.attack_base * atk.def.damage_mult);
            events.push({ type: 'hit', attack: atk.def, damage });
          }
        }
      }
      if (!atk.windowClosed && atk.t > windowEnd) {
        atk.windowClosed = true;
        events.push({ type: 'window_close', attack: atk.def });
      }
      if (atk.t >= atk.duration) {
        endAttack(sim, entry, events, rng);
      }
      break;
    }

    case 'loafing': {
      sim.loafTimer -= dt;
      if (sim.loafTimer <= 0) {
        changeState(sim, 'chasing', events);
        break;
      }
      sim.loafDir = rot(sim.loafDir, sim.loafCurveRate * dt);
      const speed = entry.stats.move_speed * LOAF_SPEED_MULT;
      sim.velocity = { x: sim.loafDir.x * speed, z: sim.loafDir.z * speed };
      sim.facing = { ...sim.loafDir };
      sim.anim = 'wlk';
      break;
    }

    case 'hurt': {
      sim.hurtTimer -= dt;
      sim.velocity = { x: 0, z: 0 };
      if (sim.hurtTimer <= 0) {
        changeState(sim, 'chasing', events);
      }
      break;
    }
  }

  sim.pos.x += sim.velocity.x * dt;
  sim.pos.z += sim.velocity.z * dt;
  return events;
}

function startAttack(
  sim: EnemySim,
  entry: ResolvedEntry,
  input: SimInput,
  dist: number,
  events: SimEvent[],
): void {
  const def = selectAttack(entry.attacks, dist, input.rng);
  if (!def) return; // resolveEntry guarantees ≥1 attack; guard anyway
  const facing = norm(sub(input.playerPos, sim.pos));
  const clipDuration = input.clipDurationFor(def.clip);
  // No resolvable clip → the timeline fractions apply to the fallback
  // duration (extends the #477 attack-recovery contract).
  const duration = clipDuration ?? entry.fsm.attack_fallback_duration;
  changeState(sim, 'attacking', events);
  sim.facing = facing;
  sim.anim = def.clip;
  sim.currentAttack = {
    def,
    duration,
    resolvedClip: clipDuration !== null ? def.clip : '',
    t: 0,
    facing,
    resolved: false,
    windowOpened: false,
    windowClosed: false,
  };
  sim.attackCooldown = entry.stats.attack_cooldown;
  events.push({ type: 'attack_start', attack: def, resolvedClip: sim.currentAttack.resolvedClip, duration });
}

function endAttack(sim: EnemySim, entry: ResolvedEntry, events: SimEvent[], rng: () => number): void {
  if (sim.currentAttack) {
    events.push({ type: 'attack_end', attack: sim.currentAttack.def });
  }
  sim.currentAttack = null;
  changeState(sim, 'loafing', events);
  sim.loafTimer =
    entry.fsm.loaf_duration_min + rng() * (entry.fsm.loaf_duration_max - entry.fsm.loaf_duration_min);
  // Perpendicular retreat curving back away, mirroring _start_loafing.
  const side = rng() > 0.5 ? 1 : -1;
  const away = rot(sim.facing, Math.PI);
  sim.loafDir = rot(away, (side * Math.PI) / 2);
  sim.loafCurveRate = -side * LOAF_CURVE_RATE;
  sim.anim = 'wlk';
}
