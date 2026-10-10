import { describe, it, expect } from 'vitest';
import data from '../../../data/enemy_attacks.json';
import { makeSim, stepEnemy, type SimInput } from '../enemy-room/fsm';
import { resolveEntry, type EnemyAttackConfig } from '../enemy-room/types';

const input = (): SimInput => ({ dt: 1 / 60, playerPos: { x: 0, z: 7 }, playerRadius: 0.5, playerInvincible: false, rng: () => 0.99,
  clipDurationFor: clip => clip === 'run_st' || clip === 'run_ed' ? 0.367 : clip === 'atk_mi' || clip === 'atk_sh' ? 5 / 6 : 1 });

for (const id of ['zaphobos', 'zaphobos_dyna']) describe(id, () => {
  const entry = resolveEntry(data as EnemyAttackConfig, id);
  it('launches three separated pairs and limits guidance to the rising half of flight', () => {
    const sim = makeSim(); sim.state = 'chasing';
    const controls = input(); const times: number[] = [];
    for (let frame = 0; frame < 170; frame++) {
      const events = stepEnemy(sim, entry, controls);
      for (const event of events) if (event.type === 'lob_fired') times.push(frame / 60);
    }
    expect(times).toHaveLength(6);
    expect(times[2] - times[0]).toBeGreaterThan(0.45);
    expect(times[4] - times[2]).toBeGreaterThan(0.45);
    expect(sim.attackCooldowns.missiles).toBeGreaterThan(7);
    const missile = sim.lobs[sim.lobs.length - 1];
    expect(missile).toBeDefined();
    missile.timer = 0.7;
    const locked = { ...missile.target };
    controls.playerPos.x = 5;
    stepEnemy(sim, entry, controls);
    expect(missile.target).toEqual(locked);
  });
  it('folds, moves quickly without attacking, then unfolds before attacking', () => {
    const sim = makeSim(); sim.state = 'chasing';
    for (const a of entry.attacks) sim.attackCooldowns[a.id] = 20;
    const controls = input(); const phases = new Set<string>();
    for (let frame = 0; frame < 165; frame++) {
      const events = stepEnemy(sim, entry, controls);
      phases.add(sim.anim);
      expect(events.some(e => e.type === 'attack_start')).toBe(false);
      if (sim.anim === 'run_st' || sim.anim === 'run_ed') expect(Math.hypot(sim.velocity.x, sim.velocity.z)).toBe(0);
    }
    expect(phases.has('run_st') && phases.has('run_lp') && phases.has('run_ed')).toBe(true);
    expect(Math.hypot(sim.pos.x, sim.pos.z)).toBeGreaterThan(2);
  });
  it('uses independent cooldowns and a contact knockdown dash', () => {
    const sim = makeSim(); sim.state = 'chasing';
    sim.attackCooldowns.missiles = 10; sim.attackCooldowns.blitz = 7;
    const controls = input();
    stepEnemy(sim, entry, controls);
    expect(sim.currentAttack?.def.id).toBe('shot');
    const dash = entry.attacks.find(a => a.id === 'blitz')!;
    expect(dash.kind).toBe('lunge'); expect(dash.knockdown).toBe(true);
    expect(entry.attacks.map(a => a.cooldown)).toEqual([7, 4, 10]);
  });
});

it('keeps the Phobos melee pair separate from the Zaphobos tank pair', () => {
  for (const id of ['phobos', 'phobos_dyna']) {
    const entry = resolveEntry(data as EnemyAttackConfig, id);
    expect(entry.archetype).toBe('shade');
    expect(entry.attacks.every(a => a.kind === 'melee_arc')).toBe(true);
  }
  for (const id of ['zaphobos', 'zaphobos_dyna']) {
    const entry = resolveEntry(data as EnemyAttackConfig, id);
    expect(entry.archetype).toBe('missile_tank');
    expect(entry.fsm.tank_kit).toBe(true);
  }
});
