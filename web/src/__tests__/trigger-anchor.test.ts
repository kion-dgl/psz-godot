/**
 * A portal's three points are one line (#617, following #612).
 *
 * gate | spawn | trigger — same lateral position, same axis, fixed distances
 * apart, in that order going outward. That is how they were authored by hand,
 * and #612 broke it by moving the gate onto psz-re's measured doorway while
 * leaving the other two on the old `position`.
 *
 * The spacing is measured, not invented. Across 552 portals the existing
 * gate→spawn distance had a median of 1.12 with an interquartile spread of
 * ~1.4, and gate→trigger a median of 5.12. The outliers, as far as −17.8, are
 * the ones the gate move stranded.
 *
 * Why this replaced a "does the trigger reach the doorway stub" check: the stub
 * cannot tell a good portal from a bad one. s05b_nc2 worked for years with its
 * trigger 3 units PAST its stub, and s02a_sa1's trigger sat inside its room and
 * was fine. Both of those refuted stub-based rules in testing. The line is the
 * invariant that actually held.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const CONFIGS = path.resolve(
  __dirname, '../../../data/stage_configs/unified-stage-configs.json');

const SPAWN_FROM_GATE = 1.1;
const TRIGGER_FROM_GATE = 5.1;
const TOL = 0.01;
const AXIS: Record<string, number> = { north: 2, south: 2, east: 0, west: 0 };
const LATERAL: Record<string, number> = { north: 0, south: 0, east: 2, west: 2 };

describe('portal gate | spawn | trigger line', () => {
  const cfgs = JSON.parse(fs.readFileSync(CONFIGS, 'utf8'));

  const portals = (): Array<[string, any]> => {
    const out: Array<[string, any]> = [];
    for (const [stageId, cfg] of Object.entries<any>(cfgs)) {
      if (!cfg || typeof cfg !== 'object') continue;
      for (const p of cfg.portals ?? []) {
        if (AXIS[p.direction] === undefined || !p.gatePosition) continue;
        out.push([stageId, p]);
      }
    }
    return out;
  };

  it('every portal with a measured gate has both points placed', () => {
    const bad: string[] = [];
    for (const [stageId, p] of portals()) {
      if (!p.spawnPosition || !p.triggerPosition) bad.push(`${stageId} ${p.direction}`);
    }
    expect(portals().length).toBeGreaterThan(500);
    expect(bad).toEqual([]);
  });

  it('holds the fixed spacing outward from the gate', () => {
    const bad: string[] = [];
    for (const [stageId, p] of portals()) {
      if (!p.spawnPosition || !p.triggerPosition) continue;
      const ax = AXIS[p.direction];
      const gate = Math.abs(p.gatePosition[ax]);
      const spawn = Math.abs(p.spawnPosition[ax]);
      const trig = Math.abs(p.triggerPosition[ax]);
      if (Math.abs(spawn - gate - SPAWN_FROM_GATE) > TOL ||
          Math.abs(trig - gate - TRIGGER_FROM_GATE) > TOL) {
        bad.push(`${stageId} ${p.direction}: gate ${gate.toFixed(2)} | ` +
                 `spawn ${spawn.toFixed(2)} | trigger ${trig.toFixed(2)}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it('keeps all three on the same axis line', () => {
    // Lateral position comes from the gate, so the three points sit on the
    // doorway's own axis rather than merely parallel to it.
    const bad: string[] = [];
    for (const [stageId, p] of portals()) {
      if (!p.spawnPosition || !p.triggerPosition) continue;
      const lat = LATERAL[p.direction];
      if (Math.abs(p.spawnPosition[lat] - p.gatePosition[lat]) > TOL ||
          Math.abs(p.triggerPosition[lat] - p.gatePosition[lat]) > TOL) {
        bad.push(`${stageId} ${p.direction}: off the gate's axis`);
      }
    }
    expect(bad).toEqual([]);
  });

  it('never spawns the player inside the trigger box', () => {
    // The failure that stranded the_paru_pact: the spawn ended up inside the
    // 6-deep trigger box, so the player re-fired a transition on arrival and
    // the room was bypassed — objectives unmet, deferred Telepipe never fired.
    // With the spacing above the near face is 2 units past the spawn, but this
    // asserts the consequence rather than trusting the arithmetic.
    const TRIGGER_HALF = 3;
    const bad: string[] = [];
    for (const [stageId, p] of portals()) {
      if (!p.spawnPosition || !p.triggerPosition) continue;
      const ax = AXIS[p.direction];
      const spawn = Math.abs(p.spawnPosition[ax]);
      const near = Math.abs(p.triggerPosition[ax]) - TRIGGER_HALF;
      if (spawn >= near) {
        bad.push(`${stageId} ${p.direction}: spawn ${spawn.toFixed(2)} ` +
                 `is at or past the trigger's near face ${near.toFixed(2)}`);
      }
    }
    expect(bad).toEqual([]);
  });
});
