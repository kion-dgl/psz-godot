/**
 * Portal consistency tests — verifies quest portals reference valid config portal IDs
 * and that baked positions match re-computed values from unified-stage-configs.json.
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

// --- Re-bake helpers (pure math, mirrors quest-io.ts computePortalPositions) ---

type Vec3 = [number, number, number];

const DIRECTION_ROTATIONS: Record<string, number> = {
  north: 0,
  south: Math.PI,
  east: Math.PI / 2,
  west: -Math.PI / 2,
};

const GATE_MODEL_ROTATIONS: Record<string, number> = {
  north: 0,
  south: Math.PI,
  east: -Math.PI / 2,
  west: Math.PI / 2,
};

const CONFIG_DIR_TO_COMPASS: Record<string, string> = {
  north: 'N',
  south: 'S',
  east: 'E',
  west: 'W',
};

function round3(v: Vec3): Vec3 {
  return [+v[0].toFixed(2), +v[1].toFixed(2), +v[2].toFixed(2)];
}

interface PortalConfig {
  id?: string;
  direction: string;
  position: [number, number, number];
  compass_label?: string;
  rotationOffset?: number;
}

function rebakePortal(portal: PortalConfig): {
  gate: Vec3; spawn: Vec3; trigger: Vec3; gate_rot: Vec3; compass_label: string;
} {
  const [x, , z] = portal.position;
  const rotation = (DIRECTION_ROTATIONS[portal.direction] ?? 0) + ((portal.rotationOffset || 0) * Math.PI) / 180;
  const spawnOutset = 3;
  const triggerOutset = 7;
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  const gateYRot = GATE_MODEL_ROTATIONS[portal.direction] ?? 0;
  const compassLabel = portal.compass_label ?? CONFIG_DIR_TO_COMPASS[portal.direction] ?? portal.direction[0].toUpperCase();

  return {
    gate: round3(portal.position),
    spawn: round3([x - sin * spawnOutset, 1, z - cos * spawnOutset]),
    trigger: round3([x - sin * triggerOutset, 0, z - cos * triggerOutset]),
    gate_rot: round3([0, gateYRot, 0]),
    compass_label: compassLabel,
  };
}

// --- Tests ---

describe('Quest portals — portal_id traceability', () => {
  it.each(quests)('$filename: every non-default portal has a portal_id', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        const cfg = stageConfigs[cell.stage_id];
        if (!cfg || !Array.isArray(cfg.portals) || cfg.portals.length === 0) continue;

        for (const [dir, portal] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (dir === 'default') continue;
          if (!portal.portal_id) {
            errors.push(`${cell.pos}/${dir} (${cell.stage_id}): missing portal_id`);
          }
        }
      }
    }
    expect(errors, `Portals missing portal_id:\n${errors.join('\n')}`).toHaveLength(0);
  });

  it.each(quests)('$filename: portal_id references a valid config portal', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        const cfg = stageConfigs[cell.stage_id];
        if (!cfg || !Array.isArray(cfg.portals)) continue;

        const configIds = new Set(cfg.portals.map((p: any) => p.id));
        for (const [dir, portal] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (dir === 'default') continue;
          if (portal.portal_id && !configIds.has(portal.portal_id)) {
            errors.push(`${cell.pos}/${dir}: portal_id "${portal.portal_id}" not found in ${cell.stage_id} config`);
          }
        }
      }
    }
    expect(errors, `Invalid portal_id refs:\n${errors.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest portals — baked positions match config', () => {
  it.each(quests)('$filename: re-baked portal positions match stored values', ({ data }) => {
    const errors: string[] = [];
    for (const section of data.sections) {
      for (const cell of section.cells || []) {
        const cfg = stageConfigs[cell.stage_id];
        if (!cfg || !Array.isArray(cfg.portals)) continue;

        // Build portal lookup by id
        const configPortalsById = new Map<string, PortalConfig>();
        for (const p of cfg.portals) {
          if (p.id) configPortalsById.set(p.id, p);
        }

        for (const [dir, stored] of Object.entries(cell.portals || {}) as [string, any][]) {
          if (dir === 'default') continue;
          if (!stored.portal_id) continue;

          const configPortal = configPortalsById.get(stored.portal_id);
          if (!configPortal) continue; // already caught by the traceability test

          const rebaked = rebakePortal(configPortal);

          for (const field of ['gate', 'spawn', 'trigger', 'gate_rot'] as const) {
            const storedVal = stored[field];
            const rebakedVal = rebaked[field];
            if (!storedVal || !rebakedVal) continue;
            if (JSON.stringify(storedVal) !== JSON.stringify(rebakedVal)) {
              errors.push(
                `${cell.pos}/${dir} ${field}: stored=${JSON.stringify(storedVal)} vs rebaked=${JSON.stringify(rebakedVal)}`
              );
            }
          }

          if (stored.compass_label !== rebaked.compass_label) {
            errors.push(
              `${cell.pos}/${dir} compass_label: stored="${stored.compass_label}" vs rebaked="${rebaked.compass_label}"`
            );
          }
        }
      }
    }
    expect(errors, `Stale portal bakes:\n${errors.join('\n')}`).toHaveLength(0);
  });
});
