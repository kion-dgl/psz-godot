import { useState, useEffect, useCallback } from 'react';
import * as THREE from 'three';
import type { OfficeLayoutData, PlacementMode } from './types';
import OfficeCanvas from './OfficeCanvas';
import OfficeExportPanel from './OfficeExportPanel';

const STORAGE_KEY = 'office-layout';

const DEFAULT_LAYOUT: OfficeLayoutData = {
  npcPosition: [0, 0, -3],
  npcRotationY: 0,
  npcScale: 0.15,
  roomScale: 0.15,
  doorTrigger: { position: [0, 1, 5], size: [3, 2, 1] },
  spawnPoint: { position: [0, 0, 3], rotationY: Math.PI },
};

function loadLayout(): OfficeLayoutData {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) return { ...DEFAULT_LAYOUT, ...JSON.parse(saved) };
  } catch { /* ignore */ }
  return DEFAULT_LAYOUT;
}

export default function OfficeEditor() {
  const [layout, setLayout] = useState<OfficeLayoutData>(loadLayout);
  const [placementMode, setPlacementMode] = useState<PlacementMode>('none');

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
  }, [layout]);

  const handlePlacePoint = useCallback((point: THREE.Vector3) => {
    const snapped: [number, number, number] = [
      Math.round(point.x * 10) / 10,
      Math.round(point.y * 10) / 10,
      Math.round(point.z * 10) / 10,
    ];

    setLayout((prev) => {
      switch (placementMode) {
        case 'npc':
          return { ...prev, npcPosition: snapped };
        case 'door':
          return { ...prev, doorTrigger: { ...prev.doorTrigger, position: [snapped[0], snapped[1] + prev.doorTrigger.size[1] / 2, snapped[2]] } };
        case 'spawn':
          return { ...prev, spawnPoint: { ...prev.spawnPoint, position: snapped } };
        default:
          return prev;
      }
    });
  }, [placementMode]);

  return (
    <div style={{ display: 'flex', width: '100%', height: '100%' }}>
      <OfficeExportPanel
        layout={layout}
        placementMode={placementMode}
        onLayoutChange={setLayout}
        onPlacementModeChange={setPlacementMode}
      />
      <div style={{ flex: 1 }}>
        <OfficeCanvas
          layout={layout}
          placementMode={placementMode}
          onPlacePoint={handlePlacePoint}
        />
      </div>
    </div>
  );
}
