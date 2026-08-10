/**
 * Waypoint coverage guard.
 *
 * Field stages need a hand-authored nav graph for the autopilot to walk them
 * (docs/waypoint-authoring.md). Free-roam generates fields per run, so a room
 * with no graph is a coin-flip autopilot failure rather than a latent gap —
 * see issue #583.
 *
 * Coverage debt is tracked in data/stage_configs/waypoint_coverage_baseline.json
 * and is allowed to shrink, never grow:
 *   • a stage losing its graph fails here
 *   • a graph that violates the authoring contract fails here
 * After authoring a batch, `npm run wp:baseline` records the new, smaller debt.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
// @ts-expect-error — plain .mjs module, shared so this guard, the `wp check`
// CLI and the dev-server save endpoint enforce one definition of a valid graph.
import { validateGraph } from '../../../scripts/tools/waypoints/validate_graph.mjs';

const DATA = path.resolve(__dirname, '../../../data/stage_configs');
const configs: Record<string, any> = JSON.parse(
  fs.readFileSync(path.join(DATA, 'unified-stage-configs.json'), 'utf-8'),
);
const baseline: { missing: string[]; invalid: string[] } = JSON.parse(
  fs.readFileSync(path.join(DATA, 'waypoint_coverage_baseline.json'), 'utf-8'),
);

const FIELD_AREAS = ['s01', 's02', 's03', 's04', 's05', 's06', 's07', 's08'];
const fieldStages = Object.keys(configs)
  .filter((id) => FIELD_AREAS.includes(id.slice(0, 3)))
  .sort();

const hasGraph = (id: string) => (configs[id].waypoints ?? []).length > 0;

describe('Waypoint coverage', () => {
  it('every field stage outside the baseline has a nav graph', () => {
    const regressed = fieldStages
      .filter((id) => !hasGraph(id))
      .filter((id) => !baseline.missing.includes(id));
    expect(
      regressed,
      `Stage(s) lost their waypoint graph: ${regressed.join(', ')}`,
    ).toHaveLength(0);
  });

  it('every authored graph satisfies the authoring contract', () => {
    const broken: string[] = [];
    for (const id of fieldStages) {
      if (!hasGraph(id) || baseline.invalid.includes(id)) continue;
      const { errors } = validateGraph(id, configs[id]);
      if (errors.length > 0) broken.push(`${id}: ${errors.join('; ')}`);
    }
    expect(broken, `Invalid waypoint graph(s):\n  ${broken.join('\n  ')}`).toHaveLength(0);
  });

  it('the baseline lists only real, still-outstanding debt', () => {
    // Keeps the baseline honest: once a room is authored (or repaired) it must
    // be dropped from the list, so the file always states the true debt.
    const stale = [
      ...baseline.missing.filter((id) => configs[id] && hasGraph(id)).map((id) => `${id} (now authored)`),
      ...baseline.invalid
        .filter((id) => configs[id] && hasGraph(id) && validateGraph(id, configs[id]).errors.length === 0)
        .map((id) => `${id} (now valid)`),
      ...[...baseline.missing, ...baseline.invalid].filter((id) => !configs[id]).map((id) => `${id} (no such stage)`),
    ];
    expect(
      stale,
      `Stale baseline entries — run \`npm run wp:baseline\`: ${stale.join(', ')}`,
    ).toHaveLength(0);
  });
});
