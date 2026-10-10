import type { EnemySim, SimInput, SimEvent } from './fsm';
import type { ResolvedEntry } from './types';

export function tankChase(sim: EnemySim, entry: ResolvedEntry, input: SimInput, dist: number): boolean {
  const travel = sim.tankTravel;
  const dx = input.playerPos.x - sim.pos.x, dz = input.playerPos.z - sim.pos.z;
  const radial = { x: dx / Math.max(dist, 0.001), z: dz / Math.max(dist, 0.001) };
  sim.velocity = { x: 0, z: 0 };
  sim.facing = radial;
  const available = entry.attacks.some(a => dist >= a.min_range && dist <= a.max_range && !(sim.attackCooldowns[a.id] > 0));
  if (!travel.phase && available && sim.attackCooldown <= 0) return false;
  if (!travel.phase && travel.cooldown <= 0 && (dist > 10 || !available)) {
    travel.phase = 'st'; travel.t = 0; travel.cooldown = 7;
  }
  if (travel.phase) {
    travel.t += input.dt;
    sim.anim = `run_${travel.phase}`;
    if (travel.phase === 'lp') {
      const direction = dist > 8 ? radial : dist < 5 ? { x: -radial.x, z: -radial.z } : { x: -radial.z * sim.arcSide, z: radial.x * sim.arcSide };
      sim.velocity = { x: direction.x * 5.5, z: direction.z * 5.5 };
      sim.facing = direction;
      if (travel.t >= 1.6) { travel.phase = 'ed'; travel.t = 0; sim.velocity = { x: 0, z: 0 }; sim.anim = 'run_ed'; }
    } else if (travel.t >= (input.clipDurationFor(sim.anim) ?? 0.367)) {
      travel.phase = travel.phase === 'st' ? 'lp' : ''; travel.t = 0;
      sim.anim = travel.phase ? 'run_lp' : 'wat';
    }
    return true;
  }
  const speed = dist > 8 ? 0.9 : dist < 3 ? -0.9 : 0;
  sim.velocity = { x: radial.x * speed, z: radial.z * speed };
  sim.anim = 'wat';
  return true;
}

export function tankWaves(sim: EnemySim, input: SimInput, events: SimEvent[]): void {
  const attack = sim.currentAttack;
  if (!attack?.def.missile_waves) return;
  while ((attack.waves ?? 0) < 3 && attack.t >= (0.32 + (attack.waves ?? 0) * 0.18) * attack.duration) {
    for (const side of [-1, 1]) {
      const target = { ...input.playerPos };
      sim.lobs.push({ from: { x: sim.pos.x - attack.facing.z * side * 0.7, z: sim.pos.z + attack.facing.x * side * 0.7 }, target, timer: 1.5, flightTime: 1.5, attack: attack.def });
      events.push({ type: 'lob_fired', attack: attack.def, at: target });
    }
    attack.waves = (attack.waves ?? 0) + 1;
  }
}
