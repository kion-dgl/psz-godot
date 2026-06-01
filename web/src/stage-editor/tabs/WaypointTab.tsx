import { useState } from 'react';
import type { UnifiedStageConfig } from '../types';

// Clipboard write that also works over plain http on a LAN, where
// navigator.clipboard is unavailable outside a secure context — falls back to
// the legacy execCommand path.
async function copyToClipboard(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch { /* fall through to legacy */ }
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}

interface WaypointTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  placementMode: boolean;
  setPlacementMode: (mode: boolean) => void;
  selectedId: string | null;
  setSelectedId: (id: string | null) => void;
  onSeedFromGates: () => void;
  onAutoConnect: () => void;
  // Manhattan grid overlay controls — visualizes what the CLI solver
  // (scripts/tools/quest_solver/solve_manhattan.ts) would produce, so the
  // user can verify the grid + sample path without spinning up the autopilot.
  showManhattan: boolean;
  setShowManhattan: (v: boolean) => void;
  manhattanResolution: number;
  setManhattanResolution: (v: number) => void;
  manhattanClearance: number;
  setManhattanClearance: (v: number) => void;
  manhattanFuseVisual: boolean;
  setManhattanFuseVisual: (v: boolean) => void;
  // Floor marker — magenta post the user pins by typing XZ. Also driven
  // by the `?marker=x,z` URL param.
  markerX: string;
  setMarkerX: (v: string) => void;
  markerZ: string;
  setMarkerZ: (v: string) => void;
  // Capsule sim — animates a sphere along the BFS-shortest path between
  // two existing waypoints, checking floor presence at every step.
  simFromId: string;
  setSimFromId: (id: string) => void;
  simToId: string;
  setSimToId: (id: string) => void;
  simSpeed: number;
  setSimSpeed: (v: number) => void;
  simResult: { ok: boolean; failedAt?: { x: number; z: number }; legIndex?: number } | null;
  onSimRun: () => void;
  // Multi-leg cell playback. When activeCellPos is set, the sim runs the
  // full per-cell autopilot sequence (spawn → switch → exit through opened
  // fence). cellPlaybackCells is the list of cells in the active quest that
  // use this stage — usually one, but a stage CAN be reused across cells.
  cellPlaybackAvailable: boolean;
  cellPlaybackCells: string[];
  activeCellPos: string;
  setActiveCellPos: (pos: string) => void;
  cellPlaybackDescription: string[];
  cellPlaybackError: string | null;
  cellSwitchActivated: boolean;
  cellLegsCompleted: number;
  cellLegsTotal: number;
  onPlayCell: () => void;
  manhattanInfo?: { loading: boolean; error: string | null; trisFiltered: number; gridSize: string | null; pathCorners: number | null; usedDiagonal: boolean };
}

const inputStyle: React.CSSProperties = {
  flex: 1, background: '#1a1a2e', color: '#ddd', border: '1px solid #333',
  borderRadius: 3, padding: '2px 4px', fontSize: 11, minWidth: 40,
};

const selectStyle: React.CSSProperties = {
  flex: 1, background: '#1a1a2e', color: '#ddd', border: '1px solid #333',
  borderRadius: 3, padding: '2px 4px', fontSize: 11,
};

const btn = (active: boolean): React.CSSProperties => ({
  padding: '8px 10px',
  background: active ? '#4a9eff' : '#3a3a55',
  color: 'white',
  border: 'none',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 13,
  width: '100%',
});

export default function WaypointTab({
  config, updateConfig, placementMode, setPlacementMode, selectedId, setSelectedId,
  onSeedFromGates, onAutoConnect,
  showManhattan, setShowManhattan,
  manhattanResolution, setManhattanResolution,
  manhattanClearance, setManhattanClearance,
  manhattanFuseVisual, setManhattanFuseVisual,
  markerX, setMarkerX, markerZ, setMarkerZ,
  simFromId, setSimFromId, simToId, setSimToId,
  simSpeed, setSimSpeed, simResult, onSimRun,
  cellPlaybackAvailable, cellPlaybackCells,
  activeCellPos, setActiveCellPos,
  cellPlaybackDescription, cellPlaybackError,
  cellSwitchActivated, cellLegsCompleted, cellLegsTotal,
  onPlayCell,
  manhattanInfo,
}: WaypointTabProps) {
  const waypoints = config.waypoints ?? [];
  const edges = config.waypointEdges ?? [];
  const edgeCount = (id: string) => edges.filter(([a, b]) => a === id || b === id).length;

  const deleteWaypoint = (id: string) => {
    updateConfig((prev) => ({
      ...prev,
      waypoints: (prev.waypoints ?? []).filter((w) => w.id !== id),
      waypointEdges: (prev.waypointEdges ?? []).filter(([a, b]) => a !== id && b !== id),
    }));
    if (selectedId === id) setSelectedId(null);
  };

  const renameWaypoint = (id: string, label: string) => {
    updateConfig((prev) => ({
      ...prev,
      waypoints: (prev.waypoints ?? []).map((w) => (w.id === id ? { ...w, label } : w)),
    }));
  };

  const clearAll = () => {
    if (!confirm('Delete all waypoints + edges for this map?')) return;
    updateConfig((prev) => ({ ...prev, waypoints: [], waypointEdges: [] }));
    setSelectedId(null);
  };

  const [copied, setCopied] = useState(false);
  const copyJson = async () => {
    const json = JSON.stringify({ mapId: config.mapId, waypoints, waypointEdges: edges }, null, 2);
    const ok = await copyToClipboard(json);
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } else {
      // Last resort if even execCommand is blocked — show it for manual copy.
      window.prompt('Copy the waypoint JSON:', json);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, color: '#ddd', fontSize: 13 }}>
      <div style={{ fontSize: 12, color: '#9ad6ff', lineHeight: 1.5 }}>
        Build the nav graph the autopilot walks. <b>Place</b> points on the floor, then click a node to
        anchor it and click others to connect/disconnect — edges mean “straight-line walkable”.
      </div>

      <button style={btn(placementMode)} onClick={() => { setPlacementMode(!placementMode); setSelectedId(null); }}>
        {placementMode ? '● Placing — click floor (click to stop)' : '+ Place waypoints'}
      </button>

      <button style={btn(false)} onClick={onSeedFromGates}>
        Seed from gates + spawn
      </button>
      <button style={btn(false)} onClick={onAutoConnect}>
        Auto-connect (raycast floor)
      </button>
      <button style={btn(false)} onClick={copyJson}>
        {copied ? '✓ Copied JSON' : 'Copy JSON'}
      </button>

      {/* Manhattan grid solver visualizer */}
      <div style={{ marginTop: 8, padding: '8px 10px', background: '#1c2538', borderRadius: 4 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
          <strong style={{ fontSize: 12, color: '#9ad6ff' }}>Manhattan grid overlay</strong>
          <button
            onClick={() => setShowManhattan(!showManhattan)}
            style={{
              padding: '3px 8px', fontSize: 11,
              background: showManhattan ? '#22c55e' : '#3a3a55',
              color: 'white', border: 'none', borderRadius: 3, cursor: 'pointer',
            }}
          >
            {showManhattan ? 'on' : 'off'}
          </button>
        </div>
        {showManhattan && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 11, color: '#bbb' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 70 }}>Resolution</span>
              <input
                type="range" min="0.25" max="1.5" step="0.05"
                value={manhattanResolution}
                onChange={(e) => setManhattanResolution(parseFloat(e.target.value))}
                style={{ flex: 1 }}
              />
              <span style={{ width: 40, textAlign: 'right' }}>{manhattanResolution.toFixed(2)}m</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 70 }}>Clearance</span>
              <input
                type="range" min="0" max="2" step="0.1"
                value={manhattanClearance}
                onChange={(e) => setManhattanClearance(parseFloat(e.target.value))}
                style={{ flex: 1 }}
              />
              <span style={{ width: 40, textAlign: 'right' }}>{manhattanClearance.toFixed(1)}m</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <input type="checkbox" checked={manhattanFuseVisual} onChange={(e) => setManhattanFuseVisual(e.target.checked)} />
              <span>fuse visual mesh (-m.glb)</span>
            </label>
            {manhattanInfo && (
              <div style={{ marginTop: 4, fontSize: 10, color: '#888' }}>
                {manhattanInfo.loading
                  ? 'computing…'
                  : manhattanInfo.error
                    ? `error: ${manhattanInfo.error}`
                    : (
                      <>
                        {manhattanInfo.trisFiltered} tris · grid {manhattanInfo.gridSize}
                        {manhattanInfo.pathCorners != null && (
                          <> · path: {manhattanInfo.pathCorners} corners{manhattanInfo.usedDiagonal ? ' (with diagonal fallback)' : ''}</>
                        )}
                      </>
                    )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Floor coord marker */}
      <div style={{ padding: '8px 10px', background: '#1c2538', borderRadius: 4 }}>
        <strong style={{ fontSize: 12, color: '#ec4899', display: 'block', marginBottom: 6 }}>Floor marker (magenta post)</strong>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 11, color: '#bbb' }}>
          <span style={{ width: 14 }}>X</span>
          <input
            type="number" step="0.5" value={markerX} onChange={(e) => setMarkerX(e.target.value)}
            placeholder="x" style={inputStyle}
          />
          <span style={{ width: 14 }}>Z</span>
          <input
            type="number" step="0.5" value={markerZ} onChange={(e) => setMarkerZ(e.target.value)}
            placeholder="z" style={inputStyle}
          />
          <button onClick={() => { setMarkerX(''); setMarkerZ(''); }} style={{ ...btn(false), padding: '2px 8px', width: 'auto', fontSize: 11 }}>clear</button>
        </div>
        <div style={{ marginTop: 4, fontSize: 10, color: '#888' }}>
          URL: <code>?marker=x,z</code> (or <code>x1,z1;x2,z2</code> for several)
        </div>
      </div>

      {/* Capsule simulator */}
      <div style={{ padding: '8px 10px', background: '#1c2538', borderRadius: 4 }}>
        <strong style={{ fontSize: 12, color: '#22d3ee', display: 'block', marginBottom: 6 }}>Capsule sim</strong>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 11, color: '#bbb' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 32 }}>from</span>
            <select value={simFromId} onChange={(e) => setSimFromId(e.target.value)} style={selectStyle}>
              <option value="">— pick —</option>
              {waypoints.map((wp) => (
                <option key={wp.id} value={wp.id}>{(wp.kind ?? 'point')}·{wp.id.slice(-4)} {wp.label ?? ''}</option>
              ))}
            </select>
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 32 }}>to</span>
            <select value={simToId} onChange={(e) => setSimToId(e.target.value)} style={selectStyle}>
              <option value="">— pick —</option>
              {waypoints.map((wp) => (
                <option key={wp.id} value={wp.id}>{(wp.kind ?? 'point')}·{wp.id.slice(-4)} {wp.label ?? ''}</option>
              ))}
            </select>
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 32 }}>speed</span>
            <input
              type="range" min="1" max="20" step="0.5" value={simSpeed}
              onChange={(e) => setSimSpeed(parseFloat(e.target.value))}
              style={{ flex: 1 }}
            />
            <span style={{ width: 40, textAlign: 'right' }}>{simSpeed.toFixed(1)}m/s</span>
          </label>
          <button
            onClick={onSimRun}
            disabled={!simFromId || !simToId}
            style={{
              padding: '6px 10px', fontSize: 11,
              background: simFromId && simToId ? '#22d3ee' : '#3a3a55',
              color: simFromId && simToId ? '#0a1118' : '#888',
              border: 'none', borderRadius: 3, cursor: simFromId && simToId ? 'pointer' : 'not-allowed',
              fontWeight: 600,
            }}
          >
            ▶ Run sim
          </button>
          {simResult && (
            <div style={{ marginTop: 4, fontSize: 10, padding: '4px 6px', borderRadius: 3,
              background: simResult.ok ? '#14532d' : '#7f1d1d',
              color: simResult.ok ? '#86efac' : '#fca5a5' }}>
              {simResult.ok
                ? '✓ reached destination — no floor holes'
                : `✗ NO FLOOR at (${simResult.failedAt?.x.toFixed(2)}, ${simResult.failedAt?.z.toFixed(2)}) on leg ${(simResult.legIndex ?? 0) + 1}`}
            </div>
          )}
        </div>
      </div>

      {/* Per-cell playback — full autopilot sequence for the active cell. */}
      {cellPlaybackAvailable && (
        <div style={{ padding: '8px 10px', background: '#1c2538', borderRadius: 4 }}>
          <strong style={{ fontSize: 12, color: '#fbbf24', display: 'block', marginBottom: 6 }}>
            Play cell (full autopilot sequence)
          </strong>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 11, color: '#bbb' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 32 }}>cell</span>
              <select
                value={activeCellPos}
                onChange={(e) => setActiveCellPos(e.target.value)}
                style={selectStyle}
              >
                <option value="">— off (single-leg mode) —</option>
                {cellPlaybackCells.map((pos) => (
                  <option key={pos} value={pos}>cell {pos}</option>
                ))}
              </select>
            </label>
            {activeCellPos && cellPlaybackDescription.length > 0 && (
              <div style={{ fontSize: 10, color: '#888', lineHeight: 1.4 }}>
                Sequence: {cellPlaybackDescription.join(' → ')}
              </div>
            )}
            {activeCellPos && cellPlaybackError && (
              <div style={{ fontSize: 10, padding: '4px 6px', borderRadius: 3, background: '#7f1d1d', color: '#fca5a5' }}>
                ⚠ {cellPlaybackError}
              </div>
            )}
            {activeCellPos && (
              <>
                <button
                  onClick={onPlayCell}
                  disabled={cellLegsTotal === 0}
                  style={{
                    padding: '6px 10px', fontSize: 11,
                    background: cellLegsTotal > 0 ? '#fbbf24' : '#3a3a55',
                    color: cellLegsTotal > 0 ? '#0a1118' : '#888',
                    border: 'none', borderRadius: 3,
                    cursor: cellLegsTotal > 0 ? 'pointer' : 'not-allowed',
                    fontWeight: 600,
                  }}
                >
                  ▶ Play cell ({cellLegsTotal} leg{cellLegsTotal === 1 ? '' : 's'})
                </button>
                <div style={{ display: 'flex', gap: 8, fontSize: 10, color: '#bbb' }}>
                  <span>Phase: {cellSwitchActivated ? 'POST-switch (fence open)' : 'PRE-switch (fence closed)'}</span>
                  <span style={{ marginLeft: 'auto' }}>
                    {cellLegsCompleted}/{cellLegsTotal} legs
                  </span>
                </div>
              </>
            )}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: '#888' }}>
        <span>{waypoints.length} waypoints</span>
        <span>{edges.length} edges</span>
      </div>

      {selectedId && (
        <div style={{ background: '#222238', padding: 8, borderRadius: 4, fontSize: 12 }}>
          Anchor: <code>{selectedId.slice(-6)}</code> — click another node to connect/disconnect.
          <button style={{ ...btn(false), marginTop: 6 }} onClick={() => setSelectedId(null)}>Clear anchor</button>
        </div>
      )}

      <div style={{ maxHeight: 360, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
        {waypoints.map((wp) => (
          <div
            key={wp.id}
            style={{
              display: 'flex', alignItems: 'center', gap: 6, padding: '4px 6px', borderRadius: 4,
              background: wp.id === selectedId ? '#2d4a6b' : '#252540',
            }}
          >
            <button
              onClick={() => setSelectedId(wp.id === selectedId ? null : wp.id)}
              style={{ background: 'none', border: 'none', color: '#9ad6ff', cursor: 'pointer', fontSize: 11, fontFamily: 'monospace' }}
              title="Select as anchor"
            >
              {(wp.kind ?? 'point')}·{wp.id.slice(-4)}
            </button>
            <input
              value={wp.label ?? ''}
              placeholder="label…"
              onChange={(e) => renameWaypoint(wp.id, e.target.value)}
              style={{ flex: 1, background: '#1a1a2e', color: '#ddd', border: '1px solid #333', borderRadius: 3, padding: '2px 4px', fontSize: 11, minWidth: 0 }}
            />
            <span style={{ fontSize: 10, color: '#888' }}>×{edgeCount(wp.id)}</span>
            <button
              onClick={() => deleteWaypoint(wp.id)}
              style={{ background: '#5a2a2a', color: '#fbb', border: 'none', borderRadius: 3, cursor: 'pointer', fontSize: 11, padding: '2px 6px' }}
            >
              ✕
            </button>
          </div>
        ))}
      </div>

      {waypoints.length > 0 && (
        <button style={{ ...btn(false), background: '#5a2a2a' }} onClick={clearAll}>Clear all</button>
      )}
    </div>
  );
}
