/**
 * Quest traversal validation tests.
 *
 * BFS-walks every quest from start to end to prove the player can reach
 * the finish. Catches orphaned cells, broken key-gate logic, and
 * cross-section continuity issues that structural tests miss.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

// ---------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------

const QUESTS_DIR = path.resolve(__dirname, '../../../data/quests');
const manifest: string[] = JSON.parse(
  fs.readFileSync(path.join(QUESTS_DIR, 'manifest.json'), 'utf-8'),
);

interface Cell {
  pos: string;
  connections: Record<string, string>;
  is_start: boolean;
  is_end: boolean;
  has_key: boolean;
  key_for_cell: string;
  key_drop: string;
  is_key_gate: boolean;
  key_gate_direction: string;
  warp_edge: string;
}

interface Section {
  type: string;
  area: string;
  start_pos: string;
  end_pos: string;
  cells: Cell[];
}

interface Quest {
  id: string;
  name: string;
  sections: Section[];
}

const quests: Array<{ filename: string; data: Quest }> = manifest.map(name => ({
  filename: `${name}.json`,
  data: JSON.parse(fs.readFileSync(path.join(QUESTS_DIR, `${name}.json`), 'utf-8')),
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Plain BFS from a source cell, returns the set of visited positions. */
function bfs(cellMap: Map<string, Cell>, startPos: string): Set<string> {
  const visited = new Set<string>();
  const queue = [startPos];
  visited.add(startPos);

  while (queue.length > 0) {
    const current = queue.shift()!;
    const cell = cellMap.get(current);
    if (!cell) continue;

    for (const neighbor of Object.values(cell.connections)) {
      if (!visited.has(neighbor)) {
        visited.add(neighbor);
        queue.push(neighbor);
      }
    }
  }
  return visited;
}

/**
 * BFS that simulates key-gate mechanics.
 * Gates block traversal until the corresponding key is collected.
 * Returns the set of reachable positions.
 */
function bfsWithKeys(cellMap: Map<string, Cell>, startPos: string): Set<string> {
  const visited = new Set<string>();
  const collectedKeys = new Set<string>(); // positions of unlocked gates
  const queue = [startPos];
  visited.add(startPos);

  // Collect key if start cell has one
  const startCell = cellMap.get(startPos);
  if (startCell?.has_key && startCell.key_for_cell) {
    collectedKeys.add(startCell.key_for_cell);
  }
  if (startCell?.key_drop) {
    collectedKeys.add(startCell.key_drop);
  }

  // We may need multiple passes: collecting a key can open a gate that
  // reveals more cells (and potentially more keys). Loop until stable.
  let changed = true;
  while (changed) {
    changed = false;

    while (queue.length > 0) {
      const current = queue.shift()!;
      const cell = cellMap.get(current);
      if (!cell) continue;

      for (const [dir, neighbor] of Object.entries(cell.connections)) {
        if (visited.has(neighbor)) continue;

        // Check if traversal in this direction is blocked by a key gate
        // A key gate on the *neighbor* blocks entry from the opposite direction,
        // but the export format puts is_key_gate + key_gate_direction on the
        // gate cell itself, and the connection exists from current→neighbor.
        // The gate blocks if the neighbor is_key_gate and key_gate_direction
        // matches the direction we're coming FROM... but actually the exported
        // data puts the gate on the cell that HAS the gate, and the
        // key_gate_direction is the direction the gate blocks on that cell.
        //
        // In practice: if *current* cell is_key_gate and key_gate_direction == dir,
        // then we need the key for current cell. If *neighbor* is_key_gate and
        // key_gate_direction points back toward us, we also need its key.
        //
        // Simpler: check both cells for gate blocking this edge.
        const blocked = isEdgeBlocked(cell, dir, cellMap.get(neighbor), collectedKeys);
        if (blocked) continue;

        visited.add(neighbor);
        queue.push(neighbor);

        // Collect key if present (has_key/key_for_cell or key_drop)
        const neighborCell = cellMap.get(neighbor);
        if (neighborCell?.has_key && neighborCell.key_for_cell) {
          if (!collectedKeys.has(neighborCell.key_for_cell)) {
            collectedKeys.add(neighborCell.key_for_cell);
            changed = true; // new key may unlock previously blocked gates
          }
        }
        if (neighborCell?.key_drop) {
          if (!collectedKeys.has(neighborCell.key_drop)) {
            collectedKeys.add(neighborCell.key_drop);
            changed = true;
          }
        }
      }
    }

    // If we collected a new key, re-enqueue all visited cells to try blocked edges
    if (changed) {
      for (const pos of visited) {
        queue.push(pos);
      }
    }
  }

  return visited;
}

const OPPOSITE: Record<string, string> = {
  north: 'south',
  south: 'north',
  east: 'west',
  west: 'east',
};

function isEdgeBlocked(
  fromCell: Cell,
  dir: string,
  toCell: Cell | undefined,
  collectedKeys: Set<string>,
): boolean {
  // Gate on the source cell blocking exit in this direction
  if (fromCell.is_key_gate && fromCell.key_gate_direction === dir) {
    if (!collectedKeys.has(fromCell.pos)) return true;
  }
  // Gate on the destination cell blocking entry from opposite direction
  if (toCell?.is_key_gate && toCell.key_gate_direction === OPPOSITE[dir]) {
    if (!collectedKeys.has(toCell.pos)) return true;
  }
  return false;
}

function buildCellMap(cells: Cell[]): Map<string, Cell> {
  const map = new Map<string, Cell>();
  for (const cell of cells) map.set(cell.pos, cell);
  return map;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Quest traversal — all cells reachable from start', () => {
  it.each(quests)('$filename', ({ data }) => {
    for (let i = 0; i < data.sections.length; i++) {
      const section = data.sections[i];
      const cellMap = buildCellMap(section.cells);
      const reachable = bfs(cellMap, section.start_pos);

      const unreachable = section.cells
        .map(c => c.pos)
        .filter(pos => !reachable.has(pos));

      expect(
        unreachable,
        `section[${i}] (${section.type}/${section.area}): orphaned cells: ${unreachable.join(', ')}`,
      ).toHaveLength(0);
    }
  });
});

describe('Quest traversal — end reachable with key-gate simulation', () => {
  it.each(quests)('$filename', ({ data }) => {
    for (let i = 0; i < data.sections.length; i++) {
      const section = data.sections[i];
      const cellMap = buildCellMap(section.cells);
      const reachable = bfsWithKeys(cellMap, section.start_pos);

      expect(
        reachable.has(section.end_pos),
        `section[${i}] (${section.type}/${section.area}): end_pos "${section.end_pos}" not reachable from start_pos "${section.start_pos}" (even after collecting keys). Reached: ${[...reachable].join(', ')}`,
      ).toBe(true);
    }
  });
});

describe('Quest traversal — cross-section continuity', () => {
  it.each(quests)('$filename', ({ data }) => {
    const errors: string[] = [];

    for (let i = 0; i < data.sections.length; i++) {
      const section = data.sections[i];
      const cellMap = buildCellMap(section.cells);
      const endCell = cellMap.get(section.end_pos);

      // Non-final sections must have a warp_edge on the end cell
      if (i < data.sections.length - 1) {
        if (!endCell?.warp_edge) {
          errors.push(
            `section[${i}] (${section.type}/${section.area}): end cell "${section.end_pos}" has no warp_edge but is not the final section`,
          );
        }

        // Next section must have a valid start_pos
        const next = data.sections[i + 1];
        const nextCellMap = buildCellMap(next.cells);
        if (!nextCellMap.has(next.start_pos)) {
          errors.push(
            `section[${i + 1}] (${next.type}/${next.area}): start_pos "${next.start_pos}" not found in cells`,
          );
        }
      }

      // Transition sections: start_pos === end_pos, single cell
      if (section.type === 'transition') {
        if (section.start_pos !== section.end_pos) {
          errors.push(
            `section[${i}] transition: start_pos "${section.start_pos}" !== end_pos "${section.end_pos}"`,
          );
        }
        if (section.cells.length !== 1) {
          errors.push(
            `section[${i}] transition: expected 1 cell, got ${section.cells.length}`,
          );
        }
      }
    }

    expect(errors, `Cross-section issues:\n${errors.join('\n')}`).toHaveLength(0);
  });
});

describe('Quest traversal — complete quest traversable end-to-end', () => {
  it.each(quests)('$filename', ({ data }) => {
    const errors: string[] = [];

    for (let i = 0; i < data.sections.length; i++) {
      const section = data.sections[i];
      const cellMap = buildCellMap(section.cells);

      // Must be able to reach end from start (with key-gate simulation)
      const reachable = bfsWithKeys(cellMap, section.start_pos);
      if (!reachable.has(section.end_pos)) {
        errors.push(
          `section[${i}] (${section.type}/${section.area}): cannot reach end "${section.end_pos}" from start "${section.start_pos}"`,
        );
        continue; // no point checking warp if we can't reach end
      }

      // Non-final sections need warp_edge to transition
      if (i < data.sections.length - 1) {
        const endCell = cellMap.get(section.end_pos);
        if (!endCell?.warp_edge) {
          errors.push(
            `section[${i}] (${section.type}/${section.area}): end cell "${section.end_pos}" missing warp_edge for section transition`,
          );
        }
      }
    }

    expect(
      errors,
      `End-to-end traversal failed:\n${errors.join('\n')}`,
    ).toHaveLength(0);
  });
});
