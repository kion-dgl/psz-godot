/**
 * Data validation tests for unified-stage-configs.json
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const CONFIG_PATH = path.resolve(__dirname, '../../../web/public/data/stage_configs/unified-stage-configs.json');
const configs: Record<string, any> = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));

// Collect all stages that actually have portals
const stagesWithPortals = Object.entries(configs).filter(
  ([, cfg]) => Array.isArray(cfg.portals) && cfg.portals.length > 0,
);

describe('Stage Configs — portal validation', () => {
  it('all portals have non-empty IDs', () => {
    const missing: string[] = [];
    for (const [stageId, cfg] of stagesWithPortals) {
      for (const p of cfg.portals) {
        if (!p.id) missing.push(`${stageId}/${p.direction}`);
      }
    }
    expect(missing, `Portals missing id: ${missing.join(', ')}`).toHaveLength(0);
  });

  it('no duplicate portal IDs across entire config', () => {
    const seen = new Map<string, string>(); // id → stageId
    const dupes: string[] = [];
    for (const [stageId, cfg] of stagesWithPortals) {
      for (const p of cfg.portals) {
        if (!p.id) continue;
        if (seen.has(p.id)) {
          dupes.push(`${p.id} in ${seen.get(p.id)} and ${stageId}`);
        }
        seen.set(p.id, stageId);
      }
    }
    expect(dupes, `Duplicate portal IDs: ${dupes.join('; ')}`).toHaveLength(0);
  });

  it('all portals have a valid direction', () => {
    const validDirs = new Set(['north', 'south', 'east', 'west']);
    const bad: string[] = [];
    for (const [stageId, cfg] of stagesWithPortals) {
      for (const p of cfg.portals) {
        if (!validDirs.has(p.direction)) {
          bad.push(`${stageId}: "${p.direction}"`);
        }
      }
    }
    expect(bad, `Invalid directions: ${bad.join(', ')}`).toHaveLength(0);
  });

  it('compass_label when set is N/S/E/W', () => {
    const validLabels = new Set(['N', 'S', 'E', 'W']);
    const bad: string[] = [];
    for (const [stageId, cfg] of stagesWithPortals) {
      for (const p of cfg.portals) {
        if (p.compass_label !== undefined && !validLabels.has(p.compass_label)) {
          bad.push(`${stageId}/${p.direction}: "${p.compass_label}"`);
        }
      }
    }
    expect(bad, `Invalid compass_labels: ${bad.join(', ')}`).toHaveLength(0);
  });

  it('portal positions have Y=0 and are not at origin', () => {
    const bad: string[] = [];
    for (const [stageId, cfg] of stagesWithPortals) {
      for (const p of cfg.portals) {
        const pos = p.position;
        if (!Array.isArray(pos) || pos.length !== 3) {
          bad.push(`${stageId}/${p.direction}: invalid position`);
          continue;
        }
        if (pos[1] !== 0) {
          bad.push(`${stageId}/${p.direction}: Y=${pos[1]} (expected 0)`);
        }
        if (pos[0] === 0 && pos[1] === 0 && pos[2] === 0) {
          bad.push(`${stageId}/${p.direction}: at origin [0,0,0]`);
        }
      }
    }
    expect(bad, `Bad portal positions:\n${bad.join('\n')}`).toHaveLength(0);
  });
});
