import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

/**
 * Guards on the dump the field preview renders
 * (web/public/field-dumps/generated-fields.json, written by
 * scripts/tools/dump_generated_fields.gd).
 *
 * These are the invariants a human would otherwise have to spot by eye in the
 * preview, and the ones that went wrong in play-testing: doors that lead
 * nowhere, and a field where every gate is the same kind.
 */

const DUMP = path.resolve(__dirname, '../../public/field-dumps/generated-fields.json');

interface Cell {
  pos: string;
  stage_id: string;
  connections: Record<string, string>;
  portals?: Record<string, string>;
  door_attributes?: Record<string, number>;
  objects?: { type: string }[];
  is_start?: boolean;
  warp_edge?: string;
  entry_warp_edge?: string;
}
interface Section { type: string; area: string; cells: Cell[] }
interface Roll { seed: number; sections: Section[] }
interface Area { area_id: string; rolls: Roll[] }

const dump = JSON.parse(fs.readFileSync(DUMP, 'utf-8')) as { areas: Area[] };
const allCells: { area: string; seed: number; section: Section; cell: Cell }[] = [];
for (const area of dump.areas)
  for (const roll of area.rolls)
    for (const section of roll.sections)
      for (const cell of section.cells)
        allCells.push({ area: area.area_id, seed: roll.seed, section, cell });

const label = (e: (typeof allCells)[number]) =>
  `${e.area} seed ${e.seed} ${e.section.area} ${e.cell.stage_id}@${e.cell.pos}`;

describe('generated field dump', () => {
  it('has cells to check', () => {
    expect(allCells.length).toBeGreaterThan(100);
  });

  it('never shows a door with no room behind it', () => {
    // A portal that is not a connection is a door leading nowhere — no gate, no
    // loading trigger — unless it is one of the section's two warps. This was
    // 182 door-slots across 60% of rooms before the retile pass.
    const bad = allCells.filter(({ cell, section }) => {
      if (section.type !== 'grid') return false;
      const spare = Object.keys(cell.portals ?? {}).filter(
        (d) =>
          d !== 'default' &&
          !(d in cell.connections) &&
          d !== cell.warp_edge &&
          d !== cell.entry_warp_edge,
      );
      return spare.length > 0;
    });
    expect(bad.map(label), 'cells with a door leading nowhere').toHaveLength(0);
  });

  it('never attributes a door that is not a connection', () => {
    const bad = allCells.filter(({ cell }) =>
      Object.keys(cell.door_attributes ?? {}).some((d) => !(d in cell.connections)),
    );
    expect(bad.map(label), 'door attributes on non-connections').toHaveLength(0);
  });

  it('produces all four door kinds across the corpus', () => {
    // Gate variety is the thing a play-test cannot confirm cheaply: three
    // stages showed only enemy-defeat and one-key, which turned out to be a
    // runtime bug on top of correct data. Here the data itself is pinned.
    const seen = new Set<number>();
    for (const { cell, section } of allCells) {
      if (section.type !== 'grid') continue;
      for (const dir of Object.keys(cell.connections)) {
        seen.add(cell.door_attributes?.[dir] ?? 0);
      }
    }
    expect([...seen].sort(), 'door attribute kinds present').toEqual([0, 1, 2, 4]);
  });

  it('places fences only where a switch can open them', () => {
    // A fence stands IN a doorway on purpose, so one with no switch in the room
    // is a sealed room. Guarded at import and again at build time.
    const bad = allCells.filter(({ cell }) => {
      const types = (cell.objects ?? []).map((o) => o.type);
      return types.includes('fence') && !types.includes('step_switch');
    });
    expect(bad.map(label), 'rooms with an unopenable fence').toHaveLength(0);
  });
});
