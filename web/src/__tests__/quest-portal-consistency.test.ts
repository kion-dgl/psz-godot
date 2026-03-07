/**
 * Portal consistency tests — verifies v1 quest portals reference valid config portal IDs
 * from unified-stage-configs.json.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const QUESTS_DIR = path.resolve(__dirname, '../../../data/quests');
const CONFIG_PATH = path.resolve(__dirname, '../../../web/public/data/stage_configs/unified-stage-configs.json');

const manifest: string[] = JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, 'manifest.json'), 'utf-8'));
const stageConfigs: Record<string, any> = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));

const quests: Array<{ filename: string; data: any }> = manifest.map(name => ({
  filename: `${name}.json`,
  data: JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, `${name}.json`), 'utf-8')),
}));

describe('Quest portals — v1 format validation', () => {
  it.each(quests)('$filename: portals are v1 string references', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        for (const [dir, value] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (typeof value !== 'string') {
            errors.push(`${cell.pos}/${dir} (${cell.stage_id}): portal should be string, got ${typeof value}`);
          }
        }
      }
    }
    expect(errors, `Non-v1 portals:\n${errors.join('\n')}`).toHaveLength(0);
  });

  it.each(quests)('$filename: portal_id references exist in stage config', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        const cfg = stageConfigs[cell.stage_id];
        if (!cfg || !Array.isArray(cfg.portals)) continue;

        const configIds = new Set(cfg.portals.map((p: any) => p.id));
        for (const [dir, portalId] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (dir === 'default' || typeof portalId !== 'string') continue;
          if (!configIds.has(portalId)) {
            errors.push(`${cell.pos}/${dir}: portal_id "${portalId}" not found in ${cell.stage_id} config`);
          }
        }
      }
    }
    expect(errors, `Invalid portal_id refs:\n${errors.join('\n')}`).toHaveLength(0);
  });

  it.each(quests)('$filename: has version 1', ({ data }) => {
    expect(data.version).toBe(1);
  });

  it.each(quests)('$filename: has last_updated date', ({ data }) => {
    expect(data.last_updated).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
