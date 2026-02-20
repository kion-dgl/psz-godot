import type { UnifiedStageConfig, GateDirection, PreviewModel } from '../types';
import { DIRECTION_ROTATIONS } from '../types';

interface PortalTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  placementMode: boolean;
  setPlacementMode: (mode: boolean) => void;
  placementDirection: GateDirection;
  setPlacementDirection: (dir: GateDirection) => void;
  placementRotationOffset: number;
  setPlacementRotationOffset: (offset: number) => void;
  previewModel: PreviewModel;
  setPreviewModel: (model: PreviewModel) => void;
  selectedPortalId: string | null;
  setSelectedPortalId: (id: string | null) => void;
  spawnPlacementMode: boolean;
  setSpawnPlacementMode: (mode: boolean) => void;
}

const DIRECTIONS: GateDirection[] = ['north', 'south', 'east', 'west'];
const PREVIEW_MODELS: PreviewModel[] = ['Gate', 'AreaWarp'];

export default function PortalTab({
  config,
  updateConfig,
  placementMode,
  setPlacementMode,
  placementDirection,
  setPlacementDirection,
  placementRotationOffset,
  setPlacementRotationOffset,
  previewModel,
  setPreviewModel,
  selectedPortalId,
  setSelectedPortalId,
  spawnPlacementMode,
  setSpawnPlacementMode,
}: PortalTabProps) {
  // Get selected portal
  const selectedPortal = config.portals.find((p) => p.id === selectedPortalId);

  // Delete portal
  const deletePortal = (id: string) => {
    updateConfig((prev) => ({
      ...prev,
      portals: prev.portals.filter((p) => p.id !== id),
    }));
    if (selectedPortalId === id) {
      setSelectedPortalId(null);
    }
  };

  // Update portal label
  const updatePortalLabel = (id: string, label: string) => {
    updateConfig((prev) => ({
      ...prev,
      portals: prev.portals.map((p) =>
        p.id === id ? { ...p, label } : p
      ),
    }));
  };

  // Update portal direction
  const updatePortalDirection = (id: string, direction: GateDirection) => {
    updateConfig((prev) => ({
      ...prev,
      portals: prev.portals.map((p) =>
        p.id === id ? { ...p, direction } : p
      ),
    }));
  };

  // Update portal rotation offset
  const updatePortalRotationOffset = (id: string, offset: number) => {
    updateConfig((prev) => ({
      ...prev,
      portals: prev.portals.map((p) =>
        p.id === id ? { ...p, rotationOffset: offset || undefined } : p
      ),
    }));
  };

  // Update portal position
  const updatePortalPosition = (id: string, axis: 'x' | 'z', value: number) => {
    updateConfig((prev) => ({
      ...prev,
      portals: prev.portals.map((p) => {
        if (p.id !== id) return p;
        const newPos: [number, number, number] = [...p.position];
        if (axis === 'x') newPos[0] = value;
        if (axis === 'z') newPos[2] = value;
        return { ...p, position: newPos };
      }),
    }));
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>
        Portal Placement
      </h3>

      {/* Placement mode toggle */}
      <div>
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
          {placementMode ? 'Click in scene to place portal' : 'Start Placement Mode'}
        </button>
      </div>

      {/* Direction selector */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Direction (sets label & rotation):
        </label>
        <div style={{ display: 'flex', gap: '4px' }}>
          {DIRECTIONS.map((dir) => (
            <button
              key={dir}
              onClick={() => setPlacementDirection(dir)}
              style={{
                flex: 1,
                padding: '10px 0',
                background: placementDirection === dir ? '#4a9eff' : '#333',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                textTransform: 'uppercase',
                fontSize: '12px',
                fontWeight: placementDirection === dir ? 'bold' : 'normal',
              }}
            >
              {dir.charAt(0)}
            </button>
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '8px' }}>
          <label style={{ fontSize: '11px', color: '#666', whiteSpace: 'nowrap' }}>Offset:</label>
          <div style={{ display: 'flex', gap: '4px', flex: 1 }}>
            {[-45, 0, 45].map((offset) => (
              <button
                key={offset}
                onClick={() => setPlacementRotationOffset(offset)}
                style={{
                  flex: 1,
                  padding: '6px 0',
                  background: placementRotationOffset === offset ? '#4a9eff' : '#333',
                  color: 'white',
                  border: 'none',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: placementRotationOffset === offset ? 'bold' : 'normal',
                }}
              >
                {offset === 0 ? '0' : `${offset > 0 ? '+' : ''}${offset}`}
              </button>
            ))}
          </div>
        </div>
        <div style={{ fontSize: '10px', color: '#666', marginTop: '4px', textAlign: 'center' }}>
          Rotation: {((DIRECTION_ROTATIONS[placementDirection] * 180) / Math.PI + placementRotationOffset).toFixed(0)}
        </div>
      </div>

      {/* Preview model selector */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Preview Model:
        </label>
        <div style={{ display: 'flex', gap: '8px' }}>
          {PREVIEW_MODELS.map((model) => (
            <button
              key={model}
              onClick={() => setPreviewModel(model)}
              style={{
                flex: 1,
                padding: '10px',
                background: previewModel === model ? '#4a9eff' : '#333',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '12px',
              }}
            >
              {model}
            </button>
          ))}
        </div>
        <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
          Note: Gate type is determined at runtime. This is just for preview.
        </div>
      </div>

      {/* Portal list */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Portals ({config.portals.length}):
        </label>
        <div
          style={{
            maxHeight: '200px',
            overflow: 'auto',
            background: '#1a1a2e',
            borderRadius: '4px',
          }}
        >
          {config.portals.length === 0 ? (
            <div style={{ padding: '20px', textAlign: 'center', color: '#666' }}>
              No portals placed yet. Click "Start Placement Mode" and click in the scene.
            </div>
          ) : (
            config.portals.map((portal) => (
              <div
                key={portal.id}
                onClick={() => setSelectedPortalId(portal.id === selectedPortalId ? null : portal.id)}
                style={{
                  padding: '10px 12px',
                  borderBottom: '1px solid #333',
                  cursor: 'pointer',
                  background: selectedPortalId === portal.id ? '#333' : 'transparent',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <span style={{ fontWeight: 'bold', textTransform: 'capitalize' }}>
                      {portal.label || portal.direction}
                    </span>
                    <span style={{ marginLeft: '8px', fontSize: '11px', color: '#888' }}>
                      {portal.direction.toUpperCase()}{portal.rotationOffset ? ` ${portal.rotationOffset > 0 ? '+' : ''}${portal.rotationOffset}` : ''}
                    </span>
                  </div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      deletePortal(portal.id);
                    }}
                    style={{
                      padding: '4px 8px',
                      background: '#a44',
                      color: 'white',
                      border: 'none',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      fontSize: '11px',
                    }}
                  >
                    Delete
                  </button>
                </div>
                <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
                  Position: [{portal.position.map((v) => v.toFixed(1)).join(', ')}]
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Selected portal editor */}
      {selectedPortal && (
        <div
          style={{
            padding: '12px',
            background: '#1a1a2e',
            borderRadius: '4px',
          }}
        >
          <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>
            Edit Portal
          </h4>

          {/* Label */}
          <div style={{ marginBottom: '12px' }}>
            <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
              Label:
            </label>
            <input
              type="text"
              value={selectedPortal.label}
              onChange={(e) => updatePortalLabel(selectedPortal.id, e.target.value)}
              placeholder="Portal label"
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

          {/* Direction */}
          <div style={{ marginBottom: '12px' }}>
            <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
              Direction:
            </label>
            <div style={{ display: 'flex', gap: '4px' }}>
              {DIRECTIONS.map((dir) => (
                <button
                  key={dir}
                  onClick={() => updatePortalDirection(selectedPortal.id, dir)}
                  style={{
                    flex: 1,
                    padding: '6px',
                    background: selectedPortal.direction === dir ? '#4a9eff' : '#333',
                    color: 'white',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    textTransform: 'uppercase',
                    fontSize: '11px',
                  }}
                >
                  {dir.charAt(0)}
                </button>
              ))}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '6px' }}>
              <label style={{ fontSize: '10px', color: '#666', whiteSpace: 'nowrap' }}>Offset:</label>
              <div style={{ display: 'flex', gap: '3px', flex: 1 }}>
                {[-45, 0, 45].map((offset) => (
                  <button
                    key={offset}
                    onClick={() => updatePortalRotationOffset(selectedPortal.id, offset)}
                    style={{
                      flex: 1,
                      padding: '5px 0',
                      background: (selectedPortal.rotationOffset || 0) === offset ? '#4a9eff' : '#333',
                      color: 'white',
                      border: 'none',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      fontSize: '10px',
                    }}
                  >
                    {offset === 0 ? '0' : `${offset > 0 ? '+' : ''}${offset}`}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Position X */}
          <div style={{ display: 'flex', gap: '8px' }}>
            <div style={{ flex: 1 }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
                X Position:
              </label>
              <input
                type="number"
                step="0.1"
                value={selectedPortal.position[0]}
                onChange={(e) => updatePortalPosition(selectedPortal.id, 'x', parseFloat(e.target.value) || 0)}
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
            <div style={{ flex: 1 }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
                Z Position:
              </label>
              <input
                type="number"
                step="0.1"
                value={selectedPortal.position[2]}
                onChange={(e) => updatePortalPosition(selectedPortal.id, 'z', parseFloat(e.target.value) || 0)}
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
          </div>
        </div>
      )}

      {/* Instructions */}
      <div style={{ fontSize: '11px', color: '#666', marginTop: '8px' }}>
        <p style={{ margin: '4px 0' }}>Select a Direction (N/S/E/W) and optional Offset to set the portal rotation</p>
        <p style={{ margin: '4px 0' }}>Click Start Placement Mode to enable click-to-place</p>
        <p style={{ margin: '4px 0' }}>Click in the scene where you want to place the portal</p>
        <p style={{ margin: '4px 0' }}>Click an existing portal to select and adjust its position</p>
      </div>

      {/* Default Spawn Point */}
      <h3 style={{ margin: '16px 0 0 0', borderBottom: '1px solid #444', paddingBottom: '8px' }}>
        Default Spawn Point
      </h3>

      <div style={{ fontSize: '11px', color: '#666', marginBottom: '8px' }}>
        For boss rooms and areas without gate portals. Exported as <code>spawn_default</code>.
      </div>

      <div>
        <button
          onClick={() => {
            const next = !spawnPlacementMode;
            setSpawnPlacementMode(next);
            if (next) setPlacementMode(false);
          }}
          style={{
            width: '100%',
            padding: '12px',
            background: spawnPlacementMode ? '#ccaa00' : '#333',
            color: spawnPlacementMode ? 'black' : 'white',
            border: spawnPlacementMode ? '2px solid #ffdd00' : '2px solid transparent',
            borderRadius: '4px',
            cursor: 'pointer',
            fontWeight: 'bold',
            fontSize: '14px',
          }}
        >
          {spawnPlacementMode ? 'Click in scene to place spawn' : 'Place Default Spawn'}
        </button>
      </div>

      {config.defaultSpawn ? (
        <div
          style={{
            padding: '12px',
            background: '#1a1a2e',
            borderRadius: '4px',
          }}
        >
          <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>
            Edit Default Spawn
          </h4>

          {/* Direction */}
          <div style={{ marginBottom: '12px' }}>
            <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
              Direction:
            </label>
            <div style={{ display: 'flex', gap: '4px' }}>
              {DIRECTIONS.map((dir) => (
                <button
                  key={dir}
                  onClick={() =>
                    updateConfig((prev) => ({
                      ...prev,
                      defaultSpawn: { ...prev.defaultSpawn!, direction: dir },
                    }))
                  }
                  style={{
                    flex: 1,
                    padding: '6px',
                    background: config.defaultSpawn!.direction === dir ? '#ccaa00' : '#333',
                    color: config.defaultSpawn!.direction === dir ? 'black' : 'white',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    textTransform: 'uppercase',
                    fontSize: '11px',
                  }}
                >
                  {dir.charAt(0)}
                </button>
              ))}
            </div>
            <button
              onClick={() =>
                updateConfig((prev) => {
                  const flip: Record<GateDirection, GateDirection> = {
                    north: 'south',
                    south: 'north',
                    east: 'west',
                    west: 'east',
                  };
                  return {
                    ...prev,
                    defaultSpawn: {
                      ...prev.defaultSpawn!,
                      direction: flip[prev.defaultSpawn!.direction],
                    },
                  };
                })
              }
              style={{
                width: '100%',
                marginTop: '4px',
                padding: '6px',
                background: '#444',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '11px',
              }}
            >
              Rotate 180
            </button>
          </div>

          {/* Position X/Z */}
          <div style={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
            <div style={{ flex: 1 }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
                X Position:
              </label>
              <input
                type="number"
                step="0.1"
                value={config.defaultSpawn.position[0]}
                onChange={(e) =>
                  updateConfig((prev) => {
                    const pos: [number, number, number] = [...prev.defaultSpawn!.position];
                    pos[0] = parseFloat(e.target.value) || 0;
                    return { ...prev, defaultSpawn: { ...prev.defaultSpawn!, position: pos } };
                  })
                }
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
            <div style={{ flex: 1 }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '11px', color: '#666' }}>
                Z Position:
              </label>
              <input
                type="number"
                step="0.1"
                value={config.defaultSpawn.position[2]}
                onChange={(e) =>
                  updateConfig((prev) => {
                    const pos: [number, number, number] = [...prev.defaultSpawn!.position];
                    pos[2] = parseFloat(e.target.value) || 0;
                    return { ...prev, defaultSpawn: { ...prev.defaultSpawn!, position: pos } };
                  })
                }
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
          </div>

          <button
            onClick={() =>
              updateConfig((prev) => {
                const { defaultSpawn: _, ...rest } = prev;
                return rest as UnifiedStageConfig;
              })
            }
            style={{
              width: '100%',
              padding: '8px',
              background: '#a44',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '12px',
            }}
          >
            Clear Default Spawn
          </button>
        </div>
      ) : (
        <div style={{ fontSize: '11px', color: '#666', fontStyle: 'italic' }}>
          No default spawn set.
        </div>
      )}
    </div>
  );
}
