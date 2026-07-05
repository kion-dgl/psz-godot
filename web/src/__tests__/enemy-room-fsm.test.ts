/**
 * Enemy-room FSM tests — pin the normative algorithms the spec cites
 * (/mechanics/enemy-attacks): attack selection, arc hit shape, and the
 * frame-tied attack timeline. Seeded rng → fully deterministic.
 */
import { describe, it, expect } from 'vitest';
import {
  makeSim,
  stepEnemy,
  selectAttack,
  arcHitTest,
  applyHurt,
  type SimEvent,
  type SimInput,
} from '../enemy-room/fsm';
import { resolveEntry, type AttackDef, type EnemyAttackConfig } from '../enemy-room/types';

/** mulberry32 — tiny seedable PRNG. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const atk = (over: Partial<AttackDef> = {}): AttackDef => ({
  id: 'basic',
  clip: 'atk',
  weight: 1,
  min_range: 0,
  max_range: 2,
  windup_frac: 0.35,
  damage_end_frac: 0.6,
  hit_half_angle_deg: 45,
  hit_reach: 2,
  damage_mult: 1,
  ...over,
});

const config = (attacks: AttackDef[]): EnemyAttackConfig => ({
  schema_version: 1,
  defaults: {
    fsm: {
      walk_speed_mult: 0.5,
      charge_range_mult: 2.0,
      charge_speed_mult: 1.5,
      loaf_duration_min: 2.5,
      loaf_duration_max: 4.0,
      hurt_duration: 0.3,
      attack_fallback_duration: 0.8,
    },
    attack: {
      windup_frac: 0.35,
      damage_end_frac: 0.6,
      hit_half_angle_deg: 45,
      hit_reach: 2,
      damage_mult: 1,
      weight: 1,
      min_range: 0,
      max_range: 999,
    },
  },
  enemies: {
    dummy: {
      stats: { move_speed: 3, attack_range: 2, attack_cooldown: 1.5, detection_range: 15, attack_base: 10 },
      fsm: {},
      attacks,
    },
  },
});

const makeInput = (over: Partial<SimInput> = {}): SimInput => ({
  dt: 1 / 60,
  playerPos: { x: 0, z: 1 },
  playerRadius: 0.4,
  playerInvincible: false,
  rng: mulberry32(0x477),
  clipDurationFor: () => 1.0,
  ...over,
});

const run = (
  sim: ReturnType<typeof makeSim>,
  entry: ReturnType<typeof resolveEntry>,
  input: SimInput,
  seconds: number,
): SimEvent[] => {
  const events: SimEvent[] = [];
  const steps = Math.round(seconds / input.dt);
  for (let i = 0; i < steps; i++) events.push(...stepEnemy(sim, entry, input));
  return events;
};

describe('enemy-room FSM — detection & chase', () => {
  it('promotes idle → chasing when the player enters detection_range', () => {
    const entry = resolveEntry(config([atk()]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const events = run(sim, entry, makeInput({ playerPos: { x: 0, z: 10 } }), 0.1);
    expect(events.some((e) => e.type === 'state_change' && e.to === 'chasing')).toBe(true);
  });

  it('stays idle beyond detection_range', () => {
    const entry = resolveEntry(config([atk()]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    run(sim, entry, makeInput({ playerPos: { x: 0, z: 40 } }), 1.0);
    expect(sim.state).toBe('idle');
  });

  it('walks beyond the charge ring, runs inside it (charge = attack_range × charge_range_mult)', () => {
    const entry = resolveEntry(config([atk()]), 'dummy');
    // Beyond 2 × 2 = 4 → walk at move_speed × 0.5
    const far = makeSim({ x: 0, z: 0 });
    stepEnemy(far, entry, makeInput({ playerPos: { x: 0, z: 10 } })); // → chasing
    stepEnemy(far, entry, makeInput({ playerPos: { x: 0, z: 10 } }));
    expect(far.anim).toBe('wlk');
    expect(Math.hypot(far.velocity.x, far.velocity.z)).toBeCloseTo(3 * 0.5, 5);
    // Inside the ring (but outside attack range) → run at move_speed × 1.5
    const near = makeSim({ x: 0, z: 0 });
    stepEnemy(near, entry, makeInput({ playerPos: { x: 0, z: 3 } }));
    stepEnemy(near, entry, makeInput({ playerPos: { x: 0, z: 3 } }));
    expect(near.anim).toBe('run');
    expect(Math.hypot(near.velocity.x, near.velocity.z)).toBeCloseTo(3 * 1.5, 5);
  });
});

describe('enemy-room FSM — frame-tied attack timeline', () => {
  const setupAttack = (input: SimInput) => {
    const entry = resolveEntry(config([atk()]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    stepEnemy(sim, entry, input); // idle → chasing
    const events = stepEnemy(sim, entry, input); // chasing → attacking
    expect(events.some((e) => e.type === 'attack_start')).toBe(true);
    return { entry, sim };
  };

  it('deals no damage during windup and none after damage_end_frac', () => {
    const input = makeInput(); // player at z=1, inside arc the whole time
    const { entry, sim } = setupAttack(input);
    const events: SimEvent[] = [];
    // Clip duration 1.0s, windup 0.35, window end 0.6.
    for (let t = 0; t < 1.05; t += input.dt) {
      const evs = stepEnemy(sim, entry, input);
      for (const e of evs) {
        if (e.type === 'hit') {
          expect(sim.currentAttack!.t).toBeGreaterThanOrEqual(0.35);
          expect(sim.currentAttack!.t).toBeLessThanOrEqual(0.6 + input.dt);
        }
        events.push(e);
      }
    }
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(1);
    // Ordering: window_open before hit before window_close before attack_end
    const order = events.map((e) => e.type);
    expect(order.indexOf('window_open')).toBeLessThan(order.indexOf('hit'));
    expect(order.indexOf('hit')).toBeLessThan(order.indexOf('window_close'));
    expect(order.indexOf('window_close')).toBeLessThan(order.indexOf('attack_end'));
  });

  it('hits at most once per attack even if the player stays in the arc', () => {
    const input = makeInput();
    const { entry, sim } = setupAttack(input);
    const events = run(sim, entry, input, 1.2);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(1);
  });

  it('damage = attack_base × damage_mult', () => {
    const entry = resolveEntry(config([atk({ damage_mult: 2.5 })]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput();
    stepEnemy(sim, entry, input);
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 1.2);
    const hit = events.find((e) => e.type === 'hit');
    expect(hit && hit.type === 'hit' && hit.damage).toBe(25);
  });

  it('i-frames consume the hit as dodged — no later hit in the same attack', () => {
    const input = makeInput({ playerInvincible: true });
    const { entry, sim } = setupAttack(input);
    // Invincible at first arc pass; then vulnerable for the rest of the window.
    const events: SimEvent[] = [];
    let vulnerableInput = input;
    for (let t = 0; t < 1.2; t += input.dt) {
      events.push(...stepEnemy(sim, entry, vulnerableInput));
      if (events.some((e) => e.type === 'hit_dodged')) {
        vulnerableInput = makeInput({ playerInvincible: false });
      }
    }
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
  });

  it('misses entirely when the player leaves the arc before the window opens', () => {
    const input = makeInput();
    const { entry, sim } = setupAttack(input);
    const awayInput = makeInput({ playerPos: { x: 0, z: 10 } });
    const events = run(sim, entry, awayInput, 1.2);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
    expect(events.some((e) => e.type === 'attack_end')).toBe(true);
  });

  it('applies the timeline to attack_fallback_duration when no clip resolves (#477 layering)', () => {
    const input = makeInput({ clipDurationFor: () => null });
    const { entry, sim } = setupAttack(input);
    expect(sim.currentAttack!.duration).toBeCloseTo(0.8, 5);
    expect(sim.currentAttack!.resolvedClip).toBe('');
    const events = run(sim, entry, input, 1.0);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(1);
    expect(events.some((e) => e.type === 'attack_end')).toBe(true);
    expect(sim.state).toBe('loafing');
  });

  it('cycles attacking → loafing → chasing', () => {
    const input = makeInput();
    const { entry, sim } = setupAttack(input);
    const events = run(sim, entry, makeInput({ playerPos: { x: 0, z: 10 } }), 6.0);
    const changes = events.filter((e) => e.type === 'state_change').map((e) => e.type === 'state_change' && e.to);
    expect(changes).toContain('loafing');
    expect(changes[changes.length - 1]).toBe('chasing');
  });

  it('hurt cancels an in-flight attack and returns to chasing after hurt_duration', () => {
    const input = makeInput();
    const { entry, sim } = setupAttack(input);
    const events = applyHurt(sim, entry);
    expect(events.some((e) => e.type === 'attack_end')).toBe(true);
    expect(sim.state).toBe('hurt');
    run(sim, entry, makeInput({ playerPos: { x: 0, z: 10 } }), 0.35);
    expect(sim.state).toBe('chasing');
  });
});

describe('enemy-room FSM — attack selection', () => {
  const near = atk({ id: 'bite', min_range: 0, max_range: 2, weight: 1 });
  const far = atk({ id: 'lunge', min_range: 2, max_range: 6, weight: 3 });

  it('selects only from attacks whose range band contains the distance', () => {
    const rng = mulberry32(1);
    for (let i = 0; i < 50; i++) {
      expect(selectAttack([near, far], 1.0, rng)!.id).toBe('bite');
      expect(selectAttack([near, far], 5.0, rng)!.id).toBe('lunge');
    }
  });

  it('weights the pick when bands overlap', () => {
    const a = atk({ id: 'a', min_range: 0, max_range: 5, weight: 1 });
    const b = atk({ id: 'b', min_range: 0, max_range: 5, weight: 9 });
    const rng = mulberry32(2);
    let bCount = 0;
    for (let i = 0; i < 1000; i++) if (selectAttack([a, b], 3, rng)!.id === 'b') bCount++;
    expect(bCount).toBeGreaterThan(800);
    expect(bCount).toBeLessThan(980);
  });

  it('falls back to the nearest band when no band contains the distance (never null)', () => {
    const rng = mulberry32(3);
    expect(selectAttack([near, far], 10.0, rng)!.id).toBe('lunge');
    expect(selectAttack([far], 0.5, rng)!.id).toBe('lunge');
    expect(selectAttack([], 1.0, rng)).toBeNull();
  });
});

describe('enemy-room FSM — arc hit shape', () => {
  const origin = { x: 0, z: 0 };
  const facing = { x: 0, z: 1 };

  it('hits inside reach + target radius, misses beyond', () => {
    expect(arcHitTest(origin, facing, { x: 0, z: 2.3 }, 0.4, 45, 2)).toBe(true);
    expect(arcHitTest(origin, facing, { x: 0, z: 2.5 }, 0.4, 45, 2)).toBe(false);
  });

  it('respects the half-angle', () => {
    // 45° off-axis at dist 1: inside a 45° half-angle, outside a 30° one.
    const diag = { x: Math.SQRT1_2, z: Math.SQRT1_2 };
    expect(arcHitTest(origin, facing, diag, 0.0, 45, 2)).toBe(true);
    expect(arcHitTest(origin, facing, diag, 0.0, 30, 2)).toBe(false);
    // Behind the enemy: never hit.
    expect(arcHitTest(origin, facing, { x: 0, z: -1 }, 0.4, 90, 2)).toBe(false);
  });

  it('hits a target standing inside the enemy', () => {
    expect(arcHitTest(origin, facing, origin, 0.4, 10, 2)).toBe(true);
  });
});
