#!/usr/bin/env node
/**
 * Patches portal_id (and bakes missing portals) into quest JSON files.
 *
 * For quests that already have baked portals: matches by gate position to find
 * the correct config portal (handles fallback portal assignments from bidirectional fixup).
 * For quests without baked portals: bakes full portal data from config.
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

// --- Portal bake math (mirrors quest-io.ts computePortalPositions) ---

const DIRECTION_ROTATIONS = { north: 0, south: Math.PI, east: Math.PI / 2, west: -Math.PI / 2 };
const GATE_MODEL_ROTATIONS = { north: 0, south: Math.PI, east: -Math.PI / 2, west: Math.PI / 2 };
const CONFIG_DIR_TO_COMPASS = { north: 'N', south: 'S', east: 'E', west: 'W' };

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

/** Find config portal matching a stored portal by gate position (nearest match) */
function findConfigPortalByGate(storedGate, configPortals) {
  let best = null;
  let bestDist = Infinity;
  for (const p of configPortals) {
    const g = round3(p.position);
    const dx = g[0] - storedGate[0];
    const dy = g[1] - storedGate[1];
    const dz = g[2] - storedGate[2];
    const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (dist < bestDist) {
      bestDist = dist;
      best = p;
    }
  }
  // Only match if within 0.5 units (handles small rounding diffs)
  return bestDist < 0.5 ? best : null;
}

// --- Main ---

const stageConfigs = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
const manifest = JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, 'manifest.json'), 'utf-8'));

let totalPatched = 0;
let totalBaked = 0;
let totalWarnings = 0;

for (const questName of manifest) {
  const questPath = path.join(QUESTS_DIR, `${questName}.json`);
  const quest = JSON.parse(fs.readFileSync(questPath, 'utf-8'));
  let patched = 0;
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

      const existingPortals = cell.portals || {};
      const hasExistingPortals = Object.keys(existingPortals).some(k => k !== 'default');

      if (hasExistingPortals) {
        // Patch portal_id into existing portals — match by gate position
        for (const [gridDir, portal] of Object.entries(existingPortals)) {
          if (gridDir === 'default') continue;
          if (portal.portal_id) continue;

          // Try direction-based match first
          const configDir = reverseRotateDirection(gridDir, rotation);
          let configPortal = configByDir.get(configDir);

          // Verify by gate position; if mismatch, fall back to position-based match
          if (configPortal && portal.gate) {
            const expectedGate = round3(configPortal.position);
            if (JSON.stringify(expectedGate) !== JSON.stringify(portal.gate)) {
              configPortal = findConfigPortalByGate(portal.gate, cfg.portals);
            }
          } else if (!configPortal && portal.gate) {
            configPortal = findConfigPortalByGate(portal.gate, cfg.portals);
          }

          if (configPortal && configPortal.id) {
            // Re-bake from the matched config portal to fix any stale data
            const rebaked = computePortalPositions(configPortal);
            cell.portals[gridDir] = rebaked;
            patched++;
          } else {
            console.warn(`  WARN: ${questName} ${cell.pos}/${gridDir}: no matching config portal found`);
            totalWarnings++;
          }
        }
      } else {
        // Bake portals from scratch
        const portalDirs = new Set(Object.keys(connections));
        if (cell.warp_edge) portalDirs.add(cell.warp_edge);
        if (cell.is_start || cell.is_end) {
          for (const origDir of cfg.portals.map(p => p.direction)) {
            const gridDir = rotateDirection(origDir, rotation);
            if (!connections[gridDir]) portalDirs.add(gridDir);
          }
        }

        const portals = {};
        for (const gridDir of portalDirs) {
          const configDir = reverseRotateDirection(gridDir, rotation);
          const configPortal = configByDir.get(configDir);
          if (configPortal) {
            portals[gridDir] = computePortalPositions(configPortal);
            baked++;
          }
        }

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
          let portalCfg = targetCfg.portals.find(p => p.direction === configDir);
          if (!portalCfg) {
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
  console.log(`${questName}: patched ${patched} portal_ids, baked ${baked} new portals`);
  totalPatched += patched;
  totalBaked += baked;
}

console.log(`\nDone. Patched ${totalPatched} portal_ids, baked ${totalBaked} new portals. Warnings: ${totalWarnings}`);
