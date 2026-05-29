import type { UnifiedStageConfig } from '../types';

interface WaypointTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  placementMode: boolean;
  setPlacementMode: (mode: boolean) => void;
  selectedId: string | null;
  setSelectedId: (id: string | null) => void;
  onSeedFromGates: () => void;
  onAutoConnect: () => void;
}

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
