import { useState, useEffect, useCallback, useMemo, Suspense } from 'react';
import * as THREE from 'three';
import type { EditorTab, FloorTriangle, GateDirection, PreviewModel, PortalData, ObstacleType, ObstacleData } from './types';
import { useStageConfig } from './useStageConfig';
import { getAreaFromMapId, getAllMapsForArea } from './constants';
import StageSelector from './StageSelector';
import StageCanvas from './StageCanvas';
import FloorOverlay from './FloorOverlay';
import PortalOverlay from './PortalOverlay';
import ObstacleOverlay from './ObstacleOverlay';
import TextureAnimator from './TextureAnimator';
import FloorCollisionTab from './tabs/FloorCollisionTab';
import PortalTab from './tabs/PortalTab';
import TextureTab, { type AnimatedTextureInfo } from './tabs/TextureTab';
import ObstacleTab, { type PlacementDimensions, DEFAULT_PLACEMENT_DIMENSIONS } from './tabs/ObstacleTab';
import ExportTab from './tabs/ExportTab';
import SvgTab from './tabs/SvgTab';

// Extract floor triangles from scene
function extractFloorTriangles(
  scene: THREE.Object3D,
  yTolerance: number,
  triangleStates: Record<string, boolean>
): FloorTriangle[] {
  const triangles: FloorTriangle[] = [];
  let triangleId = 0;

  scene.traverse((object) => {
    if (!(object as THREE.Mesh).isMesh) return;

    const mesh = object as THREE.Mesh;
    const geometry = mesh.geometry;
    const positions = geometry.attributes.position;
    const index = geometry.index;

    if (!positions) return;

    const material = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
    let textureName = 'unknown';
    if ((material as any).map?.name) {
      textureName = (material as any).map.name;
    }

    const processTriangle = (i0: number, i1: number, i2: number) => {
      const v0 = new THREE.Vector3(positions.getX(i0), positions.getY(i0), positions.getZ(i0));
      const v1 = new THREE.Vector3(positions.getX(i1), positions.getY(i1), positions.getZ(i1));
      const v2 = new THREE.Vector3(positions.getX(i2), positions.getY(i2), positions.getZ(i2));

      v0.applyMatrix4(mesh.matrixWorld);
      v1.applyMatrix4(mesh.matrixWorld);
      v2.applyMatrix4(mesh.matrixWorld);

      if (
        Math.abs(v0.y) < yTolerance &&
        Math.abs(v1.y) < yTolerance &&
        Math.abs(v2.y) < yTolerance
      ) {
        const id = `tri_${triangleId++}`;
        const edge1 = new THREE.Vector3().subVectors(v1, v0);
        const edge2 = new THREE.Vector3().subVectors(v2, v0);
        const area = new THREE.Vector3().crossVectors(edge1, edge2).length() / 2;

        // Check if included (default true, false only if explicitly excluded)
        const included = triangleStates[id] !== false;

        triangles.push({
          id,
          vertices: [v0.clone(), v1.clone(), v2.clone()],
          meshName: mesh.name,
          textureName,
          included,
          area,
        });
      }
    };

    if (index) {
      for (let i = 0; i < index.count; i += 3) {
        processTriangle(index.getX(i), index.getX(i + 1), index.getX(i + 2));
      }
    } else {
      for (let i = 0; i < positions.count; i += 3) {
        processTriangle(i, i + 1, i + 2);
      }
    }
  });

  return triangles;
}

const TABS: { id: EditorTab; label: string }[] = [
  { id: 'floor', label: 'Floor' },
  { id: 'portals', label: 'Portals' },
  { id: 'textures', label: 'Textures' },
  { id: 'obstacles', label: 'Obstacles' },
  { id: 'svg', label: 'SVG' },
  { id: 'export', label: 'Export' },
];

export default function UnifiedStageEditor() {
  const [activeTab, setActiveTab] = useState<EditorTab>('floor');
  const [selectedMapId, setSelectedMapId] = useState('s01a_ga1');
  const [stageScene, setStageScene] = useState<THREE.Group | null>(null);
  const [showStage, setShowStage] = useState(true);

  // Portal placement state
  const [portalPlacementMode, setPortalPlacementMode] = useState(false);
  const [portalPlacementDirection, setPortalPlacementDirection] = useState<GateDirection>('north');
  const [portalPlacementRotationOffset, setPortalPlacementRotationOffset] = useState(0);
  const [portalPreviewModel, setPortalPreviewModel] = useState<PreviewModel>('Gate');
  const [selectedPortalId, setSelectedPortalId] = useState<string | null>(null);

  // Default spawn placement state
  const [spawnPlacementMode, setSpawnPlacementMode] = useState(false);

  // Obstacle placement state
  const [obstaclePlacementMode, setObstaclePlacementMode] = useState(false);
  const [obstaclePlacementType, setObstaclePlacementType] = useState<ObstacleType>('box');
  const [obstaclePlacementDimensions, setObstaclePlacementDimensions] = useState<PlacementDimensions>(DEFAULT_PLACEMENT_DIMENSIONS);
  const [selectedObstacleId, setSelectedObstacleId] = useState<string | null>(null);
  const [obstaclePlacementLabel, setObstaclePlacementLabel] = useState('Boulder');

  // Animated textures state
  const [animatedTextures, setAnimatedTextures] = useState<AnimatedTextureInfo[]>([]);

  // Derive area from mapId
  const selectedArea = useMemo(() => {
    return getAreaFromMapId(selectedMapId) || 'valley';
  }, [selectedMapId]);

  // Get all maps for navigation
  const allMaps = useMemo(() => getAllMapsForArea(selectedArea), [selectedArea]);
  const currentMapIndex = useMemo(() => allMaps.indexOf(selectedMapId), [allMaps, selectedMapId]);

  // Navigation functions
  const goToPrevMap = useCallback(() => {
    if (currentMapIndex > 0) {
      setSelectedMapId(allMaps[currentMapIndex - 1]);
    }
  }, [allMaps, currentMapIndex]);

  const goToNextMap = useCallback(() => {
    if (currentMapIndex < allMaps.length - 1) {
      setSelectedMapId(allMaps[currentMapIndex + 1]);
    }
  }, [allMaps, currentMapIndex]);

  // Get config for current map
  const { config, updateConfig, undo, redo, canUndo, canRedo } = useStageConfig(selectedMapId);

  // Handle scene ready callback
  const handleSceneReady = useCallback((scene: THREE.Group) => {
    setStageScene(scene);
  }, []);

  // Extract floor triangles for overlay
  const floorTriangles = useMemo(() => {
    if (!stageScene || !config) return [];
    return extractFloorTriangles(
      stageScene,
      config.floorCollision.yTolerance,
      config.floorCollision.triangles
    );
  }, [stageScene, config?.floorCollision.yTolerance, config?.floorCollision.triangles]);

  // Get only included triangles for the overlay
  const includedTriangles = useMemo(() => {
    return floorTriangles.filter((t) => t.included);
  }, [floorTriangles]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
        e.preventDefault();
        if (e.shiftKey) {
          redo();
        } else {
          undo();
        }
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'y') {
        e.preventDefault();
        redo();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [undo, redo]);

  // Handle portal placement
  const handlePlacePortal = useCallback(
    (position: [number, number, number]) => {
      const id = `portal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      const newPortal: PortalData = {
        id,
        direction: portalPlacementDirection,
        position,
        label: portalPlacementDirection, // Default label to direction
        ...(portalPlacementRotationOffset ? { rotationOffset: portalPlacementRotationOffset } : {}),
      };

      updateConfig((prev) => ({
        ...prev,
        portals: [...prev.portals, newPortal],
      }));

      // Select the new portal and exit placement mode
      setSelectedPortalId(id);
      setPortalPlacementMode(false);
    },
    [portalPlacementDirection, portalPlacementRotationOffset, updateConfig]
  );

  // Handle default spawn placement
  const handlePlaceDefaultSpawn = useCallback(
    (position: [number, number, number]) => {
      updateConfig((prev) => ({
        ...prev,
        defaultSpawn: { position, direction: portalPlacementDirection },
      }));
      setSpawnPlacementMode(false);
    },
    [portalPlacementDirection, updateConfig]
  );

  // Mutual exclusion wrappers for placement modes
  const setPortalPlacementModeExclusive = useCallback((mode: boolean) => {
    setPortalPlacementMode(mode);
    if (mode) setSpawnPlacementMode(false);
  }, []);

  const setSpawnPlacementModeExclusive = useCallback((mode: boolean) => {
    setSpawnPlacementMode(mode);
    if (mode) setPortalPlacementMode(false);
  }, []);

  // Handle portal click in canvas
  const handlePortalClick = useCallback((id: string) => {
    setSelectedPortalId(id);
  }, []);

  // Handle portal position update from drag
  const handleUpdatePortalPosition = useCallback(
    (id: string, position: [number, number, number]) => {
      updateConfig((prev) => ({
        ...prev,
        portals: prev.portals.map((p) =>
          p.id === id ? { ...p, position } : p
        ),
      }));
    },
    [updateConfig]
  );

  // Handle obstacle placement
  const handlePlaceObstacle = useCallback(
    (position: [number, number, number]) => {
      const id = `obs_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      // Convert degrees to radians for rotation
      const rotationYRad = (obstaclePlacementDimensions.rotationY * Math.PI) / 180;
      const newObstacle: ObstacleData = {
        id,
        type: obstaclePlacementType,
        position,
        rotation: obstaclePlacementType === 'box' ? [0, rotationYRad, 0] : [0, 0, 0],
        label: obstaclePlacementLabel,
        ...(obstaclePlacementType === 'box'
          ? {
              width: obstaclePlacementDimensions.width,
              height: obstaclePlacementDimensions.height,
              depth: obstaclePlacementDimensions.depth,
            }
          : {
              radius: obstaclePlacementDimensions.radius,
              cylinderHeight: obstaclePlacementDimensions.cylinderHeight,
            }),
      };

      updateConfig((prev) => ({
        ...prev,
        obstacles: [...prev.obstacles, newObstacle],
      }));

      // Select the new obstacle and exit placement mode
      setSelectedObstacleId(id);
      setObstaclePlacementMode(false);
    },
    [obstaclePlacementType, obstaclePlacementLabel, obstaclePlacementDimensions, updateConfig]
  );

  // Handle obstacle click in canvas
  const handleObstacleClick = useCallback((id: string) => {
    setSelectedObstacleId(id);
  }, []);

  // Render the active tab's control panel
  const renderTabPanel = () => {
    if (!config) return null;

    switch (activeTab) {
      case 'floor':
        return (
          <FloorCollisionTab
            config={config}
            updateConfig={updateConfig}
            stageScene={stageScene}
          />
        );
      case 'portals':
        return (
          <PortalTab
            config={config}
            updateConfig={updateConfig}
            placementMode={portalPlacementMode}
            setPlacementMode={setPortalPlacementModeExclusive}
            placementDirection={portalPlacementDirection}
            setPlacementDirection={setPortalPlacementDirection}
            placementRotationOffset={portalPlacementRotationOffset}
            setPlacementRotationOffset={setPortalPlacementRotationOffset}
            previewModel={portalPreviewModel}
            setPreviewModel={setPortalPreviewModel}
            selectedPortalId={selectedPortalId}
            setSelectedPortalId={setSelectedPortalId}
            spawnPlacementMode={spawnPlacementMode}
            setSpawnPlacementMode={setSpawnPlacementModeExclusive}
          />
        );
      case 'textures':
        return (
          <TextureTab
            config={config}
            updateConfig={updateConfig}
            stageScene={stageScene}
            onAnimatedTexturesChange={setAnimatedTextures}
          />
        );
      case 'obstacles':
        return (
          <ObstacleTab
            config={config}
            updateConfig={updateConfig}
            placementMode={obstaclePlacementMode}
            setPlacementMode={setObstaclePlacementMode}
            placementType={obstaclePlacementType}
            setPlacementType={setObstaclePlacementType}
            placementDimensions={obstaclePlacementDimensions}
            setPlacementDimensions={setObstaclePlacementDimensions}
            selectedObstacleId={selectedObstacleId}
            setSelectedObstacleId={setSelectedObstacleId}
            placementLabel={obstaclePlacementLabel}
            setPlacementLabel={setObstaclePlacementLabel}
          />
        );
      case 'svg':
        return (
          <SvgTab
            config={config}
            updateConfig={updateConfig}
            floorTriangles={floorTriangles}
            mapId={selectedMapId}
          />
        );
      case 'export':
        return (
          <ExportTab
            config={config}
            stageScene={stageScene}
            mapId={selectedMapId}
          />
        );
      default:
        return null;
    }
  };

  // Handle triangle click to toggle inclusion
  const handleTriangleClick = useCallback(
    (triangleId: string) => {
      updateConfig((prev) => ({
        ...prev,
        floorCollision: {
          ...prev.floorCollision,
          triangles: {
            ...prev.floorCollision.triangles,
            [triangleId]: prev.floorCollision.triangles[triangleId] === false ? true : false,
          },
        },
      }));
    },
    [updateConfig]
  );

  // Render tab-specific canvas overlays
  const renderCanvasOverlays = () => {
    if (!config) return null;

    switch (activeTab) {
      case 'floor':
        // Show ALL triangles (interactive) - green for included, red for excluded
        return (
          <FloorOverlay
            triangles={floorTriangles}
            yOffset={0.1}
            onTriangleClick={handleTriangleClick}
            interactive
          />
        );
      case 'portals':
        return (
          <PortalOverlay
            portals={config.portals}
            selectedPortalId={selectedPortalId}
            placementMode={portalPlacementMode}
            placementDirection={portalPlacementDirection}
            placementRotationOffset={portalPlacementRotationOffset}
            previewModel={portalPreviewModel}
            onPortalClick={handlePortalClick}
            onPlacePortal={handlePlacePortal}
            onUpdatePortalPosition={handleUpdatePortalPosition}
            defaultSpawn={config.defaultSpawn}
            spawnPlacementMode={spawnPlacementMode}
            onPlaceDefaultSpawn={handlePlaceDefaultSpawn}
          />
        );
      case 'obstacles':
        return (
          <>
            {/* Show floor mesh as reference */}
            <FloorOverlay triangles={includedTriangles} yOffset={0.05} />
            {/* Obstacle placement and existing obstacles */}
            <ObstacleOverlay
              obstacles={config.obstacles}
              selectedObstacleId={selectedObstacleId}
              placementMode={obstaclePlacementMode}
              placementType={obstaclePlacementType}
              placementDimensions={obstaclePlacementDimensions}
              onObstacleClick={handleObstacleClick}
              onPlaceObstacle={handlePlaceObstacle}
            />
          </>
        );
      case 'svg':
        // Show only included triangles (non-interactive preview)
        return <FloorOverlay triangles={includedTriangles} yOffset={0.1} />;
      case 'export':
        // Show only included triangles (non-interactive preview)
        return <FloorOverlay triangles={includedTriangles} yOffset={0.1} />;
      default:
        return null;
    }
  };

  return (
    <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: '#1a1a2e' }}>
      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '12px 16px',
          background: '#252540',
          borderBottom: '1px solid #333',
        }}
      >
        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          <StageSelector
            selectedArea={selectedArea}
            selectedMapId={selectedMapId}
            onAreaChange={() => {}} // Area is derived from mapId
            onMapChange={setSelectedMapId}
          />

          <button
            onClick={goToPrevMap}
            disabled={currentMapIndex <= 0}
            style={{
              padding: '6px 10px',
              background: currentMapIndex > 0 ? '#444' : '#333',
              color: currentMapIndex > 0 ? 'white' : '#666',
              border: 'none',
              borderRadius: '4px',
              cursor: currentMapIndex > 0 ? 'pointer' : 'not-allowed',
              fontSize: '14px',
            }}
            title="Previous map"
          >
            &larr;
          </button>
          <span style={{ fontSize: '11px', color: '#888', minWidth: '50px', textAlign: 'center' }}>
            {currentMapIndex + 1}/{allMaps.length}
          </span>
          <button
            onClick={goToNextMap}
            disabled={currentMapIndex >= allMaps.length - 1}
            style={{
              padding: '6px 10px',
              background: currentMapIndex < allMaps.length - 1 ? '#444' : '#333',
              color: currentMapIndex < allMaps.length - 1 ? 'white' : '#666',
              border: 'none',
              borderRadius: '4px',
              cursor: currentMapIndex < allMaps.length - 1 ? 'pointer' : 'not-allowed',
              fontSize: '14px',
            }}
            title="Next map"
          >
            &rarr;
          </button>
        </div>

        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          <button
            onClick={undo}
            disabled={!canUndo}
            style={{
              padding: '6px 12px',
              background: canUndo ? '#444' : '#333',
              color: canUndo ? 'white' : '#666',
              border: 'none',
              borderRadius: '4px',
              cursor: canUndo ? 'pointer' : 'not-allowed',
            }}
            title="Undo (Ctrl+Z)"
          >
            Undo
          </button>
          <button
            onClick={redo}
            disabled={!canRedo}
            style={{
              padding: '6px 12px',
              background: canRedo ? '#444' : '#333',
              color: canRedo ? 'white' : '#666',
              border: 'none',
              borderRadius: '4px',
              cursor: canRedo ? 'pointer' : 'not-allowed',
            }}
            title="Redo (Ctrl+Y)"
          >
            Redo
          </button>

          <div style={{ width: '1px', height: '20px', background: '#444', margin: '0 4px' }} />

          <button
            onClick={() => setShowStage(!showStage)}
            style={{
              padding: '6px 12px',
              background: showStage ? '#444' : '#4a9eff',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
            }}
            title="Toggle stage visibility (show only floor collision)"
          >
            {showStage ? 'Hide Stage' : 'Show Stage'}
          </button>
        </div>
      </div>

      {/* Tab bar */}
      <div
        style={{
          display: 'flex',
          gap: '2px',
          padding: '8px 16px',
          background: '#1e1e32',
          borderBottom: '1px solid #333',
        }}
      >
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              padding: '8px 20px',
              background: activeTab === tab.id ? '#4a9eff' : 'transparent',
              color: activeTab === tab.id ? 'white' : '#888',
              border: 'none',
              borderRadius: '4px 4px 0 0',
              cursor: 'pointer',
              fontWeight: activeTab === tab.id ? 'bold' : 'normal',
              transition: 'all 0.2s',
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Main content */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Left panel - Tab controls */}
        <div
          style={{
            width: '320px',
            background: '#252540',
            borderRight: '1px solid #333',
            overflow: 'auto',
            padding: '16px',
          }}
        >
          {renderTabPanel()}
        </div>

        {/* Right panel - 3D Canvas */}
        <div style={{ flex: 1 }}>
          <Suspense fallback={<div style={{ color: 'white', padding: 20 }}>Loading stage...</div>}>
            <StageCanvas
              mapId={selectedMapId}
              onSceneReady={handleSceneReady}
              showGrid={true}
              showStage={showStage}
            >
              {renderCanvasOverlays()}
              <TextureAnimator animatedTextures={animatedTextures} />
            </StageCanvas>
          </Suspense>
        </div>
      </div>

      {/* Status bar */}
      <div
        style={{
          padding: '8px 16px',
          background: '#1e1e32',
          borderTop: '1px solid #333',
          display: 'flex',
          justifyContent: 'space-between',
          fontSize: '12px',
          color: '#888',
        }}
      >
        <span>
          Floor triangles: {includedTriangles.length}/{floorTriangles.length} |
          Portals: {config?.portals?.length || 0} |
          Obstacles: {config?.obstacles?.length || 0}
        </span>
        <span>Ctrl+Z = Undo | Ctrl+Y = Redo</span>
      </div>
    </div>
  );
}
