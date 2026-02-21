import * as THREE from 'three';

// =============== Core Types ===============

export type GateDirection = 'north' | 'south' | 'east' | 'west';
export type GateEdge = GateDirection; // Alias for compatibility
export type GateType = 'Gate' | 'KeyGate' | 'AreaWarp'; // Still used for preview only
export type PreviewModel = 'Gate' | 'AreaWarp';
export type ObstacleType = 'box' | 'cylinder';
export type EditorTab = 'floor' | 'portals' | 'textures' | 'obstacles' | 'svg' | 'export';

// =============== Floor Collision ===============

export interface FloorTriangle {
  id: string;
  vertices: [THREE.Vector3, THREE.Vector3, THREE.Vector3];
  meshName: string;
  textureName: string;
  included: boolean;
  area: number;
}

export interface FloorCollisionConfig {
  yTolerance: number;
  excludedMeshPatterns: string[];
  triangles: Record<string, boolean>; // id -> included status
}

// =============== Portal/Gate Configuration ===============

export interface PortalData {
  id: string;
  direction: GateDirection; // Label (north/south/east/west) AND determines rotation
  position: [number, number, number]; // x, y, z position in world space
  label: string;
  rotationOffset?: number; // Additional rotation in degrees (e.g. 45, -45)
}

export interface SpawnPointData {
  position: [number, number, number];
  direction: GateDirection;
}

// Rotation values for each direction (radians, Y-axis rotation)
export const DIRECTION_ROTATIONS: Record<GateDirection, number> = {
  north: 0,
  south: Math.PI,
  east: -Math.PI / 2,
  west: Math.PI / 2,
};

// Get effective rotation for a portal (base direction + optional offset)
export function getPortalRotation(portal: PortalData): number {
  return DIRECTION_ROTATIONS[portal.direction] + ((portal.rotationOffset || 0) * Math.PI) / 180;
}

// =============== Texture Fixes ===============

export type WrapMode = 'repeat' | 'mirror' | 'clamp';

export interface TextureFix {
  textureFile: string;
  meshNames: string[];
  repeatX: number;
  repeatY: number;
  offsetX: number;
  offsetY: number;
  wrapS?: WrapMode;
  wrapT?: WrapMode;
}

// =============== Collision Obstacles ===============

export interface ObstacleData {
  id: string;
  type: ObstacleType;
  position: [number, number, number];
  rotation: [number, number, number];
  // Box dimensions
  width?: number;
  height?: number;
  depth?: number;
  // Cylinder dimensions
  radius?: number;
  cylinderHeight?: number;
  label: string;
}

// =============== Unified Stage Config ===============

export interface UnifiedStageConfig {
  mapId: string;
  version: number;
  floorCollision: FloorCollisionConfig;
  portals: PortalData[];
  defaultSpawn?: SpawnPointData;
  textureFixes: TextureFix[];
  obstacles: ObstacleData[];
  svgSettings?: SvgSettings;
  lastModified: string;
  exportedAt?: string;
}

// =============== Editor State ===============

export interface FloorEditorState {
  hoveredTriangle: string | null;
  selectedTriangles: Set<string>;
  yTolerance: number;
  meshFilter: string;
}

export interface PortalEditorState {
  selectedPortal: string | null;
  placementMode: boolean;
  placementDirection: GateDirection;
  previewModel: PreviewModel;
}

export interface ObstacleEditorState {
  selectedObstacle: string | null;
  placementType: ObstacleType | null;
}

export interface EditorState {
  activeTab: EditorTab;
  selectedMapId: string;
  selectedArea: string;
  floorState: FloorEditorState;
  portalState: PortalEditorState;
  obstacleState: ObstacleEditorState;
  showFloorMesh: boolean;
  showGrid: boolean;
  zoom: number;
}

// =============== Stage Area Configuration ===============

export interface StageAreaConfig {
  name: string;
  prefix: string;
  folder: string;
  maps: Record<string, string[]>;
}

// =============== Export Options ===============

export interface ExportOptions {
  includeLambert: boolean;
  includeFloorCollision: boolean;
  includeObstacles: boolean;
  includeMarkers: boolean;
  stripSkinning: boolean;
}

export interface SvgOptions {
  width: number;
  height: number;
  padding: number;
  strokeWidth: number;
  floorFill: string;
  outlineColor: string;
  gateColors: Record<GateType, string>;
}

// SVG Tab Settings (saved per-map)
export interface SvgSettings {
  gridSize: number;
  centerX: number;
  centerZ: number;
  svgSize: number;
  padding: number;
}

// =============== Default Values ===============

export const DEFAULT_FLOOR_CONFIG: FloorCollisionConfig = {
  yTolerance: 0.25,
  excludedMeshPatterns: [],
  triangles: {},
};

export const DEFAULT_EXPORT_OPTIONS: ExportOptions = {
  includeLambert: true,
  includeFloorCollision: true,
  includeObstacles: true,
  includeMarkers: true,
  stripSkinning: true,
};

export const DEFAULT_SVG_OPTIONS: SvgOptions = {
  width: 512,
  height: 512,
  padding: 20,
  strokeWidth: 2,
  floorFill: '#2a2a4e',
  outlineColor: '#ffffff',
  gateColors: {
    Gate: '#ff4444',
    KeyGate: '#ffaa00',
    AreaWarp: '#4444ff',
  },
};

export const DEFAULT_SVG_SETTINGS: SvgSettings = {
  gridSize: 40,
  centerX: 0,
  centerZ: 0,
  svgSize: 400,
  padding: 20,
};

export function createDefaultConfig(mapId: string): UnifiedStageConfig {
  return {
    mapId,
    version: 1,
    floorCollision: { ...DEFAULT_FLOOR_CONFIG },
    portals: [],
    textureFixes: [],
    obstacles: [],
    lastModified: new Date().toISOString(),
  };
}
