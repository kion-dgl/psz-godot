import { useState, useEffect, useCallback } from 'react';
import * as THREE from 'three';
import type { OfficeLayoutData, PlacementMode } from './types';
import OfficeCanvas from './OfficeCanvas';
import OfficeExportPanel from './OfficeExportPanel';

const STORAGE_KEY = 'office-layout';

const DEFAULT_LAYOUT: OfficeLayoutData = {
  npcPosition: [0, 0, -5.6],
  npcRotationY: 0,
  npcScale: 0.09,
  roomScale: 0.16,
  // Aligned to the entrance columns of the redesigned room (#356): the
  // loading trigger sits at the column threshold (z 6.5), spawn just inside
  // (z 4.4). Values dialed in via the editor.
  doorTrigger: { position: [0, 1, 6.5], size: [8.1, 2, 1.2] },
  spawnPoint: { position: [0, 0, 4.4], rotationY: Math.PI },
  npcPositions: {
    pos_1: { position: [-2.8, 0, -2.4], rotationY: 0 },
    pos_2: { position: [-3.9, 0, -1.5], rotationY: -0.401 },
  },
};

function loadLayout(): OfficeLayoutData {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved);
      return {
        ...DEFAULT_LAYOUT,
        ...parsed,
        npcPositions: { ...DEFAULT_LAYOUT.npcPositions, ...parsed.npcPositions },
      };
    }
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
        case 'pos_1':
        case 'pos_2':
          return { ...prev, npcPositions: { ...prev.npcPositions, [placementMode]: { ...prev.npcPositions[placementMode], position: snapped } } };
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
