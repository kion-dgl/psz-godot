import * as THREE from 'three';

// =============== Core Types ===============

export type GateDirection = 'north' | 'south' | 'east' | 'west';
export type PreviewModel = 'Gate' | 'AreaWarp';
export type ObstacleType = 'box' | 'cylinder';
export type EditorTab = 'floor' | 'portals' | 'textures' | 'obstacles' | 'scene' | 'waypoints' | 'svg' | 'export';

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
  direction: GateDirection; // Structural direction — determines rotation mapping (do NOT change for visual fixes)
  position: [number, number, number]; // x, y, z position in world space
  label: string;
  compass_label?: string; // Visual compass label (N/S/E/W) — fixed, does not rotate with cell
  rotationOffset?: number; // Additional rotation in degrees (e.g. 45, -45)
}

export interface SpawnPointData {
  position: [number, number, number];
  direction: GateDirection;
}

// Portal rotation math lives in ./directions (shared with quest-io).
export { DIRECTION_ROTATIONS, getPortalRotation } from './directions';

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

// =============== Navigation Waypoints ===============
// A visibility graph the autopilot walks: nodes are floor positions, edges mean
// "you can walk straight from A to B without snagging geometry". Locations of
// interest (gates, spawn, NPCs, exits) are just waypoints tagged with a `kind`.

export type WaypointKind = 'point' | 'gate' | 'spawn' | 'npc' | 'exit' | 'switch' | 'key_drop' | 'telepipe' | 'via';

export interface WaypointData {
  id: string;
  position: [number, number, number];
  label?: string;
  kind?: WaypointKind;
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
  waypoints?: WaypointData[];
  waypointEdges?: [string, string][]; // undirected edges by waypoint id
  svgSettings?: SvgSettings;
  lastModified: string;
  exportedAt?: string;
}

// =============== Stage Area Configuration ===============

export interface StageAreaConfig {
  name: string;
  prefix: string;
  folder: string;
  maps: Record<string, string[]>;
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
