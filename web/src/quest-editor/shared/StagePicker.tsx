/**
 * StagePicker — Modal for selecting a stage to place in a cell
 *
 * Filters stages by gate compatibility with neighbors.
 */

import { useState, useMemo } from 'react';
import type { QuestProject, Direction } from '../types';
import {
  getRotatedGates,
  getNeighbor,
  isValidPos,
  oppositeDirection,
  getStagesForArea,
  getStageSuffix,
} from '../hooks/useStageConfigs';

interface StagePickerProps {
  project: QuestProject;
  targetPos: string;
  onSelect: (stageName: string, rotation: number) => void;
  onClose: () => void;
}

interface StageCandidate {
  stageName: string;
  rotation: number;
}

/** Mini 3x3 grid icon showing gate positions */
function GateIcon({ gates, size = 28 }: { gates: Set<Direction>; size?: number }) {
  const cellSize = size / 3;
  const active = '#88ff88';
  const inactive = '#222';
  const center = '#555';

  const dirs: { dir: Direction; row: number; col: number }[] = [
    { dir: 'north', row: 0, col: 1 },
    { dir: 'west', row: 1, col: 0 },
    { dir: 'east', row: 1, col: 2 },
    { dir: 'south', row: 2, col: 1 },
  ];

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      {/* Background */}
      <rect width={size} height={size} fill="#111" rx={2} />
      {/* Center dot */}
      <rect
        x={cellSize} y={cellSize}
        width={cellSize} height={cellSize}
        fill={center} rx={1}
      />
      {/* Gate cells */}
      {dirs.map(({ dir, row, col }) => (
        <rect
          key={dir}
          x={col * cellSize + 0.5}
          y={row * cellSize + 0.5}
          width={cellSize - 1}
          height={cellSize - 1}
          fill={gates.has(dir) ? active : inactive}
          rx={1}
        />
      ))}
    </svg>
  );
}

/**
 * Determine gate constraints for a cell position based on neighbors.
 * Returns required gates (must connect to occupied neighbor) and
 * forbidden gates (must not connect to empty neighbor or outside grid).
 */
function getConstraints(
  project: QuestProject,
  pos: string,
): { required: Direction[]; forbidden: Direction[] } {
  const [row, col] = pos.split(',').map(Number);
  const directions: Direction[] = ['north', 'south', 'east', 'west'];
  const required: Direction[] = [];
  const forbidden: Direction[] = [];

  for (const dir of directions) {
    const [nr, nc] = getNeighbor(row, col, dir);

    if (!isValidPos(nr, nc, project.gridSize)) {
      // Outside grid — gate here would be a warp. Not forbidden, but not required.
      continue;
    }

    const neighborKey = `${nr},${nc}`;
    const neighbor = project.cells[neighborKey];

    if (neighbor) {
      // Occupied neighbor — check if it has a gate pointing back at us
      const neighborGates = getRotatedGates(neighbor.stageName, neighbor.rotation ?? 0);
      if (neighborGates.has(oppositeDirection(dir))) {
        // Neighbor has a gate toward us — we MUST have a gate this direction
        required.push(dir);
      } else {
        // Neighbor exists but no gate toward us — we must NOT have a gate this direction
        forbidden.push(dir);
      }
    }
    // Empty neighbor — no constraint (gate okay or not)
  }

  return { required, forbidden };
}

export default function StagePicker({ project, targetPos, onSelect, onClose }: StagePickerProps) {
  const [search, setSearch] = useState('');
  const [showAll, setShowAll] = useState(false);

  const stages = useMemo(
    () => getStagesForArea(project.areaKey, project.variant),
    [project.areaKey, project.variant]
  );

  const constraints = useMemo(
    () => getConstraints(project, targetPos),
    [project, targetPos]
  );

  const candidates = useMemo(() => {
    const result: StageCandidate[] = [];

    for (const stageName of stages) {
      // Try all 4 rotations, but deduplicate when rotation produces identical gate sets
      const seenGateKeys = new Set<string>();

      for (const rot of [0, 90, 180, 270]) {
        const gates = getRotatedGates(stageName, rot);

        // Deduplicate: skip if this rotation produces the same gate layout as a previous one
        const gateKey = [...gates].sort().join(',');
        if (seenGateKeys.has(gateKey)) continue;
        seenGateKeys.add(gateKey);

        // Check required: must have gates in these directions
        let meetsRequired = true;
        for (const dir of constraints.required) {
          if (!gates.has(dir)) {
            meetsRequired = false;
            break;
          }
        }
        if (!meetsRequired) continue;

        // Check forbidden: must NOT have gates in these directions
        let hasForbidden = false;
        for (const dir of constraints.forbidden) {
          if (gates.has(dir)) {
            hasForbidden = true;
            break;
          }
        }
        if (hasForbidden) continue;

        result.push({ stageName, rotation: rot });
      }
    }

    return result;
  }, [stages, constraints]);

  // Filter by search
  const filtered = useMemo(() => {
    if (!search) return showAll ? candidates : candidates.slice(0, 30);
    const q = search.toLowerCase();
    const matches = candidates.filter(c =>
      c.stageName.toLowerCase().includes(q) ||
      getStageSuffix(c.stageName).toLowerCase().includes(q)
    );
    return showAll ? matches : matches.slice(0, 30);
  }, [candidates, search, showAll]);

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 1000,
        background: 'rgba(0,0,0,0.7)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: '#1a1a2e',
          border: '1px solid #444',
          borderRadius: '12px',
          width: '600px',
          maxHeight: '80vh',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div style={{
          padding: '16px',
          borderBottom: '1px solid #333',
          display: 'flex',
          flexDirection: 'column',
          gap: '8px',
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ fontSize: '16px', fontWeight: 700, color: '#fff' }}>
              Select Stage
            </div>
            <button
              onClick={onClose}
              style={{
                background: 'none', border: 'none', color: '#888',
                fontSize: '18px', cursor: 'pointer', padding: '4px',
              }}
            >
              ✕
            </button>
          </div>
          <div style={{ fontSize: '11px', color: '#888' }}>
            Position: {targetPos} | Compatible: {candidates.length} of {stages.length} stages
            {constraints.required.length > 0 && (
              <span style={{ color: '#88ff88' }}>
                {' '}| Needs: {constraints.required.map(d => d[0].toUpperCase()).join(',')}
              </span>
            )}
            {constraints.forbidden.length > 0 && (
              <span style={{ color: '#ff8888' }}>
                {' '}| No: {constraints.forbidden.map(d => d[0].toUpperCase()).join(',')}
              </span>
            )}
          </div>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search stages..."
            autoFocus
            style={{
              width: '100%',
              padding: '8px 12px',
              background: '#2a2a4a',
              border: '1px solid #444',
              borderRadius: '6px',
              color: '#fff',
              fontSize: '13px',
            }}
          />
        </div>

        {/* Stage list */}
        <div style={{
          flex: 1, overflowY: 'auto', padding: '8px',
          display: 'flex', flexDirection: 'column', gap: '4px',
        }}>
          {filtered.length === 0 && (
            <div style={{ padding: '20px', textAlign: 'center', color: '#888' }}>
              No compatible stages found
            </div>
          )}
          {filtered.map(candidate => (
            <StageRow
              key={`${candidate.stageName}:${candidate.rotation}`}
              candidate={candidate}
              onSelect={onSelect}
            />
          ))}
          {!showAll && candidates.length > 30 && (
            <button
              onClick={() => setShowAll(true)}
              style={{
                padding: '8px',
                background: '#2a2a4a',
                border: '1px solid #444',
                borderRadius: '4px',
                color: '#88aaff',
                fontSize: '12px',
                cursor: 'pointer',
              }}
            >
              Show all {candidates.length} stages...
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function StageRow({
  candidate,
  onSelect,
}: {
  candidate: StageCandidate;
  onSelect: (stageName: string, rotation: number) => void;
}) {
  const suffix = getStageSuffix(candidate.stageName);
  const gates = getRotatedGates(candidate.stageName, candidate.rotation);

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        padding: '8px 12px',
        background: '#222244',
        borderRadius: '6px',
        cursor: 'pointer',
        transition: 'background 0.1s',
      }}
      onClick={() => onSelect(candidate.stageName, candidate.rotation)}
      onMouseEnter={(e) => e.currentTarget.style.background = '#333366'}
      onMouseLeave={(e) => e.currentTarget.style.background = '#222244'}
    >
      {/* Gate icon */}
      <GateIcon gates={gates} />

      {/* Stage name */}
      <div style={{ flex: 1 }}>
        <div style={{ color: '#fff', fontSize: '13px', fontWeight: 600 }}>
          {suffix}
          {candidate.rotation !== 0 && (
            <span style={{ color: '#88aaff', fontSize: '10px', marginLeft: '6px' }}>
              {candidate.rotation}&deg;
            </span>
          )}
        </div>
        <div style={{ color: '#666', fontSize: '10px' }}>
          {candidate.stageName}
        </div>
      </div>

      {/* Select button */}
      <button
        style={{
          padding: '4px 10px',
          background: '#3a3a6a',
          border: '1px solid #555',
          borderRadius: '4px',
          color: '#fff',
          fontSize: '11px',
          cursor: 'pointer',
          transition: 'background 0.1s',
        }}
        onMouseEnter={(e) => e.currentTarget.style.background = '#5588ff'}
        onMouseLeave={(e) => e.currentTarget.style.background = '#3a3a6a'}
      >
        Place
      </button>
    </div>
  );
}
