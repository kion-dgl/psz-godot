import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import {
  occupiedGroups,
  layoutEligibility,
  layoutShares,
  maskGroups,
  filterByLayout,
  pickDefaultLayout,
} from '../stage-editor/layoutMasks';

// The constants as room_objects.json publishes them — the tests mirror
// field_population.gd's _pick_layout against the real table.
const MASKS = [33, 35, 37, 40, 48];
const ROWS: Record<string, number[]> = {
  lt4: [50, 20, 20, 10],
  '4_6': [40, 20, 20, 20],
  ge7: [25, 25, 25, 25],
};

describe('occupiedGroups', () => {
  it('sets a bit per non-empty group and always forces group 5', () => {
    expect(occupiedGroups([2, 0, 0, 0, 3, 0])).toBe(0b110001);
  });

  it('ignores group sizes beyond six', () => {
    expect(occupiedGroups([1, 1, 1, 1, 1, 1, 9])).toBe(occupiedGroups([1, 1, 1, 1, 1, 1]));
  });
});

describe('layoutEligibility (mirrors _pick_layout)', () => {
  it('every group populated → every mask eligible', () => {
    expect(layoutEligibility([3, 2, 1, 4, 2, 7], MASKS)).toEqual([true, true, true, true, true]);
  });

  it('only group 0 populated → only mask 33 eligible', () => {
    expect(layoutEligibility([5, 0, 0, 0, 0, 0], MASKS)).toEqual([true, false, false, false, false]);
  });

  it('groups 0 and 4 (s07a_ga1_d) → masks 33 and 48', () => {
    expect(layoutEligibility([2, 0, 0, 0, 3, 0], MASKS)).toEqual([true, false, false, false, true]);
  });

  it('no group 0–4 populated → no mask eligible (draw falls back to 0)', () => {
    expect(layoutEligibility([0, 0, 0, 0, 0, 7], MASKS)).toEqual([false, false, false, false, false]);
  });
});

describe('layoutShares', () => {
  it('all eligible → shares are the weight row itself', () => {
    const all = [true, true, true, true, true];
    for (const row of Object.values(ROWS)) {
      expect(layoutShares(MASKS, all, row)).toEqual([...row, 0]);
    }
  });

  it('only L0 eligible → every draw lands on L0', () => {
    expect(layoutShares(MASKS, [true, false, false, false, false], ROWS.lt4)).toEqual([100, 0, 0, 0, 0]);
  });

  it('L1–L3 ineligible fall to the highest eligible index ≤ 3', () => {
    // eligible L2 (and never-drawn L4): every ineligible draw cascades to L2.
    expect(layoutShares(MASKS, [false, false, true, false, true], ROWS.ge7)).toEqual([0, 0, 100, 0, 0]);
    // eligible L0 and L2: draws 0 and 2 stay, 1 and 3 cascade down to L2.
    expect(layoutShares(MASKS, [true, false, true, false, false], ROWS.lt4)).toEqual([50, 0, 50, 0, 0]);
  });

  it('no mask eligible → everything falls back to layout 0', () => {
    const none = [false, false, false, false, false];
    for (const row of Object.values(ROWS)) {
      expect(layoutShares(MASKS, none, row)).toEqual([100, 0, 0, 0, 0]);
    }
  });

  it('mask 4 never receives weight — the draw returns 0..3', () => {
    expect(layoutShares(MASKS, [false, false, false, false, true], ROWS.ge7)[4]).toBe(0);
  });

  it('shares sum to 100 per row', () => {
    const eligible = layoutEligibility([1, 2, 0, 1, 0, 3], MASKS);
    for (const row of Object.values(ROWS)) {
      expect(layoutShares(MASKS, eligible, row).reduce((a, b) => a + b, 0)).toBe(100);
    }
  });
});

describe('maskGroups', () => {
  it('lists groups 0–4 by bit; group 5 rides every mask as the roll', () => {
    expect(maskGroups(33)).toEqual([0]);
    expect(maskGroups(35)).toEqual([0, 1]);
    expect(maskGroups(37)).toEqual([0, 2]);
    expect(maskGroups(40)).toEqual([3]);
    expect(maskGroups(48)).toEqual([4]);
  });
});

describe('filterByLayout', () => {
  const objects = [
    { g: 0, k: 'box' },
    { g: 0, k: 'box' },
    { g: 1, k: 'wall' },
    { g: 4, k: 'rare_box' },
    { g: 5, k: 'ice_trap' },
    { g: 5, k: 'gun_trap' },
    { g: null, k: 'box' },
  ];
  const kinds = (out: typeof objects) => out.map((o) => o.k);

  it('builds groups 0–4 by mask bit (33 = groups 0, 5)', () => {
    expect(kinds(filterByLayout(objects, 33, 0))).toEqual(['box', 'box']);
  });

  it('mask 35 adds group 1 verbatim', () => {
    expect(kinds(filterByLayout(objects, 35, 0))).toEqual(['box', 'box', 'wall']);
  });

  it('takes only the first N of group 5 (the visit shuffles; which N varies)', () => {
    expect(kinds(filterByLayout(objects, 33, 1))).toEqual(['box', 'box', 'ice_trap']);
  });

  it('caps group 5 at its size when the roll exceeds it', () => {
    expect(kinds(filterByLayout(objects, 33, 3))).toEqual(['box', 'box', 'ice_trap', 'gun_trap']);
  });

  it('mask 48 = group 4 — the only mask that ever renders it', () => {
    expect(kinds(filterByLayout(objects, 48, 2))).toEqual(['rare_box', 'ice_trap', 'gun_trap']);
  });

  it('ungrouped records build in no mask', () => {
    expect(filterByLayout([objects[6]], 33, 3)).toEqual([]);
  });
});

// The same computations against the real table, the way the Authored tab
// runs them at browse time.
describe('room_objects.json through the preview logic', () => {
  const doc = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, '../../../data/re_reference/room_objects.json'),
      'utf-8',
    ),
  ) as {
    layout_masks: number[];
    layout_weights_by_depth: Record<string, number[]>;
    group5_weights: number[];
    caps: { per_group: number; per_room: number };
    rooms: Record<string, { groups?: number[] | null; objects: { g?: number | null; k: string }[] }>;
  };
  const MASKS: number[] = doc.layout_masks;
  const grouped = Object.entries(doc.rooms).filter(([, e]) => e.groups != null);

  it('every room: shares sum to 100 per depth row and mask 4 never draws', () => {
    for (const [code, entry] of grouped) {
      const eligible = layoutEligibility(entry.groups!, MASKS);
      for (const row of Object.values(doc.layout_weights_by_depth)) {
        const shares = layoutShares(MASKS, eligible, row);
        expect(shares.reduce((a, b) => a + b, 0), code).toBe(100);
        expect(shares[4], code).toBe(0);
      }
    }
  });

  it("no room's preview can exceed the caps — the reason the filter need not truncate", () => {
    for (const [code, entry] of grouped) {
      const counts = [0, 1, 2, 3, 4, 5].map(
        (g) => entry.objects.filter((o) => o.g === g).length,
      );
      for (const n of counts) expect(n, code).toBeLessThanOrEqual(doc.caps.per_group);
      for (const m of MASKS) {
        const outcome = filterByLayout(entry.objects, m, Math.min(3, counts[5])).length;
        expect(outcome, code).toBeLessThanOrEqual(doc.caps.per_room);
      }
    }
  });

  it('s03a_ic1_d: five real arrangements; mask 48 previews the group-4 objects', () => {
    const entry = doc.rooms['s03a_ic1_d'];
    const eligible = layoutEligibility(entry.groups!, MASKS);
    expect(eligible).toEqual([true, true, true, true, true]);
    // The reachable layouts exclude mask 4 — its 7 group-4 objects never
    // spawn in a free field, and the L4 button is the only way to see them.
    const reachable = filterByLayout(entry.objects, 33, 0);
    expect(reachable.every((o) => o.g === 0)).toBe(true);
    expect(filterByLayout(entry.objects, 48, 0).filter((o) => o.g === 4).length).toBe(7);
    // Group-5 roll takes exactly the first N traps.
    expect(filterByLayout(entry.objects, 33, 2).filter((o) => o.g === 5).length).toBe(2);
  });

  it("s07a_ga1_d: only masks 33/48 eligible, and every reachable layout renders nothing", () => {
    const entry = doc.rooms['s07a_ga1_d'];
    const eligible = layoutEligibility(entry.groups!, MASKS);
    expect(eligible).toEqual([true, false, false, false, true]);
    const shares = layoutShares(MASKS, eligible, doc.layout_weights_by_depth['4_6']);
    expect(shares[0]).toBe(100);
    // All imported objects are group 4, so the layout the room actually takes
    // builds none of them — the documented fall-through-to-the-ring case.
    expect(filterByLayout(entry.objects, 33, 3)).toEqual([]);
  });
});

describe('pickDefaultLayout', () => {
  it('picks the most-taken reachable layout', () => {
    const all = [true, true, true, true, true];
    expect(pickDefaultLayout(MASKS, all, [50, 20, 20, 10])).toBe(0);
    expect(pickDefaultLayout(MASKS, all, [10, 60, 20, 10])).toBe(1);
  });

  it('cascades to the eligible layout when the drawn one is not', () => {
    // only L2 eligible: everything falls to L2, so it is the most-taken.
    expect(pickDefaultLayout(MASKS, [false, false, true, false, false], [25, 25, 25, 25])).toBe(2);
  });

  it('falls back to layout 0 when nothing is eligible', () => {
    expect(pickDefaultLayout(MASKS, [false, false, false, false, false], [25, 25, 25, 25])).toBe(0);
  });
});
