/**
 * Boss behavior sim (spec /states/bosses, DRAFT) — pins the shared skeleton
 * and the observed Reyburn patterns against the pure step function: intro,
 * chase, the chain timeline (telegraph clips deal no damage; the window
 * fractions apply to the release clip), the fireball volley (one projectile
 * per lp rep), the wing-flap knockback, the rush-bite charge, the fly-away →
 * sky-fireball → landing-slam cycle, the punish break, the low-HP enrage,
 * and death. Clip durations are injected — no three.js, no rig.
 */
import { describe, it, expect } from 'vitest';
import {
  damageBoss,
  lobImpacts,
  makeBossSim,
  stepBoss,
  type BossEvent,
  type BossSimInput,
} from '../boss-room/sim';
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

const landSlam = atk({ id: 'land_slam', clip: 'gld2claw', kind: 'aoe_burst', phases: ['flight'], hit_half_angle_deg: 180, hit_reach: 6, damage_mult: 1.5 });
const skyFireball = atk({ id: 'sky_fireball', clip: 'brs2', kind: 'lob', phases: ['flight'], split: 3, hit_reach: 2.5 });

const makeEntry = (over: Partial<ResolvedBoss> = {}): ResolvedBoss => ({
  stats: { hp: 100, move_speed: 4, attack_cooldown: 2, attack_base: 10, turn_speed_deg: 720 },
  fsm: {
    flight_interval: 0,
    flight_attacks: 1,
    hover_height: 8,
    fly_speed_mult: 2.5,
    punish_break_damage: 30,
    punish_vulnerable_mult: 2,
    punish_clip: 'dmg1',
  },
  phases: [
    { id: 'ground', label: 'Ground' },
    { id: 'flight', label: 'Airborne' },
    { id: 'enrage', label: 'Enraged', hp_frac: 0.35, speed_mult: 1.3, cooldown_mult: 0.6 },
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

  it('never selects flight-gated attacks while grounded', () => {
    const entry = makeEntry({ attacks: [landSlam, skyFireball] });
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
    run(sim, entry, player, 60, () => sim.state === 'attacking');
    expect(sim.state).toBe('attacking');
    // chain = windup(1s) + bite(1s); window = [1.5, 2.0] of the attack
    const hits: BossEvent[] = [];
    for (let t = 0; t < 25; t++) {
      const evs = stepBoss(sim, entry, input(player));
      hits.push(...evs.filter((e) => e.type === 'player-hit'));
      if (sim.state !== 'attacking') break;
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

describe('boss sim — observed patterns', () => {
  it('wing flap: the hit carries knockback along the facing', () => {
    const flap = atk({ id: 'wing_flap', clip: 'atkwg', kind: 'melee_arc', phases: ['ground'], max_range: 6, hit_half_angle_deg: 90, hit_reach: 6, knockback: 8, windup_frac: 0, damage_end_frac: 1 });
    const entry = makeEntry({ attacks: [flap] });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const hits = run(sim, entry, { x: 0, z: 3 }, 80).filter((e) => e.type === 'player-hit');
    expect(hits.length).toBeGreaterThan(0);
    const kb = (hits[0] as Extract<BossEvent, { type: 'player-hit' }>).knockback!;
    expect(kb).toBeTruthy();
    expect(Math.hypot(kb.x, kb.z)).toBeCloseTo(8, 3);
    expect(kb.z).toBeGreaterThan(7); // facing the player at +z → blown away along +z
  });

  it('fireball volley: one projectile per lp rep, and they travel to hit', () => {
    const volley = atk({ id: 'fireball_volley', clip: 'brs2', chain: ['brsst', 'brslp', 'brs2'], kind: 'projectile', phases: ['ground'], min_range: 5, max_range: 18, lp_loops: 3 });
    const entry = makeEntry({ attacks: [volley] });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 10 };
    run(sim, entry, player, 60, () => sim.state === 'attacking');
    expect(sim.state).toBe('attacking');
    // telegraph = brsst(1) + brslp×3(3) = 4s; shots at t=2,3,4
    let spawned = 0;
    const hits: BossEvent[] = [];
    for (let i = 0; i < 120; i++) {
      const evs = stepBoss(sim, entry, input(player));
      spawned = Math.max(spawned, sim.projectiles.length);
      hits.push(...evs.filter((e) => e.type === 'player-hit'));
      if (sim.state !== 'attacking' && sim.projectiles.length === 0) break;
    }
    expect(hits.length + sim.projectiles.length).toBeGreaterThanOrEqual(1);
    expect(hits.length).toBeLessThanOrEqual(3);
    expect(hits.every((h) => (h as any).via === 'fireball_volley')).toBe(true);
    // stationary player straight ahead: every shot connects
    expect(hits).toHaveLength(3);
  });

  it('rush bite: the charge closes distance during the telegraph', () => {
    const rush = atk({ id: 'rush_bite', clip: 'atkh2', chain: ['wlk2', 'atkh2'], kind: 'charge', phases: ['ground'], min_range: 4, max_range: 12, windup_frac: 0, damage_end_frac: 1, hit_reach: 3 });
    const entry = makeEntry({ attacks: [rush] });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 10 };
    run(sim, entry, player, 60, () => sim.state === 'attacking');
    const startZ = sim.pos.z;
    const hits = run(sim, entry, player, 30).filter((e) => e.type === 'player-hit');
    expect(sim.pos.z).toBeGreaterThan(startZ + 3); // ran forward during wlk2
    expect(hits).toHaveLength(1); // closed into reach, then the bite lands
  });
});

describe('boss sim — flight cycle', () => {
  it('flies away, drops the sky cluster-fireball, lands on the player with the slam', () => {
    const entry = makeEntry({
      attacks: [bite, landSlam, skyFireball],
      fsm: { ...makeEntry().fsm, flight_interval: 2 },
    });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 30 }; // far: walks (out of bite band), so ACTIVE time accrues
    const evs = run(sim, entry, player, 60, () => sim.state === 'relocate');
    expect(sim.state).toBe('relocate');
    expect(evs).toContainEqual({ type: 'anim', tokens: ['flst'], loop: false });
    const flight = run(sim, entry, player, 900, () => sim.state === 'active');
    expect(sim.state).toBe('active');
    expect(sim.alt).toBe(0);
    expect(sim.sinceFlight).toBeLessThan(2); // reset on landing
    const hits = flight.filter((e) => e.type === 'player-hit') as Extract<BossEvent, { type: 'player-hit' }>[];
    // stationary player: the lob lands on them AND the boss lands next to them
    expect(hits.some((h) => h.via === 'sky_fireball')).toBe(true);
    expect(hits.some((h) => h.via === 'land_slam')).toBe(true);
    expect(flight).toContainEqual({ type: 'anim', tokens: ['gld2claw', 'claw2wat'], loop: false });
  });

  it('a split lob produces its ring of impact points', () => {
    const impacts = lobImpacts({ target: { x: 5, z: 5 }, split: 3 });
    expect(impacts).toHaveLength(3);
    expect(impacts[0]).toEqual({ x: 5, z: 5 });
    for (const p of impacts.slice(1)) {
      expect(Math.hypot(p.x - 5, p.z - 5)).toBeCloseTo(3, 3);
    }
  });
});

describe('boss sim — punish, enrage, death', () => {
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

  it('low health: growls, emits enrage, and speeds up', () => {
    const entry = makeEntry({ fsm: { ...makeEntry().fsm, punish_break_damage: 0 } }); // isolate enrage
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(sim, entry, { x: 0, z: 40 }, 12, () => sim.state === 'active');
    const evs = damageBoss(sim, entry, 70); // 30/100 ≤ 0.35 hp_frac
    expect(sim.enraged).toBe(true);
    expect(evs).toContainEqual({ type: 'enrage' });
    expect(evs).toContainEqual({ type: 'anim', tokens: ['tht'], loop: false });
    // enraged walk covers more ground per step (speed_mult 1.3)
    const calm = makeBossSim(entry, { x: 0, z: 0 }, 0);
    run(calm, entry, { x: 0, z: 40 }, 12, () => calm.state === 'active');
    const z0e = sim.pos.z;
    const z0c = calm.pos.z;
    run(sim, entry, { x: 0, z: 40 }, 10);
    run(calm, entry, { x: 0, z: 40 }, 10);
    expect(sim.pos.z - z0e).toBeGreaterThan((calm.pos.z - z0c) * 1.2);
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
