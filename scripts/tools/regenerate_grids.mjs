#!/usr/bin/env node
/**
 * regenerate_grids.mjs — Regenerate grid layouts for quest JSON files
 *
 * Generates new random grid layouts for each "grid" section (a, b) while
 * preserving cell objects (enemies, boxes, quest items, triggers, etc.)
 * by mapping old cells to new cells based on path order.
 *
 * Usage:
 *   node scripts/tools/regenerate_grids.mjs                          # all story quests
 *   node scripts/tools/regenerate_grids.mjs --field                  # all field quests
 *   node scripts/tools/regenerate_grids.mjs --field valley_field     # specific field quest
 *   node scripts/tools/regenerate_grids.mjs search_and_rescue        # specific story quest
 *   node scripts/tools/regenerate_grids.mjs --dry-run                # preview without writing
 */

import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { resolve, basename } from 'path';

// ============================================================================
// Config
// ============================================================================

const ROOT = resolve(import.meta.dirname, '..', '..');
const QUEST_DIR = resolve(ROOT, 'data', 'quests');
const CONFIG_PATH = resolve(ROOT, 'data', 'stage_configs', 'unified-stage-configs.json');

const EDITOR_AREAS = [
  { key: 'valley',    prefix: 's01' },
  { key: 'wetlands',  prefix: 's02' },
  { key: 'snowfield', prefix: 's03' },
  { key: 'makara',    prefix: 's04' },
  { key: 'paru',      prefix: 's05' },
  { key: 'arca',      prefix: 's06' },
  { key: 'shrine',    prefix: 's07' },
  { key: 'tower',     prefix: 's08' },
];

const AREA_ID_TO_KEY = {
  gurhacia: 'valley',
  ozette: 'wetlands',
  rioh: 'snowfield',
  makara: 'makara',
  paru: 'paru',
  arca: 'arca',
  dark: 'shrine',
  tower: 'tower',
};

// ============================================================================
// Stage config loading
// ============================================================================

/** @type {Record<string, {portals: Array<{id?: string, direction: string, position: number[]}>, defaultSpawn?: any}>} */
const fullConfigs = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));

/** @type {Record<string, Set<string>>} - gate directions per stage */
const gateCache = {};

function getOriginalGates(stageName) {
  if (gateCache[stageName]) return gateCache[stageName];
  const config = fullConfigs[stageName];
  if (!config) { gateCache[stageName] = new Set(); return gateCache[stageName]; }
  gateCache[stageName] = new Set(
    (config.portals || []).filter(p => p.direction).map(p => p.direction)
  );
  return gateCache[stageName];
}

const DIR_ORDER = ['north', 'east', 'south', 'west'];

function rotateDirection(dir, rotation) {
  if (rotation === 0) return dir;
  const idx = DIR_ORDER.indexOf(dir);
  if (idx < 0) return dir;
  const steps = ((rotation / 90) % 4 + 4) % 4;
  return DIR_ORDER[(idx + steps) % 4];
}

function getRotatedGates(stageName, rotation) {
  const original = getOriginalGates(stageName);
  if (rotation === 0) return original;
  return new Set([...original].map(g => rotateDirection(g, rotation)));
}

function oppositeDirection(dir) {
  return { north: 'south', south: 'north', east: 'west', west: 'east' }[dir];
}

function getNeighbor(row, col, dir) {
  switch (dir) {
    case 'north': return [row - 1, col];
    case 'south': return [row + 1, col];
    case 'east': return [row, col + 1];
    case 'west': return [row, col - 1];
  }
}

function isValidPos(row, col, gridSize) {
  return row >= 0 && row < gridSize && col >= 0 && col < gridSize;
}

function getStagesForArea(areaKey, variant) {
  const area = EDITOR_AREAS.find(a => a.key === areaKey);
  if (!area) return [];
  const prefix = `${area.prefix}${variant}_`;
  return Object.keys(fullConfigs).filter(k => k.startsWith(prefix));
}

// ============================================================================
// Grid generation (ported from grid-generation.ts)
// ============================================================================

function tryGenerateGrid(areaKey, variant, params) {
  const { gridSize, usedCells, keyGates, branches } = params;
  const grid = Array.from({ length: gridSize }, () =>
    Array.from({ length: gridSize }, () => ({
      stageName: null, rotation: 0, entryDirection: null,
      isKeyGate: false, keyGateDirection: null,
      hasKey: false, keyForCell: null,
      isStart: false, isEnd: false, isBranch: false, pathOrder: -1,
    }))
  );

  const allStages = getStagesForArea(areaKey, variant);
  if (allStages.length === 0) return null;

  const startStageName = allStages.find(s => s.endsWith('_sa1'));
  if (!startStageName) return null;

  const candidateStages = allStages.filter(s => s !== startStageName);
  const usedStages = new Set();
  const path = [];

  // Try all 4 rotations for sa1, pick a valid one randomly
  const sa1Gates = getOriginalGates(startStageName);
  const sa1Placements = [];
  for (const rot of [0, 90, 180, 270]) {
    const rotatedGates = [...sa1Gates].map(g => rotateDirection(g, rot));
    for (const exitDir of rotatedGates) {
      let row, col;
      switch (exitDir) {
        case 'south': row = 0; col = Math.floor(gridSize / 2); break;
        case 'north': row = gridSize - 1; col = Math.floor(gridSize / 2); break;
        case 'east': row = Math.floor(gridSize / 2); col = 0; break;
        case 'west': row = Math.floor(gridSize / 2); col = gridSize - 1; break;
        default: continue;
      }
      let valid = true;
      for (const gate of rotatedGates) {
        if (gate === exitDir) continue;
        const [nr, nc] = getNeighbor(row, col, gate);
        if (isValidPos(nr, nc, gridSize)) { valid = false; break; }
      }
      if (valid) sa1Placements.push({ row, col, rotation: rot, exitDir });
    }
  }
  if (sa1Placements.length === 0) return null;
  const sa1Pick = sa1Placements[Math.floor(Math.random() * sa1Placements.length)];

  grid[sa1Pick.row][sa1Pick.col] = {
    stageName: startStageName, rotation: sa1Pick.rotation, entryDirection: null,
    isKeyGate: false, keyGateDirection: null, hasKey: false, keyForCell: null,
    isStart: true, isEnd: false, isBranch: false, pathOrder: 0,
  };
  usedStages.add(startStageName);
  path.push([sa1Pick.row, sa1Pick.col]);

  let currentRow = sa1Pick.row, currentCol = sa1Pick.col, lastExitDir = sa1Pick.exitDir;

  while (path.length < usedCells) {
    const [nextRow, nextCol] = getNeighbor(currentRow, currentCol, lastExitDir);
    const entryDir = oppositeDirection(lastExitDir);

    if (!isValidPos(nextRow, nextCol, gridSize)) break;
    if (grid[nextRow][nextCol].stageName) break;

    const isLastCell = path.length === usedCells - 1;
    const validCandidates = [];

    for (const stage of candidateStages) {
      for (const rot of [0, 90, 180, 270]) {
        const gates = getRotatedGates(stage, rot);
        if (!gates.has(entryDir)) continue;
        const otherGates = [...gates].filter(g => g !== entryDir);

        if (isLastCell) {
          if (otherGates.length !== 1) continue;
          const exitGate = otherGates[0];
          const [er, ec] = getNeighbor(nextRow, nextCol, exitGate);
          if (isValidPos(er, ec, gridSize)) continue;
          validCandidates.push({ stage, rotation: rot, exitDir: exitGate });
        } else {
          if (otherGates.length !== 1) continue;
          const exitGate = otherGates[0];
          const [er, ec] = getNeighbor(nextRow, nextCol, exitGate);
          if (!isValidPos(er, ec, gridSize)) continue;
          if (grid[er][ec].stageName) continue;
          validCandidates.push({ stage, rotation: rot, exitDir: exitGate });
        }
      }
    }

    if (validCandidates.length === 0) {
      if (path.length >= 3) {
        const earlyEndStages = [...candidateStages].sort((a, b) =>
          (usedStages.has(a) ? 1 : 0) - (usedStages.has(b) ? 1 : 0)
        );
        for (const stage of earlyEndStages) {
          let earlyEnd = false;
          for (const rot of [0, 90, 180, 270]) {
            const gates = getRotatedGates(stage, rot);
            if (!gates.has(entryDir)) continue;
            const otherGates = [...gates].filter(g => g !== entryDir);
            if (otherGates.length !== 1) continue;
            const exitGate = otherGates[0];
            const [er, ec] = getNeighbor(nextRow, nextCol, exitGate);
            if (!isValidPos(er, ec, gridSize)) {
              grid[nextRow][nextCol] = {
                stageName: stage, rotation: rot, entryDirection: entryDir,
                isKeyGate: false, keyGateDirection: exitGate,
                hasKey: false, keyForCell: null,
                isStart: false, isEnd: true, isBranch: false, pathOrder: path.length,
              };
              path.push([nextRow, nextCol]);
              earlyEnd = true;
              break;
            }
          }
          if (earlyEnd) break;
        }
      }
      break;
    }

    const unused = validCandidates.filter(c => !usedStages.has(c.stage));
    const pool = unused.length > 0 ? unused : validCandidates;
    const chosen = pool[Math.floor(Math.random() * pool.length)];
    usedStages.add(chosen.stage);
    grid[nextRow][nextCol] = {
      stageName: chosen.stage, rotation: chosen.rotation, entryDirection: entryDir,
      isKeyGate: false, keyGateDirection: isLastCell ? chosen.exitDir : null,
      hasKey: false, keyForCell: null,
      isStart: false, isEnd: isLastCell, isBranch: false, pathOrder: path.length,
    };
    path.push([nextRow, nextCol]);
    if (isLastCell || !chosen.exitDir) break;
    currentRow = nextRow; currentCol = nextCol; lastExitDir = chosen.exitDir;
  }

  if (path.length < 3) return null;

  // Fix end cell
  const [endRow, endCol] = path[path.length - 1];
  const endCell = grid[endRow][endCol];
  if (!endCell.isEnd || !endCell.keyGateDirection) {
    const entryDir = endCell.entryDirection;
    if (!entryDir) return null;
    let foundValidEnd = false;
    const endStages = [...candidateStages].sort((a, b) =>
      (usedStages.has(a) ? 1 : 0) - (usedStages.has(b) ? 1 : 0)
    );
    for (const stage of endStages) {
      if (foundValidEnd) break;
      for (const rot of [0, 90, 180, 270]) {
        const gates = getRotatedGates(stage, rot);
        if (!gates.has(entryDir)) continue;
        let warpDir = null, hasOrphan = false;
        for (const gate of gates) {
          if (gate === entryDir) continue;
          const [nr, nc] = getNeighbor(endRow, endCol, gate);
          if (!isValidPos(nr, nc, gridSize)) { warpDir = gate; }
          else if (grid[nr][nc].stageName) {
            const neighborGates = getRotatedGates(grid[nr][nc].stageName, grid[nr][nc].rotation);
            if (!neighborGates.has(oppositeDirection(gate))) { hasOrphan = true; break; }
          }
        }
        if (hasOrphan || !warpDir) continue;
        grid[endRow][endCol] = { ...endCell, stageName: stage, rotation: rot, isEnd: true, keyGateDirection: warpDir };
        foundValidEnd = true; break;
      }
    }
    if (!foundValidEnd) return null;
  }

  // Add branches
  const branchCells = [];
  if (branches > 0) {
    const branchCandidates = [];
    for (const [pr, pc] of path) {
      const cell = grid[pr][pc];
      if (cell.isStart || cell.isEnd) continue;
      const currentGates = getRotatedGates(cell.stageName, cell.rotation);
      const exitDir = [...currentGates].find(g => g !== cell.entryDirection);
      if (!exitDir) continue;

      for (const dir of ['north', 'south', 'east', 'west']) {
        if (dir === cell.entryDirection || dir === exitDir) continue;
        const [br, bc] = getNeighbor(pr, pc, dir);
        if (!isValidPos(br, bc, gridSize)) continue;
        if (grid[br][bc].stageName) continue;

        if (currentGates.has(dir)) {
          branchCandidates.push({ pathCell: [pr, pc], branchDir: dir, branchPos: [br, bc], needsReplacement: false });
        } else {
          for (const stage of candidateStages) {
            let found = false;
            for (const rot of [0, 90, 180, 270]) {
              const gates = getRotatedGates(stage, rot);
              if (!gates.has(cell.entryDirection)) continue;
              if (!gates.has(exitDir)) continue;
              if (!gates.has(dir)) continue;
              let valid = true;
              for (const gate of gates) {
                if (gate === cell.entryDirection || gate === exitDir || gate === dir) continue;
                const [nr, nc] = getNeighbor(pr, pc, gate);
                if (isValidPos(nr, nc, gridSize) && grid[nr][nc].stageName) { valid = false; break; }
              }
              if (!valid) continue;
              branchCandidates.push({
                pathCell: [pr, pc], branchDir: dir, branchPos: [br, bc],
                needsReplacement: true, replacementStage: stage, replacementRotation: rot,
              });
              found = true; break;
            }
            if (found) break;
          }
        }
      }
    }

    const shuffled = [...branchCandidates].sort(() => Math.random() - 0.5);
    let placed = 0;
    for (const cand of shuffled) {
      if (placed >= branches) break;
      const [pr, pc] = cand.pathCell;
      const [br, bc] = cand.branchPos;
      if (grid[br][bc].stageName) continue;

      if (cand.needsReplacement && cand.replacementStage) {
        grid[pr][pc] = { ...grid[pr][pc], stageName: cand.replacementStage, rotation: cand.replacementRotation ?? 0 };
      }

      const branchEntry = oppositeDirection(cand.branchDir);
      const shuffledStages = [...candidateStages].sort((a, b) => {
        const aUsed = usedStages.has(a) ? 1 : 0;
        const bUsed = usedStages.has(b) ? 1 : 0;
        if (aUsed !== bUsed) return aUsed - bUsed;
        return Math.random() - 0.5;
      });
      let placedBranch = false;
      for (const stage of shuffledStages) {
        if (placedBranch) break;
        const gates = getOriginalGates(stage);
        if (gates.size !== 1) continue;
        for (const rot of [0, 90, 180, 270]) {
          const rotatedGate = rotateDirection([...gates][0], rot);
          if (rotatedGate !== branchEntry) continue;
          grid[br][bc] = {
            stageName: stage, rotation: rot, entryDirection: branchEntry,
            isKeyGate: false, keyGateDirection: null, hasKey: false, keyForCell: null,
            isStart: false, isEnd: false, isBranch: true, pathOrder: -1,
          };
          branchCells.push([br, bc]);
          usedStages.add(stage);
          placed++; placedBranch = true; break;
        }
      }
    }
  }

  // Place key-gates and keys
  const keyLinks = {};
  if (keyGates > 0) {
    const branchToPathOrder = new Map();
    for (const [br, bc] of branchCells) {
      const branchCell = grid[br][bc];
      if (!branchCell.entryDirection) continue;
      const [pr, pc] = getNeighbor(br, bc, branchCell.entryDirection);
      if (isValidPos(pr, pc, gridSize) && grid[pr][pc].stageName) {
        branchToPathOrder.set(`${br},${bc}`, grid[pr][pc].pathOrder);
      }
    }

    const keyGateCandidates = path.slice(3).filter(([r, c]) => !grid[r][c].isEnd);
    const shuffledGateCells = [...keyGateCandidates].sort(() => Math.random() - 0.5);
    let placed = 0;

    for (const [gateRow, gateCol] of shuffledGateCells) {
      if (placed >= keyGates) break;
      const gateCell = grid[gateRow][gateCol];
      const gatePathOrder = gateCell.pathOrder;

      const mainPathCandidates = path.filter(([r, c]) => {
        const cell = grid[r][c];
        return cell.pathOrder < gatePathOrder && cell.pathOrder > 0 && !cell.hasKey && !cell.isKeyGate;
      });
      const branchKeyCandidates = branchCells.filter(([br, bc]) => {
        const cell = grid[br][bc];
        if (cell.hasKey) return false;
        const order = branchToPathOrder.get(`${br},${bc}`);
        return order !== undefined && order < gatePathOrder;
      });

      let keyCandidates;
      if (branchKeyCandidates.length > 0 && Math.random() < 0.8) keyCandidates = branchKeyCandidates;
      else if (mainPathCandidates.length > 0) keyCandidates = mainPathCandidates;
      else if (branchKeyCandidates.length > 0) keyCandidates = branchKeyCandidates;
      else continue;

      const [keyRow, keyCol] = keyCandidates[Math.floor(Math.random() * keyCandidates.length)];
      const gates = getRotatedGates(gateCell.stageName, gateCell.rotation);
      const exitGates = [...gates].filter(g => g !== gateCell.entryDirection);
      if (exitGates.length === 0) continue;

      const lockedDir = exitGates[Math.floor(Math.random() * exitGates.length)];
      gateCell.isKeyGate = true;
      gateCell.keyGateDirection = lockedDir;
      grid[keyRow][keyCol].hasKey = true;
      grid[keyRow][keyCol].keyForCell = [gateRow, gateCol];
      keyLinks[`${gateRow},${gateCol}`] = `${keyRow},${keyCol}`;
      placed++;
    }
  }

  // Validate all gate connections
  for (let r = 0; r < gridSize; r++) {
    for (let c = 0; c < gridSize; c++) {
      const cell = grid[r][c];
      if (!cell.stageName) continue;
      const gates = getRotatedGates(cell.stageName, cell.rotation);
      for (const dir of gates) {
        const [nr, nc] = getNeighbor(r, c, dir);
        if (!isValidPos(nr, nc, gridSize)) continue;
        const neighbor = grid[nr][nc];
        if (!neighbor.stageName) return null;
        const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation);
        if (!neighborGates.has(oppositeDirection(dir))) return null;
      }
    }
  }

  // BFS validation — ensure end is reachable
  const simVisited = new Set();
  const simKeys = new Set();
  const simQueue = [[sa1Pick.row, sa1Pick.col]];
  while (simQueue.length > 0) {
    const [r, c] = simQueue.shift();
    const key = `${r},${c}`;
    if (simVisited.has(key)) continue;
    simVisited.add(key);
    const cell = grid[r][c];
    if (!cell.stageName) continue;
    if (cell.hasKey && cell.keyForCell) simKeys.add(`${cell.keyForCell[0]},${cell.keyForCell[1]}`);
    const gates = getRotatedGates(cell.stageName, cell.rotation);
    for (const dir of gates) {
      if (cell.isKeyGate && cell.keyGateDirection === dir && !simKeys.has(key)) continue;
      const [nr, nc] = getNeighbor(r, c, dir);
      if (!isValidPos(nr, nc, gridSize)) continue;
      if (!grid[nr][nc].stageName) continue;
      if (simVisited.has(`${nr},${nc}`)) continue;
      const neighborGates = getRotatedGates(grid[nr][nc].stageName, grid[nr][nc].rotation);
      if (!neighborGates.has(oppositeDirection(dir))) continue;
      simQueue.push([nr, nc]);
    }
  }
  if (!simVisited.has(`${endRow},${endCol}`)) return null;

  return { grid, path, branchCells, keyLinks, sa1Row: sa1Pick.row, sa1Col: sa1Pick.col, endRow, endCol, gridSize };
}

function generateGrid(areaKey, variant, params, maxAttempts = 500) {
  for (let i = 0; i < maxAttempts; i++) {
    const result = tryGenerateGrid(areaKey, variant, params);
    if (result) return result;
  }
  return null;
}

// ============================================================================
// Quest JSON cell building
// ============================================================================

function reverseRotateDirection(gridDir, rotation) {
  return rotateDirection(gridDir, (360 - rotation) % 360);
}

/** BFS to compute path_order for all cells in a grid */
function computePathOrder(cellsByPos, startPos, gridSize) {
  const order = new Map();
  if (!startPos || !cellsByPos.has(startPos)) return order;
  const visited = new Set();
  const queue = [startPos];
  visited.add(startPos);
  let idx = 0;
  while (queue.length > 0) {
    const pos = queue.shift();
    order.set(pos, idx++);
    const cell = cellsByPos.get(pos);
    if (!cell) continue;
    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation || 0);
    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);
      const nk = `${nr},${nc}`;
      if (!visited.has(nk) && cellsByPos.has(nk)) {
        visited.add(nk);
        queue.push(nk);
      }
    }
  }
  return order;
}

/** Build a quest JSON cell from generated grid data + migrated objects */
function buildQuestCell(pos, genCell, connections, gridSize, keyLinks, startPos, endPos, pathOrder, objects) {
  const stageConfig = fullConfigs[genCell.stageName];
  const rotation = genCell.rotation || 0;

  // Compute portals
  const portals = {};
  if (stageConfig && stageConfig.portals) {
    const configPortalsByDir = new Map();
    for (const p of stageConfig.portals) {
      configPortalsByDir.set(p.direction, p);
    }
    const allGridDirs = new Set(Object.keys(connections));
    // For start/end cells, include all unconnected gate directions
    const gates = getRotatedGates(genCell.stageName, rotation);
    if (pos === startPos || pos === endPos) {
      for (const dir of gates) {
        if (!connections[dir]) allGridDirs.add(dir);
      }
    }
    // Warp edge
    let warpEdge = '';
    if (pos === endPos) {
      for (const dir of gates) {
        const [row, col] = pos.split(',').map(Number);
        const [nr, nc] = getNeighbor(row, col, dir);
        if (!isValidPos(nr, nc, gridSize) || !connections[dir]) {
          warpEdge = dir;
          break;
        }
      }
    }
    for (const gridDir of allGridDirs) {
      const configDir = reverseRotateDirection(gridDir, rotation);
      const portal = configPortalsByDir.get(configDir);
      if (portal && portal.id) {
        portals[gridDir] = portal.id;
      }
    }
    if (stageConfig.defaultSpawn) {
      portals['default'] = 'default';
    }

    // Build cell data
    const keyGateDirection = genCell.isKeyGate ? (genCell.keyGateDirection || '') : '';
    const hasKey = genCell.hasKey;
    const keyForCellPos = hasKey && genCell.keyForCell ? `${genCell.keyForCell[0]},${genCell.keyForCell[1]}` : '';

    const cellData = {
      pos,
      stage_id: genCell.stageName,
      rotation,
      connections,
      portals,
      is_start: pos === startPos,
      is_end: pos === endPos,
      is_branch: Object.keys(connections).length > 2 || genCell.isBranch,
      has_key: hasKey,
      key_for_cell: keyForCellPos,
      is_key_gate: genCell.isKeyGate,
      key_gate_direction: keyGateDirection,
      key_drop: '',
      required_keys: genCell.isKeyGate ? 1 : 0,
      warp_edge: warpEdge,
      path_order: pathOrder,
    };

    cellData.objects = objects && objects.length > 0 ? objects : [];

    return cellData;
  }

  // Fallback (no config)
  let warpEdge = '';
  if (pos === endPos) {
    const gates = getRotatedGates(genCell.stageName, rotation);
    const [row, col] = pos.split(',').map(Number);
    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);
      if (!isValidPos(nr, nc, gridSize)) { warpEdge = dir; break; }
    }
  }

  const cellData = {
    pos,
    stage_id: genCell.stageName,
    rotation,
    connections,
    portals,
    is_start: pos === startPos,
    is_end: pos === endPos,
    is_branch: Object.keys(connections).length > 2 || genCell.isBranch,
    has_key: genCell.hasKey,
    key_for_cell: genCell.hasKey && genCell.keyForCell ? `${genCell.keyForCell[0]},${genCell.keyForCell[1]}` : '',
    is_key_gate: genCell.isKeyGate,
    key_gate_direction: genCell.isKeyGate ? (genCell.keyGateDirection || '') : '',
    key_drop: '',
    required_keys: genCell.isKeyGate ? 1 : 0,
    warp_edge: warpEdge,
    path_order: pathOrder,
    objects: objects && objects.length > 0 ? objects : [],
  };

  return cellData;
}

// ============================================================================
// Object migration
// ============================================================================

/**
 * Migrate objects from old section cells to new grid cells.
 * Strategy:
 *  - Start cell objects → new start cell
 *  - End cell objects → new end cell
 *  - Main path objects → map by path_order ratio (old order/old max → new order)
 *  - Branch objects → map to new branches by index
 */
function migrateObjects(oldCells, newCellPositions, newGrid, newPath, newBranches, newStartPos, newEndPos) {
  // Categorize old cells
  const oldStart = oldCells.find(c => c.is_start);
  const oldEnd = oldCells.find(c => c.is_end);
  const oldMainPath = oldCells
    .filter(c => !c.is_start && !c.is_end && c.path_order >= 0)
    .sort((a, b) => a.path_order - b.path_order);
  const oldBranches = oldCells
    .filter(c => c.path_order < 0 || (c.is_branch && !c.is_start && !c.is_end))
    .filter(c => c !== oldStart && c !== oldEnd)
    // Exclude main-path cells that were double-counted
    .filter(c => !oldMainPath.includes(c));

  // New cell ordering
  const newMainPath = newPath
    .map(([r, c]) => `${r},${c}`)
    .filter(p => p !== newStartPos && p !== newEndPos);

  const newBranchPositions = newBranches.map(([r, c]) => `${r},${c}`);

  // Result: pos → objects[]
  const objectMap = {};
  for (const pos of newCellPositions) objectMap[pos] = [];

  // Transfer start cell objects
  if (oldStart && oldStart.objects && oldStart.objects.length > 0) {
    objectMap[newStartPos] = [...(objectMap[newStartPos] || []), ...oldStart.objects];
  }

  // Transfer end cell objects
  if (oldEnd && oldEnd.objects && oldEnd.objects.length > 0) {
    objectMap[newEndPos] = [...(objectMap[newEndPos] || []), ...oldEnd.objects];
  }

  // Transfer main path objects (map by proportional position)
  for (let i = 0; i < oldMainPath.length; i++) {
    const oldCell = oldMainPath[i];
    if (!oldCell.objects || oldCell.objects.length === 0) continue;
    // Map to proportional position in new path
    const ratio = oldMainPath.length > 1 ? i / (oldMainPath.length - 1) : 0;
    const newIdx = Math.min(Math.round(ratio * (newMainPath.length - 1)), newMainPath.length - 1);
    const targetPos = newMainPath[newIdx] || newEndPos;
    objectMap[targetPos] = [...(objectMap[targetPos] || []), ...oldCell.objects];
  }

  // Transfer branch objects (map by index)
  for (let i = 0; i < oldBranches.length; i++) {
    const oldCell = oldBranches[i];
    if (!oldCell.objects || oldCell.objects.length === 0) continue;
    const targetPos = i < newBranchPositions.length
      ? newBranchPositions[i]
      : newMainPath[newMainPath.length - 1] || newEndPos;
    objectMap[targetPos] = [...(objectMap[targetPos] || []), ...oldCell.objects];
  }

  return objectMap;
}

// ============================================================================
// Section regeneration
// ============================================================================

// Progressive difficulty scaling per area (valley=easy → shrine=hardest)
// Order matches game progression: valley, wetlands, snowfield, makara, paru, arca, shrine
const AREA_SCALING = {
  valley:    { usedCells: [10, 12], branches: [1, 1], keyGates: [0, 1] },
  wetlands:  { usedCells: [11, 13], branches: [1, 2], keyGates: [0, 1] },
  snowfield: { usedCells: [11, 13], branches: [2, 2], keyGates: [1, 2] },
  makara:    { usedCells: [12, 14], branches: [2, 3], keyGates: [1, 2] },
  paru:      { usedCells: [13, 15], branches: [3, 3], keyGates: [1, 2] },
  arca:      { usedCells: [14, 16], branches: [3, 4], keyGates: [1, 2] },
  shrine:    { usedCells: [15, 17], branches: [4, 4], keyGates: [2, 3] },
};

function regenerateSection(section, areaKey) {
  const variant = section.area || 'a';
  const oldCells = section.cells || [];

  // Use progressive scaling if available, otherwise fall back to old analysis
  const scaling = AREA_SCALING[areaKey];
  const variantIdx = variant === 'b' ? 1 : 0;

  let params;
  if (scaling) {
    params = {
      gridSize: 5,
      usedCells: scaling.usedCells[variantIdx],
      branches: scaling.branches[variantIdx],
      keyGates: scaling.keyGates[variantIdx],
    };
  } else {
    const oldMainPath = oldCells.filter(c => c.path_order >= 0);
    const oldBranches = oldCells.filter(c => c.path_order < 0 && !c.is_start);
    const oldKeyGates = oldCells.filter(c => c.is_key_gate);
    params = {
      gridSize: 5,
      usedCells: Math.min(Math.max(oldMainPath.length, 5) + 1, 10),
      branches: Math.max(oldBranches.length, 2),
      keyGates: Math.max(oldKeyGates.length, 1),
    };
  }

  console.log(`    Generating: usedCells=${params.usedCells}, branches=${params.branches}, keyGates=${params.keyGates}`);

  const result = generateGrid(areaKey, variant, params);
  if (!result) {
    console.log(`    ⚠ Generation failed, trying with fewer constraints...`);
    // Retry with relaxed params
    const relaxed = { ...params, branches: 1, keyGates: 0 };
    const result2 = generateGrid(areaKey, variant, relaxed);
    if (!result2) {
      console.log(`    ✗ Generation failed entirely, skipping section`);
      return null;
    }
    return buildSection(section, result2, oldCells, areaKey);
  }

  return buildSection(section, result, oldCells, areaKey);
}

function buildSection(section, genResult, oldCells, areaKey) {
  const { grid, path, branchCells, keyLinks, sa1Row, sa1Col, endRow, endCol, gridSize } = genResult;
  const startPos = `${sa1Row},${sa1Col}`;
  const endPos = `${endRow},${endCol}`;

  // Collect all cell positions
  const allPositions = [];
  const cellMap = new Map();  // pos → genCell
  for (let r = 0; r < gridSize; r++) {
    for (let c = 0; c < gridSize; c++) {
      if (grid[r][c].stageName) {
        const pos = `${r},${c}`;
        allPositions.push(pos);
        cellMap.set(pos, grid[r][c]);
      }
    }
  }

  // Compute connections
  const connectionMap = {};
  for (const pos of allPositions) {
    const [r, c] = pos.split(',').map(Number);
    const cell = cellMap.get(pos);
    const gates = getRotatedGates(cell.stageName, cell.rotation);
    const conns = {};
    for (const dir of gates) {
      const [nr, nc] = getNeighbor(r, c, dir);
      const nk = `${nr},${nc}`;
      if (cellMap.has(nk)) conns[dir] = nk;
    }
    connectionMap[pos] = conns;
  }

  // Compute path order via BFS
  const pathOrderMap = computePathOrder(cellMap, startPos, gridSize);

  // Migrate objects
  const objectMap = migrateObjects(
    oldCells, allPositions, grid, path, branchCells, startPos, endPos
  );

  // Build quest JSON cells
  const newCells = [];
  for (const pos of allPositions) {
    const genCell = cellMap.get(pos);
    const connections = connectionMap[pos];
    const pathOrder = pathOrderMap.get(pos) ?? -1;
    const objects = objectMap[pos] || [];
    const cell = buildQuestCell(pos, genCell, connections, gridSize, keyLinks, startPos, endPos, pathOrder, objects);
    newCells.push(cell);
  }

  // Sort by path_order
  newCells.sort((a, b) => (a.path_order ?? 999) - (b.path_order ?? 999));

  // Reconstruct section
  return {
    type: section.type,
    area: section.area,
    start_pos: startPos,
    end_pos: endPos,
    cells: newCells,
    ...(section.entry_direction ? { entry_direction: section.entry_direction } : {}),
    ...(section.exit_direction ? { exit_direction: section.exit_direction } : {}),
    ...(section.warp_requires ? { warp_requires: section.warp_requires } : {}),
  };
}

// ============================================================================
// Main
// ============================================================================

const FIELD_QUEST_DIR = resolve(ROOT, 'data', 'field_quests');

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const useField = args.includes('--field');
const questFilter = args.find(a => !a.startsWith('--'));

const questDir = useField ? FIELD_QUEST_DIR : QUEST_DIR;
const questFiles = readdirSync(questDir)
  .filter(f => f.endsWith('.json') && f !== 'manifest.json')
  .filter(f => !questFilter || f.replace('.json', '') === questFilter);

if (questFiles.length === 0) {
  console.log('No matching quest files found.');
  process.exit(1);
}

console.log(`\n=== Regenerating grids for ${questFiles.length} quest(s) ===\n`);

for (const filename of questFiles) {
  const filepath = resolve(questDir, filename);
  const quest = JSON.parse(readFileSync(filepath, 'utf8'));
  const areaKey = AREA_ID_TO_KEY[quest.area_id] || 'valley';

  console.log(`📋 ${quest.name} (${filename}) — area: ${areaKey}`);

  if (!quest.sections || quest.sections.length === 0) {
    console.log('  No sections, skipping.\n');
    continue;
  }

  let modified = false;

  for (let i = 0; i < quest.sections.length; i++) {
    const section = quest.sections[i];
    if (section.type !== 'grid') {
      console.log(`  Section ${i} (${section.type}, area=${section.area}): skipped (not a grid)`);
      continue;
    }

    console.log(`  Section ${i} (grid, area=${section.area}): ${section.cells.length} cells`);

    const newSection = regenerateSection(section, areaKey);
    if (newSection) {
      quest.sections[i] = newSection;
      modified = true;
      console.log(`    ✓ Regenerated: ${newSection.cells.length} cells, start=${newSection.start_pos}, end=${newSection.end_pos}`);
    }
  }

  if (modified) {
    quest.last_updated = new Date().toISOString().slice(0, 10);
    if (dryRun) {
      console.log(`  [DRY RUN] Would write ${filepath}\n`);
    } else {
      writeFileSync(filepath, JSON.stringify(quest, null, 2) + '\n');
      console.log(`  ✏ Written: ${filepath}\n`);
    }
  } else {
    console.log('  No changes.\n');
  }
}

console.log('Done.\n');
