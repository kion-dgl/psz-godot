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
import { projectToGodotQuest } from '../utils/quest-io';
import StageScene from '../preview/StageScene';
import type { PortalData } from '../preview/StageScene';
import PreviewMinimap from '../preview/PreviewMinimap';

interface PreviewTabProps {
  project: QuestProject;
}

/** Rotate a model-local position by cell rotation degrees around Y */
function rotateSpawn(pos: [number, number, number], degY: number): [number, number, number] {
  if (degY === 0) return pos;
  const rad = (degY * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  return [pos[0] * cos + pos[2] * sin, pos[1], -pos[0] * sin + pos[2] * cos];
}

/** Get the yaw (facing direction) from a portal's gate_rot, accounting for cell rotation.
 *  gate_rot[1] is the gate's Y rotation in radians — this is the inward-facing direction,
 *  exactly where the player should face when spawning. */
function getSpawnYaw(portal: PortalData, cellRotDeg: number): number {
  const gateRotY = portal.gate_rot ? portal.gate_rot[1] : 0;
  // gate_rot points outward from the room; player should face inward (+PI)
  return gateRotY + (cellRotDeg * Math.PI) / 180 + Math.PI;
}

interface BakedCell {
  pos: string;
  stage_id: string;
  rotation: number;
  connections: Record<string, string>;
  portals: Record<string, PortalData>;
  is_start: boolean;
  is_end: boolean;
}

export default function PreviewTab({ project }: PreviewTabProps) {
  const [bakedCells, setBakedCells] = useState<Record<string, BakedCell>>({});
  const [currentCellPos, setCurrentCellPos] = useState<string | null>(null);
  // initialPosition/initialYaw are passed to StageScene when a cell loads
  const [spawnPos, setSpawnPos] = useState<[number, number, number]>([0, 2, 0]);
  const [spawnYaw, setSpawnYaw] = useState(0);
  // Throttled position from StageScene for overlays
  const [reportedPos, setReportedPos] = useState<[number, number, number]>([0, 2, 0]);
  // Floor triangles extracted from GLB for minimap
  const [floorTriangles, setFloorTriangles] = useState<number[][] | null>(null);
  const [sectionIdx, setSectionIdx] = useState(0);
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
        cells[cell.pos] = {
          pos: cell.pos,
          stage_id: cell.stage_id,
          rotation: cell.rotation || 0,
          connections: cell.connections || {},
          portals: cell.portals || {},
          is_start: cell.is_start || false,
          is_end: cell.is_end || false,
        };
      }

      setBakedCells(cells);

      // Set initial cell to start pos
      const startCell = Object.values(cells).find(c => c.is_start);
      const firstCell = startCell || Object.values(cells)[0];
      if (firstCell && !currentCellPos) {
        setCurrentCellPos(firstCell.pos);
        const dp = firstCell.portals['default'];
        if (dp) {
          setSpawnPos(rotateSpawn(dp.spawn, firstCell.rotation));
          setSpawnYaw(getSpawnYaw(dp, firstCell.rotation));
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

  // Rotated portals for minimap (same world space as 3D view)
  const rotatedPortals = useMemo(() => {
    if (!currentCell) return {};
    const rot = currentCell.rotation;
    if (rot === 0) return currentCell.portals;
    const result: Record<string, PortalData> = {};
    for (const [key, p] of Object.entries(currentCell.portals)) {
      result[key] = {
        ...p,
        gate: rotateSpawn(p.gate, rot),
        spawn: rotateSpawn(p.spawn, rot),
        trigger: rotateSpawn(p.trigger, rot),
      };
    }
    return result;
  }, [currentCell]);

  const handlePositionReport = useCallback((x: number, y: number, z: number) => {
    setReportedPos([x, y, z]);
  }, []);

  const handleFloorData = useCallback((triangles: number[][]) => {
    setFloorTriangles(triangles);
  }, []);

  const handleTriggerEnter = useCallback((direction: string, targetCellPos: string) => {
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

    const rot = targetCell.rotation;
    const returnPortal = returnDir ? targetCell.portals[returnDir] : null;

    let pos: [number, number, number];
    let yaw: number;

    if (returnPortal) {
      pos = rotateSpawn(returnPortal.spawn, rot);
      yaw = getSpawnYaw(returnPortal, rot);
    } else {
      const dp = targetCell.portals['default'];
      if (dp) {
        pos = rotateSpawn(dp.spawn, rot);
        yaw = getSpawnYaw(dp, rot);
      } else {
        pos = [0, 2, 0];
        yaw = 0;
      }
    }

    setCurrentCellPos(targetCellPos);
    setSpawnPos(pos);
    setSpawnYaw(yaw);
  }, [bakedCells, currentCellPos]);

  const handleCellClick = useCallback((pos: string) => {
    const cell = bakedCells[pos];
    if (!cell) return;
    setCurrentCellPos(pos);
    const dp = cell.portals['default'];
    if (dp) {
      setSpawnPos(rotateSpawn(dp.spawn, cell.rotation));
      setSpawnYaw(getSpawnYaw(dp, cell.rotation));
    } else {
      setSpawnPos([0, 2, 0]);
      setSpawnYaw(0);
    }
  }, [bakedCells]);

  const sections = useMemo(() => getProjectSections(project), [project]);

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
              cellRotation={currentCell.rotation}
              portals={currentCell.portals}
              connections={currentCell.connections}
              initialPosition={spawnPos}
              initialYaw={spawnYaw}
              onPositionReport={handlePositionReport}
              onTriggerEnter={handleTriggerEnter}
              onFloorData={handleFloorData}
            />
          </Suspense>
        </Canvas>

        {/* Minimap overlay */}
        <div style={{ position: 'absolute', top: 12, right: 12, pointerEvents: 'none' }}>
          <PreviewMinimap
            floorTriangles={floorTriangles}
            portals={rotatedPortals}
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
              `${dir[0].toUpperCase()}→${target}`
            ).join('  ') || 'no connections'}
          </div>
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
