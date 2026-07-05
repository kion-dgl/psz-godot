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
  applyBerserk,
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

describe('enemy-room FSM — quadruped circler (spec /states/enemies §quadruped)', () => {
  const quadConfig = (): EnemyAttackConfig => {
    const c = config([atk()]);
    c.enemies.dummy.archetype = 'quadruped';
    return c;
  };

  it('never walks straight at the target while arcing — velocity stays ≥30° off the radial', () => {
    const entry = resolveEntry(quadConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 9 } }); // outside charge ring (4)
    stepEnemy(sim, entry, input); // idle → chasing
    for (let i = 0; i < 120; i++) {
      stepEnemy(sim, entry, input);
      if (sim.state !== 'chasing' || sim.chaseMode !== 'arc') break;
      const toPlayer = { x: input.playerPos.x - sim.pos.x, z: input.playerPos.z - sim.pos.z
      };
      const tl = Math.hypot(toPlayer.x, toPlayer.z);
      const vl = Math.hypot(sim.velocity.x, sim.velocity.z);
      const cos = (sim.velocity.x * toPlayer.x + sim.velocity.z * toPlayer.z) / (tl * vl);
      const angle = (Math.acos(Math.min(Math.max(cos, -1), 1)) * 180) / Math.PI;
      expect(angle, `tick ${i}: straight-walking at the player`).toBeGreaterThanOrEqual(30);
      expect(['wlk_l', 'wlk_r'], `tick ${i}: anim ${sim.anim}`).toContain(sim.anim);
    }
  });

  it('walk clip matches the side the target is on (head turned toward the player)', () => {
    const entry = resolveEntry(quadConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 9 } });
    stepEnemy(sim, entry, input);
    for (let i = 0; i < 120; i++) {
      stepEnemy(sim, entry, input);
      if (sim.state !== 'chasing' || sim.chaseMode !== 'arc') break;
      const radial = { x: input.playerPos.x - sim.pos.x, z: input.playerPos.z - sim.pos.z };
      const leftDot = radial.x * sim.facing.z + radial.z * -sim.facing.x;
      expect(sim.anim).toBe(leftDot > 0 ? 'wlk_l' : 'wlk_r');
    }
  });

  it('dashes straight with stt inside the charge ring, then attacks', () => {
    const entry = resolveEntry(quadConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 3.5 } }); // inside charge ring, outside attack range
    stepEnemy(sim, entry, input); // idle → chasing
    stepEnemy(sim, entry, input); // chasing tick → dash
    expect(sim.chaseMode).toBe('dash');
    expect(sim.anim).toBe('stt');
    // Dash velocity is parallel to the radial (straight line at the target).
    const toPlayer = { x: 0 - sim.pos.x, z: 3.5 - sim.pos.z };
    const cos =
      (sim.velocity.x * toPlayer.x + sim.velocity.z * toPlayer.z) /
      (Math.hypot(toPlayer.x, toPlayer.z) * Math.hypot(sim.velocity.x, sim.velocity.z));
    expect(cos).toBeGreaterThan(0.999);
    // Dash carries into the attack.
    const events = run(sim, entry, input, 2.0);
    expect(events.some((e) => e.type === 'attack_start')).toBe(true);
  });

  it('non-quadruped entries keep the straight walk/run chase', () => {
    const entry = resolveEntry(config([atk()]), 'dummy'); // simple_melee default
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 9 } });
    stepEnemy(sim, entry, input);
    stepEnemy(sim, entry, input);
    expect(sim.anim).toBe('wlk');
  });
});

describe('enemy-room FSM — quad machine kiter (spec /states/enemies §quad-machine)', () => {
  const shot = atk({ id: 'shot', clip: 'atk', kind: 'projectile', min_range: 3, max_range: 10, hit_half_angle_deg: 8, hit_reach: 10 });
  const grenade = atk({ id: 'grenade', clip: 'atkb', kind: 'lob', min_range: 4, max_range: 12, hit_reach: 1.6, damage_mult: 1.5 });
  const kiterConfig = (attacks: AttackDef[]): EnemyAttackConfig => {
    const c = config(attacks);
    c.enemies.dummy.archetype = 'quad_machine';
    c.enemies.dummy.fsm = { standoff_range: 6 };
    return c;
  };

  it('faces the target while strafing at standoff, clip matching lateral movement', () => {
    const entry = resolveEntry(kiterConfig([shot]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 6 } });
    sim.attackCooldown = 99; // suppress attacks — locomotion under test
    stepEnemy(sim, entry, input); // idle → chasing
    for (let i = 0; i < 60; i++) {
      stepEnemy(sim, entry, input);
      const radial = { x: 0 - sim.pos.x, z: 6 - sim.pos.z };
      const rl = Math.hypot(radial.x, radial.z);
      const facingDot = (sim.facing.x * radial.x + sim.facing.z * radial.z) / rl;
      expect(facingDot, `tick ${i}: body must face the target`).toBeGreaterThan(0.999);
      expect(['wlk_l', 'wlk_r'], `tick ${i}`).toContain(sim.anim);
      // lateral: velocity ⊥ radial
      const vl = Math.hypot(sim.velocity.x, sim.velocity.z);
      const cos = Math.abs((sim.velocity.x * radial.x + sim.velocity.z * radial.z) / (vl * rl));
      expect(cos, `tick ${i}: strafe must be lateral`).toBeLessThan(0.1);
    }
  });

  it('retreats fast with wlk_b when the player closes inside the standoff band', () => {
    const entry = resolveEntry(kiterConfig([shot]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 2 } }); // well inside standoff 6
    sim.attackCooldown = 99;
    stepEnemy(sim, entry, input);
    stepEnemy(sim, entry, input);
    expect(sim.anim).toBe('wlk_b');
    // Moving away from the player, at retreat (charge-mult) speed.
    const away = sim.velocity.z < 0;
    expect(away).toBe(true);
    expect(Math.hypot(sim.velocity.x, sim.velocity.z)).toBeCloseTo(3 * 1.5, 5);
  });

  it('closes with wlk_f when beyond the band', () => {
    const entry = resolveEntry(kiterConfig([shot]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 12 } });
    sim.attackCooldown = 99;
    stepEnemy(sim, entry, input);
    stepEnemy(sim, entry, input);
    expect(sim.anim).toBe('wlk_f');
    expect(sim.velocity.z).toBeGreaterThan(0);
  });

  it('fires a projectile at window open that hits a stationary player exactly once', () => {
    const entry = resolveEntry(kiterConfig([shot]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 6 } });
    stepEnemy(sim, entry, input); // idle → chasing
    const events = run(sim, entry, input, 3.0);
    expect(events.filter((e) => e.type === 'projectile_fired')).toHaveLength(1);
    const hits = events.filter((e) => e.type === 'hit');
    expect(hits).toHaveLength(1);
    expect(hits[0].type === 'hit' && hits[0].damage).toBe(10);
    // Ranged release means the melee arc never resolves a second hit.
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(0);
  });

  it('lobs a grenade that lands on the target point for AoE damage', () => {
    const entry = resolveEntry(kiterConfig([grenade]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 6 } });
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 4.0);
    expect(events.filter((e) => e.type === 'lob_fired')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'lob_landed')).toHaveLength(1);
    const hit = events.find((e) => e.type === 'hit');
    expect(hit && hit.type === 'hit' && hit.damage).toBe(15); // 10 × 1.5
  });

  it('grenade misses when the player leaves the blast radius before landing', () => {
    const entry = resolveEntry(kiterConfig([grenade]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const near = makeInput({ playerPos: { x: 0, z: 6 } });
    stepEnemy(sim, entry, near);
    // step until the lob is in the air, then move the player away
    let events: SimEvent[] = [];
    let guard = 0;
    while (sim.lobs.length === 0 && guard++ < 600) events.push(...stepEnemy(sim, entry, near));
    expect(sim.lobs.length).toBe(1);
    const far = makeInput({ playerPos: { x: 8, z: -6 } });
    events = events.concat(run(sim, entry, far, 1.5));
    expect(events.some((e) => e.type === 'lob_landed')).toBe(true);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
  });

  it('i-frames at projectile impact register as dodged', () => {
    const entry = resolveEntry(kiterConfig([shot]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 6 }, playerInvincible: true });
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 3.0);
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
  });
});

describe('enemy-room FSM — big-rig combo (spec /states/enemies §big-rig)', () => {
  const slam = atk({ id: 'shoulder_slam', clip: 'atk2', kind: 'charge', min_range: 3, max_range: 9, hit_half_angle_deg: 40, hit_reach: 1.4, damage_mult: 1.4 });
  const flop = atk({ id: 'belly_flop', clip: 'atk3', kind: 'leap', min_range: 2.5, max_range: 7, windup_frac: 0.4, damage_end_frac: 0.75, hit_half_angle_deg: 180, hit_reach: 2.0, damage_mult: 1.8 });
  const bigrigConfig = (attacks: AttackDef[]): EnemyAttackConfig => {
    const c = config(attacks);
    c.enemies.dummy.archetype = 'bigrig_combo';
    return c;
  };
  // Segment-aware clip durations: st 0.3s, lp 1.0s (looped), ed 0.4s, else 1.0s.
  const segDurations = (token: string) =>
    token.endsWith('_st') ? 0.3 : token.endsWith('_ed') ? 0.4 : 1.0;

  it('holds the chest-beat threat (stt) on aggro before pursuing', () => {
    const entry = resolveEntry(bigrigConfig([slam]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 10 }, clipDurationFor: segDurations });
    stepEnemy(sim, entry, input); // idle → chasing + threat
    expect(sim.anim).toBe('stt');
    // Held in place for the stt clip (1.0s), then moves.
    const events = run(sim, entry, input, 0.9);
    expect(sim.pos.z).toBeCloseTo(0, 3);
    run(sim, entry, input, 0.3);
    expect(Math.hypot(sim.velocity.x, sim.velocity.z)).toBeGreaterThan(0);
    expect(events.filter((e) => e.type === 'attack_start')).toHaveLength(0);
  });

  it('charge: st windup is stationary, lp charges forward and hits on contact once, ed recovers', () => {
    const entry = resolveEntry(bigrigConfig([slam]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    sim.threatTimer = 0;
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations });
    stepEnemy(sim, entry, input); // idle → chasing (threat)
    sim.threatTimer = 0; // skip the display for this test
    stepEnemy(sim, entry, input); // gate: band 3–9 contains 5 → attacking
    expect(sim.currentAttack?.charge?.phase).toBe('st');
    expect(sim.anim).toBe('atk2_st');
    // st: stationary, no damage
    let events = run(sim, entry, input, 0.29);
    expect(sim.pos.z).toBeCloseTo(0, 2);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
    // lp: charges forward, contact hit ends the charge
    events = run(sim, entry, input, 2.0);
    const hits = events.filter((e) => e.type === 'hit');
    expect(hits).toHaveLength(1);
    expect(hits[0].type === 'hit' && hits[0].damage).toBe(14); // 10 × 1.4
    expect(events.some((e) => e.type === 'window_open')).toBe(true);
    expect(events.some((e) => e.type === 'window_close')).toBe(true);
    expect(sim.pos.z).toBeGreaterThan(2); // actually traveled
    // recovers to loafing (never wedges)
    expect(['loafing', 'chasing']).toContain(sim.state);
  });

  it('charge: a dodged slam passes by and keeps traveling to its max_range', () => {
    const entry = resolveEntry(bigrigConfig([slam]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations, playerInvincible: true });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input); // → attacking (charge)
    const events = run(sim, entry, input, 4.0);
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
    // Traveled well past the player — the slam kept going.
    expect(sim.pos.z).toBeGreaterThan(6);
  });

  it('leap: travels to the window-open target and deals AoE damage on landing', () => {
    const entry = resolveEntry(bigrigConfig([flop]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input); // → attacking (leap)
    const events = run(sim, entry, input, 1.5);
    const landed = events.find((e) => e.type === 'leap_landed');
    expect(landed && landed.type === 'leap_landed' && landed.at.z).toBeCloseTo(5, 5);
    const hit = events.find((e) => e.type === 'hit');
    expect(hit && hit.type === 'hit' && hit.damage).toBe(18); // 10 × 1.8
    // Near the landing point (it loafs away after the attack ends).
    expect(sim.pos.z).toBeGreaterThan(4);
  });

  it('leap: i-frames at landing register as dodged', () => {
    const entry = resolveEntry(bigrigConfig([flop]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations, playerInvincible: true });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 1.5);
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
  });

  it('band gate fires ranged attacks from distance (slam at 5m) without closing to melee', () => {
    const entry = resolveEntry(bigrigConfig([slam]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    const events = stepEnemy(sim, entry, input);
    expect(events.some((e) => e.type === 'attack_start')).toBe(true);
  });
});

describe('enemy-room FSM — flyer combo (spec /states/enemies §flyer)', () => {
  const beak = atk({ id: 'beak', clip: 'atk1', min_range: 0, max_range: 2.2 });
  const flyerConfig = (): EnemyAttackConfig => {
    const c = config([beak]);
    c.enemies.dummy.archetype = 'flyer_combo';
    c.enemies.dummy.fsm = { hover_height: 1.3, standoff_range: 2.5 };
    return c;
  };

  it('takes off on aggro: stt hold while rising to hover height', () => {
    const entry = resolveEntry(flyerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 10 } }); // clip durations 1.0
    stepEnemy(sim, entry, input); // idle → chasing + takeoff
    expect(sim.anim).toBe('stt');
    run(sim, entry, input, 0.5);
    expect(sim.pos.z).toBeCloseTo(0, 3); // held in place
    expect(sim.altitude).toBeGreaterThan(0.3);
    expect(sim.altitude).toBeLessThan(1.3);
    run(sim, entry, input, 0.6);
    expect(sim.altitude).toBeCloseTo(1.3, 1); // airborne
  });

  it('approaches with fly, then hover-orbits with tk at the orbit radius', () => {
    const entry = resolveEntry(flyerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 10 } });
    sim.attackCooldown = 99;
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0; // skip takeoff for locomotion probing
    stepEnemy(sim, entry, input);
    expect(sim.anim).toBe('fly');
    expect(sim.velocity.z).toBeGreaterThan(0); // toward the player
    expect(sim.altitude).toBeCloseTo(1.3, 5); // MUST NOT ground while engaged
    // Now close: orbit
    const near = makeInput({ playerPos: { x: 0, z: sim.pos.z + 2.5 } });
    stepEnemy(sim, entry, near);
    expect(sim.anim).toBe('tk');
    // Lateral: velocity ⊥ radial, facing on the target.
    const vl = Math.hypot(sim.velocity.x, sim.velocity.z);
    expect(Math.abs(sim.velocity.z) / vl).toBeLessThan(0.1);
    expect(sim.facing.z).toBeCloseTo(1, 3);
  });

  it('attacks from the air via the band gate (beak at melee band)', () => {
    const entry = resolveEntry(flyerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 1.5 } });
    stepEnemy(sim, entry, input); // aggro → takeoff hold (1.0s)
    const events = run(sim, entry, input, 1.2); // takeoff completes, gate fires
    expect(events.some((e) => e.type === 'attack_start')).toBe(true);
    expect(sim.altitude).toBeCloseTo(1.3, 1); // still airborne when striking
  });
});

describe('enemy-room FSM — roller (spec /states/enemies §roller)', () => {
  const roll = atk({
    id: 'roll', clip: 'wat3', kind: 'charge',
    charge_segments: { st: 'trf1', lp: 'wat3', ed: 'trf2' },
    stop_on_hit: false, overshoot: 3, knockdown: true, recovery_vulnerable_mult: 2,
    min_range: 3, max_range: 12, hit_half_angle_deg: 35, hit_reach: 1.3, damage_mult: 1.5,
  });
  const rollerConfig = (): EnemyAttackConfig => {
    const c = config([roll]);
    c.enemies.dummy.archetype = 'roller';
    c.enemies.dummy.fsm = { standoff_range: 5 };
    return c;
  };
  const segDurations = (token: string) => (token === 'trf1' ? 0.3 : token === 'trf2' ? 0.6 : 1.0);

  it('walks at medium distance (standoff band) with wlk, facing its movement', () => {
    const entry = resolveEntry(rollerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations });
    sim.attackCooldown = 99;
    stepEnemy(sim, entry, input); // aggro (stt hold)
    expect(sim.anim).toBe('stt');
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input);
    expect(sim.anim).toBe('wlk');
    // In-band → sidling laterally, facing along movement
    const vl = Math.hypot(sim.velocity.x, sim.velocity.z);
    expect(Math.abs(sim.velocity.z) / vl).toBeLessThan(0.15);
    expect(sim.facing.x).toBeCloseTo(sim.velocity.x / vl, 3);
  });

  it('roll plays trf1 → wat3 (traveling) → trf2, bowls THROUGH the player with knockdown, overshoots', () => {
    const entry = resolveEntry(rollerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input); // band 3–12 contains 5 → roll starts
    expect(sim.currentAttack?.charge?.tokens).toEqual({ st: 'trf1', lp: 'wat3', ed: 'trf2' });
    expect(sim.anim).toBe('trf1');
    // Overshoot: travel target = start dist (≈5) + 3.
    expect(sim.currentAttack?.charge?.travelTarget).toBeCloseTo(8, 0);
    const events = run(sim, entry, input, 4.0);
    const hits = events.filter((e) => e.type === 'hit');
    expect(hits).toHaveLength(1);
    expect(hits[0].type === 'hit' && hits[0].attack.knockdown).toBe(true);
    // Rolled THROUGH the player (z≈5) and well past — no stop on hit.
    expect(sim.pos.z).toBeGreaterThan(6.5);
    // Fall-over vulnerability announced when the roll ends.
    const vuln = events.find((e) => e.type === 'vulnerable_open');
    expect(vuln && vuln.type === 'vulnerable_open' && vuln.mult).toBe(2);
    // Sequence: window_open (wat3 travel) before hit before vulnerable_open.
    const order = events.map((e) => e.type);
    expect(order.indexOf('window_open')).toBeLessThan(order.indexOf('hit'));
    expect(order.indexOf('hit')).toBeLessThan(order.indexOf('vulnerable_open'));
  });

  it('an i-frame dodge lets the roll pass without a hit', () => {
    const entry = resolveEntry(rollerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 5 }, clipDurationFor: segDurations, playerInvincible: true });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 4.0);
    expect(events.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
    expect(events.some((e) => e.type === 'vulnerable_open')).toBe(true); // punish window still opens
  });

  it('roller idles standing (wat1), never the mis-aliased stt', () => {
    const entry = resolveEntry(rollerConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 40 } }); // out of detection
    run(sim, entry, input, 6.0);
    expect(sim.state).toBe('idle');
    expect(['wat1', 'wlk']).toContain(sim.anim);
    expect(sim.anim).not.toBe('wat');
  });
});

describe('enemy-room FSM — ape gunner windup_clips (spec /states/enemies §ape-gunner)', () => {
  const punch = atk({
    id: 'charged_punch', clip: 'atckswg', windup_clips: ['atckstt', 'atckwat'],
    min_range: 0, max_range: 2.4, windup_frac: 0.2, damage_end_frac: 0.6,
    hit_half_angle_deg: 55, hit_reach: 2.4, damage_mult: 1.6,
  });
  const apeConfig = (): EnemyAttackConfig => {
    const c = config([punch]);
    c.enemies.dummy.archetype = 'ape_gunner';
    return c;
  };
  // atckstt 0.5s, atckwat 0.7s hold, atckswg 1.0s swing.
  const durations = (token: string) => (token === 'atckstt' ? 0.5 : token === 'atckwat' ? 0.7 : 1.0);

  it('plays the windup chain as pure telegraph, then the swing carries the window', () => {
    const entry = resolveEntry(apeConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 1.5 }, clipDurationFor: durations });
    stepEnemy(sim, entry, input); // aggro → stt hold
    expect(sim.anim).toBe('stt');
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input); // → attacking
    expect(sim.anim).toBe('atckstt');
    expect(sim.currentAttack?.duration).toBeCloseTo(0.5 + 0.7 + 1.0, 5);
    // Through the wind-up (0.5s) into the hold (0.7s): telegraph only.
    let events = run(sim, entry, input, 0.55);
    expect(sim.anim).toBe('atckwat');
    expect(events.filter((e) => e.type === 'hit' || e.type === 'window_open')).toHaveLength(0);
    events = run(sim, entry, input, 0.7);
    expect(sim.anim).toBe('atckswg');
    // Swing: window opens at 1.2 + 0.2×1.0 = 1.4s; one hit, charged damage.
    events = events.concat(run(sim, entry, input, 1.2));
    expect(events.filter((e) => e.type === 'window_open')).toHaveLength(1);
    const hits = events.filter((e) => e.type === 'hit');
    expect(hits).toHaveLength(1);
    expect(hits[0].type === 'hit' && hits[0].damage).toBe(16); // 10 × 1.6
    expect(['loafing', 'chasing']).toContain(sim.state);
  });

  it('no damage is possible during any windup clip even with the player inside the arc', () => {
    const entry = resolveEntry(apeConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 1.0 }, clipDurationFor: durations });
    stepEnemy(sim, entry, input);
    sim.threatTimer = 0;
    stepEnemy(sim, entry, input);
    const events = run(sim, entry, input, 1.15); // all of atckstt + most of atckwat
    expect(events.filter((e) => e.type === 'hit')).toHaveLength(0);
    expect(sim.currentAttack?.windowOpened).toBe(false);
  });
});

describe('enemy-room FSM — box mimic (spec /states/enemies §box-mimic)', () => {
  const strike = atk({ id: 'strike', clip: 'atk', min_range: 0, max_range: 2 });
  const mimicConfig = (): EnemyAttackConfig => {
    const c = config([strike]);
    c.enemies.dummy.archetype = 'box_mimic';
    c.enemies.dummy.fsm = { reveal_range: 3.5 };
    return c;
  };

  it('stays dormant inside detection range but outside reveal range — no wander, boxed pose held', () => {
    const entry = resolveEntry(mimicConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 6 } }); // well inside detection 15
    run(sim, entry, input, 5.0);
    expect(sim.state).toBe('idle');
    expect(sim.pos).toEqual({ x: 0, z: 0 }); // never wanders
    // Disguise pose: stt held at frame 0, or the rare wlk2 sway tell.
    expect(['stt', 'wlk2']).toContain(sim.anim);
    if (sim.anim === 'stt') expect(sim.animHold).toBe(true);
  });

  it('reveals inside reveal_range: stt pop-out hold, then walks on wlk1 and attacks', () => {
    const entry = resolveEntry(mimicConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 3 } });
    const events = run(sim, entry, input, 0.1);
    expect(events.some((e) => e.type === 'state_change' && e.to === 'chasing')).toBe(true);
    expect(sim.anim).toBe('stt');
    expect(sim.animHold).toBe(false); // the reveal PLAYS, not held
    expect(sim.threatTimer).toBeGreaterThan(0);
    const later = run(sim, entry, input, 2.0);
    expect(later.some((e) => e.type === 'attack_start')).toBe(true);
  });

  it('reveal-cancel: backing off mid-reveal plays tk2 and returns to the disguise, then re-reveals', () => {
    const entry = resolveEntry(mimicConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const near = makeInput({ playerPos: { x: 0, z: 3 } });
    stepEnemy(sim, entry, near); // reveal starts (hold 1.0s)
    expect(sim.state).toBe('chasing');
    const far = makeInput({ playerPos: { x: 0, z: 9 } }); // > 1.5 × reveal_range
    stepEnemy(sim, entry, far);
    expect(sim.state).toBe('idle');
    expect(sim.anim).toBe('tk2'); // retreats into the box
    run(sim, entry, far, 1.2); // tk2 plays out
    // Boxed again (or already rolling its random wlk2 sway tell).
    expect(['stt', 'wlk2']).toContain(sim.anim);
    if (sim.anim === 'stt') expect(sim.animHold).toBe(true);
    expect(sim.state).toBe('idle');
    // Approach again → re-reveals.
    const again = run(sim, entry, near, 0.1);
    expect(again.some((e) => e.type === 'state_change' && e.to === 'chasing')).toBe(true);
  });
});

describe('enemy-room FSM — stationary (poison lily, spec §poison-lily)', () => {
  it('never moves, faces the target, and fires from its bands', () => {
    const c = config([
      atk({ id: 'bite', clip: 'attack_re2_b_root', min_range: 0, max_range: 3 }),
      atk({ id: 'poison_spit', clip: 'attack_re2_b_root', kind: 'projectile', min_range: 3, max_range: 12, hit_reach: 18, hit_half_angle_deg: 5 }),
    ]);
    c.enemies.dummy.fsm = { stationary: true } as Partial<import('../enemy-room/types').FsmParams>;
    c.enemies.dummy.idle_clip = 'waito_re2_b_root';
    const entry = resolveEntry(c, 'dummy');
    expect(entry.fsm.stationary).toBe(true);
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: 7 } }); // spit band
    const events = run(sim, entry, input, 3.0);
    expect(sim.pos).toEqual({ x: 0, z: 0 }); // rooted through idle/chase/attack/loaf
    expect(events.some((e) => e.type === 'projectile_fired')).toBe(true);
    expect(sim.facing.z).toBeCloseTo(1, 2); // faces the target
  });
});

describe('enemy-room FSM — shooter berserk (spec /states/enemies §shooter)', () => {
  const shot = atk({ id: 'shot', clip: 'atk_sh', kind: 'projectile', min_range: 3, max_range: 10, hit_reach: 10, hit_half_angle_deg: 8 });
  const kamikaze = atk({ id: 'kamikaze', clip: 'atk_ji', berserk_only: true, min_range: 0, max_range: 0, hit_reach: 1.5, hit_half_angle_deg: 180, damage_mult: 2.5 });
  const shooterConfig = (): EnemyAttackConfig => {
    const c = config([shot, kamikaze]);
    c.enemies.dummy.archetype = 'shooter';
    c.enemies.dummy.fsm = { standoff_range: 5 };
    return c;
  };
  const setup = (playerZ: number, invincible = false) => {
    const entry = resolveEntry(shooterConfig(), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput({ playerPos: { x: 0, z: playerZ }, playerInvincible: invincible });
    stepEnemy(sim, entry, input); // idle → chasing
    return { entry, sim, input };
  };

  it('normal mode holds standoff (wat) and fires the shot; the kamikaze never fires from the gate', () => {
    const { entry, sim, input } = setup(5);
    const events = run(sim, entry, input, 3.0);
    expect(events.filter((e) => e.type === 'projectile_fired').length).toBeGreaterThan(0);
    const fired = events.filter((e) => e.type === 'attack_start').map((e) => e.type === 'attack_start' && e.attack.id);
    expect(fired).not.toContain('kamikaze');
  });

  it('berserk: atk_an display, then atk_ji dive at the player, contact explosion kills the shooter', () => {
    const { entry, sim, input } = setup(6);
    const events = applyBerserk(sim, entry, input);
    expect(events.some((e) => e.type === 'berserk')).toBe(true);
    expect(sim.anim).toBe('atk_an'); // confusion spin display
    const all = run(sim, entry, input, 4.0);
    // After the display, dives with atk_ji and explodes on contact.
    expect(all.some((e) => e.type === 'exploded')).toBe(true);
    const hits = all.filter((e) => e.type === 'hit');
    expect(hits).toHaveLength(1);
    expect(hits[0].type === 'hit' && hits[0].damage).toBe(25); // 10 × 2.5
    expect(sim.exploded).toBe(true);
    // Post-explosion the sim is inert.
    const after = stepEnemy(sim, entry, input);
    expect(after.filter((e) => e.type === 'hit')).toHaveLength(0);
  });

  it('i-frames dodge the blast damage but the explosion still consumes the shooter', () => {
    const { entry, sim, input } = setup(6, true);
    applyBerserk(sim, entry, input);
    const all = run(sim, entry, input, 4.0);
    expect(all.some((e) => e.type === 'exploded')).toBe(true);
    expect(all.filter((e) => e.type === 'hit_dodged')).toHaveLength(1);
    expect(all.filter((e) => e.type === 'hit')).toHaveLength(0);
    expect(sim.exploded).toBe(true);
  });

  it('berserk is a no-op for enemies without a berserk_only attack', () => {
    const entry = resolveEntry(config([atk()]), 'dummy');
    const sim = makeSim({ x: 0, z: 0 });
    const input = makeInput();
    expect(applyBerserk(sim, entry, input)).toEqual([]);
    expect(sim.berserk).toBe(false);
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
