import { useState, useEffect, useCallback, useMemo, Suspense } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import type { EditorTab, FloorTriangle, GateDirection, PreviewModel, PortalData, ObstacleType, ObstacleData, WaypointData } from './types';
import { useStageConfig } from './useStageConfig';
import { getPortalRotation } from './types';
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
import WaypointTab from './tabs/WaypointTab';
import WaypointOverlay from './WaypointOverlay';
import ManhattanGridOverlay from './ManhattanGridOverlay';
import CoordMarkerOverlay from './CoordMarkerOverlay';
import { useManhattanGrid } from './manhattan/useManhattanGrid';
import QuestObjectOverlay from './QuestObjectOverlay';
import { useQuestObjects } from './useQuestObjects';
import SvgTab from './tabs/SvgTab';
import SceneTab, { computeLighting, PLACED_PRESETS } from './tabs/SceneTab';
import ParticleOverlay, { type ParticleEffect } from './ParticleOverlay';

// Extract floor triangles from scene
function extractFloorTriangles(
  scene: THREE.Object3D,
  yTolerance: number,
  triangleStates: Record<string, boolean>,
  showAllUpward: boolean = false
): FloorTriangle[] {
  const triangles: FloorTriangle[] = [];
  // Two separate ID namespaces so old saved states (which only knew about
  // near-floor triangles) keep mapping to the same physical faces:
  //   tri_N — Nth near-floor triangle in iteration order (existing scheme)
  //   up_N  — Nth above-floor non-wall (upward-facing) triangle
  // Both counters increment in iteration order regardless of whether the
  // triangle is emitted to the output, so the id is stable across the
  // showAllUpward toggle.
  let nearFloorId = 0;
  let upwardId = 0;

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

      const isNearFloor =
        Math.abs(v0.y) < yTolerance &&
        Math.abs(v1.y) < yTolerance &&
        Math.abs(v2.y) < yTolerance;

      const edge1 = new THREE.Vector3().subVectors(v1, v0);
      const edge2 = new THREE.Vector3().subVectors(v2, v0);
      const area = new THREE.Vector3().crossVectors(edge1, edge2).length() / 2;

      let id: string;
      let included: boolean;

      if (isNearFloor) {
        // Near-floor branch: keep the historic `tri_N` numbering and default
        // to included unless explicitly excluded.
        id = `tri_${nearFloorId++}`;
        const saved = triangleStates[id];
        included = saved === undefined ? true : saved;
      } else {
        // Above-floor branch: skip walls via normal direction, then assign
        // a stable `up_N` id for every upward-facing face. Whether the face
        // is emitted depends on the toggle and the saved state.
        const n = new THREE.Vector3().crossVectors(edge1, edge2).normalize();
        if (Math.abs(n.y) <= 0.3) return;
        id = `up_${upwardId++}`;
        const saved = triangleStates[id];
        included = saved === undefined ? false : saved;
        // - showAllUpward on  → emit so the user can click it
        // - showAllUpward off → emit only if the user has opted it in, so
        //   stair selections persist after the toggle is turned back off
        if (!showAllUpward && !included) return;
      }

      triangles.push({
        id,
        vertices: [v0.clone(), v1.clone(), v2.clone()],
        meshName: mesh.name,
        textureName,
        included,
        area,
      });
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

// Point-in-triangle (XZ projection) — used to auto-derive waypoint edges by
// checking the straight segment between two waypoints stays over floor.
function pointInTriXZ(px: number, pz: number, t: FloorTriangle): boolean {
  const [v0, v1, v2] = t.vertices;
  const d = (v1.z - v2.z) * (v0.x - v2.x) + (v2.x - v1.x) * (v0.z - v2.z);
  if (Math.abs(d) < 1e-9) return false;
  const l1 = ((v1.z - v2.z) * (px - v2.x) + (v2.x - v1.x) * (pz - v2.z)) / d;
  const l2 = ((v2.z - v0.z) * (px - v2.x) + (v0.x - v2.x) * (pz - v2.z)) / d;
  const l3 = 1 - l1 - l2;
  const eps = -0.02;
  return l1 >= eps && l2 >= eps && l3 >= eps;
}

function segmentOverFloor(
  a: [number, number, number],
  b: [number, number, number],
  tris: FloorTriangle[]
): boolean {
  if (tris.length === 0) return false;
  const SAMPLES = 14;
  for (let s = 1; s < SAMPLES; s++) {
    const f = s / SAMPLES;
    const px = a[0] + (b[0] - a[0]) * f;
    const pz = a[2] + (b[2] - a[2]) * f;
    if (!tris.some((t) => pointInTriXZ(px, pz, t))) return false;
  }
  return true;
}

const TABS: { id: EditorTab; label: string }[] = [
  { id: 'floor', label: 'Floor' },
  { id: 'portals', label: 'Portals' },
  { id: 'textures', label: 'Textures' },
  { id: 'obstacles', label: 'Obstacles' },
  { id: 'scene', label: 'Scene' },
  { id: 'waypoints', label: 'Waypoints' },
  { id: 'svg', label: 'SVG' },
  { id: 'export', label: 'Export' },
];

export default function UnifiedStageEditor() {
  // Deep-link via URL params: ?stage=...&quest=...&cell=... — the autopilot's
  // FAIL line surfaces the failing stage + cell, and a URL with those
  // pre-filled drops the human directly on the right room with quest object
  // overlays visible. Uses react-router's useSearchParams so it works
  // correctly under HashRouter (params live after the # route).
  const [searchParams, setSearchParams] = useSearchParams();
  const urlStage = searchParams.get('stage') ?? undefined;
  const urlQuest = searchParams.get('quest') ?? undefined;
  const urlCell = searchParams.get('cell') ?? undefined;
  // `?marker=-18.6,-10` or `?marker=x,z;x,z;…` pins one or more magenta
  // posts on the floor. Useful for "go look at where the autopilot got
  // stuck" links. Multiple markers semicolon-separated.
  const urlMarker = searchParams.get('marker') ?? undefined;

  const [activeTab, setActiveTab] = useState<EditorTab>(urlQuest ? 'waypoints' : 'floor');
  const [selectedMapId, setSelectedMapId] = useState(urlStage || 's01a_ga1');
  const [selectedQuest, setSelectedQuest] = useState<string | null>(urlQuest ?? null);
  const [highlightCell, setHighlightCell] = useState<string | null>(urlCell ?? null);
  const questObjects = useQuestObjects(selectedQuest, selectedMapId);

  // Keep URL in sync with state. replace:true so we don't pollute history
  // with one entry per character typed into the cell input. Preserve the
  // `marker` param (it's set externally for "go look here" links and the
  // editor itself doesn't write to it).
  useEffect(() => {
    const next = new URLSearchParams();
    next.set('stage', selectedMapId);
    if (selectedQuest) next.set('quest', selectedQuest);
    if (highlightCell) next.set('cell', highlightCell);
    if (urlMarker) next.set('marker', urlMarker);
    setSearchParams(next, { replace: true });
  }, [selectedMapId, selectedQuest, highlightCell, setSearchParams, urlMarker]);
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

  // Portal rotation preview (shared between PortalTab sidebar and 3D overlay)
  const [portalPreviewRotation, setPortalPreviewRotation] = useState(0);

  // Obstacle placement state
  const [obstaclePlacementMode, setObstaclePlacementMode] = useState(false);
  const [obstaclePlacementType, setObstaclePlacementType] = useState<ObstacleType>('box');
  const [obstaclePlacementDimensions, setObstaclePlacementDimensions] = useState<PlacementDimensions>(DEFAULT_PLACEMENT_DIMENSIONS);
  const [selectedObstacleId, setSelectedObstacleId] = useState<string | null>(null);
  const [obstaclePlacementLabel, setObstaclePlacementLabel] = useState('Boulder');

  // Scene tab state
  const [timeOfDay, setTimeOfDay] = useState(10.0);
  const [particles, setParticles] = useState<ParticleEffect[]>([]);
  const [particlePlacementMode, setParticlePlacementMode] = useState(false);
  const [particlePlacementPreset, setParticlePlacementPreset] = useState('spores');
  const [selectedEffectId, setSelectedEffectId] = useState<string | null>(null);
  const [repositionEffectId, setRepositionEffectId] = useState<string | null>(null);
  const [indoor, setIndoor] = useState(false);

  // Waypoint tab state
  const [waypointPlacementMode, setWaypointPlacementMode] = useState(false);
  const [selectedWaypointId, setSelectedWaypointId] = useState<string | null>(null);

  // Manhattan grid overlay: visualizes what scripts/tools/quest_solver/
  // solve_manhattan.ts would produce. Toggle from the waypoints tab.
  // The hook itself is called below, after `config` is initialized.
  const [showManhattanGrid, setShowManhattanGrid] = useState(false);
  const [manhattanResolution, setManhattanResolution] = useState(0.5);
  const [manhattanClearance, setManhattanClearance] = useState(0.5);
  const [manhattanFuseVisual, setManhattanFuseVisual] = useState(false);
  const [manhattanPathStart, setManhattanPathStart] = useState<{ x: number; z: number } | null>(null);
  const [manhattanPathEnd, setManhattanPathEnd] = useState<{ x: number; z: number } | null>(null);

  // Coordinate markers — independent of the Manhattan overlay. Magenta
  // posts on the floor at specified XZ. Initialized from `?marker=x,z`
  // (or `?marker=x1,z1;x2,z2;…` for multiple) so the user can share /
  // be sent links pointing at specific spots.
  const initialUrlMarkers: { x: number; z: number }[] = urlMarker
    ? urlMarker
        .split(';')
        .map((pair) => pair.split(',').map((s) => parseFloat(s.trim())))
        .filter((p) => p.length === 2 && !isNaN(p[0]) && !isNaN(p[1]))
        .map(([x, z]) => ({ x, z }))
    : [];
  const [markerX, setMarkerX] = useState<string>(initialUrlMarkers[0]?.x.toString() ?? '');
  const [markerZ, setMarkerZ] = useState<string>(initialUrlMarkers[0]?.z.toString() ?? '');
  const [urlMarkers] = useState(initialUrlMarkers); // all url-supplied markers (read-once)
  const markerXNum = parseFloat(markerX);
  const markerZNum = parseFloat(markerZ);
  const markerActive = !isNaN(markerXNum) && !isNaN(markerZNum);

  // Floor extraction: show all upward-facing surfaces (stairs, ramps) so they
  // can be clicked into the floor collision mesh. Default off to keep the
  // viewport uncluttered for stages that don't need it.
  const [showAllUpwardFloor, setShowAllUpwardFloor] = useState(false);

  const lighting = useMemo(() => computeLighting(indoor ? 10.0 : timeOfDay), [indoor, timeOfDay]);

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
  const { config, updateConfig, undo, redo, canUndo, canRedo, reloadFromDisk } = useStageConfig(selectedMapId);

  const manhattan = useManhattanGrid({
    mapId: selectedMapId,
    enabled: showManhattanGrid && activeTab === 'waypoints',
    floorCollisionTriangles: config?.floorCollision?.triangles,
    pathStart: manhattanPathStart,
    pathEnd: manhattanPathEnd,
    resolution: manhattanResolution,
    clearance: manhattanClearance,
    fuseVisualMesh: manhattanFuseVisual,
  });

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
      config.floorCollision.triangles,
      showAllUpwardFloor
    );
  }, [stageScene, config?.floorCollision.yTolerance, config?.floorCollision.triangles, showAllUpwardFloor]);

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

  // ── Waypoints ──────────────────────────────────────────────────
  // Drop a waypoint; placement mode stays on so several can be placed in a row.
  const handlePlaceWaypoint = useCallback((position: [number, number, number]) => {
    const id = `wp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    updateConfig((prev) => ({
      ...prev,
      waypoints: [...(prev.waypoints ?? []), { id, position, kind: 'point' as const }],
    }));
  }, [updateConfig]);

  // Click a node to anchor it, then click others to connect/disconnect (the
  // anchor stays selected so you can fan out several edges).
  const handleWaypointClick = useCallback((id: string) => {
    if (waypointPlacementMode) return;
    if (selectedWaypointId === null) { setSelectedWaypointId(id); return; }
    if (selectedWaypointId === id) { setSelectedWaypointId(null); return; }
    const a = selectedWaypointId;
    const b = id;
    updateConfig((prev) => {
      const e = prev.waypointEdges ?? [];
      const exists = e.some(([x, y]) => (x === a && y === b) || (x === b && y === a));
      return {
        ...prev,
        waypointEdges: exists
          ? e.filter(([x, y]) => !((x === a && y === b) || (x === b && y === a)))
          : [...e, [a, b] as [string, string]],
      };
    });
  }, [waypointPlacementMode, selectedWaypointId, updateConfig]);

  // Seed the graph from already-authored locations: for each gate, a spawn node
  // + a loading-trigger node behind it, joined by one edge. Spawns are the
  // connectable network; a load point is a leaf that only links to the spawn it
  // sits behind. Offsets match the gate markers (spawn 3 units out, trigger 7).
  const handleSeedFromGates = useCallback(() => {
    updateConfig((prev) => {
      const waypoints: WaypointData[] = [...(prev.waypoints ?? [])];
      const edges = [...(prev.waypointEdges ?? [])];
      const near = (p: [number, number, number]) =>
        waypoints.some((w) => Math.hypot(w.position[0] - p[0], w.position[2] - p[2]) < 2);
      const stamp = Date.now();
      prev.portals.forEach((portal, i) => {
        const rot = getPortalRotation(portal);
        const sin = Math.sin(rot);
        const cos = Math.cos(rot);
        const [gx, , gz] = portal.position;
        const spawnPos: [number, number, number] = [gx - sin * 3, 0, gz - cos * 3];
        const loadPos: [number, number, number] = [gx - sin * 7, 0, gz - cos * 7];
        if (near(spawnPos)) return;
        const spawnId = `wp_spawn_${i}_${stamp}`;
        const loadId = `wp_load_${i}_${stamp}`;
        waypoints.push({ id: spawnId, position: spawnPos, kind: 'spawn', label: `spawn ${portal.label}` });
        waypoints.push({ id: loadId, position: loadPos, kind: 'exit', label: `load ${portal.label}` });
        edges.push([spawnId, loadId]);
      });
      if (prev.defaultSpawn && !near(prev.defaultSpawn.position)) {
        waypoints.push({ id: `wp_spawn_default_${stamp}`, position: prev.defaultSpawn.position, kind: 'spawn', label: 'spawn (default)' });
      }
      return { ...prev, waypoints, waypointEdges: edges };
    });
  }, [updateConfig]);

  // Auto-connect any waypoint pair (within range) whose straight segment stays
  // over included floor — the "walk straight A→B" invariant.
  const handleAutoConnect = useCallback(() => {
    const tris = includedTriangles;
    updateConfig((prev) => {
      // Only connect the spawn network (+ generic points). Load/exit nodes stay
      // leaves linked solely to the spawn they were seeded behind.
      const wps = (prev.waypoints ?? []).filter((w) => w.kind !== 'exit' && w.kind !== 'gate');
      const keys = new Set((prev.waypointEdges ?? []).map(([a, b]) => [a, b].sort().join('|')));
      const MAX_DIST = 45;
      for (let i = 0; i < wps.length; i++) {
        for (let j = i + 1; j < wps.length; j++) {
          const a = wps[i];
          const b = wps[j];
          const d = Math.hypot(a.position[0] - b.position[0], a.position[2] - b.position[2]);
          if (d > MAX_DIST) continue;
          if (segmentOverFloor(a.position, b.position, tris)) {
            keys.add([a.id, b.id].sort().join('|'));
          }
        }
      }
      const out: [string, string][] = Array.from(keys).map((k) => k.split('|') as [string, string]);
      return { ...prev, waypointEdges: out };
    });
  }, [includedTriangles, updateConfig]);

  // Handle particle effect placement (new or reposition)
  const handlePlaceEffect = useCallback(
    (position: [number, number, number]) => {
      if (repositionEffectId) {
        // Reposition existing effect
        setParticles(prev => prev.map(p =>
          p.id === repositionEffectId ? { ...p, position } as ParticleEffect : p
        ));
        setSelectedEffectId(repositionEffectId);
        setRepositionEffectId(null);
        setParticlePlacementMode(false);
        return;
      }
      // Create new — inherit properties from the last placed effect of the same preset
      const preset = PLACED_PRESETS[particlePlacementPreset];
      const lastOfPreset = [...particles].reverse().find(
        p => p.category === 'placed' && (p as any).preset === particlePlacementPreset
      );
      if (!lastOfPreset && !preset) return;
      const base = lastOfPreset
        ? { ...lastOfPreset }
        : { ...preset };
      const id = `placed_${particlePlacementPreset}_${Date.now()}`;
      const newEffect = { ...base, id, position } as ParticleEffect;
      setParticles(prev => [...prev, newEffect]);
      setSelectedEffectId(id);
      setParticlePlacementMode(false);
    },
    [particlePlacementPreset, repositionEffectId, particles]
  );

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
            showAllUpward={showAllUpwardFloor}
            setShowAllUpward={setShowAllUpwardFloor}
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
            floorTriangles={floorTriangles}
            previewRotation={portalPreviewRotation}
            setPreviewRotation={setPortalPreviewRotation}
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
      case 'scene':
        return (
          <SceneTab
            timeOfDay={timeOfDay}
            onTimeChange={setTimeOfDay}
            particles={particles}
            onParticlesChange={setParticles}
            placementMode={particlePlacementMode}
            onSetPlacementMode={setParticlePlacementMode}
            placementPreset={particlePlacementPreset}
            onSetPlacementPreset={setParticlePlacementPreset}
            selectedEffectId={selectedEffectId}
            onSelectEffect={setSelectedEffectId}
            mapId={selectedMapId}
            indoor={indoor}
            onIndoorChange={setIndoor}
            repositionEffectId={repositionEffectId}
            onStartReposition={(id) => {
              setRepositionEffectId(id);
              setParticlePlacementMode(true);
            }}
          />
        );
      case 'waypoints':
        return (
          <WaypointTab
            config={config}
            updateConfig={updateConfig}
            placementMode={waypointPlacementMode}
            setPlacementMode={setWaypointPlacementMode}
            selectedId={selectedWaypointId}
            setSelectedId={setSelectedWaypointId}
            onSeedFromGates={handleSeedFromGates}
            onAutoConnect={handleAutoConnect}
            showManhattan={showManhattanGrid}
            setShowManhattan={setShowManhattanGrid}
            manhattanResolution={manhattanResolution}
            setManhattanResolution={setManhattanResolution}
            manhattanClearance={manhattanClearance}
            setManhattanClearance={setManhattanClearance}
            manhattanFuseVisual={manhattanFuseVisual}
            setManhattanFuseVisual={setManhattanFuseVisual}
            markerX={markerX}
            setMarkerX={setMarkerX}
            markerZ={markerZ}
            setMarkerZ={setMarkerZ}
            manhattanInfo={{
              loading: manhattan.loading,
              error: manhattan.error,
              trisFiltered: manhattan.trisFiltered,
              gridSize: manhattan.grid ? `${manhattan.grid.rows}×${manhattan.grid.cols}` : null,
              pathCorners: manhattan.path?.worldCorners.length ?? null,
              usedDiagonal: manhattan.path?.usedDiagonal ?? false,
            }}
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

  // Handle triangle click to toggle inclusion. Flips the *currently rendered*
  // state, not just the saved one — important for above-floor surfaces whose
  // saved state may be undefined while the rendered state is "excluded" via
  // the default rule (isNearFloor=false → excluded). The previous version
  // only checked the saved state, so the very first click on an above-floor
  // triangle wrote `false` (the existing default) and the user saw nothing
  // change.
  const handleTriangleClick = useCallback(
    (triangleId: string, currentIncluded: boolean) => {
      updateConfig((prev) => ({
        ...prev,
        floorCollision: {
          ...prev.floorCollision,
          triangles: {
            ...prev.floorCollision.triangles,
            [triangleId]: !currentIncluded,
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
            previewRotation={portalPreviewRotation}
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
      case 'waypoints':
        return (
          <>
            {/* Floor + read-only gates/triggers + obstacles as placement reference */}
            <FloorOverlay triangles={includedTriangles} yOffset={0.05} />
            <PortalOverlay
              portals={config.portals}
              selectedPortalId={null}
              placementMode={false}
              placementDirection={portalPlacementDirection}
              placementRotationOffset={0}
              previewModel={portalPreviewModel}
              onPortalClick={() => {}}
              onPlacePortal={() => {}}
              defaultSpawn={config.defaultSpawn}
            />
            <ObstacleOverlay
              obstacles={config.obstacles}
              selectedObstacleId={null}
              placementMode={false}
              placementType={'box'}
              placementDimensions={obstaclePlacementDimensions}
              onObstacleClick={() => {}}
              onPlaceObstacle={() => {}}
            />
            <WaypointOverlay
              waypoints={config.waypoints ?? []}
              edges={config.waypointEdges ?? []}
              selectedId={selectedWaypointId}
              placementMode={waypointPlacementMode}
              onPlace={handlePlaceWaypoint}
              onWaypointClick={handleWaypointClick}
            />
            <QuestObjectOverlay markers={questObjects} highlightCell={highlightCell} />
            {showManhattanGrid && manhattan.grid && (
              <ManhattanGridOverlay grid={manhattan.grid} path={manhattan.path} />
            )}
            {markerActive && <CoordMarkerOverlay x={markerXNum} z={markerZNum} />}
            {/* URL-supplied markers stay rendered alongside the editable one
                so the user can see the original "go look here" pin and the
                spot they're currently typing at the same time. */}
            {urlMarkers
              .filter((m, i) => !(i === 0 && markerActive && m.x === markerXNum && m.z === markerZNum))
              .map((m, i) => (
                <CoordMarkerOverlay key={`url-${i}`} x={m.x} z={m.z} />
              ))}
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

          {/* Quest context — overlays switches/fences/key drops/NPCs on the floor
              so the user knows where to drop waypoints. URL param ?quest=...&cell=...
              auto-fills these. */}
          <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginLeft: 6, paddingLeft: 10, borderLeft: '1px solid #444' }}>
            <label style={{ fontSize: 12, color: '#9ad6ff' }}>Quest:</label>
            <select
              value={selectedQuest ?? ''}
              onChange={(e) => setSelectedQuest(e.target.value || null)}
              style={{ padding: '5px 6px', background: '#1a1a2e', color: '#e6edf3', border: '1px solid #444', borderRadius: 3, fontSize: 12 }}
            >
              <option value="">— none —</option>
              <option value="search_and_rescue">Search and Rescue</option>
            </select>
            {questObjects.length > 0 && (
              <input
                type="text"
                placeholder="cell e.g. 2,2"
                value={highlightCell ?? ''}
                onChange={(e) => setHighlightCell(e.target.value || null)}
                style={{ width: 90, padding: '5px 6px', background: '#1a1a2e', color: '#e6edf3', border: '1px solid #444', borderRadius: 3, fontSize: 12, fontFamily: 'monospace' }}
                title="Highlight a specific cell's objects (dims others)"
              />
            )}
            {selectedQuest && (
              <span style={{ fontSize: 11, color: '#7a8b94' }}>{questObjects.length} objs</span>
            )}
          </div>

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

          <button
            onClick={() => {
              if (confirm(`Discard local edits for ${selectedMapId} and reload from committed JSON?`)) {
                reloadFromDisk();
              }
            }}
            style={{
              padding: '6px 12px',
              background: '#665',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
            }}
            title="Refetch this stage's config from data/stage_configs/unified-stage-configs.json, discarding local edits."
          >
            Reload from Disk
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
              lighting={activeTab === 'scene' ? lighting : null}
            >
              {renderCanvasOverlays()}
              <TextureAnimator animatedTextures={animatedTextures} />
              {activeTab === 'scene' && (
                <ParticleOverlay
                  effects={particles}
                  placementMode={particlePlacementMode}
                  placementPreset={particlePlacementPreset}
                  placementColor={PLACED_PRESETS[particlePlacementPreset]?.color || [0.2, 1.0, 0.3]}
                  selectedEffectId={selectedEffectId}
                  onPlaceEffect={handlePlaceEffect}
                  onSelectEffect={setSelectedEffectId}
                />
              )}
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
