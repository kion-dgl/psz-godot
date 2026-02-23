/**
 * Data validation tests for quest JSON files in data/quests/
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const QUESTS_DIR = path.resolve(__dirname, '../../../data/quests');
const CONFIG_PATH = path.resolve(__dirname, '../../../web/public/data/stage_configs/unified-stage-configs.json');

const manifest: string[] = JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, 'manifest.json'), 'utf-8'));
const stageConfigs: Record<string, any> = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));

// Load all quest files referenced by manifest
const quests: Array<{ filename: string; data: any }> = manifest.map(name => ({
  filename: `${name}.json`,
  data: JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, `${name}.json`), 'utf-8')),
}));

const OPPOSITE: Record<string, string> = {
  north: 'south',
  south: 'north',
  east: 'west',
  west: 'east',
};

describe('Quest manifest', () => {
  it('every manifest entry has a corresponding .json file', () => {
    const missing: string[] = [];
    for (const name of manifest) {
      const fp = path.join(QUESTS_DIR, `${name}.json`);
      if (!fs.existsSync(fp)) missing.push(name);
    }
    expect(missing, `Missing quest files: ${missing.join(', ')}`).toHaveLength(0);
  });
});

describe('Quest files — structure', () => {
  it.each(quests)('$filename has required fields', ({ data }) => {
    expect(data.id).toBeTruthy();
    expect(data.name).toBeTruthy();
    expect(Array.isArray(data.sections)).toBe(true);
  });
});

describe('Quest files — stage_id references', () => {
  it.each(quests)('$filename: all stage_ids exist in unified config', ({ data }) => {
    const missing: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        if (!stageConfigs[cell.stage_id]) {
          missing.push(`section ${section.type}/${section.area} cell ${cell.pos}: ${cell.stage_id}`);
        }
      }
    }
    expect(missing, `Unknown stage_ids:\n${missing.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest files — connections', () => {
  it.each(quests)('$filename: connections are bidirectional', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      const cellMap = new Map<string, any>();
      for (const cell of section.cells || []) cellMap.set(cell.pos, cell);

      for (const cell of section.cells || []) {
        for (const [dir, targetPos] of Object.entries(cell.connections || {})) {
          const target = cellMap.get(targetPos as string);
          if (!target) {
            errors.push(`${cell.pos} connects ${dir}→${targetPos} but target cell missing`);
            continue;
          }
          const reverseDir = OPPOSITE[dir];
          const targetConns = target.connections || {};
          if (targetConns[reverseDir] !== cell.pos) {
            errors.push(`${cell.pos} connects ${dir}→${targetPos} but ${targetPos} does not connect ${reverseDir}→${cell.pos}`);
          }
        }
      }
    }
    expect(errors, `Broken connections:\n${errors.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest files — portals', () => {
  it.each(quests)('$filename: portal keys cover connections + warp_edge', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        const portalKeys = new Set(Object.keys(cell.portals || {}).filter(k => k !== 'default'));
        // Skip cells with no baked portals (quest exported before baking was added)
        if (portalKeys.size === 0) continue;

        const expectedDirs = new Set([
          ...Object.keys(cell.connections || {}),
          ...(cell.warp_edge ? [cell.warp_edge] : []),
        ]);
        for (const dir of expectedDirs) {
          if (!portalKeys.has(dir)) {
            errors.push(`${cell.pos} (${cell.stage_id}): missing portal for "${dir}"`);
          }
        }
      }
    }
    expect(errors, `Missing portals:\n${errors.join('\n')}`).toHaveLength(0);
  });

  it.each(quests)('$filename: non-default baked portals have compass_label', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        // Only check cells that have baked portals (from stages with portal configs)
        const cfg = stageConfigs[cell.stage_id];
        if (!cfg || !Array.isArray(cfg.portals) || cfg.portals.length === 0) continue;

        for (const [dir, portal] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (dir === 'default') continue;
          if (!portal.compass_label) {
            errors.push(`${cell.pos}/${dir}: missing compass_label`);
          }
        }
      }
    }
    expect(errors, `Portals missing compass_label:\n${errors.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest files — start/end cells', () => {
  it.each(quests)('$filename: start_pos and end_pos reference actual cells', ({ data }) => {
    const errors: string[] = [];
    for (let i = 0; i < data.sections.length; i++) {
      const section = data.sections[i];
      const cellPositions = new Set((section.cells || []).map((c: any) => c.pos));
      if (section.start_pos && !cellPositions.has(section.start_pos)) {
        errors.push(`section[${i}] start_pos "${section.start_pos}" not in cells`);
      }
      if (section.end_pos && !cellPositions.has(section.end_pos)) {
        errors.push(`section[${i}] end_pos "${section.end_pos}" not in cells`);
      }
    }
    expect(errors, `Invalid start/end:\n${errors.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest files — warp_edge', () => {
  it.each(quests)('$filename: warp_edge direction has no connection', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        if (cell.warp_edge) {
          const conns = cell.connections || {};
          if (conns[cell.warp_edge]) {
            errors.push(`${cell.pos}: warp_edge="${cell.warp_edge}" but has connection in that direction`);
          }
        }
      }
    }
    expect(errors, `warp_edge conflicts:\n${errors.join('\n')}`).toHaveLength(0);
  });
});
