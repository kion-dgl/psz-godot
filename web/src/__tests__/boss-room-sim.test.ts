/**
 * Boss behavior sim (spec /states/bosses, DRAFT) — pins the shared skeleton
 * against the pure step function: intro, chase, the chain timeline (telegraph
 * clips deal no damage; the window fractions apply to the release clip), the
 * flight cycle, the punish break, and death. Clip durations are injected —
 * no three.js, no rig.
 */
import { describe, it, expect } from 'vitest';
import { damageBoss, makeBossSim, stepBoss, type BossEvent, type BossSimInput } from '../boss-room/sim';
import { DEFAULT_BOSS_ATTACK, type ResolvedBoss, type ResolvedBossAttack } from '../boss-room/types';

const CLIP_DUR = 1.0;
const input = (player: { x: number; z: number }, dt = 0.1): BossSimInput => ({
  dt,
  player,
  clipDur: () => CLIP_DUR,
  rng: () => 0,
});

const atk = (over: Partial<ResolvedBossAttack> & { id: string; clip: string }): ResolvedBossAttack => ({
  ...DEFAULT_BOSS_ATTACK,
  ...over,
});

const bite = atk({
  id: 'bite',
  clip: 'bite',
  chain: ['windup', 'bite'],
  kind: 'melee_arc',
  phases: ['ground'],
  min_range: 0,
  max_range: 4,
  windup_frac: 0.5,
  damage_end_frac: 1.0,
  hit_half_angle_deg: 60,
  hit_reach: 3,
});

const pass = atk({ id: 'strafe', clip: 'fly', kind: 'fly_pass', phases: ['flight'], damage_mult: 2 });

const makeEntry = (over: Partial<ResolvedBoss> = {}): ResolvedBoss => ({
  stats: { hp: 100, move_speed: 4, attack_cooldown: 2, attack_base: 10, turn_speed_deg: 720 },
  fsm: {
    flight_interval: 0,
    flight_passes: 2,
    hover_height: 8,
    fly_speed_mult: 2.5,
    punish_break_damage: 30,
    punish_vulnerable_mult: 2,
    punish_clip: 'dmg1',
  },
  phases: [
    { id: 'ground', label: 'Ground' },
    { id: 'flight', label: 'Flight' },
  ],
  attacks: [bite],
  ...over,
});

/** Step until a predicate hits (or the step budget runs out). Returns all events. */
function run(sim: ReturnType<typeof makeBossSim>, entry: ResolvedBoss, player: { x: number; z: number }, steps: number, until?: (evs: BossEvent[]) => boolean): BossEvent[] {
  const all: BossEvent[] = [];
  for (let i = 0; i < steps; i++) {
    const evs = stepBoss(sim, entry, input(player));
    all.push(...evs);
    if (until?.(evs)) break;
  }
  return all;
}

describe('boss sim — intro and chase', () => {
  it('plays the threat display, then goes active', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const first = stepBoss(sim, entry, input({ x: 0, z: 20 }));
    expect(first).toContainEqual({ type: 'anim', tokens: ['tht'], loop: false });
    run(sim, entry, { x: 0, z: 20 }, 12, () => sim.state === 'active');
    expect(sim.state).toBe('active');
  });

  it('walks toward a far player with the wlk1 loop', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const evs = run(sim, entry, { x: 0, z: 20 }, 30);
    expect(evs).toContainEqual({ type: 'anim', tokens: ['wlk1'], loop: true });
    expect(sim.pos.z).toBeGreaterThan(0.5); // moved toward the player
  });

  it('never selects a fly_pass attack while grounded', () => {
    const entry = makeEntry({ attacks: [pass] });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(sim, entry, { x: 0, z: 2 }, 100);
    expect(sim.state).not.toBe('attacking');
  });
});

describe('boss sim — chain timeline', () => {
  it('telegraph deals no damage; the window hits exactly once; recovery ends the attack', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 2 }; // inside the band and the arc
    // reach attacking (intro 1s + cooldown grace 1s)
    run(sim, entry, player, 60, () => sim.state === 'attacking');
    expect(sim.state).toBe('attacking');
    // chain = windup(1s) + bite(1s); window = [1.5, 2.0] of the attack
    const hits: BossEvent[] = [];
    for (let t = 0; t < 25; t++) {
      const evs = stepBoss(sim, entry, input(player));
      hits.push(...evs.filter((e) => e.type === 'player-hit'));
      if (sim.state !== 'attacking') break;
      // no damage during the telegraph clip
      if (sim.current && sim.current.t < 1.5) expect(hits).toHaveLength(0);
    }
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ type: 'player-hit', damage: 10, via: 'bite' });
    expect(sim.state).toBe('active');
    expect(sim.cooldown).toBeCloseTo(entry.stats.attack_cooldown, 5);
  });

  it('misses when the player leaves the arc before the window', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(sim, entry, { x: 0, z: 2 }, 60, () => sim.state === 'attacking');
    // player runs behind the boss during the telegraph (facing locked at start)
    const hits = run(sim, entry, { x: 0, z: -6 }, 25).filter((e) => e.type === 'player-hit');
    expect(hits).toHaveLength(0);
  });
});

describe('boss sim — flight cycle', () => {
  it('takes off after the interval, strafes passes, and lands back grounded', () => {
    const entry = makeEntry({ attacks: [bite, pass], fsm: { ...makeEntry().fsm, flight_interval: 2 } });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 30 }; // far: walks (out of bite band), so ACTIVE time accrues
    const evs = run(sim, entry, player, 40, () => sim.state === 'relocate');
    expect(sim.state).toBe('relocate');
    expect(evs).toContainEqual({ type: 'anim', tokens: ['flst'], loop: false });
    // fly the whole cycle out (climb + 2 passes + land)
    const flight = run(sim, entry, player, 600, () => sim.state === 'active');
    expect(sim.state).toBe('active');
    expect(sim.alt).toBe(0);
    expect(sim.sinceFlight).toBeLessThan(2); // reset on landing
    // contact passes over the stationary player: at most one hit per pass
    const hits = flight.filter((e) => e.type === 'player-hit');
    expect(hits.length).toBeGreaterThanOrEqual(1);
    expect(hits.length).toBeLessThanOrEqual(entry.fsm.flight_passes);
    expect(hits[0]).toMatchObject({ damage: 20, via: 'strafe' }); // attack_base × damage_mult 2
    expect(flight).toContainEqual({ type: 'anim', tokens: ['gld2claw', 'claw2wat'], loop: false });
  });
});

describe('boss sim — punish and death', () => {
  it('break damage topples the boss; punish window doubles damage; it recovers', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(sim, entry, { x: 0, z: 20 }, 12, () => sim.state === 'active');
    damageBoss(sim, entry, 15);
    expect(sim.state).toBe('active');
    const evs = damageBoss(sim, entry, 15); // 30 ≥ break
    expect(sim.state).toBe('punish');
    expect(evs).toContainEqual({ type: 'anim', tokens: ['dmg1'], loop: false });
    const before = sim.hp;
    damageBoss(sim, entry, 10); // ×2 while punished
    expect(before - sim.hp).toBe(20);
    run(sim, entry, { x: 0, z: 20 }, 15, () => sim.state === 'active');
    expect(sim.state).toBe('active');
    expect(sim.punishAccum).toBe(0);
  });

  it('dies at 0 hp and goes quiet', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(sim, entry, { x: 0, z: 20 }, 12, () => sim.state === 'active');
    const evs = damageBoss(sim, entry, 999);
    expect(sim.state).toBe('dead');
    expect(evs).toContainEqual({ type: 'anim', tokens: ['ded'], loop: false });
    expect(evs.some((e) => e.type === 'died')).toBe(true);
    expect(stepBoss(sim, entry, input({ x: 0, z: 2 }))).toHaveLength(0);
    expect(damageBoss(sim, entry, 10)).toHaveLength(0);
  });
});
