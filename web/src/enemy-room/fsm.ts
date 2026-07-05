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
  /** kind: 'charge' — segmented st → lp(move) → ed phases (the segments ARE the timeline). */
  charge?: { phase: 'st' | 'lp' | 'ed'; phaseT: number; stDur: number; edDur: number; traveled: number };
  /** kind: 'leap' — travel from → target during the damaging window, AoE at landing. */
  leap?: { from: Vec2; target: Vec2 };
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
  // Quadruped archetype (spec /states/enemies §quadruped): arc-only approach
  // with an stt dash-charge as the only straight-line movement.
  chaseMode: 'arc' | 'dash';
  arcSide: 1 | -1;
  arcTimer: number;
  // Ranged deliveries in flight (quad_machine etc.) — stepped every tick.
  projectiles: Projectile[];
  lobs: Lob[];
  /** Aggro threat display hold (bigrig_combo stt chest-beat): seconds remaining. */
  threatTimer: number;
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
  | { type: 'attack_end'; attack: AttackDef }
  | { type: 'projectile_fired'; attack: AttackDef }
  | { type: 'lob_fired'; attack: AttackDef; at: Vec2 }
  | { type: 'lob_landed'; attack: AttackDef; at: Vec2 }
  | { type: 'leap_landed'; attack: AttackDef; at: Vec2 };

/** Straight projectile in flight (kind: 'projectile') — hits on contact. */
export interface Projectile {
  pos: Vec2;
  dir: Vec2;
  traveled: number;
  maxRange: number;
  attack: AttackDef;
}

/** Grenade in flight (kind: 'lob') — area damage at `target` when it lands. */
export interface Lob {
  from: Vec2;
  target: Vec2;
  timer: number;
  flightTime: number;
  attack: AttackDef;
}

export const PROJECTILE_SPEED = 10.0;
export const PROJECTILE_RADIUS = 0.25;
export const LOB_FLIGHT_TIME = 0.9;

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
    chaseMode: 'arc',
    arcSide: 1,
    arcTimer: 0,
    projectiles: [],
    lobs: [],
    threatTimer: 0,
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
        if (entry.archetype === 'bigrig_combo') {
          // Chest-beat threat (spec §big-rig): stt is this family's threat
          // display — hold position for the clip before pursuing.
          sim.anim = 'stt';
          sim.threatTimer = input.clipDurationFor('stt') ?? 1.0;
        } else {
          sim.anim = 'tht';
        }
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
      // Aggro threat hold (bigrig chest-beat): stand and display, then pursue.
      if (sim.threatTimer > 0) {
        sim.threatTimer -= dt;
        sim.velocity = { x: 0, z: 0 };
        break;
      }
      // Trigger (spec /mechanics/enemy-attacks §selection): cooldown ready AND
      // some attack's band contains the distance. Identical to the old melee
      // gate for all-melee tables (default bands end at attack_range).
      if (
        sim.attackCooldown <= 0 &&
        entry.attacks.some((a) => dist >= a.min_range && dist <= a.max_range)
      ) {
        startAttack(sim, entry, input, dist, events);
        break;
      }
      if (entry.archetype === 'quad_machine') {
        processChasingQuadMachine(sim, entry, input, dist);
        break;
      }
      if (entry.archetype === 'quadruped') {
        processChasingQuadruped(sim, entry, input, dist);
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
      const atk = sim.currentAttack;
      if (!atk) {
        // Shouldn't happen; recover like the #477 contract — never wedge.
        endAttack(sim, entry, events, rng);
        break;
      }
      // Segmented charge (bigrig shoulder slam): its own phase machine —
      // the st/lp/ed segments ARE the timeline (spec §big-rig).
      if ((atk.def.kind ?? 'melee_arc') === 'charge' && atk.charge) {
        processAttackCharge(sim, entry, input, events);
        break;
      }
      sim.velocity = { x: 0, z: 0 };
      atk.t += dt;
      const windowStart = atk.def.windup_frac * atk.duration;
      const windowEnd = atk.def.damage_end_frac * atk.duration;
      if (!atk.windowOpened && atk.t >= windowStart) {
        atk.windowOpened = true;
        events.push({ type: 'window_open', attack: atk.def });
        // Ranged kinds release exactly once, at window open (spec: kind) —
        // resolution then happens at impact/landing, not via the arc test.
        const kind = atk.def.kind ?? 'melee_arc';
        if (kind === 'projectile') {
          atk.resolved = true;
          sim.projectiles.push({
            pos: { ...sim.pos },
            dir: { ...atk.facing },
            traveled: 0,
            maxRange: Math.max(atk.def.hit_reach, 1),
            attack: atk.def,
          });
          events.push({ type: 'projectile_fired', attack: atk.def });
        } else if (kind === 'lob') {
          atk.resolved = true;
          const target = { ...playerPos };
          sim.lobs.push({
            from: { ...sim.pos },
            target,
            timer: LOB_FLIGHT_TIME,
            flightTime: LOB_FLIGHT_TIME,
            attack: atk.def,
          });
          events.push({ type: 'lob_fired', attack: atk.def, at: target });
        } else if (kind === 'leap') {
          // Belly flop: jump to the target's window-open position, landing
          // at window close for AoE (spec §big-rig).
          atk.leap = { from: { ...sim.pos }, target: { ...playerPos } };
        }
      }
      // Leap flight: the enemy itself travels during the window.
      if (atk.leap && atk.windowOpened && !atk.windowClosed) {
        const f = Math.min(Math.max((atk.t - windowStart) / (windowEnd - windowStart), 0), 1);
        sim.pos.x = atk.leap.from.x + (atk.leap.target.x - atk.leap.from.x) * f;
        sim.pos.z = atk.leap.from.z + (atk.leap.target.z - atk.leap.from.z) * f;
      }
      // Damaging window: first arc pass resolves the hit — at most once per
      // attack. Melee only — ranged/leap kinds resolve at impact/landing.
      if (
        (atk.def.kind ?? 'melee_arc') === 'melee_arc' &&
        atk.windowOpened && !atk.windowClosed && !atk.resolved && atk.t <= windowEnd
      ) {
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
        // Leap landing: AoE around the landing point, i-frames at landing.
        if (atk.leap && !atk.resolved) {
          atk.resolved = true;
          sim.pos.x = atk.leap.target.x;
          sim.pos.z = atk.leap.target.z;
          events.push({ type: 'leap_landed', attack: atk.def, at: { ...atk.leap.target } });
          if (len(sub(playerPos, atk.leap.target)) <= atk.def.hit_reach + input.playerRadius) {
            if (input.playerInvincible) {
              events.push({ type: 'hit_dodged', attack: atk.def });
            } else {
              const damage = Math.round(entry.stats.attack_base * atk.def.damage_mult);
              events.push({ type: 'hit', attack: atk.def, damage });
            }
          }
        }
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

  stepDeliveries(sim, entry, input, events);
  return events;
}


/** Step in-flight projectiles and lobs; i-frames are tested at impact/landing. */
function stepDeliveries(sim: EnemySim, entry: ResolvedEntry, input: SimInput, events: SimEvent[]): void {
  const { dt, playerPos, playerRadius, playerInvincible } = input;

  sim.projectiles = sim.projectiles.filter((p) => {
    p.pos.x += p.dir.x * PROJECTILE_SPEED * dt;
    p.pos.z += p.dir.z * PROJECTILE_SPEED * dt;
    p.traveled += PROJECTILE_SPEED * dt;
    const hitDist = playerRadius + PROJECTILE_RADIUS;
    if (len(sub(playerPos, p.pos)) <= hitDist) {
      if (playerInvincible) {
        events.push({ type: 'hit_dodged', attack: p.attack });
      } else {
        const damage = Math.round(entry.stats.attack_base * p.attack.damage_mult);
        events.push({ type: 'hit', attack: p.attack, damage });
      }
      return false;
    }
    return p.traveled < p.maxRange;
  });

  sim.lobs = sim.lobs.filter((l) => {
    l.timer -= dt;
    if (l.timer > 0) return true;
    events.push({ type: 'lob_landed', attack: l.attack, at: l.target });
    // AoE at the landing point: hit_reach is the blast radius.
    if (len(sub(playerPos, l.target)) <= l.attack.hit_reach + playerRadius) {
      if (playerInvincible) {
        events.push({ type: 'hit_dodged', attack: l.attack });
      } else {
        const damage = Math.round(entry.stats.attack_base * l.attack.damage_mult);
        events.push({ type: 'hit', attack: l.attack, damage });
      }
    }
    return false;
  });
}

/**
 * Quadruped circler chase (spec /states/enemies §quadruped, normative):
 * wlk_l/wlk_r rigs have the head turned that way, so the approach MUST arc
 * (never straight at the target) with the clip matching the target's side;
 * the stt dash-charge is the only straight-line movement. First real
 * per-archetype behavior (#494) — extract to archetypes/ when a third lands.
 */
function processChasingQuadruped(sim: EnemySim, entry: ResolvedEntry, input: SimInput, dist: number): void {
  const { dt, playerPos, rng } = input;
  const radial = norm(sub(playerPos, sim.pos));
  const chargeRange = entry.stats.attack_range * entry.fsm.charge_range_mult;

  if (sim.chaseMode !== 'dash' && dist <= chargeRange && sim.attackCooldown <= 0) {
    sim.chaseMode = 'dash';
  }
  if (sim.chaseMode === 'dash' && dist > chargeRange * 1.5) {
    sim.chaseMode = 'arc'; // lost the charge — fall back to circling
  }

  if (sim.chaseMode === 'dash') {
    const speed = entry.stats.move_speed * entry.fsm.charge_speed_mult;
    sim.velocity = { x: radial.x * speed, z: radial.z * speed };
    sim.facing = radial;
    sim.anim = 'stt'; // the dash clip — the ONLY straight-forward locomotion
    return;
  }

  // Arc approach: tangent around the target blended with a gentle inward
  // spiral. Re-pick the side occasionally so circling doesn't look scripted.
  sim.arcTimer -= dt;
  if (sim.arcTimer <= 0) {
    sim.arcTimer = 2.0 + rng() * 3.0;
    if (rng() < 0.35) sim.arcSide = sim.arcSide === 1 ? -1 : 1;
  }
  const tangent: Vec2 = { x: -radial.z * sim.arcSide, z: radial.x * sim.arcSide };
  const dir = norm({ x: tangent.x + radial.x * 0.45, z: tangent.z + radial.z * 0.45 });
  const speed = entry.stats.move_speed * entry.fsm.walk_speed_mult;
  sim.velocity = { x: dir.x * speed, z: dir.z * speed };
  sim.facing = dir;
  // Clip matches geometry: head turned toward the target's side.
  // left-of-facing (y-up) = (facing.z, -facing.x).
  const leftDot = radial.x * dir.z + radial.z * -dir.x;
  sim.anim = leftDot > 0 ? 'wlk_l' : 'wlk_r';
}


/**
 * Quad-machine hover kiter (spec /states/enemies §quad-machine, normative):
 * the body always faces the target; movement is strafing with the clip
 * matching the direction relative to facing (wlk_f close / wlk_b retreat /
 * wlk_l·wlk_r lateral). Holds fsm.standoff_range to stay out of melee reach;
 * retreat is fast (charge mult) — cornering it is the intended counterplay,
 * so there is deliberately NO wall-aware escape routing.
 */
function processChasingQuadMachine(sim: EnemySim, entry: ResolvedEntry, input: SimInput, dist: number): void {
  const { dt, playerPos, rng } = input;
  const radial = norm(sub(playerPos, sim.pos));
  sim.facing = radial; // hover body tracks the target
  const standoff = entry.fsm.standoff_range;

  if (dist < standoff * 0.85) {
    // Too close — back straight out at retreat speed.
    const speed = entry.stats.move_speed * entry.fsm.charge_speed_mult;
    sim.velocity = { x: -radial.x * speed, z: -radial.z * speed };
    sim.anim = 'wlk_b';
    return;
  }
  if (dist > standoff * 1.25) {
    const speed = entry.stats.move_speed * entry.fsm.walk_speed_mult;
    sim.velocity = { x: radial.x * speed, z: radial.z * speed };
    sim.anim = 'wlk_f';
    return;
  }
  // At standoff: lateral strafe, side re-picked on a timer.
  sim.arcTimer -= dt;
  if (sim.arcTimer <= 0) {
    sim.arcTimer = 1.5 + rng() * 2.5;
    if (rng() < 0.4) sim.arcSide = sim.arcSide === 1 ? -1 : 1;
  }
  const tangent: Vec2 = { x: -radial.z * sim.arcSide, z: radial.x * sim.arcSide };
  const speed = entry.stats.move_speed * entry.fsm.walk_speed_mult;
  sim.velocity = { x: tangent.x * speed, z: tangent.z * speed };
  // Movement relative to facing: left-of-facing = (facing.z, -facing.x).
  const leftDot = tangent.x * radial.z + tangent.z * -radial.x;
  sim.anim = leftDot > 0 ? 'wlk_l' : 'wlk_r';
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
  const kind = def.kind ?? 'melee_arc';
  changeState(sim, 'attacking', events);
  sim.chaseMode = 'arc'; // next approach starts as an arc again
  sim.facing = facing;

  if (kind === 'charge') {
    // Segmented st → lp(move) → ed; the segments ARE the timeline.
    const stDur = input.clipDurationFor(`${def.clip}_st`) ?? 0.4;
    const edDur = input.clipDurationFor(`${def.clip}_ed`) ?? 0.4;
    const chargeSpeed = entry.stats.move_speed * entry.fsm.charge_speed_mult;
    const lpMax = Math.max(def.max_range, 1) / chargeSpeed;
    sim.anim = `${def.clip}_st`;
    sim.currentAttack = {
      def,
      duration: stDur + lpMax + edDur, // estimate, for the HUD
      resolvedClip: `${def.clip}_lp`,
      t: 0,
      facing,
      resolved: false,
      windowOpened: false,
      windowClosed: false,
      charge: { phase: 'st', phaseT: 0, stDur, edDur, traveled: 0 },
    };
    sim.attackCooldown = entry.stats.attack_cooldown;
    events.push({ type: 'attack_start', attack: def, resolvedClip: `${def.clip}_lp`, duration: sim.currentAttack.duration });
    return;
  }

  const clipDuration = input.clipDurationFor(def.clip);
  // No resolvable clip → the timeline fractions apply to the fallback
  // duration (extends the #477 attack-recovery contract).
  const duration = clipDuration ?? entry.fsm.attack_fallback_duration;
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

/**
 * Charge attack phases (bigrig shoulder slam, spec §big-rig): st windup
 * (stationary) → lp loop charging forward along the locked facing, hitting
 * on first contact (dodge lets it pass and keep going), capped at max_range
 * of travel → ed recovery (stationary) → loafing.
 */
function processAttackCharge(sim: EnemySim, entry: ResolvedEntry, input: SimInput, events: SimEvent[]): void {
  const { dt, playerPos, rng } = input;
  const atk = sim.currentAttack!;
  const c = atk.charge!;
  atk.t += dt;
  c.phaseT += dt;

  switch (c.phase) {
    case 'st': {
      sim.velocity = { x: 0, z: 0 };
      sim.anim = `${atk.def.clip}_st`;
      if (c.phaseT >= c.stDur) {
        c.phase = 'lp';
        c.phaseT = 0;
        atk.windowOpened = true;
        sim.anim = `${atk.def.clip}_lp`;
        events.push({ type: 'window_open', attack: atk.def });
      }
      break;
    }
    case 'lp': {
      const speed = entry.stats.move_speed * entry.fsm.charge_speed_mult;
      sim.velocity = { x: atk.facing.x * speed, z: atk.facing.z * speed };
      c.traveled += speed * dt;
      sim.anim = `${atk.def.clip}_lp`;
      let endCharge = false;
      if (!atk.resolved) {
        const contact = arcHitTest(
          sim.pos, atk.facing, playerPos, input.playerRadius,
          atk.def.hit_half_angle_deg, atk.def.hit_reach,
        );
        if (contact) {
          atk.resolved = true;
          if (input.playerInvincible) {
            // Dodged — the slam passes by and keeps going.
            events.push({ type: 'hit_dodged', attack: atk.def });
          } else {
            const damage = Math.round(entry.stats.attack_base * atk.def.damage_mult);
            events.push({ type: 'hit', attack: atk.def, damage });
            endCharge = true; // slam connected
          }
        }
      }
      if (c.traveled >= Math.max(atk.def.max_range, 1) || c.phaseT > 8) {
        endCharge = true;
      }
      if (endCharge) {
        c.phase = 'ed';
        c.phaseT = 0;
        atk.windowClosed = true;
        events.push({ type: 'window_close', attack: atk.def });
      }
      break;
    }
    case 'ed': {
      sim.velocity = { x: 0, z: 0 };
      sim.anim = `${atk.def.clip}_ed`;
      if (c.phaseT >= c.edDur) {
        endAttack(sim, entry, events, rng);
      }
      break;
    }
  }
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
