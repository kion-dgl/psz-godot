/**
 * GridCanvas — Renders the NxN grid with cells, gates, badges
 *
 * Click empty cell -> onCellClick (for StagePicker)
 * Click occupied cell -> onCellSelect (for CellInspector)
 */

import { useMemo, useState, useEffect, useCallback } from 'react';
import type { QuestProject, EditorGridCell, Direction } from '../types';
import { getRotatedGates, oppositeDirection, getNeighbor, isValidPos } from '../hooks/useStageConfigs';
import { STAGE_AREAS, getStageSubfolder } from '../../stage-editor/constants';
import { assetUrl } from '../../utils/assets';

interface GridCanvasProps {
  project: QuestProject;
  selectedCell: string | null;
  onCellClick: (pos: string) => void;
  onCellSelect: (pos: string) => void;
  showMinimap?: boolean;
  areaKey?: string;
  swapSource?: string | null;
  onSwapExecute?: (targetPos: string) => void;
  onSwapCancel?: () => void;
  isMobile?: boolean;
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
  if (isKeyGate && (cell.lockedGates ?? []).includes(direction)) {
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

function SvgMinimapBg({ stageId, rotation, areaKey }: { stageId: string; rotation: number; areaKey: string }) {
  const [svg, setSvg] = useState<string | null>(null);

  useEffect(() => {
    const area = STAGE_AREAS[areaKey];
    if (!area) return;
    const subfolder = getStageSubfolder(stageId, area.folder);
    // Always fetch the unrotated SVG — we apply rotation via CSS
    const url = assetUrl(`assets/stages/${subfolder}/${stageId}/lndmd/${stageId}_minimap_r0.svg`);
    let cancelled = false;
    fetch(url)
      .then(r => r.ok ? r.text() : null)
      .then(text => { if (!cancelled && text) setSvg(text); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [stageId, areaKey]);

  if (!svg) return null;
  const sized = svg.replace('<svg ', '<svg width="100%" height="100%" ');
  // Rotate CW to match the game's rotation convention
  return (
    <div
      style={{
        position: 'absolute', inset: 0, zIndex: 0, opacity: 0.7, overflow: 'hidden',
        transform: `rotate(${rotation}deg)`,
      }}
      dangerouslySetInnerHTML={{ __html: sized }}
    />
  );
}

function CellDisplay({
  pos,
  cell,
  project,
  isSelected,
  entryDir,
  showMinimap,
  areaKey,
  onClick,
  isSwapSource,
  cellSize = 110,
}: {
  pos: string;
  cell: EditorGridCell | null;
  project: QuestProject;
  isSelected: boolean;
  entryDir: Direction | null;
  showMinimap?: boolean;
  areaKey?: string;
  onClick: () => void;
  isSwapSource?: boolean;
  cellSize?: number;
}) {
  const [row, col] = pos.split(',').map(Number);

  const compact = cellSize < 80;
  const gateW = compact ? 14 : 22;
  const gateH = compact ? 3 : 5;
  const badgeSize = compact ? 10 : 14;
  const suffixFontSize = compact ? '9px' : '11px';
  const coordFontSize = compact ? '6px' : '8px';

  if (!cell) {
    return (
      <div
        onClick={onClick}
        style={{
          width: `${cellSize}px`,
          height: `${cellSize}px`,
          background: isSelected ? '#2a2a4a' : '#1a1a2e',
          border: `1px solid ${isSelected ? '#5588ff' : '#333'}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#444',
          fontSize: compact ? '8px' : '10px',
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
  const cellColor = '#556';
  const isStart = project.startPos === pos;
  const isEnd = project.endPos === pos;
  const hasKey = Object.values(project.keyLinks).includes(pos);
  const isKeyGate = pos in project.keyLinks;
  const keyDropLinks = project.keyDropLinks || {};
  const isKeyDrop = pos in keyDropLinks;

  const badgeOffset = compact ? 13 : 19;

  return (
    <div
      onClick={onClick}
      style={{
        width: `${cellSize}px`,
        height: `${cellSize}px`,
        background: isSwapSource ? '#4a3a1a' : isSelected ? '#3a3a6a' : '#2a2a4a',
        border: `2px solid ${isSwapSource ? '#ff9922' : isSelected ? '#88aaff' : cellColor}`,
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
      {showMinimap && areaKey && (
        <SvgMinimapBg stageId={cell.stageName} rotation={cell.rotation ?? 0} areaKey={areaKey} />
      )}
      {isStart && (
        <div style={{
          position: 'absolute', top: '2px', left: '2px',
          background: '#66aaff', color: '#fff', fontSize: compact ? '5px' : '7px',
          padding: '1px 3px', borderRadius: '3px', fontWeight: 700,
        }}>START</div>
      )}
      {isEnd && (
        <div style={{
          position: 'absolute', top: '2px', left: '2px',
          background: '#ffaa66', color: '#fff', fontSize: compact ? '5px' : '7px',
          padding: '1px 3px', borderRadius: '3px', fontWeight: 700,
        }}>END</div>
      )}
      {hasKey && (
        <div style={{
          position: 'absolute', top: '2px', right: '2px',
          width: `${badgeSize}px`, height: `${badgeSize}px`, background: '#ff66aa',
          borderRadius: '50%', border: compact ? '1px solid #fff' : '2px solid #fff',
        }} title="Key" />
      )}
      {isKeyDrop && (
        <div style={{
          position: 'absolute', top: '2px', right: hasKey ? `${badgeOffset + 2}px` : '2px',
          width: `${badgeSize}px`, height: `${badgeSize}px`, background: '#ddaa33',
          borderRadius: '50%', border: compact ? '1px solid #fff' : '2px solid #fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: compact ? '6px' : '8px', color: '#fff', fontWeight: 700,
        }} title="Key Drop">D</div>
      )}
      {isKeyGate && (
        <div style={{
          position: 'absolute', top: '2px',
          right: (hasKey || isKeyDrop) ? ((hasKey ? badgeOffset : 0) + (isKeyDrop ? badgeOffset : 0) + 2) + 'px' : '2px',
          width: `${badgeSize}px`, height: `${badgeSize}px`, background: '#ff66ff',
          borderRadius: '2px', border: compact ? '1px solid #fff' : '2px solid #fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: compact ? '6px' : '8px', color: '#fff', fontWeight: 700,
        }} title="Key-Gate">G</div>
      )}

      <div style={{ color: '#fff', fontSize: suffixFontSize, fontWeight: 600, textAlign: 'center', zIndex: 1 }}>
        {getSuffix(cell.stageName)}
      </div>
      {gates.has('north') && (
        <div style={{
          position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)',
          width: `${gateW}px`, height: `${gateH}px`, borderRadius: '0 0 3px 3px',
          background: entryDir === 'north' ? '#88ff88' : getGateColor(project, pos, cell, 'north', project.gridSize),
          opacity: entryDir === 'north' ? 0.5 : 1,
        }} />
      )}
      {gates.has('south') && (
        <div style={{
          position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)',
          width: `${gateW}px`, height: `${gateH}px`, borderRadius: '3px 3px 0 0',
          background: entryDir === 'south' ? '#88ff88' : getGateColor(project, pos, cell, 'south', project.gridSize),
          opacity: entryDir === 'south' ? 0.5 : 1,
        }} />
      )}
      {gates.has('east') && (
        <div style={{
          position: 'absolute', right: 0, top: '50%', transform: 'translateY(-50%)',
          width: `${gateH}px`, height: `${gateW}px`, borderRadius: '3px 0 0 3px',
          background: entryDir === 'east' ? '#88ff88' : getGateColor(project, pos, cell, 'east', project.gridSize),
          opacity: entryDir === 'east' ? 0.5 : 1,
        }} />
      )}
      {gates.has('west') && (
        <div style={{
          position: 'absolute', left: 0, top: '50%', transform: 'translateY(-50%)',
          width: `${gateH}px`, height: `${gateW}px`, borderRadius: '0 3px 3px 0',
          background: entryDir === 'west' ? '#88ff88' : getGateColor(project, pos, cell, 'west', project.gridSize),
          opacity: entryDir === 'west' ? 0.5 : 1,
        }} />
      )}

      <div style={{ position: 'absolute', bottom: '1px', right: '3px', fontSize: coordFontSize, color: '#555' }}>
        {row},{col}
      </div>
    </div>
  );
}

export default function GridCanvas({ project, selectedCell, onCellClick, onCellSelect, showMinimap, areaKey, swapSource, onSwapExecute, onSwapCancel, isMobile }: GridCanvasProps) {
  const { gridSize, cells } = project;
  const cellSize = isMobile ? 66 : 110;
  const entryDirs = useMemo(() => computeEntryDirections(project), [project]);
  const inSwapMode = !!swapSource;

  // ESC to cancel swap mode
  useEffect(() => {
    if (!inSwapMode || !onSwapCancel) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { onSwapCancel(); }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [inSwapMode, onSwapCancel]);

  const handleCellClick = useCallback((pos: string) => {
    if (inSwapMode) {
      if (onSwapExecute) onSwapExecute(pos);
      return;
    }
    const cell = cells[pos];
    if (cell) onCellSelect(pos); else onCellClick(pos);
  }, [inSwapMode, cells, onSwapExecute, onCellSelect, onCellClick]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '0px' }}>
      {/* Swap mode banner */}
      {inSwapMode && (
        <div style={{
          padding: '8px 16px',
          background: '#886622',
          color: '#fff',
          fontSize: '13px',
          fontWeight: 600,
          textAlign: 'center',
          borderRadius: '6px',
          marginBottom: '8px',
        }}>
          Click a cell to swap or move to &middot; Press ESC to cancel
        </div>
      )}
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
                  showMinimap={showMinimap}
                  areaKey={areaKey}
                  onClick={() => handleCellClick(pos)}
                  isSwapSource={swapSource === pos}
                  cellSize={cellSize}
                />
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}
