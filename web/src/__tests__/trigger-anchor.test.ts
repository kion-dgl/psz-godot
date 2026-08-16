/**
 * Every load trigger must reach its own doorway (#617).
 *
 * The gate mesh was moved onto psz-re's measured doorway (#612) while the
 * trigger kept deriving from the authored `position`, which left it free to
 * sit anywhere relative to the door it belongs to. Measured before the fix:
 * 109 portals had a trigger past the end of the doorway stub — unreachable,
 * the s01b_tb3 failure — and 14 had one entirely inside the room, firing a
 * cell load in open floor (s01b_xb2 spanned 5.2..11.2 against a door at 22.0).
 *
 * This is the invariant that says it cannot come back. It is a data guard
 * rather than a behaviour test: whether the player can WALK into the trigger
 * is the autopilot's job, but a trigger that does not overlap its doorway is
 * wrong without anyone having to run the game.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const CONFIGS = path.resolve(
  __dirname, '../../../data/stage_configs/unified-stage-configs.json');

// Matches the engine: BoxShape3D(6, 3, 6) centred on the trigger, so it reaches
// 3 either side. A doorway stub runs from the wall out to +3.
const TRIGGER_HALF = 3;
const STUB_DEPTH = 3;
const EXIT_OUTSET = 7;
const AXIS: Record<string, number> = { north: 2, south: 2, east: 0, west: 0 };

describe('load trigger anchoring', () => {
  const cfgs = JSON.parse(fs.readFileSync(CONFIGS, 'utf8'));

  it('every portal with a measured doorway has a trigger that reaches it', () => {
    const bad: string[] = [];
    let checked = 0;

    for (const [stageId, cfg] of Object.entries<any>(cfgs)) {
      if (!cfg || typeof cfg !== 'object') continue;
      for (const p of cfg.portals ?? []) {
        const axis = AXIS[p.direction];
        if (axis === undefined || !p.position || !p.gatePosition) continue;
        checked++;

        const gate = Math.abs(p.gatePosition[axis]);
        // position + 7 unless the portal was re-anchored, in which case the
        // trigger position is data — read it the way the engine does.
        const centre = p.triggerPosition
          ? Math.abs(p.triggerPosition[axis])
          : Math.abs(p.position[axis]) + EXIT_OUTSET;

        const near = centre - TRIGGER_HALF;
        const far = centre + TRIGGER_HALF;
        if (near > gate + STUB_DEPTH || far < gate) {
          bad.push(
            `${stageId} ${p.direction}: trigger ${near.toFixed(1)}..${far.toFixed(1)} ` +
            `misses doorway ${gate.toFixed(1)}..${(gate + STUB_DEPTH).toFixed(1)}`);
        }
      }
    }

    expect(checked).toBeGreaterThan(500);
    expect(bad).toEqual([]);
  });

  it('a re-anchored portal keeps its exit waypoint on the trigger', () => {
    // Moving the trigger without its exit node leaves the autopilot walking to
    // where the trigger used to be. validate_graph.mjs cannot catch that on its
    // own: a pair at the wrong place is still a well-formed pair.
    const bad: string[] = [];

    for (const [stageId, cfg] of Object.entries<any>(cfgs)) {
      if (!cfg || typeof cfg !== 'object') continue;
      for (const p of cfg.portals ?? []) {
        if (!p.triggerPosition) continue;
        const exits = (cfg.waypoints ?? []).filter((w: any) => w.kind === 'exit');
        const near = Math.min(...exits.map((w: any) => Math.hypot(
          w.position[0] - p.triggerPosition[0],
          w.position[2] - p.triggerPosition[2])));
        if (!(near <= 1.5)) {
          bad.push(`${stageId} ${p.direction}: nearest exit node is ${near.toFixed(2)}m away`);
        }
      }
    }

    expect(bad).toEqual([]);
  });
});
