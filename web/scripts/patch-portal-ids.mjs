#!/usr/bin/env node
/**
 * Patches portal_id (and bakes missing portals) into quest JSON files.
 * Fixes east/west portal swap: config labels have east/west inverted vs physical positions.
 *
 * Usage: node web/scripts/patch-portal-ids.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const QUESTS_DIR = path.resolve(__dirname, '../../data/quests');
const CONFIG_PATH = path.resolve(__dirname, '../public/data/stage_configs/unified-stage-configs.json');

// --- Direction helpers ---

const DIRECTION_ORDER = ['north', 'east', 'south', 'west'];
const OPPOSITE = { north: 'south', south: 'north', east: 'west', west: 'east' };

function rotateDirection(dir, rotation) {
  if (rotation === 0) return dir;
  const idx = DIRECTION_ORDER.indexOf(dir);
  if (idx < 0) return dir;
  const steps = ((rotation / 90) % 4 + 4) % 4;
  return DIRECTION_ORDER[(idx + steps) % 4];
}

function reverseRotateDirection(gridDir, rotation) {
  return rotateDirection(gridDir, (360 - rotation) % 360);
}

/** Swap east↔west config direction (config labels are inverted vs physical positions) */
function swapEW(dir) {
  if (dir === 'east') return 'west';
  if (dir === 'west') return 'east';
  return dir;
}

// --- Portal bake math (mirrors quest-io.ts computePortalPositions) ---

// Config east/west labels are inverted vs physical positions:
// config "east" is physically at -X → angle = -PI/2 (outward toward -X)
// config "west" is physically at +X → angle = PI/2 (outward toward +X)
const DIRECTION_ROTATIONS = { north: 0, south: Math.PI, east: -Math.PI / 2, west: Math.PI / 2 };
const GATE_MODEL_ROTATIONS = { north: 0, south: Math.PI, east: -Math.PI / 2, west: Math.PI / 2 };
// Config direction → compass label (inverted for east/west)
const CONFIG_DIR_TO_COMPASS = { north: 'N', south: 'S', east: 'W', west: 'E' };

function round3(v) {
  return [+v[0].toFixed(2), +v[1].toFixed(2), +v[2].toFixed(2)];
}

function computePortalPositions(portal) {
  const [x, , z] = portal.position;
  const rotation = (DIRECTION_ROTATIONS[portal.direction] ?? 0) + ((portal.rotationOffset || 0) * Math.PI) / 180;
  const spawnOutset = 3;
  const triggerOutset = 7;
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  const gateYRot = GATE_MODEL_ROTATIONS[portal.direction] ?? 0;
  const compassLabel = portal.compass_label ?? CONFIG_DIR_TO_COMPASS[portal.direction] ?? portal.direction[0].toUpperCase();

  const result = {};
  if (portal.id) result.portal_id = portal.id;
  result.gate = round3(portal.position);
  result.spawn = round3([x - sin * spawnOutset, 1, z - cos * spawnOutset]);
  result.trigger = round3([x - sin * triggerOutset, 0, z - cos * triggerOutset]);
  result.gate_rot = round3([0, gateYRot, 0]);
  result.compass_label = compassLabel;
  return result;
}

// --- Main ---

const stageConfigs = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
const manifest = JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, 'manifest.json'), 'utf-8'));

let totalBaked = 0;

for (const questName of manifest) {
  const questPath = path.join(QUESTS_DIR, `${questName}.json`);
  const quest = JSON.parse(fs.readFileSync(questPath, 'utf-8'));
  let baked = 0;

  for (const section of quest.sections || []) {
    const cellMap = new Map();
    for (const cell of section.cells || []) cellMap.set(cell.pos, cell);

    for (const cell of section.cells || []) {
      const cfg = stageConfigs[cell.stage_id];
      if (!cfg || !Array.isArray(cfg.portals) || cfg.portals.length === 0) continue;

      const configByDir = new Map();
      for (const p of cfg.portals) configByDir.set(p.direction, p);

      const rotation = cell.rotation || 0;
      const connections = cell.connections || {};

      // Determine which grid directions need portals
      const portalDirs = new Set(Object.keys(connections));
      if (cell.warp_edge) portalDirs.add(cell.warp_edge);
      if (cell.is_start || cell.is_end) {
        for (const origDir of cfg.portals.map(p => p.direction)) {
          const gridDir = rotateDirection(origDir, rotation);
          if (!connections[gridDir]) portalDirs.add(gridDir);
        }
      }

      // Re-bake all portals from scratch with east/west swap fix
      const portals = {};
      for (const gridDir of portalDirs) {
        const configDir = reverseRotateDirection(gridDir, rotation);
        // Swap east↔west lookup (config labels are inverted)
        const swapped = swapEW(configDir);
        const configPortal = configByDir.get(swapped) || configByDir.get(configDir);
        if (configPortal) {
          portals[gridDir] = computePortalPositions(configPortal);
          baked++;
        }
      }

      // Bake default_spawn if config has one
      if (cfg.defaultSpawn) {
        const ds = cfg.defaultSpawn;
        const dsRot = DIRECTION_ROTATIONS[ds.direction] ?? 0;
        portals['default'] = {
          gate: round3(ds.position),
          spawn: round3([ds.position[0], 1, ds.position[2]]),
          trigger: round3([ds.position[0], 0, ds.position[2]]),
          default_rotation: +dsRot.toFixed(4),
        };
      }

      if (Object.keys(portals).length > 0) {
        cell.portals = portals;
      }
    }

    // Ensure bidirectional portal coverage
    for (const cell of section.cells || []) {
      const connections = cell.connections || {};
      for (const [dir, targetPos] of Object.entries(connections)) {
        const target = cellMap.get(targetPos);
        if (!target) continue;
        const reverseDir = OPPOSITE[dir];
        const targetPortals = target.portals || {};
        if (!targetPortals[reverseDir]) {
          const targetCfg = stageConfigs[target.stage_id];
          if (!targetCfg || !Array.isArray(targetCfg.portals)) continue;
          const targetRot = target.rotation || 0;
          const configDir = reverseRotateDirection(reverseDir, targetRot);
          const swapped = swapEW(configDir);
          let portalCfg = targetCfg.portals.find(p => p.direction === swapped)
            || targetCfg.portals.find(p => p.direction === configDir);
          if (!portalCfg) {
            // Fallback: pick unused config portal
            const usedConfigDirs = new Set();
            for (const gDir of Object.keys(targetPortals)) {
              if (gDir === 'default') continue;
              usedConfigDirs.add(reverseRotateDirection(gDir, targetRot));
            }
            portalCfg = targetCfg.portals.find(p => !usedConfigDirs.has(p.direction));
          }
          if (portalCfg) {
            if (!target.portals) target.portals = {};
            target.portals[reverseDir] = computePortalPositions(portalCfg);
            baked++;
          }
        }
      }
    }
  }

  fs.writeFileSync(questPath, JSON.stringify(quest, null, 2) + '\n');
  console.log(`${questName}: baked ${baked} portals`);
  totalBaked += baked;
}

console.log(`\nDone. Baked ${totalBaked} portals total.`);
