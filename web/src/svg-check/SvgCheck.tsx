import { useState, useEffect, useCallback, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import type { UnifiedStageConfig } from '../stage-editor/types';
import { STAGE_AREAS, getStageSubfolder } from '../stage-editor/constants';
import { assetUrl } from '../utils/assets';
import { extractFloorTriangles, applyTriangleFilters, generateSvgMinimap } from '../shared/svg-minimap';

// --- Types ---

interface StageResult {
  mapId: string;
  svgs: Record<number, string>; // rotation -> svg string
  error?: string;
  loading?: boolean;
}

type AreaGroup = { area: string; label: string; stages: string[] };

// --- Helpers ---

const loader = new GLTFLoader();

function loadGLB(url: string): Promise<THREE.Group> {
  return new Promise((resolve, reject) => {
    loader.load(url, (gltf) => resolve(gltf.scene), undefined, reject);
  });
}

function getAreaFolder(mapId: string): string {
  for (const [, areaConfig] of Object.entries(STAGE_AREAS)) {
    if (mapId.startsWith(areaConfig.prefix)) {
      return getStageSubfolder(mapId, areaConfig.folder);
    }
  }
  return 'unknown';
}

function getGlbUrl(mapId: string): string {
  const folder = getAreaFolder(mapId);
  return assetUrl(`assets/stages/${folder}/${mapId}/lndmd/${mapId}_m.glb`);
}

// --- Main component ---

export default function SvgCheck() {
  const [allConfigs, setAllConfigs] = useState<Record<string, UnifiedStageConfig>>({});
  const [areaGroups, setAreaGroups] = useState<AreaGroup[]>([]);
  const [selectedArea, setSelectedArea] = useState<string>('');
  const [results, setResults] = useState<Record<string, StageResult>>({});
  const [loadingArea, setLoadingArea] = useState(false);
  const abortRef = useRef(false);

  // Load configs
  useEffect(() => {
    fetch(assetUrl('data/stage_configs/unified-stage-configs.json'))
      .then((r) => r.json())
      .then((configs: Record<string, UnifiedStageConfig>) => {
        setAllConfigs(configs);

        // Group stages by area folder, only those with portals
        const groups: Record<string, { label: string; stages: string[] }> = {};
        for (const [mapId, config] of Object.entries(configs)) {
          if (!config.portals || config.portals.length === 0) continue;
          const folder = getAreaFolder(mapId);
          if (!groups[folder]) groups[folder] = { label: folder, stages: [] };
          groups[folder].stages.push(mapId);
        }
        for (const g of Object.values(groups)) g.stages.sort();
        const sorted = Object.entries(groups)
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([area, g]) => ({ area, ...g }));
        setAreaGroups(sorted);
        if (sorted.length > 0) setSelectedArea(sorted[0].area);
      });
  }, []);

  // Generate SVGs for a single stage
  const generateForStage = useCallback(
    async (mapId: string) => {
      const config = allConfigs[mapId];
      if (!config) return;

      setResults((prev) => ({
        ...prev,
        [mapId]: { mapId, svgs: {}, loading: true },
      }));

      try {
        const scene = await loadGLB(getGlbUrl(mapId));
        const yTol = config.floorCollision?.yTolerance ?? 0.25;
        let triangles = extractFloorTriangles(scene, yTol);
        triangles = applyTriangleFilters(triangles, config);

        const svgs: Record<number, string> = {};
        for (const rot of [0, 90, 180, 270]) {
          svgs[rot] = generateSvgMinimap(triangles, config, rot);
        }

        // Dispose
        scene.traverse((obj) => {
          if ((obj as THREE.Mesh).isMesh) {
            (obj as THREE.Mesh).geometry?.dispose();
            const mat = (obj as THREE.Mesh).material;
            if (Array.isArray(mat)) mat.forEach((m) => m.dispose());
            else (mat as THREE.Material)?.dispose();
          }
        });

        setResults((prev) => ({
          ...prev,
          [mapId]: { mapId, svgs },
        }));
      } catch (err: any) {
        setResults((prev) => ({
          ...prev,
          [mapId]: { mapId, svgs: {}, error: err.message },
        }));
      }
    },
    [allConfigs]
  );

  // Load all stages in selected area
  const loadArea = useCallback(async () => {
    const group = areaGroups.find((g) => g.area === selectedArea);
    if (!group) return;
    setLoadingArea(true);
    abortRef.current = false;

    for (const mapId of group.stages) {
      if (abortRef.current) break;
      await generateForStage(mapId);
    }
    setLoadingArea(false);
  }, [selectedArea, areaGroups, generateForStage]);

  const stopLoading = useCallback(() => {
    abortRef.current = true;
  }, []);

  const currentGroup = areaGroups.find((g) => g.area === selectedArea);
  const currentStages = currentGroup?.stages ?? [];

  // Count loaded
  const loadedCount = currentStages.filter((id) => results[id] && !results[id].loading).length;

  return (
    <div style={{ height: '100%', overflow: 'auto', background: '#111', padding: 20 }}>
      <h1 style={{ margin: '0 0 12px', fontSize: 18, color: '#88bbff' }}>SVG Minimap Check (Live)</h1>

      {/* Area tabs */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 12 }}>
        {areaGroups.map((g) => (
          <button
            key={g.area}
            onClick={() => setSelectedArea(g.area)}
            style={{
              padding: '6px 12px',
              background: g.area === selectedArea ? '#335' : '#222',
              border: `1px solid ${g.area === selectedArea ? '#66aaff' : '#444'}`,
              color: g.area === selectedArea ? '#88bbff' : '#aaa',
              cursor: 'pointer',
              fontFamily: 'monospace',
              fontSize: 13,
              borderRadius: 4,
            }}
          >
            {g.area} ({g.stages.length})
          </button>
        ))}
      </div>

      {/* Controls */}
      <div style={{ display: 'flex', gap: 12, alignItems: 'center', marginBottom: 16 }}>
        <button
          onClick={loadArea}
          disabled={loadingArea || currentStages.length === 0}
          style={{
            padding: '8px 16px',
            background: loadingArea ? '#333' : '#335',
            color: '#88bbff',
            border: '1px solid #557',
            cursor: loadingArea ? 'not-allowed' : 'pointer',
            fontFamily: 'monospace',
            fontSize: 14,
            borderRadius: 4,
          }}
        >
          {loadingArea ? 'Loading...' : 'Load All'}
        </button>
        {loadingArea && (
          <button
            onClick={stopLoading}
            style={{
              padding: '8px 16px',
              background: '#533',
              color: '#ffaaaa',
              border: '1px solid #755',
              cursor: 'pointer',
              fontFamily: 'monospace',
              fontSize: 14,
              borderRadius: 4,
            }}
          >
            Stop
          </button>
        )}
        <span style={{ color: '#888', fontSize: 13 }}>
          {loadedCount} / {currentStages.length} loaded
        </span>
      </div>

      {/* Stage cards */}
      {currentStages.map((mapId) => {
        const result = results[mapId];
        const config = allConfigs[mapId];
        const dirs = config?.portals?.map((p) => p.direction[0].toUpperCase()).join('+') ?? '';

        return (
          <div key={mapId} style={{ marginBottom: 20 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 6 }}>
              <h3 style={{ margin: 0, fontSize: 14, color: '#aac' }}>
                {mapId}
                {dirs && <span style={{ color: '#666', fontWeight: 'normal' }}> ({dirs})</span>}
              </h3>
              {!result && !loadingArea && (
                <button
                  onClick={() => generateForStage(mapId)}
                  style={{
                    padding: '3px 10px',
                    background: '#223',
                    color: '#88bbff',
                    border: '1px solid #446',
                    cursor: 'pointer',
                    fontFamily: 'monospace',
                    fontSize: 12,
                    borderRadius: 3,
                  }}
                >
                  Load
                </button>
              )}
              {result?.loading && <span style={{ color: '#886', fontSize: 12 }}>loading...</span>}
              {result?.error && <span style={{ color: '#c66', fontSize: 12 }}>Error: {result.error}</span>}
            </div>

            {result && !result.loading && !result.error && (
              <div style={{ display: 'flex', gap: 8 }}>
                {[0, 90, 180, 270].map((rot) => (
                  <div key={rot} style={{ textAlign: 'center' }}>
                    <div
                      style={{ width: 220, height: 220, border: '1px solid #333' }}
                      dangerouslySetInnerHTML={{ __html: result.svgs[rot] ?? '' }}
                    />
                    <div style={{ marginTop: 4, fontSize: 12, color: '#888' }}>r{rot}</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
