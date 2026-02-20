import type { UnifiedStageConfig, ObstacleData, ObstacleType } from '../types';

interface ObstacleTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  placementMode: boolean;
  setPlacementMode: (mode: boolean) => void;
  placementType: ObstacleType;
  setPlacementType: (type: ObstacleType) => void;
  placementDimensions: PlacementDimensions;
  setPlacementDimensions: (dims: PlacementDimensions) => void;
  selectedObstacleId: string | null;
  setSelectedObstacleId: (id: string | null) => void;
  placementLabel: string;
  setPlacementLabel: (label: string) => void;
}

export interface PlacementDimensions {
  width: number;
  height: number;
  depth: number;
  radius: number;
  cylinderHeight: number;
  rotationY: number; // Y rotation in degrees for boxes
}

export const DEFAULT_PLACEMENT_DIMENSIONS: PlacementDimensions = {
  width: 2,
  height: 2,
  depth: 2,
  radius: 1,
  cylinderHeight: 2,
  rotationY: 0,
};

// Helper to convert degrees to radians
const radToDeg = (rad: number) => (rad * 180) / Math.PI;
const degToRad = (deg: number) => (deg * Math.PI) / 180;

const OBSTACLE_TYPES: ObstacleType[] = ['box', 'cylinder'];

export default function ObstacleTab({
  config,
  updateConfig,
  placementMode,
  setPlacementMode,
  placementType,
  setPlacementType,
  placementDimensions,
  setPlacementDimensions,
  selectedObstacleId,
  setSelectedObstacleId,
  placementLabel,
  setPlacementLabel,
}: ObstacleTabProps) {

  const selectedObstacle = config.obstacles.find((o) => o.id === selectedObstacleId);

  // Update obstacle
  const updateObstacle = (id: string, updates: Partial<ObstacleData>) => {
    updateConfig((prev) => ({
      ...prev,
      obstacles: prev.obstacles.map((o) => (o.id === id ? { ...o, ...updates } : o)),
    }));
  };

  // Delete obstacle
  const deleteObstacle = (id: string) => {
    updateConfig((prev) => ({
      ...prev,
      obstacles: prev.obstacles.filter((o) => o.id !== id),
    }));
    if (selectedObstacleId === id) {
      setSelectedObstacleId(null);
    }
  };

  // Duplicate obstacle
  const duplicateObstacle = (obstacle: ObstacleData) => {
    const newId = `obs_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const newObs: ObstacleData = {
      ...obstacle,
      id: newId,
      label: `${obstacle.label} (copy)`,
      position: [obstacle.position[0] + 2, obstacle.position[1], obstacle.position[2] + 2],
    };

    updateConfig((prev) => ({
      ...prev,
      obstacles: [...prev.obstacles, newObs],
    }));

    setSelectedObstacleId(newId);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>
        Collision Obstacles
      </h3>

      {/* Placement mode toggle */}
      <button
        onClick={() => setPlacementMode(!placementMode)}
        style={{
          width: '100%',
          padding: '12px',
          background: placementMode ? '#4a9eff' : '#333',
          color: 'white',
          border: placementMode ? '2px solid #6ab4ff' : '2px solid transparent',
          borderRadius: '4px',
          cursor: 'pointer',
          fontWeight: 'bold',
          fontSize: '14px',
        }}
      >
        {placementMode ? 'Click in scene to place obstacle' : 'Start Placement Mode'}
      </button>

      {/* Type selector */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Obstacle Type:
        </label>
        <div style={{ display: 'flex', gap: '8px' }}>
          {OBSTACLE_TYPES.map((type) => (
            <button
              key={type}
              onClick={() => setPlacementType(type)}
              style={{
                flex: 1,
                padding: '10px',
                background: placementType === type ? (type === 'box' ? '#6b5b95' : '#88b04b') : '#333',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                textTransform: 'capitalize',
                fontWeight: placementType === type ? 'bold' : 'normal',
              }}
            >
              {type}
            </button>
          ))}
        </div>
      </div>

      {/* Label input */}
      <div>
        <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px', color: '#888' }}>
          Label for new obstacles:
        </label>
        <input
          type="text"
          value={placementLabel}
          onChange={(e) => setPlacementLabel(e.target.value)}
          placeholder="Label"
          style={{
            width: '100%',
            padding: '8px',
            background: '#252540',
            color: 'white',
            border: '1px solid #444',
            borderRadius: '4px',
          }}
        />
      </div>

      {/* Dimensions */}
      <div style={{ background: '#1a1a2e', padding: '12px', borderRadius: '4px' }}>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Dimensions (for new obstacles):
        </label>

        {placementType === 'box' ? (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '8px' }}>
              <div>
                <label style={{ fontSize: '10px', color: '#666' }}>Width:</label>
                <input type="number" step="0.5" min="0.1" value={placementDimensions.width} onChange={(e) => setPlacementDimensions({ ...placementDimensions, width: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
              </div>
              <div>
                <label style={{ fontSize: '10px', color: '#666' }}>Height:</label>
                <input type="number" step="0.5" min="0.1" value={placementDimensions.height} onChange={(e) => setPlacementDimensions({ ...placementDimensions, height: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
              </div>
              <div>
                <label style={{ fontSize: '10px', color: '#666' }}>Depth:</label>
                <input type="number" step="0.5" min="0.1" value={placementDimensions.depth} onChange={(e) => setPlacementDimensions({ ...placementDimensions, depth: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
              </div>
            </div>
            {/* Rotation control for boxes */}
            <div style={{ marginTop: '8px' }}>
              <label style={{ fontSize: '10px', color: '#666' }}>Rotation Y:</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '4px' }}>
                <button onClick={() => setPlacementDimensions({ ...placementDimensions, rotationY: placementDimensions.rotationY - 5 })} style={{ padding: '6px 12px', background: '#444', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>-5</button>
                <span style={{ flex: 1, textAlign: 'center', fontSize: '14px' }}>{placementDimensions.rotationY}</span>
                <button onClick={() => setPlacementDimensions({ ...placementDimensions, rotationY: placementDimensions.rotationY + 5 })} style={{ padding: '6px 12px', background: '#444', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>+5</button>
              </div>
            </div>
          </>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
            <div>
              <label style={{ fontSize: '10px', color: '#666' }}>Radius:</label>
              <input type="number" step="0.5" min="0.1" value={placementDimensions.radius} onChange={(e) => setPlacementDimensions({ ...placementDimensions, radius: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
            </div>
            <div>
              <label style={{ fontSize: '10px', color: '#666' }}>Height:</label>
              <input type="number" step="0.5" min="0.1" value={placementDimensions.cylinderHeight} onChange={(e) => setPlacementDimensions({ ...placementDimensions, cylinderHeight: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
            </div>
          </div>
        )}
      </div>

      {/* Obstacle list */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Obstacles ({config.obstacles.length}):
        </label>
        <div style={{ maxHeight: '150px', overflow: 'auto', background: '#1a1a2e', borderRadius: '4px' }}>
          {config.obstacles.length === 0 ? (
            <div style={{ padding: '20px', textAlign: 'center', color: '#666' }}>
              No obstacles. Click "Start Placement Mode" and click in the scene.
            </div>
          ) : (
            config.obstacles.map((obs) => (
              <div
                key={obs.id}
                onClick={() => setSelectedObstacleId(obs.id === selectedObstacleId ? null : obs.id)}
                style={{ padding: '10px 12px', borderBottom: '1px solid #333', cursor: 'pointer', background: selectedObstacleId === obs.id ? '#333' : 'transparent' }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <span style={{ fontWeight: 'bold' }}>{obs.label}</span>
                    <span style={{ marginLeft: '8px', padding: '2px 6px', background: obs.type === 'box' ? '#6b5b95' : '#88b04b', borderRadius: '3px', fontSize: '10px', textTransform: 'uppercase' }}>{obs.type}</span>
                  </div>
                  <div style={{ display: 'flex', gap: '4px' }}>
                    <button onClick={(e) => { e.stopPropagation(); duplicateObstacle(obs); }} style={{ padding: '4px 8px', background: '#555', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '10px' }}>Dup</button>
                    <button onClick={(e) => { e.stopPropagation(); deleteObstacle(obs.id); }} style={{ padding: '4px 8px', background: '#a44', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '10px' }}>Del</button>
                  </div>
                </div>
                <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
                  Pos: [{obs.position.map((v) => v.toFixed(1)).join(', ')}]
                  {obs.type === 'box' && ` | Size: ${obs.width}x${obs.height}x${obs.depth}`}
                  {obs.type === 'cylinder' && ` | R:${obs.radius} H:${obs.cylinderHeight}`}
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Selected obstacle editor */}
      {selectedObstacle && (
        <div style={{ padding: '12px', background: '#1a1a2e', borderRadius: '4px' }}>
          <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>
            Edit: {selectedObstacle.label}
          </h4>

          <input type="text" value={selectedObstacle.label} onChange={(e) => updateObstacle(selectedObstacle.id, { label: e.target.value })} placeholder="Label" style={{ width: '100%', padding: '8px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px', marginBottom: '8px' }} />

          {/* Position */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '8px', marginBottom: '8px' }}>
            <div>
              <label style={{ fontSize: '10px', color: '#666' }}>X:</label>
              <input type="number" step="0.5" value={selectedObstacle.position[0]} onChange={(e) => updateObstacle(selectedObstacle.id, { position: [parseFloat(e.target.value) || 0, selectedObstacle.position[1], selectedObstacle.position[2]] })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
            </div>
            <div>
              <label style={{ fontSize: '10px', color: '#666' }}>Y:</label>
              <input type="number" step="0.5" value={selectedObstacle.position[1]} onChange={(e) => updateObstacle(selectedObstacle.id, { position: [selectedObstacle.position[0], parseFloat(e.target.value) || 0, selectedObstacle.position[2]] })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
            </div>
            <div>
              <label style={{ fontSize: '10px', color: '#666' }}>Z:</label>
              <input type="number" step="0.5" value={selectedObstacle.position[2]} onChange={(e) => updateObstacle(selectedObstacle.id, { position: [selectedObstacle.position[0], selectedObstacle.position[1], parseFloat(e.target.value) || 0] })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
            </div>
          </div>

          {/* Type-specific dimensions */}
          {selectedObstacle.type === 'box' && (
            <>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '8px' }}>
                <div>
                  <label style={{ fontSize: '10px', color: '#666' }}>Width:</label>
                  <input type="number" step="0.5" min="0.1" value={selectedObstacle.width || 1} onChange={(e) => updateObstacle(selectedObstacle.id, { width: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
                </div>
                <div>
                  <label style={{ fontSize: '10px', color: '#666' }}>Height:</label>
                  <input type="number" step="0.5" min="0.1" value={selectedObstacle.height || 1} onChange={(e) => updateObstacle(selectedObstacle.id, { height: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
                </div>
                <div>
                  <label style={{ fontSize: '10px', color: '#666' }}>Depth:</label>
                  <input type="number" step="0.5" min="0.1" value={selectedObstacle.depth || 1} onChange={(e) => updateObstacle(selectedObstacle.id, { depth: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
                </div>
              </div>
              <div style={{ marginTop: '8px' }}>
                <label style={{ fontSize: '10px', color: '#666' }}>Rotation Y:</label>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '4px' }}>
                  <button onClick={() => { const currentDeg = radToDeg(selectedObstacle.rotation[1]); updateObstacle(selectedObstacle.id, { rotation: [selectedObstacle.rotation[0], degToRad(currentDeg - 15), selectedObstacle.rotation[2]] }); }} style={{ padding: '6px 12px', background: '#444', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>-15</button>
                  <span style={{ flex: 1, textAlign: 'center', fontSize: '14px' }}>{Math.round(radToDeg(selectedObstacle.rotation[1]))}</span>
                  <button onClick={() => { const currentDeg = radToDeg(selectedObstacle.rotation[1]); updateObstacle(selectedObstacle.id, { rotation: [selectedObstacle.rotation[0], degToRad(currentDeg + 15), selectedObstacle.rotation[2]] }); }} style={{ padding: '6px 12px', background: '#444', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>+15</button>
                </div>
              </div>
            </>
          )}

          {selectedObstacle.type === 'cylinder' && (
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
              <div>
                <label style={{ fontSize: '10px', color: '#666' }}>Radius:</label>
                <input type="number" step="0.5" min="0.1" value={selectedObstacle.radius || 1} onChange={(e) => updateObstacle(selectedObstacle.id, { radius: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
              </div>
              <div>
                <label style={{ fontSize: '10px', color: '#666' }}>Height:</label>
                <input type="number" step="0.5" min="0.1" value={selectedObstacle.cylinderHeight || 1} onChange={(e) => updateObstacle(selectedObstacle.id, { cylinderHeight: parseFloat(e.target.value) || 1 })} style={{ width: '100%', padding: '6px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px' }} />
              </div>
            </div>
          )}
        </div>
      )}

      {/* Instructions */}
      <div style={{ fontSize: '11px', color: '#666', marginTop: '8px' }}>
        <p style={{ margin: '4px 0' }}>Click "Start Placement Mode" then click in scene to place</p>
        <p style={{ margin: '4px 0' }}>Floor collision mesh is shown as reference</p>
        <p style={{ margin: '4px 0' }}>Use Dup button to quickly copy obstacles</p>
      </div>
    </div>
  );
}
