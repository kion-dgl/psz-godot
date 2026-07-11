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
    intro_clip: 'tht',
    stationary: false,
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
  anchors: [],
  ...over,
});

// — Octo Diablo shape: rooted surfacing emplacement with a submerge cycle —
const spout = atk({ id: 'spout', clip: 'spout', chain: ['wt2spwt', 'spout'], kind: 'spout', phases: ['surfaced'], min_range: 3, max_range: 15, windup_frac: 0.3, damage_end_frac: 0.9 });
const grab = atk({ id: 'absorb_eat', clip: 'eat', kind: 'grab', phases: ['surfaced'], max_range: 8, hit_reach: 8, hit_half_angle_deg: 40, damage_mult: 2, cancel_clip: 'eatcnc', windup_frac: 0.1, damage_end_frac: 1 });

const makeOcto = (over: Partial<ResolvedBoss> = {}): ResolvedBoss => makeEntry({
  stats: { hp: 200, move_speed: 5, attack_cooldown: 1, attack_base: 10, turn_speed_deg: 90 },
  fsm: {
    ...makeEntry().fsm,
    intro_clip: '',
    stationary: true,
    relocate_kind: 'submerge',
    relocate_untargetable: true,
    submerge_depth: 3,
    fly_speed_mult: 2,
    loaf_duration_min: 1,
    loaf_duration_max: 1,
    fatigue_attacks: 3,
    punish_duration: 4,
    punish_break_damage: 0,
    punish_clip: 'wattir',
  },
  phases: [
    { id: 'surfaced', label: 'Surfaced' },
    { id: 'tired', label: 'Tired' },
    { id: 'submerged', label: 'Submerged' },
  ],
  attacks: [spout],
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
    expect(sim.state).toBe('loaf'); // recovery disengages — never straight back to chase
    expect(sim.cooldown).toBeCloseTo(entry.stats.attack_cooldown, 5);
  });

  it('after the attack it loafs away from the player, then re-engages', () => {
    const entry = makeEntry();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 2 };
    run(sim, entry, player, 100, () => sim.state === 'loaf');
    expect(sim.state).toBe('loaf');
    const d0 = Math.hypot(sim.pos.x - player.x, sim.pos.z - player.z);
    // walk the whole loaf out — the boss gains distance instead of camping
    run(sim, entry, player, 100, () => sim.state !== 'loaf');
    const d1 = Math.hypot(sim.pos.x - player.x, sim.pos.z - player.z);
    expect(d1).toBeGreaterThan(d0 + 1.5);
    expect(sim.state).toBe('active'); // and then it comes back for more
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

describe('boss sim — octo diablo cycle', () => {
  it('skips the intro (no clip) and never walks — a rooted emplacement', () => {
    const entry = makeOcto();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    stepBoss(sim, entry, input({ x: 0, z: 30 }));
    expect(sim.state).toBe('active'); // intro_clip '' → straight in
    run(sim, entry, { x: 0, z: 30 }, 50); // out of every band → would walk if it could
    expect(sim.pos).toEqual({ x: 0, z: 0 });
  });

  it('three attacks → tired loop (×2 damage) → submerge → resurface rested', () => {
    const entry = makeOcto();
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 10 }; // inside the spout band
    // ride through 3 attack/loaf rounds into the fatigue punish
    const evs = run(sim, entry, player, 800, () => sim.state === 'punish');
    expect(sim.state).toBe('punish');
    expect(sim.attacksSinceRest).toBe(3);
    expect(evs).toContainEqual({ type: 'anim', tokens: ['wattir'], loop: true }); // tired LOOPS
    const before = sim.hp;
    damageBoss(sim, entry, 10);
    expect(before - sim.hp).toBe(20); // vulnerable ×2
    // tired window ends in a submerge, untargetable, then resurfaces rested
    run(sim, entry, player, 50, () => sim.state === 'relocate');
    expect(sim.state).toBe('relocate');
    run(sim, entry, player, 30, () => sim.alt <= -entry.fsm.submerge_depth);
    expect(sim.alt).toBe(-3);
    const hpBefore = sim.hp;
    expect(damageBoss(sim, entry, 50)).toHaveLength(0); // submerged: hit doesn't land
    expect(sim.hp).toBe(hpBefore);
    run(sim, entry, player, 600, () => sim.state === 'active');
    expect(sim.state).toBe('active');
    expect(sim.alt).toBe(0);
    expect(sim.attacksSinceRest).toBe(0);
    // fallback spot: ~10u from the player (no anchors authored)
    expect(Math.hypot(sim.pos.x - player.x, sim.pos.z - player.z)).toBeGreaterThan(6);
  });

  it('with authored anchors it resurfaces at one of them', () => {
    const entry = makeOcto({
      anchors: [
        { name: 'pool_a', pos: [20, 0, 0] },
        { name: 'pool_b', pos: [-20, 0, 0] },
      ],
    });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 10 };
    run(sim, entry, player, 800, () => sim.state === 'relocate');
    run(sim, entry, player, 900, () => sim.state === 'active');
    const dA = Math.hypot(sim.pos.x - 20, sim.pos.z);
    const dB = Math.hypot(sim.pos.x + 20, sim.pos.z);
    expect(Math.min(dA, dB)).toBeLessThan(2); // surfaced at an authored spot
  });

  it('the grab ticks while held and breaks when the boss is damaged', () => {
    const entry = makeOcto({ attacks: [grab] });
    const sim = makeBossSim(entry, { x: 0, z: 0 }, 0);
    const player = { x: 0, z: 5 }; // inside the grab band and cone
    run(sim, entry, player, 60, () => sim.state === 'attacking');
    expect(sim.state).toBe('attacking');
    // hold ticks: damage × GRAB_TICK_FRAC per tick, multiple ticks
    const ticks: BossEvent[] = [];
    for (let i = 0; i < 12; i++) {
      ticks.push(...stepBoss(sim, entry, input(player)).filter((e) => e.type === 'player-hit'));
      if (ticks.length >= 2) break;
    }
    expect(ticks.length).toBeGreaterThanOrEqual(2);
    expect(ticks[0]).toMatchObject({ damage: 8, via: 'absorb_eat' }); // 10 × 2 × 0.4
    // damaging the boss mid-hold breaks the grip
    const evs = damageBoss(sim, entry, 5);
    expect(evs).toContainEqual({ type: 'anim', tokens: ['eatcnc'], loop: false });
    expect(sim.state).toBe('active');
    expect(sim.current).toBeNull();
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
