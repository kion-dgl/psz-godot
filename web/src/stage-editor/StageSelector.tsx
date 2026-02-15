import { useMemo } from 'react';
import { STAGE_AREAS, getAllMapsForArea } from './constants';

interface StageSelectorProps {
  selectedArea: string;
  selectedMapId: string;
  onAreaChange: (area: string) => void;
  onMapChange: (mapId: string) => void;
}

export default function StageSelector({
  selectedArea,
  selectedMapId,
  onAreaChange,
  onMapChange,
}: StageSelectorProps) {
  const areas = Object.entries(STAGE_AREAS);

  // Get maps for selected area, grouped by variant
  const mapsByVariant = useMemo(() => {
    const area = STAGE_AREAS[selectedArea];
    if (!area) return {};
    return area.maps;
  }, [selectedArea]);

  // Get all maps for selected area as flat list
  const allMaps = useMemo(() => {
    return getAllMapsForArea(selectedArea);
  }, [selectedArea]);

  // Handle area change
  const handleAreaChange = (newArea: string) => {
    onAreaChange(newArea);
    // Auto-select first map in new area
    const maps = getAllMapsForArea(newArea);
    if (maps.length > 0) {
      onMapChange(maps[0]);
    }
  };

  return (
    <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
      {/* Area selector */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
        <label style={{ fontSize: '11px', color: '#888' }}>Area:</label>
        <select
          value={selectedArea}
          onChange={(e) => handleAreaChange(e.target.value)}
          style={{
            padding: '6px 10px',
            background: '#1a1a2e',
            color: 'white',
            border: '1px solid #444',
            borderRadius: '4px',
            cursor: 'pointer',
            minWidth: '150px',
          }}
        >
          {areas.map(([key, area]) => (
            <option key={key} value={key}>
              {area.name}
            </option>
          ))}
        </select>
      </div>

      {/* Variant selector */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
        <label style={{ fontSize: '11px', color: '#888' }}>Variant:</label>
        <div style={{ display: 'flex', gap: '4px' }}>
          {Object.keys(mapsByVariant).map((variant) => {
            const isActive = selectedMapId.includes(`${STAGE_AREAS[selectedArea]?.prefix}${variant}_`);
            return (
              <button
                key={variant}
                onClick={() => {
                  const maps = mapsByVariant[variant];
                  if (maps && maps.length > 0) {
                    onMapChange(maps[0]);
                  }
                }}
                style={{
                  padding: '6px 12px',
                  background: isActive ? '#4a9eff' : '#333',
                  color: 'white',
                  border: 'none',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  fontWeight: isActive ? 'bold' : 'normal',
                  textTransform: 'uppercase',
                }}
              >
                {variant}
              </button>
            );
          })}
        </div>
      </div>

      {/* Map selector */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
        <label style={{ fontSize: '11px', color: '#888' }}>Map:</label>
        <select
          value={selectedMapId}
          onChange={(e) => onMapChange(e.target.value)}
          style={{
            padding: '6px 10px',
            background: '#1a1a2e',
            color: 'white',
            border: '1px solid #444',
            borderRadius: '4px',
            cursor: 'pointer',
            minWidth: '120px',
          }}
        >
          {allMaps.map((mapId) => {
            // Extract suffix for display (e.g., 's01a_ga1' -> 'ga1')
            const suffix = mapId.split('_')[1] || mapId;
            return (
              <option key={mapId} value={mapId}>
                {suffix}
              </option>
            );
          })}
        </select>
      </div>

      {/* Current map display */}
      <div
        style={{
          padding: '6px 12px',
          background: '#2a2a4e',
          borderRadius: '4px',
          fontSize: '12px',
          fontFamily: 'monospace',
          color: '#4a9eff',
        }}
      >
        {selectedMapId}
      </div>
    </div>
  );
}
