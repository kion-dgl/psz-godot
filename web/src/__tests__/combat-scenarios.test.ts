import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import { makeSim, stepEnemy, type SimInput } from '../enemy-room/fsm';
import { resolveEntry, type EnemyAttackConfig } from '../enemy-room/types';

const read = (name: string) => JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../data', name), 'utf8'));
const attacks: EnemyAttackConfig = read('enemy_attacks.json');
const scenarios: { seed: number; observation_frames: number; cases: Array<{
  id: string; enemies: string[]; distance: number; condition: string;
  allowed_attacks: string[]; web: boolean;
}> } = read('combat_scenarios.json');

describe('shared combat decision scenarios — ordinary enemy-room AI', () => {
  for (const row of scenarios.cases.filter(c => c.web)) {
    for (const id of row.enemies) {
      it(`${id}: ${row.id}`, () => {
        const entry = resolveEntry(attacks, id);
        for (let seedOffset = 0; seedOffset < 8; seedOffset++) {
          let seed = scenarios.seed + seedOffset;
          const sim = makeSim({ x: 0, z: 0 });
          sim.state = row.condition === 'hurt' ? 'hurt' : row.condition === 'recovery' ? 'loafing' : 'chasing';
          sim.attackCooldown = row.condition === 'cooldown' ? 1 : 0;
          sim.hurtTimer = sim.loafTimer = 1;
          const input: SimInput = { dt: 1/60, playerPos: {x:0,z:row.distance}, playerRadius:0.5,
            playerInvincible:false, clipDurationFor:()=>1,
            rng:()=> { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; } };
          let actual = '';
          for (let frame=0; frame<scenarios.observation_frames; frame++) {
            const started = stepEnemy(sim, entry, input).find(e => e.type === 'attack_start');
            if (started?.type === 'attack_start') { actual = started.attack.id; break; }
          }
          expect(row.allowed_attacks.length ? row.allowed_attacks : [''], `seed ${scenarios.seed + seedOffset}`).toContain(actual);
        }
      });
    }
  }
});
