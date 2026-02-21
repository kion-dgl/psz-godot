/**
 * PreviewTab — 3D walkthrough preview for the quest editor
 *
 * Renders the current cell's GLB stage model with portal markers,
 * a capsule player with tank controls, an SVG minimap overlay,
 * and coordinate readout. Walking into trigger zones switches cells.
 *
 * Player position is owned by StageScene (ref-based, no React re-renders).
 * PreviewTab only receives throttled position reports for the overlays.
 */

import { useState, useEffect, useMemo, useCallback, Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import type { QuestProject } from '../types';
import { getProjectSections } from '../types';
import { projectToGodotQuest, getSvgSettings } from '../utils/quest-io';
import type { SvgSettings } from '../utils/quest-io';
import { STAGE_AREAS } from '../../stage-editor/constants';
import StageScene from '../preview/StageScene';
import type { PortalData } from '../preview/StageScene';
import PreviewMinimap from '../preview/PreviewMinimap';
import PreviewGrid from '../preview/PreviewGrid';

interface PreviewTabProps {
  project: QuestProject;
}

/** Get the yaw (facing direction) from a portal's gate_rot.
 *  gate_rot[1] is the gate's Y rotation in radians (outward-facing).
 *  Player should face inward (+PI). No cell rotation — 3D view is unrotated. */
function getSpawnYaw(portal: PortalData): number {
  const gateRotY = portal.gate_rot ? portal.gate_rot[1] : 0;
  return gateRotY + Math.PI;
}

/** Find spawn portal: prefer 'default', fall back to first non-default portal */
function findSpawnPortal(portals: Record<string, PortalData>): PortalData | null {
  if (portals['default']) return portals['default'];
  for (const [dir, p] of Object.entries(portals)) {
    if (dir !== 'default') return p;
  }
  return null;
}

/** Special connection target for warp_edge portals (cross-section transitions) */
const WARP_TARGET = '__warp__';

interface BakedCell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  portals: Record<string, PortalData>;
  is_start: boolean;
  is_end: boolean;
  warp_edge: string;
}

export default function PreviewTab({ project }: PreviewTabProps) {
  const [bakedCells, setBakedCells] = useState<Record<string, BakedCell>>({});
  const [currentCellPos, setCurrentCellPos] = useState<string | null>(null);
  // initialPosition/initialYaw are passed to StageScene when a cell loads
  const [spawnPos, setSpawnPos] = useState<[number, number, number]>([0, 2, 0]);
  const [spawnYaw, setSpawnYaw] = useState(0);
  // Throttled position from StageScene for overlays
  const [reportedPos, setReportedPos] = useState<[number, number, number]>([0, 2, 0]);
  const [svgSettings, setSvgSettings] = useState<SvgSettings | null>(null);
  const [sectionIdx, setSectionIdx] = useState(0);
  // When warping between sections, stores entry context
  const [pendingEntryDir, setPendingEntryDir] = useState<string | null>(null);
  const [pendingEntryForward, setPendingEntryForward] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Bake portal data from the project
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    projectToGodotQuest(project).then(godotQuest => {
      if (cancelled) return;

      const quest = godotQuest as any;
      const sections = quest.sections || [];
      if (sections.length === 0) {
        setError('No sections found');
        setLoading(false);
        return;
      }

      const secIdx = Math.min(sectionIdx, sections.length - 1);
      const section = sections[secIdx];
      const cells: Record<string, BakedCell> = {};

      for (const cell of section.cells || []) {
        const warpEdge: string = cell.warp_edge || '';
        const connections: Record<string, string> = { ...(cell.connections || {}) };
        const cellPortals: Record<string, PortalData> = cell.portals || {};
        // Add warp_edge as a navigable connection with special target
        if (warpEdge && !connections[warpEdge]) {
          connections[warpEdge] = WARP_TARGET;
        }
        // For start/end cells, any portal direction without a connection is also a warp
        // (handles transition sections with 2 gates, where warp_edge only captures one)
        if (cell.is_start || cell.is_end) {
          for (const dir of Object.keys(cellPortals)) {
            if (dir !== 'default' && !connections[dir]) {
              connections[dir] = WARP_TARGET;
            }
          }
        }
        cells[cell.pos] = {
          pos: cell.pos,
          stage_id: cell.stage_id,
          rotation: cell.rotation || 0,
          connections,
          portals: cellPortals,
          is_start: cell.is_start || false,
          is_end: cell.is_end || false,
          warp_edge: warpEdge,
        };
      }

      setBakedCells(cells);

      // Set initial cell when entering a section
      const startCell = Object.values(cells).find(c => c.is_start);
      const endCell = Object.values(cells).find(c => c.is_end);
      const firstCell = startCell || Object.values(cells)[0];
      if (firstCell && !currentCellPos) {
        // If we have a pending entry direction (from cross-section warp),
        // pick the cell that has a portal on that direction
        const entryDir = pendingEntryDir;
        const isForward = pendingEntryForward;
        setPendingEntryDir(null);

        // Forward warps enter at start cell, backward warps at end cell
        const primaryCell = isForward ? startCell : endCell;
        const secondaryCell = isForward ? endCell : startCell;
        const entryCell = (entryDir && primaryCell && primaryCell.portals[entryDir])
          ? primaryCell
          : (entryDir && secondaryCell && secondaryCell.portals[entryDir])
            ? secondaryCell
            : firstCell;

        setCurrentCellPos(entryCell.pos);

        // Spawn at the entry direction's portal if available
        const entryPortal = entryDir ? entryCell.portals[entryDir] : null;
        const sp = entryPortal || findSpawnPortal(entryCell.portals);
        if (sp) {
          setSpawnPos(sp.spawn);
          setSpawnYaw(getSpawnYaw(sp));
        } else {
          setSpawnPos([0, 2, 0]);
          setSpawnYaw(0);
        }
      }

      setLoading(false);
    }).catch(err => {
      if (!cancelled) {
        setError(`Failed to bake data: ${err.message}`);
        setLoading(false);
      }
    });

    return () => { cancelled = true; };
  }, [project, sectionIdx]);

  const currentCell = currentCellPos ? bakedCells[currentCellPos] : null;

  // Load SVG settings when stage changes
  useEffect(() => {
    if (!currentCell) { setSvgSettings(null); return; }
    let cancelled = false;
    getSvgSettings(currentCell.stage_id).then(settings => {
      if (!cancelled) setSvgSettings(settings);
    });
    return () => { cancelled = true; };
  }, [currentCell?.stage_id]);

  const sections = useMemo(() => getProjectSections(project), [project]);

  const handlePositionReport = useCallback((x: number, y: number, z: number) => {
    setReportedPos([x, y, z]);
  }, []);

  const handleTriggerEnter = useCallback((direction: string, targetCellPos: string) => {
    // Warp edge → switch to next or previous section
    if (targetCellPos === WARP_TARGET) {
      const cell = currentCellPos ? bakedCells[currentCellPos] : null;
      if (!cell) return;

      // Determine direction: warp_edge direction goes forward (to next section),
      // any other unconnected gate goes backward (to previous section)
      const isForward = cell.warp_edge === direction || (cell.is_end && !cell.is_start);
      const nextIdx = isForward
        ? Math.min(sectionIdx + 1, sections.length - 1)
        : Math.max(sectionIdx - 1, 0);

      if (nextIdx !== sectionIdx) {
        // Player enters the new section from the same direction they walked through
        setPendingEntryDir(direction);
        setPendingEntryForward(isForward);
        setCurrentCellPos(null);
        setSectionIdx(nextIdx);
      }
      return;
    }

    const targetCell = bakedCells[targetCellPos];
    if (!targetCell) return;

    // Find which direction in the TARGET cell connects back to the SOURCE cell
    const sourcePos = currentCellPos;
    let returnDir: string | null = null;
    for (const [dir, connectedPos] of Object.entries(targetCell.connections)) {
      if (connectedPos === sourcePos) {
        returnDir = dir;
        break;
      }
    }

    const returnPortal = returnDir ? targetCell.portals[returnDir] : null;

    let pos: [number, number, number];
    let yaw: number;

    // 3D view is unrotated — use raw model-local spawn positions
    if (returnPortal) {
      pos = returnPortal.spawn;
      yaw = getSpawnYaw(returnPortal);
    } else {
      const sp = findSpawnPortal(targetCell.portals);
      if (sp) {
        pos = sp.spawn;
        yaw = getSpawnYaw(sp);
      } else {
        pos = [0, 2, 0];
        yaw = 0;
      }
    }

    setCurrentCellPos(targetCellPos);
    setSpawnPos(pos);
    setSpawnYaw(yaw);
  }, [bakedCells, currentCellPos, sectionIdx, sections.length]);

  const handleCellClick = useCallback((pos: string) => {
    const cell = bakedCells[pos];
    if (!cell) return;
    setCurrentCellPos(pos);
    const sp = findSpawnPortal(cell.portals);
    if (sp) {
      setSpawnPos(sp.spawn);
      setSpawnYaw(getSpawnYaw(sp));
    } else {
      setSpawnPos([0, 2, 0]);
      setSpawnYaw(0);
    }
  }, [bakedCells]);

  if (loading) {
    return (
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#1a1a2e', color: '#888' }}>
        Baking portal data...
      </div>
    );
  }

  if (error) {
    return (
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#1a1a2e', color: '#cc4444' }}>
        {error}
      </div>
    );
  }

  if (!currentCell) {
    return (
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#1a1a2e', color: '#888' }}>
        No cells to preview. Add cells in the Layout tab first.
      </div>
    );
  }

  const cellKeys = Object.keys(bakedCells);

  return (
    <div style={{ flex: 1, display: 'flex', position: 'relative', overflow: 'hidden' }}>
      {/* Cell sidebar */}
      <div style={{
        width: 160,
        background: '#151525',
        borderRight: '1px solid #333',
        overflow: 'auto',
        flexShrink: 0,
      }}>
        {sections.length > 1 && (
          <div style={{ padding: '8px', borderBottom: '1px solid #333' }}>
            <div style={{ fontSize: 10, color: '#888', marginBottom: 4 }}>Section</div>
            {sections.map((sec, idx) => (
              <button
                key={idx}
                onClick={() => { setSectionIdx(idx); setCurrentCellPos(null); }}
                style={{
                  display: 'block', width: '100%', padding: '4px 8px', marginBottom: 2,
                  background: idx === sectionIdx ? '#3a3a6a' : '#222',
                  border: `1px solid ${idx === sectionIdx ? '#5588ff' : '#444'}`,
                  borderRadius: 4, color: idx === sectionIdx ? '#fff' : '#888',
                  fontSize: 11, cursor: 'pointer', textAlign: 'left',
                }}
              >
                {sec.type} {sec.variant.toUpperCase()}
              </button>
            ))}
          </div>
        )}

        <div style={{ padding: '8px' }}>
          <div style={{ fontSize: 10, color: '#888', marginBottom: 4 }}>Cells ({cellKeys.length})</div>
          {cellKeys.map(pos => {
            const cell = bakedCells[pos];
            const isCurrent = pos === currentCellPos;
            return (
              <button
                key={pos}
                onClick={() => handleCellClick(pos)}
                style={{
                  display: 'block', width: '100%', padding: '5px 8px', marginBottom: 2,
                  background: isCurrent ? '#3a3a6a' : '#222',
                  border: `1px solid ${isCurrent ? '#5588ff' : '#333'}`,
                  borderRadius: 4, color: isCurrent ? '#fff' : '#aaa',
                  fontSize: 11, cursor: 'pointer', textAlign: 'left',
                }}
              >
                <div style={{ fontWeight: isCurrent ? 600 : 400 }}>{pos}</div>
                <div style={{ fontSize: 9, color: '#888' }}>
                  {cell.stage_id}
                  {cell.is_start ? ' [START]' : ''}
                  {cell.is_end ? ' [END]' : ''}
                </div>
              </button>
            );
          })}
        </div>

        <div style={{
          padding: '8px', borderTop: '1px solid #333',
          fontSize: 10, color: '#666', lineHeight: 1.6,
        }}>
          <div><strong style={{ color: '#888' }}>W/S</strong> — Forward / Back</div>
          <div><strong style={{ color: '#888' }}>A/D</strong> — Turn left / right</div>
          <div><strong style={{ color: '#888' }}>Triggers</strong> — Auto cell switch</div>
        </div>
      </div>

      {/* 3D Canvas */}
      <div style={{ flex: 1, position: 'relative' }}>
        <Canvas style={{ background: '#1a1a2e' }}>
          <Suspense fallback={null}>
            <StageScene
              areaKey={project.areaKey}
              stageId={currentCell.stage_id}
              portals={currentCell.portals}
              connections={currentCell.connections}
              initialPosition={spawnPos}
              initialYaw={spawnYaw}
              onPositionReport={handlePositionReport}
              onTriggerEnter={handleTriggerEnter}
            />
          </Suspense>
        </Canvas>

        {/* Minimap overlay */}
        <div style={{ position: 'absolute', top: 12, right: 12, pointerEvents: 'none' }}>
          <PreviewMinimap
            areaFolder={STAGE_AREAS[project.areaKey]?.folder ?? 'valley'}
            stageId={currentCell.stage_id}
            svgSettings={svgSettings}
            cellRotation={currentCell.rotation}
            portals={currentCell.portals}
            connections={currentCell.connections}
            playerX={reportedPos[0]}
            playerZ={reportedPos[2]}
          />
        </div>

        {/* Cell info — selectable for copy-paste */}
        <div
          style={{
            position: 'absolute', top: 12, left: 12,
            background: 'rgba(0,0,0,0.85)', padding: '8px 12px',
            borderRadius: 6, fontSize: 11, color: '#ccc',
            fontFamily: 'monospace', userSelect: 'text', cursor: 'text',
            lineHeight: 1.6,
          }}
          onClick={e => e.stopPropagation()}
        >
          <div style={{ color: '#fff', fontWeight: 600, fontSize: 12, marginBottom: 2 }}>
            {currentCell.stage_id}
          </div>
          <div>cell: {currentCell.pos}</div>
          <div>rot: {currentCell.rotation}</div>
          <div style={{ color: '#888', marginTop: 2 }}>
            {Object.entries(currentCell.connections).map(([dir, target]) =>
              `${dir[0].toUpperCase()}→${target === WARP_TARGET ? 'warp' : target}`
            ).join('  ') || 'no connections'}
          </div>
        </div>

        {/* Grid overview overlay */}
        <div style={{ position: 'absolute', bottom: 12, right: 12 }}>
          <PreviewGrid
            bakedCells={bakedCells}
            currentCellPos={currentCellPos}
            onCellClick={handleCellClick}
          />
        </div>

        {/* Coordinate readout */}
        <div style={{
          position: 'absolute', bottom: 12, left: 12,
          background: 'rgba(0,0,0,0.7)', padding: '4px 10px',
          borderRadius: 6, fontSize: 11, color: '#88cc88',
          fontFamily: 'monospace', pointerEvents: 'none',
        }}>
          x:{reportedPos[0].toFixed(1)} y:{reportedPos[1].toFixed(1)} z:{reportedPos[2].toFixed(1)}
        </div>
      </div>
    </div>
  );
}
