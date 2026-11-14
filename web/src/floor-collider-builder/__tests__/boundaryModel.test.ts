import { describe, expect, it } from 'vitest';
import marketRaw from '../../../../data/stage_configs/city-boundaries/market.json';
import undergroundRaw from '../../../../data/stage_configs/city-boundaries/underground.json';
import officeRaw from '../../../../data/stage_configs/city-boundaries/office.json';
import counterRaw from '../../../../data/stage_configs/city-boundaries/counter.json';
import {
  type CityAreaId,
  CITY_BOUNDARY_PRESETS,
  computeSolidEdgeSpans,
  isPointWalkable2D,
  normalizeBoundaryConfig,
  serializeBoundaryConfig,
  splitPolygonEdge,
} from '../boundaryModel';

const RAW_BY_AREA: Record<CityAreaId, unknown> = {
  market: marketRaw,
  underground: undergroundRaw,
  office: officeRaw,
  counter: counterRaw,
};

describe('city boundary model & committed sidecars (#371)', () => {
  it('loads and validates all four committed city boundary JSONs', () => {
    for (const [areaId, raw] of Object.entries(RAW_BY_AREA) as [CityAreaId, unknown][]) {
      const cfg = normalizeBoundaryConfig(raw);
      expect(cfg.areaId).toBe(areaId);
      expect(cfg.stageId).toBe(CITY_BOUNDARY_PRESETS[areaId].stageId);
      expect(cfg.perimeter.length).toBeGreaterThanOrEqual(4);
      expect(cfg.wallHeight).toBeGreaterThanOrEqual(2.5);
      expect(serializeBoundaryConfig(cfg)).toContain(`"areaId": "${areaId}"`);

      for (const pin of CITY_BOUNDARY_PRESETS[areaId].pins) {
        if (pin.kind === 'spawn' || pin.kind === 'trigger') {
          expect(
            isPointWalkable2D(cfg, pin.pos[0], pin.pos[2], pin.pos[1] + 0.5),
            `${areaId} pin "${pin.label}" at (${pin.pos.join(', ')}) should be walkable`,
          ).toBe(true);
        }
      }
    }
  });

  it('splits solid wall spans around non-portal openings and preserves portalOnly walls', () => {
    expect(
      computeSolidEdgeSpans(0, [
        { id: 'gate', edge: 0, tStart: 0.2, tEnd: 0.8, portalOnly: true },
      ]),
    ).toEqual([[0, 1]]);

    expect(
      computeSolidEdgeSpans(2, [
        { id: 'door', edge: 2, tStart: 0.25, tEnd: 0.75, portalOnly: false },
      ]),
    ).toEqual([
      [0, 0.25],
      [0.75, 1],
    ]);
  });

  it('splits polygon edges at their rounded midpoint', () => {
    const pts: [number, number][] = [
      [0, 0],
      [10, 0],
      [10, 10],
    ];
    expect(splitPolygonEdge(pts, 0)).toEqual([
      [0, 0],
      [5, 0],
      [10, 0],
      [10, 10],
    ]);
  });
});
