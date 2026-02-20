/**
 * Grid Generation — extracted from GridViewer.tsx
 *
 * Parameterized by area configs so it works with any area, not just valley.
 * Generates random grid layouts with linear paths, branches, and key-gates.
 */

import type { Direction, EditorGridCell } from '../types';
import {
  getOriginalGates,
  getRotatedGates,
  rotateDirection,
  getNeighbor,
  isValidPos,
  oppositeDirection,
  getStagesForArea,
  loadAllConfigs,
} from '../hooks/useStageConfigs';

// ============================================================================
// Generation types
// ============================================================================

export interface GenParams {
  gridSize: number;
  usedCells: number;
  keyGates: number;
  branches: number;
}

/** Internal cell used during generation (richer than EditorGridCell) */
interface GenCell {
  stageName: string | null;
  rotation: number;
  entryDirection: Direction | null;
  isKeyGate: boolean;
  keyGateDirection: Direction | null;
  hasKey: boolean;
  keyForCell: [number, number] | null;
  isStart: boolean;
  isEnd: boolean;
  isBranch: boolean;
  pathOrder: number;
}

export interface GenerationResult {
  /** Sparse map of EditorGridCells keyed by "row,col" */
  cells: Record<string, EditorGridCell>;
  startPos: string | null;
  endPos: string | null;
  keyLinks: Record<string, string>;
  /** Debug info */
  pathLength: number;
}

// ============================================================================
// Core algorithm
// ============================================================================

function emptyGenCell(): GenCell {
  return {
    stageName: null,
    rotation: 0,
    entryDirection: null,
    isKeyGate: false,
    keyGateDirection: null,
    hasKey: false,
    keyForCell: null,
    isStart: false,
    isEnd: false,
    isBranch: false,
    pathOrder: -1,
  };
}

/**
 * Generate a grid layout for a given area and variant.
 * Returns sparse EditorGridCell map suitable for QuestProject.
 */
export async function generateGrid(
  areaKey: string,
  variant: string,
  params: GenParams,
  maxAttempts = 200
): Promise<GenerationResult> {
  // Ensure stage configs are loaded before attempting generation
  await loadAllConfigs();

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const result = tryGenerateGrid(areaKey, variant, params);
    if (result) return result;
  }

  // Fallback: empty
  return { cells: {}, startPos: null, endPos: null, keyLinks: {}, pathLength: 0 };
}

function tryGenerateGrid(
  areaKey: string,
  variant: string,
  params: GenParams
): GenerationResult | null {
  const { gridSize, usedCells, keyGates, branches } = params;

  // Initialize grid
  const grid: GenCell[][] = Array(gridSize).fill(null).map(() =>
    Array(gridSize).fill(null).map(emptyGenCell)
  );

  const allStages = getStagesForArea(areaKey, variant);
  if (allStages.length === 0) return null;

  // Find the sa1 stage for this area
  const startStageSuffix = 'sa1';
  const startStageName = allStages.find(s => s.endsWith(`_${startStageSuffix}`));
  if (!startStageName) return null;

  const candidateStages = allStages.filter(s => s !== startStageName);
  const path: [number, number][] = [];

  // Place sa1 at top-center, exiting south
  const sa1Row = 0;
  const sa1Col = Math.floor(gridSize / 2);

  // Check sa1's original gates: must have south, other gates must point outside grid
  const sa1Gates = getOriginalGates(startStageName);
  if (!sa1Gates.has('south')) return null;

  let sa1Valid = true;
  for (const gate of sa1Gates) {
    if (gate === 'south') continue;
    const [nr, nc] = getNeighbor(sa1Row, sa1Col, gate);
    if (isValidPos(nr, nc, gridSize)) {
      sa1Valid = false;
      break;
    }
  }
  if (!sa1Valid) return null;

  // Place start cell
  grid[sa1Row][sa1Col] = {
    stageName: startStageName,
    rotation: 0,
    entryDirection: null,
    isKeyGate: false,
    keyGateDirection: null,
    hasKey: false,
    keyForCell: null,
    isStart: true,
    isEnd: false,
    isBranch: false,
    pathOrder: 0,
  };
  path.push([sa1Row, sa1Col]);

  // Build linear path
  let currentRow = sa1Row;
  let currentCol = sa1Col;
  let lastExitDir: Direction = 'south';

  while (path.length < usedCells) {
    const [nextRow, nextCol] = getNeighbor(currentRow, currentCol, lastExitDir);
    const entryDir = oppositeDirection(lastExitDir);

    if (!isValidPos(nextRow, nextCol, gridSize)) break;
    if (grid[nextRow][nextCol].stageName) break;

    const isLastCell = path.length === usedCells - 1;
    const validCandidates: { stage: string; rotation: number; exitDir: Direction | null }[] = [];

    for (const stage of candidateStages) {
      // Try all 4 rotations for each stage
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
      // Try to end early if we have enough cells
      if (path.length >= 3) {
        let earlyEnd = false;
        for (const stage of candidateStages) {
          if (earlyEnd) break;
          for (const rot of [0, 90, 180, 270]) {
            const gates = getRotatedGates(stage, rot);
            if (!gates.has(entryDir)) continue;
            const otherGates = [...gates].filter(g => g !== entryDir);
            if (otherGates.length !== 1) continue;
            const exitGate = otherGates[0];
            const [er, ec] = getNeighbor(nextRow, nextCol, exitGate);
            if (!isValidPos(er, ec, gridSize)) {
              grid[nextRow][nextCol] = {
                stageName: stage,
                rotation: rot,
                entryDirection: entryDir,
                isKeyGate: false,
                keyGateDirection: exitGate,
                hasKey: false,
                keyForCell: null,
                isStart: false,
                isEnd: true,
                isBranch: false,
                pathOrder: path.length,
              };
              path.push([nextRow, nextCol]);
              earlyEnd = true;
              break;
            }
          }
        }
      }
      break;
    }

    const chosen = validCandidates[Math.floor(Math.random() * validCandidates.length)];

    grid[nextRow][nextCol] = {
      stageName: chosen.stage,
      rotation: chosen.rotation,
      entryDirection: entryDir,
      isKeyGate: false,
      keyGateDirection: isLastCell ? chosen.exitDir : null,
      hasKey: false,
      keyForCell: null,
      isStart: false,
      isEnd: isLastCell,
      isBranch: false,
      pathOrder: path.length,
    };
    path.push([nextRow, nextCol]);

    if (isLastCell || !chosen.exitDir) break;
    currentRow = nextRow;
    currentCol = nextCol;
    lastExitDir = chosen.exitDir;
  }

  if (path.length < 3) return null;

  // Fix end cell if needed
  const [endRow, endCol] = path[path.length - 1];
  const endCell = grid[endRow][endCol];

  if (!endCell.isEnd || !endCell.keyGateDirection) {
    const entryDir = endCell.entryDirection;
    if (!entryDir) return null;

    let foundValidEnd = false;
    for (const stage of candidateStages) {
      if (foundValidEnd) break;
      for (const rot of [0, 90, 180, 270]) {
        const gates = getRotatedGates(stage, rot);
        if (!gates.has(entryDir)) continue;

        let warpDir: Direction | null = null;
        let hasOrphan = false;
        for (const gate of gates) {
          if (gate === entryDir) continue;
          const [nr, nc] = getNeighbor(endRow, endCol, gate);
          if (!isValidPos(nr, nc, gridSize)) {
            warpDir = gate;
          } else if (grid[nr][nc].stageName) {
            const neighborGates = getRotatedGates(grid[nr][nc].stageName!, grid[nr][nc].rotation);
            if (!neighborGates.has(oppositeDirection(gate))) {
              hasOrphan = true;
              break;
            }
          }
        }

        if (hasOrphan || !warpDir) continue;

        grid[endRow][endCol] = {
          ...endCell,
          stageName: stage,
          rotation: rot,
          isEnd: true,
          keyGateDirection: warpDir,
        };
        foundValidEnd = true;
        break;
      }
    }

    if (!foundValidEnd) return null;
  }

  // Add dead-end branches
  const branchCells: [number, number][] = [];
  if (branches > 0) {
    const branchCandidates: {
      pathCell: [number, number];
      branchDir: Direction;
      branchPos: [number, number];
      needsReplacement: boolean;
      replacementStage?: string;
      replacementRotation?: number;
    }[] = [];

    for (const [pr, pc] of path) {
      const cell = grid[pr][pc];
      if (cell.isStart || cell.isEnd) continue;

      const currentGates = getRotatedGates(cell.stageName!, cell.rotation);
      const exitDir = [...currentGates].find(g => g !== cell.entryDirection);
      if (!exitDir) continue;

      const directions: Direction[] = ['north', 'south', 'east', 'west'];
      for (const dir of directions) {
        if (dir === cell.entryDirection || dir === exitDir) continue;

        const [br, bc] = getNeighbor(pr, pc, dir);
        if (!isValidPos(br, bc, gridSize)) continue;
        if (grid[br][bc].stageName) continue;

        if (currentGates.has(dir)) {
          branchCandidates.push({
            pathCell: [pr, pc],
            branchDir: dir,
            branchPos: [br, bc],
            needsReplacement: false,
          });
        } else {
          let foundReplacement = false;
          for (const stage of candidateStages) {
            if (foundReplacement) break;
            for (const rot of [0, 90, 180, 270]) {
              const gates = getRotatedGates(stage, rot);
              if (!gates.has(cell.entryDirection!)) continue;
              if (!gates.has(exitDir)) continue;
              if (!gates.has(dir)) continue;

              let valid = true;
              for (const gate of gates) {
                if (gate === cell.entryDirection || gate === exitDir || gate === dir) continue;
                const [nr, nc] = getNeighbor(pr, pc, gate);
                if (isValidPos(nr, nc, gridSize) && grid[nr][nc].stageName) {
                  valid = false;
                  break;
                }
              }
              if (!valid) continue;

              branchCandidates.push({
                pathCell: [pr, pc],
                branchDir: dir,
                branchPos: [br, bc],
                needsReplacement: true,
                replacementStage: stage,
                replacementRotation: rot,
              });
              foundReplacement = true;
              break;
            }
          }
        }
      }
    }

    const shuffled = [...branchCandidates].sort(() => Math.random() - 0.5);
    let placedBranches = 0;

    for (const candidate of shuffled) {
      if (placedBranches >= branches) break;
      const { pathCell, branchDir, branchPos, needsReplacement, replacementStage, replacementRotation } = candidate;
      const [pr, pc] = pathCell;
      const [br, bc] = branchPos;

      if (grid[br][bc].stageName) continue;

      if (needsReplacement && replacementStage) {
        const oldCell = grid[pr][pc];
        grid[pr][pc] = { ...oldCell, stageName: replacementStage, rotation: replacementRotation ?? 0 };
      }

      const branchEntry = oppositeDirection(branchDir);
      const shuffledStages = [...candidateStages].sort(() => Math.random() - 0.5);

      let placed = false;
      for (const stage of shuffledStages) {
        if (placed) break;
        const gates = getOriginalGates(stage);
        if (gates.size !== 1) continue;
        for (const rot of [0, 90, 180, 270]) {
          const rotatedGate = rotateDirection([...gates][0], rot);
          if (rotatedGate !== branchEntry) continue;

          grid[br][bc] = {
            stageName: stage,
            rotation: rot,
            entryDirection: branchEntry,
            isKeyGate: false,
            keyGateDirection: null,
            hasKey: false,
            keyForCell: null,
            isStart: false,
            isEnd: false,
            isBranch: true,
            pathOrder: -1,
          };
          branchCells.push([br, bc]);
          placedBranches++;
          placed = true;
          break;
        }
      }
    }
  }

  // Place key-gates and keys
  const keyLinks: Record<string, string> = {};
  if (keyGates > 0) {
    const branchToPathOrder = new Map<string, number>();
    for (const [br, bc] of branchCells) {
      const branchCell = grid[br][bc];
      const entryDir = branchCell.entryDirection;
      if (!entryDir) continue;
      const [pr, pc] = getNeighbor(br, bc, entryDir);
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

      let keyCandidates: [number, number][];
      if (branchKeyCandidates.length > 0 && Math.random() < 0.8) {
        keyCandidates = branchKeyCandidates;
      } else if (mainPathCandidates.length > 0) {
        keyCandidates = mainPathCandidates;
      } else if (branchKeyCandidates.length > 0) {
        keyCandidates = branchKeyCandidates;
      } else {
        continue;
      }

      const [keyRow, keyCol] = keyCandidates[Math.floor(Math.random() * keyCandidates.length)];

      const gates = getRotatedGates(gateCell.stageName!, gateCell.rotation);
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
  const simVisited = new Set<string>();
  const simKeys = new Set<string>();
  const simQueue: [number, number][] = [[sa1Row, sa1Col]];

  while (simQueue.length > 0) {
    const [r, c] = simQueue.shift()!;
    const key = `${r},${c}`;
    if (simVisited.has(key)) continue;
    simVisited.add(key);

    const cell = grid[r][c];
    if (!cell.stageName) continue;

    if (cell.hasKey && cell.keyForCell) {
      simKeys.add(`${cell.keyForCell[0]},${cell.keyForCell[1]}`);
    }

    const gates = getRotatedGates(cell.stageName, cell.rotation);
    for (const dir of gates) {
      if (cell.isKeyGate && cell.keyGateDirection === dir && !simKeys.has(key)) continue;

      const [nr, nc] = getNeighbor(r, c, dir);
      if (!isValidPos(nr, nc, gridSize)) continue;

      const neighbor = grid[nr][nc];
      if (!neighbor.stageName) continue;
      if (simVisited.has(`${nr},${nc}`)) continue;

      const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation);
      if (!neighborGates.has(oppositeDirection(dir))) continue;

      simQueue.push([nr, nc]);
    }
  }

  if (!simVisited.has(`${endRow},${endCol}`)) return null;

  // Convert to EditorGridCell map
  const cells: Record<string, EditorGridCell> = {};
  let startPos: string | null = null;
  let endPos: string | null = null;

  for (let r = 0; r < gridSize; r++) {
    for (let c = 0; c < gridSize; c++) {
      const cell = grid[r][c];
      if (!cell.stageName) continue;

      const pos = `${r},${c}`;
      if (cell.isStart) startPos = pos;
      if (cell.isEnd) endPos = pos;

      cells[pos] = {
        stageName: cell.stageName,
        rotation: cell.rotation || undefined,
        lockedGate: cell.isKeyGate && cell.keyGateDirection ? cell.keyGateDirection as Direction : undefined,
        manual: false,
      };
    }
  }

  return {
    cells,
    startPos,
    endPos,
    keyLinks,
    pathLength: path.length,
  };
}
