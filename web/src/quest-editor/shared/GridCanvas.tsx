/**
 * GridCanvas — Renders the NxN grid with cells, gates, badges
 *
 * Click empty cell -> onCellClick (for StagePicker)
 * Click occupied cell -> onCellSelect (for CellInspector)
 */

import { useMemo } from 'react';
import type { QuestProject, EditorGridCell, Direction } from '../types';
import { ROLE_COLORS } from '../types';
import { getRotatedGates, oppositeDirection, getNeighbor, isValidPos } from '../hooks/useStageConfigs';

interface GridCanvasProps {
  project: QuestProject;
  selectedCell: string | null;
  onCellClick: (pos: string) => void;
  onCellSelect: (pos: string) => void;
}

/** Get suffix from stage name (e.g., "s01a_ib1" -> "ib1") */
function getSuffix(stageName: string): string {
  const idx = stageName.indexOf('_');
  return idx >= 0 ? stageName.substring(idx + 1) : stageName;
}

/** Get gate display color based on cell state */
function getGateColor(
  project: QuestProject,
  pos: string,
  cell: EditorGridCell,
  direction: Direction,
  gridSize: number,
): string {
  const [row, col] = pos.split(',').map(Number);
  const [nr, nc] = getNeighbor(row, col, direction);

  // Key-locked gate?
  const isKeyGate = Object.keys(project.keyLinks).includes(pos);
  if (isKeyGate && cell.lockedGate === direction) {
    return '#ff66ff';
  }

  // Warp exit (gate points outside grid)
  if (!isValidPos(nr, nc, gridSize)) return '#aa66ff';

  // Gate to empty neighbor
  const neighborKey = `${nr},${nc}`;
  if (!project.cells[neighborKey]) return '#ccaa44';

  // Gate to occupied neighbor — check if neighbor has matching gate
  const neighbor = project.cells[neighborKey];
  const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation ?? 0);
  if (!neighborGates.has(oppositeDirection(direction))) return '#cc4444'; // Orphan — red

  return '#88ff88'; // Normal connected gate
}

/** BFS from startPos to determine entry direction for each cell */
function computeEntryDirections(project: QuestProject): Map<string, Direction> {
  const entries = new Map<string, Direction>();
  if (!project.startPos || !project.cells[project.startPos]) return entries;

  const visited = new Set<string>();
  const queue: string[] = [project.startPos];
  visited.add(project.startPos);

  while (queue.length > 0) {
    const pos = queue.shift()!;
    const cell = project.cells[pos];
    if (!cell) continue;

    const [row, col] = pos.split(',').map(Number);
    const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);

    for (const dir of gates) {
      const [nr, nc] = getNeighbor(row, col, dir);
      const nk = `${nr},${nc}`;
      if (visited.has(nk)) continue;
      if (!isValidPos(nr, nc, project.gridSize)) continue;

      const neighbor = project.cells[nk];
      if (!neighbor) continue;

      const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation ?? 0);
      if (!neighborGates.has(oppositeDirection(dir))) continue;

      visited.add(nk);
      entries.set(nk, oppositeDirection(dir));
      queue.push(nk);
    }
  }

  return entries;
}

function CellDisplay({
  pos,
  cell,
  project,
  isSelected,
  entryDir,
  onClick,
}: {
  pos: string;
  cell: EditorGridCell | null;
  project: QuestProject;
  isSelected: boolean;
  entryDir: Direction | null;
  onClick: () => void;
}) {
  const [row, col] = pos.split(',').map(Number);

  if (!cell) {
    return (
      <div
        onClick={onClick}
        style={{
          width: '110px',
          height: '110px',
          background: isSelected ? '#2a2a4a' : '#1a1a2e',
          border: `1px solid ${isSelected ? '#5588ff' : '#333'}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#444',
          fontSize: '10px',
          cursor: 'pointer',
          transition: 'background 0.1s',
        }}
        onMouseEnter={(e) => { if (!isSelected) e.currentTarget.style.background = '#222244'; }}
        onMouseLeave={(e) => { if (!isSelected) e.currentTarget.style.background = '#1a1a2e'; }}
      >
        {row},{col}
      </div>
    );
  }

  const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);
  const roleColor = ROLE_COLORS[cell.role];
  const isStart = project.startPos === pos;
  const isEnd = project.endPos === pos;
  const hasKey = Object.values(project.keyLinks).includes(pos);
  const isKeyGate = pos in project.keyLinks;

  return (
    <div
      onClick={onClick}
      style={{
        width: '110px',
        height: '110px',
        background: isSelected ? '#3a3a6a' : '#2a2a4a',
        border: `2px solid ${isSelected ? '#88aaff' : roleColor}`,
        position: 'relative',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        cursor: 'pointer',
        transition: 'all 0.1s',
      }}
      onMouseEnter={(e) => { if (!isSelected) e.currentTarget.style.background = '#333366'; }}
      onMouseLeave={(e) => { if (!isSelected) e.currentTarget.style.background = '#2a2a4a'; }}
    >
      {isStart && (
        <div style={{
          position: 'absolute', top: '3px', left: '3px',
          background: '#66aaff', color: '#fff', fontSize: '7px',
          padding: '1px 4px', borderRadius: '3px', fontWeight: 700,
        }}>START</div>
      )}
      {isEnd && (
        <div style={{
          position: 'absolute', top: '3px', left: '3px',
          background: '#ffaa66', color: '#fff', fontSize: '7px',
          padding: '1px 4px', borderRadius: '3px', fontWeight: 700,
        }}>END</div>
      )}
      {hasKey && (
        <div style={{
          position: 'absolute', top: '3px', right: '3px',
          width: '14px', height: '14px', background: '#ff66aa',
          borderRadius: '50%', border: '2px solid #fff',
        }} title="Key" />
      )}
      {isKeyGate && (
        <div style={{
          position: 'absolute', top: '3px', right: hasKey ? '22px' : '3px',
          width: '14px', height: '14px', background: '#ff66ff',
          borderRadius: '2px', border: '2px solid #fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: '8px', color: '#fff', fontWeight: 700,
        }} title="Key-Gate">G</div>
      )}

      <div style={{ color: '#fff', fontSize: '11px', fontWeight: 600, textAlign: 'center' }}>
        {getSuffix(cell.stageName)}
      </div>
      <div style={{
        color: roleColor, fontSize: '8px', marginTop: '2px',
        textTransform: 'uppercase', fontWeight: 600,
      }}>
        {cell.role}
      </div>

      {gates.has('north') && (
        <div style={{
          position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)',
          width: '22px', height: '5px', borderRadius: '0 0 3px 3px',
          background: entryDir === 'north' ? '#88ff88' : getGateColor(project, pos, cell, 'north', project.gridSize),
          opacity: entryDir === 'north' ? 0.5 : 1,
        }} />
      )}
      {gates.has('south') && (
        <div style={{
          position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)',
          width: '22px', height: '5px', borderRadius: '3px 3px 0 0',
          background: entryDir === 'south' ? '#88ff88' : getGateColor(project, pos, cell, 'south', project.gridSize),
          opacity: entryDir === 'south' ? 0.5 : 1,
        }} />
      )}
      {gates.has('east') && (
        <div style={{
          position: 'absolute', right: 0, top: '50%', transform: 'translateY(-50%)',
          width: '5px', height: '22px', borderRadius: '3px 0 0 3px',
          background: entryDir === 'east' ? '#88ff88' : getGateColor(project, pos, cell, 'east', project.gridSize),
          opacity: entryDir === 'east' ? 0.5 : 1,
        }} />
      )}
      {gates.has('west') && (
        <div style={{
          position: 'absolute', left: 0, top: '50%', transform: 'translateY(-50%)',
          width: '5px', height: '22px', borderRadius: '0 3px 3px 0',
          background: entryDir === 'west' ? '#88ff88' : getGateColor(project, pos, cell, 'west', project.gridSize),
          opacity: entryDir === 'west' ? 0.5 : 1,
        }} />
      )}

      <div style={{ position: 'absolute', bottom: '2px', right: '4px', fontSize: '8px', color: '#555' }}>
        {row},{col}
      </div>
    </div>
  );
}

export default function GridCanvas({ project, selectedCell, onCellClick, onCellSelect }: GridCanvasProps) {
  const { gridSize, cells } = project;
  const entryDirs = useMemo(() => computeEntryDirections(project), [project]);

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      gap: '2px',
      background: '#111',
      padding: '4px',
      borderRadius: '8px',
    }}>
      {Array.from({ length: gridSize }, (_, row) => (
        <div key={row} style={{ display: 'flex', gap: '2px' }}>
          {Array.from({ length: gridSize }, (_, col) => {
            const pos = `${row},${col}`;
            const cell = cells[pos] || null;
            const isSelected = selectedCell === pos;

            return (
              <CellDisplay
                key={col}
                pos={pos}
                cell={cell}
                project={project}
                isSelected={isSelected}
                entryDir={entryDirs.get(pos) ?? null}
                onClick={() => cell ? onCellSelect(pos) : onCellClick(pos)}
              />
            );
          })}
        </div>
      ))}
    </div>
  );
}
