/**
 * PreviewGrid — compact 2D grid overlay showing all cells in the current section.
 * Renders in the bottom-right of the 3D preview canvas.
 * Current cell is highlighted; clicking a cell teleports to it.
 */

import { useMemo } from 'react';

interface BakedCell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  is_start: boolean;
  is_end: boolean;
  warp_edge: string;
}

interface PreviewGridProps {
  bakedCells: Record<string, BakedCell>;
  currentCellPos: string | null;
  onCellClick: (pos: string) => void;
}

const CELL_SIZE = 26;
const GAP = 2;
const EDGE_BAR = 3;

const WARP_TARGET = '__warp__';

/** Direction → CSS offset for connection indicator bars */
const EDGE_OFFSETS: Record<string, React.CSSProperties> = {
  north: { top: 0, left: '25%', width: '50%', height: EDGE_BAR },
  south: { bottom: 0, left: '25%', width: '50%', height: EDGE_BAR },
  west:  { left: 0, top: '25%', height: '50%', width: EDGE_BAR },
  east:  { right: 0, top: '25%', height: '50%', width: EDGE_BAR },
};

function parsePos(pos: string): [number, number] {
  const [r, c] = pos.split(',').map(Number);
  return [r, c];
}

export default function PreviewGrid({ bakedCells, currentCellPos, onCellClick }: PreviewGridProps) {
  const { cells, minRow, minCol, rows, cols } = useMemo(() => {
    const entries = Object.entries(bakedCells);
    if (entries.length === 0) return { cells: [], minRow: 0, minCol: 0, rows: 0, cols: 0 };

    let mnR = Infinity, mxR = -Infinity, mnC = Infinity, mxC = -Infinity;
    const parsed: Array<{ pos: string; row: number; col: number; cell: BakedCell }> = [];

    for (const [pos, cell] of entries) {
      const [r, c] = parsePos(pos);
      parsed.push({ pos, row: r, col: c, cell });
      if (r < mnR) mnR = r;
      if (r > mxR) mxR = r;
      if (c < mnC) mnC = c;
      if (c > mxC) mxC = c;
    }

    return {
      cells: parsed,
      minRow: mnR,
      minCol: mnC,
      rows: mxR - mnR + 1,
      cols: mxC - mnC + 1,
    };
  }, [bakedCells]);

  if (cells.length === 0) return null;

  const gridW = cols * (CELL_SIZE + GAP) - GAP;
  const gridH = rows * (CELL_SIZE + GAP) - GAP;

  return (
    <div style={{
      background: 'rgba(0,0,0,0.8)',
      borderRadius: 6,
      padding: 8,
      pointerEvents: 'auto',
    }}>
      <div style={{
        position: 'relative',
        width: gridW,
        height: gridH,
      }}>
        {cells.map(({ pos, row, col, cell }) => {
          const isCurrent = pos === currentCellPos;
          const x = (col - minCol) * (CELL_SIZE + GAP);
          const y = (row - minRow) * (CELL_SIZE + GAP);

          let bg = '#2a2a3a';
          if (isCurrent) bg = '#3355aa';
          else if (cell.is_start) bg = '#2a3a2a';
          else if (cell.is_end) bg = '#3a2a2a';

          return (
            <div
              key={pos}
              onClick={() => onCellClick(pos)}
              title={`${pos} — ${cell.stage_id}`}
              style={{
                position: 'absolute',
                left: x,
                top: y,
                width: CELL_SIZE,
                height: CELL_SIZE,
                background: bg,
                border: `2px solid ${isCurrent ? '#88bbff' : '#444'}`,
                borderRadius: 3,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 10,
                fontWeight: 700,
                color: isCurrent ? '#fff' : '#999',
                fontFamily: 'monospace',
              }}
            >
              {cell.is_start ? 'S' : cell.is_end ? 'E' : null}

              {/* Connection edge bars */}
              {Object.entries(cell.connections).map(([dir, target]) => {
                const style = EDGE_OFFSETS[dir];
                if (!style) return null;
                const isWarp = target === WARP_TARGET;
                return (
                  <div
                    key={dir}
                    style={{
                      position: 'absolute',
                      ...style,
                      background: isWarp ? '#aa66ff' : '#55aa55',
                      borderRadius: 1,
                      pointerEvents: 'none',
                    }}
                  />
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}
