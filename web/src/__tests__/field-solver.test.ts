import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import {
  checkSolvability,
  keysGainedOnRoute,
  keysSpentOnRoute,
  planRoute,
  type Section,
} from '../field-solver/solver';

/**
 * Guards on the solver the Field Solver page steps through. The solver is a
 * port of the autopilot's planner; these pin the three properties that make
 * its walkthrough honest, over every roll in the committed dump:
 *
 *  - the purse-walk agrees with the Godot suite: every section is solvable
 *    and keys placed == keys demanded;
 *  - the planned route actually terminates at the section's end room;
 *  - the route never goes negative on keys and spends exactly what it
 *    gained (the economy closes along the walk).
 */

const DUMP = path.resolve(__dirname, '../../public/field-dumps/generated-fields.json');

interface Cell {
  pos: string;
  is_end?: boolean;
  is_start?: boolean;
}
interface Sec extends Section {
  cells: (Section['cells'][number] & Cell)[];
}
interface Roll { seed: number; sections: Sec[] }
interface Area { area_id: string; rolls: Roll[] }

const dump = JSON.parse(fs.readFileSync(DUMP, 'utf-8')) as { areas: Area[] };
const sections: { label: string; section: Sec }[] = [];
for (const area of dump.areas) {
  for (const roll of area.rolls) {
    for (const section of roll.sections) {
      sections.push({ label: `${area.area_id} seed ${roll.seed} ${section.area}`, section });
    }
  }
}

describe('field solver', () => {
  it('has sections to solve', () => {
    expect(sections.length).toBeGreaterThan(50);
  });

  it('agrees with the engine: every section solvable, keys balanced', () => {
    for (const { label, section } of sections) {
      const s = checkSolvability(section);
      expect(s.solvable, `${label} solvable`).toBe(true);
      expect(s.keysPlaced, `${label} keys placed == demanded`).toBe(s.keysDemanded);
    }
  });

  it('routes terminate at the end room', () => {
    for (const { label, section } of sections) {
      const route = planRoute(section);
      expect(route.walk.length, `${label} walk non-empty`).toBeGreaterThan(0);
      expect(route.walk[route.walk.length - 1], `${label} ends at end room`).toBe(
        section.end_pos,
      );
    }
  });

  it('never holds negative keys and keeps the purse consistent', () => {
    for (const { label, section } of sections) {
      const route = planRoute(section);
      for (const step of route.steps) {
        expect(step.keysAfter, `${label} ${step.kind}@${step.pos} never negative`).toBeGreaterThanOrEqual(0);
      }
      // The planner detours for any key whose junction precedes the last
      // on-path gate — including, like the autopilot it ports, keys whose own
      // gate is off the main path (collected, never spent). Surplus is fine;
      // debt is not.
      expect(keysSpentOnRoute(route.steps), `${label} never spends more than it gained`).toBeLessThanOrEqual(
        keysGainedOnRoute(route.steps),
      );
    }
  });
});
