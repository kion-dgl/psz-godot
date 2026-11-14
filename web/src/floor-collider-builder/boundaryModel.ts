import * as THREE from 'three';

export type CityAreaId = 'market' | 'underground' | 'office' | 'counter';

export const CITY_AREA_IDS: readonly CityAreaId[] = [
  'market',
  'underground',
  'office',
  'counter',
] as const;

export function isCityAreaId(v: string): v is CityAreaId {
  return (CITY_AREA_IDS as readonly string[]).includes(v);
}

export interface BoundaryCutout {
  id: string;
  points: [number, number][];
  subtractFloor?: boolean;
  wallBottomY?: number;
  wallHeight?: number;
}

export interface BoundaryOpening {
  id: string;
  label?: string;
  edge: number;
  tStart: number;
  tEnd: number;
  portalOnly?: boolean;
}

export interface CityBoundaryConfig {
  version: number;
  areaId: CityAreaId;
  stageId: string;
  buildFloor: boolean;
  floorY: number;
  wallBottomY?: number;
  wallHeight: number;
  fallRespawnY: number;
  perimeter: [number, number][];
  cutouts: BoundaryCutout[];
  openings: BoundaryOpening[];
}

export interface ReferencePin {
  label: string;
  kind: 'spawn' | 'npc' | 'trigger';
  pos: [number, number, number];
}

export interface CityPreset {
  areaId: CityAreaId;
  title: string;
  stageId: string;
  glbPath: string | null; // null = procedural OfficeLibraryRoom
  pins: ReferencePin[];
}

export const CITY_BOUNDARY_PRESETS: Record<CityAreaId, CityPreset> = {
  market: {
    areaId: 'market',
    title: 'Market (s00e_sa1)',
    stageId: 's00e_sa1',
    glbPath: 'assets/stages/city_e/market/dairon3.glb',
    pins: [
      { label: 'Default Spawn', kind: 'spawn', pos: [0.98, 0.0, 62.79] },
      { label: 'Counter Exit Spawn', kind: 'spawn', pos: [0.98, 0.0, 18.84] },
      { label: 'Underground Exit Spawn', kind: 'spawn', pos: [-13.44, 0.0, 55.0] },
      { label: 'Item Shop NPC', kind: 'npc', pos: [-10.34, 0.0, 27.67] },
      { label: 'Weapon Shop NPC', kind: 'npc', pos: [-6.78, 0.0, 21.81] },
      { label: 'Grind Shop NPC', kind: 'npc', pos: [6.25, 0.0, 23.45] },
      { label: 'Exit -> Counter', kind: 'trigger', pos: [0.38, 0.5, 14.43] },
      { label: 'Exit -> Underground', kind: 'trigger', pos: [-13.44, 0.5, 57.44] },
    ],
  },
  underground: {
    areaId: 'underground',
    title: 'Underground (s00e_sa4)',
    stageId: 's00e_sa4',
    glbPath: 'assets/stages/city_e/s00e_sa4/lndmd/s00e_sa4_m.glb',
    pins: [
      { label: 'Default Spawn', kind: 'spawn', pos: [0.04, 0.0, -1.0] },
      { label: 'Synthesis NPC', kind: 'npc', pos: [8.38, 0.0, -4.81] },
      { label: 'Photon Collector NPC', kind: 'npc', pos: [-6.32, 0.0, -5.35] },
      { label: 'Blackjack NPC', kind: 'npc', pos: [-10.0, 0.0, 0.0] },
      { label: 'Exit -> Market', kind: 'trigger', pos: [0.0, 0.5, -3.0] },
    ],
  },
  office: {
    areaId: 'office',
    title: "Principal's Office (procedural)",
    stageId: 's00e_office',
    glbPath: null,
    pins: [
      { label: 'Default Spawn', kind: 'spawn', pos: [0.0, 0.0, 4.4] },
      { label: 'Intro Spawn', kind: 'spawn', pos: [0.0, 0.0, 1.5] },
      { label: 'Principal NPC', kind: 'npc', pos: [0.0, 1.05, -5.6] },
      { label: 'Principal Interact', kind: 'spawn', pos: [0.0, 1.05, -3.9] },
      { label: 'Briefing NPC 1', kind: 'npc', pos: [-2.8, 0.0, -2.4] },
      { label: 'Briefing NPC 2', kind: 'npc', pos: [-3.9, 0.0, -1.5] },
      { label: 'Door -> Counter', kind: 'trigger', pos: [0.0, 0.5, 6.5] },
    ],
  },
  counter: {
    areaId: 'counter',
    title: 'Guild Counter (s00e_sa2)',
    stageId: 's00e_sa2',
    glbPath: 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb',
    pins: [
      { label: 'Default Spawn', kind: 'spawn', pos: [-0.05, -10.67, 121.78] },
      { label: 'Market Exit Spawn', kind: 'spawn', pos: [-0.06, -10.67, 137.68] },
      { label: 'Office Exit Spawn', kind: 'spawn', pos: [10.59, -10.67, 111.17] },
      { label: 'Warp Exit Spawn', kind: 'spawn', pos: [0.05, -5.33, 64.0] },
      { label: 'Quest Counter NPC', kind: 'npc', pos: [-7.86, -10.67, 111.39] },
      { label: 'Counter Stand Pos', kind: 'spawn', pos: [-6.2, -10.67, 112.84] },
      { label: 'Storage NPC', kind: 'npc', pos: [-10.53, -10.67, 114.15] },
      { label: 'Coliseum Master NPC', kind: 'npc', pos: [-9.8, -10.67, 121.28] },
      { label: 'Exit -> Market', kind: 'trigger', pos: [-0.06, -10.17, 140.65] },
      { label: 'Exit -> Office', kind: 'trigger', pos: [14.3, -10.17, 107.47] },
      { label: 'Warp Teleporter Pad', kind: 'trigger', pos: [0.05, -5.08, 60.96] },
    ],
  },
};

const round2 = (n: number): number => Math.round(n * 100) / 100;

function parsePointPair(item: unknown): [number, number] | null {
  if (!Array.isArray(item) || item.length < 2) return null;
  const x = Number(item[0]);
  const z = Number(item[1]);
  if (!Number.isFinite(x) || !Number.isFinite(z)) return null;
  return [round2(x), round2(z)];
}

export function normalizeBoundaryConfig(raw: unknown): CityBoundaryConfig {
  if (!raw || typeof raw !== 'object') {
    throw new Error('Boundary config must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;
  const areaId = String(obj.areaId ?? '');
  if (!isCityAreaId(areaId)) {
    throw new Error(`Unsupported city areaId "${areaId}"`);
  }
  const perimeterRaw = Array.isArray(obj.perimeter) ? obj.perimeter : [];
  const perimeter = perimeterRaw
    .map(parsePointPair)
    .filter((p): p is [number, number] => p !== null);
  if (perimeter.length < 3) {
    throw new Error('Boundary perimeter must contain at least 3 [x, z] points');
  }
  const cutoutsRaw = Array.isArray(obj.cutouts) ? obj.cutouts : [];
  const cutouts: BoundaryCutout[] = [];
  for (let i = 0; i < cutoutsRaw.length; i++) {
    const c = cutoutsRaw[i] as Record<string, unknown> | null;
    if (!c || typeof c !== 'object') continue;
    const pts = (Array.isArray(c.points) ? c.points : [])
      .map(parsePointPair)
      .filter((p): p is [number, number] => p !== null);
    if (pts.length < 3) continue;
    const entry: BoundaryCutout = {
      id: String(c.id || `cutout_${i + 1}`),
      subtractFloor: c.subtractFloor !== undefined ? Boolean(c.subtractFloor) : true,
      points: pts,
    };
    if (c.wallBottomY !== undefined && Number.isFinite(Number(c.wallBottomY))) {
      entry.wallBottomY = round2(Number(c.wallBottomY));
    }
    if (c.wallHeight !== undefined && Number.isFinite(Number(c.wallHeight))) {
      entry.wallHeight = round2(Number(c.wallHeight));
    }
    cutouts.push(entry);
  }

  const openingsRaw = Array.isArray(obj.openings) ? obj.openings : [];
  const openings: BoundaryOpening[] = [];
  for (let i = 0; i < openingsRaw.length; i++) {
    const o = openingsRaw[i] as Record<string, unknown> | null;
    if (!o || typeof o !== 'object') continue;
    const edge = Math.max(0, Math.floor(Number(o.edge ?? 0)));
    const tStart = Math.max(0, Math.min(1, round2(Number(o.tStart ?? 0))));
    const tEnd = Math.max(0, Math.min(1, round2(Number(o.tEnd ?? 1))));
    if (tEnd <= tStart) continue;
    openings.push({
      id: String(o.id || `opening_${i + 1}`),
      ...(o.label ? { label: String(o.label) } : {}),
      edge,
      tStart,
      tEnd,
      portalOnly: Boolean(o.portalOnly),
    });
  }

  const out: CityBoundaryConfig = {
    version: Number(obj.version ?? 1) || 1,
    areaId,
    stageId: String(obj.stageId || CITY_BOUNDARY_PRESETS[areaId].stageId),
    buildFloor: obj.buildFloor !== undefined ? Boolean(obj.buildFloor) : true,
    floorY: round2(Number(obj.floorY ?? 0)),
    ...(obj.wallBottomY !== undefined && Number.isFinite(Number(obj.wallBottomY))
      ? { wallBottomY: round2(Number(obj.wallBottomY)) }
      : {}),
    wallHeight: Math.max(0.5, round2(Number(obj.wallHeight ?? 4.0))),
    fallRespawnY: round2(Number(obj.fallRespawnY ?? -10.0)),
    perimeter,
    cutouts,
    openings,
  };
  return out;
}

export function serializeBoundaryConfig(cfg: CityBoundaryConfig): string {
  return JSON.stringify(normalizeBoundaryConfig(cfg), null, 2) + '\n';
}

export function computeSolidEdgeSpans(
  edgeIdx: number,
  openings: readonly BoundaryOpening[],
): [number, number][] {
  const gaps: [number, number][] = [];
  for (const op of openings) {
    if (op.portalOnly || op.edge !== edgeIdx) continue;
    const t0 = Math.max(0, Math.min(1, op.tStart));
    const t1 = Math.max(0, Math.min(1, op.tEnd));
    if (t1 > t0 + 0.001) gaps.push([t0, t1]);
  }
  if (!gaps.length) return [[0, 1]];
  gaps.sort((a, b) => a[0] - b[0]);
  const spans: [number, number][] = [];
  let cursor = 0;
  for (const [g0, g1] of gaps) {
    if (g0 > cursor + 0.001) spans.push([cursor, g0]);
    cursor = Math.max(cursor, g1);
  }
  if (cursor < 0.999) spans.push([cursor, 1]);
  return spans;
}

export function pointInPolygon2D(x: number, z: number, poly: readonly [number, number][]): boolean {
  let inside = false;
  for (let i = 0, n = poly.length; i < n; i++) {
    const [x1, z1] = poly[i];
    const [x2, z2] = poly[(i + 1) % n];
    if (z1 > z !== z2 > z) {
      const xInt = x1 + ((z - z1) * (x2 - x1)) / (z2 - z1);
      if (x < xInt) inside = !inside;
    }
  }
  return inside;
}

export function isPointWalkable2D(
  cfg: CityBoundaryConfig,
  x: number,
  z: number,
  y?: number,
): boolean {
  if (cfg.perimeter.length < 3 || !pointInPolygon2D(x, z, cfg.perimeter)) {
    return false;
  }
  for (const c of cfg.cutouts) {
    const subFloor = c.subtractFloor ?? true;
    const wb = c.wallBottomY ?? cfg.floorY;
    const wh = c.wallHeight ?? cfg.wallHeight;
    const blocksY = y === undefined || (y >= wb - 0.1 && y <= wb + wh + 0.1);
    if ((subFloor || blocksY) && pointInPolygon2D(x, z, c.points)) {
      return false;
    }
  }
  return true;
}

export function splitPolygonEdge(
  points: readonly [number, number][],
  edgeIdx: number,
): [number, number][] {
  if (points.length < 2) return [...points];
  const i = ((edgeIdx % points.length) + points.length) % points.length;
  const a = points[i];
  const b = points[(i + 1) % points.length];
  const mid: [number, number] = [round2((a[0] + b[0]) * 0.5), round2((a[1] + b[1]) * 0.5)];
  const next = [...points];
  next.splice(i + 1, 0, mid);
  return next;
}

/**
 * Procedural preview of `scripts/3d/city/office_library_room.gd` so the web
 * FloorColliderBuilder renders an accurate 1:1 Principal's Office reference
 * (R=9 disc, 270 deg apse wall, y=1.05 rear landing, stairs, railings,
 * bookcases + ladders, and Principal's desk) without requiring a stage GLB.
 */
export function buildProceduralOfficeGroup(): THREE.Group {
  const group = new THREE.Group();
  group.name = 'ProceduralOfficePreview';
  const R = 9.0;
  const WALL_H = 8.2;
  const LANDING_H = 1.05;
  const LANDING_FRONT = -2.6;
  const STAIR_WIDTH = 3.5;
  const STAIR_RUN = 2.52;
  const ARC_HALF = 0.75 * Math.PI;

  const floorMat = new THREE.MeshStandardMaterial({ color: 0x4b564a, roughness: 0.9 });
  const landingMat = new THREE.MeshStandardMaterial({ color: 0x5d6858, roughness: 0.85 });
  const wallMat = new THREE.MeshStandardMaterial({
    color: 0x3b414d,
    side: THREE.DoubleSide,
    roughness: 0.92,
  });
  const woodMat = new THREE.MeshStandardMaterial({ color: 0x7a5b3a, roughness: 0.8 });

  // Main R=9 floor disc
  const disc = new THREE.Mesh(new THREE.CylinderGeometry(R, R, 0.06, 64), floorMat);
  disc.position.set(0, -0.03, 0);
  group.add(disc);

  // 270 deg apse wall
  const segs = 48;
  const wallVerts: number[] = [];
  for (let i = 0; i < segs; i++) {
    const th0 = -ARC_HALF + (i / segs) * ARC_HALF * 2;
    const th1 = -ARC_HALF + ((i + 1) / segs) * ARC_HALF * 2;
    const x0 = Math.sin(th0) * R, z0 = -Math.cos(th0) * R;
    const x1 = Math.sin(th1) * R, z1 = -Math.cos(th1) * R;
    wallVerts.push(x0, 0, z0, x1, 0, z1, x1, WALL_H, z1);
    wallVerts.push(x0, 0, z0, x1, WALL_H, z1, x0, WALL_H, z0);
  }
  const wallGeom = new THREE.BufferGeometry();
  wallGeom.setAttribute('position', new THREE.Float32BufferAttribute(wallVerts, 3));
  wallGeom.computeVertexNormals();
  group.add(new THREE.Mesh(wallGeom, wallMat));

  // Rear raised library landing (y = 1.05, z <= -2.6)
  const halfArc = Math.acos(-LANDING_FRONT / (R - 0.08));
  const landingShape = new THREE.Shape();
  for (let i = 0; i <= 40; i++) {
    const phi = -halfArc + (i / 40) * halfArc * 2;
    const x = Math.sin(phi) * (R - 0.08);
    const z = -Math.cos(phi) * (R - 0.08);
    if (i === 0) landingShape.moveTo(x, z);
    else landingShape.lineTo(x, z);
  }
  landingShape.closePath();
  const landingExtrude = new THREE.ExtrudeGeometry(landingShape, {
    depth: LANDING_H,
    bevelEnabled: false,
  });
  landingExtrude.rotateX(Math.PI / 2);
  landingExtrude.translate(0, LANDING_H, 0);
  group.add(new THREE.Mesh(landingExtrude, landingMat));

  // Central 6-step staircase
  const stepDepth = STAIR_RUN / 6;
  for (let i = 0; i < 6; i++) {
    const h = (LANDING_H * (i + 1)) / 6;
    const z = LANDING_FRONT + STAIR_RUN - (i + 0.5) * stepDepth;
    const step = new THREE.Mesh(new THREE.BoxGeometry(STAIR_WIDTH, h, stepDepth), landingMat);
    step.position.set(0, h * 0.5, z);
    group.add(step);
  }

  // Landing railings
  for (const side of [-1, 1]) {
    const x0 = side * (STAIR_WIDTH * 0.5 + 0.17);
    const x1 = side * 7.65;
    const rail = new THREE.Mesh(
      new THREE.BoxGeometry(Math.abs(x1 - x0), 0.85, 0.18),
      woodMat,
    );
    rail.position.set((x0 + x1) * 0.5, LANDING_H + 0.425, LANDING_FRONT);
    group.add(rail);
  }

  // Bookcases + leaning library ladders along SHELF_PHIS
  for (const phi of [-2.2, -1.68, -1.08, -0.7, 0.7, 1.08, 1.68, 2.2]) {
    const baseH = Math.abs(phi) < 1.3 ? LANDING_H : 0;
    const unitH = WALL_H - 0.4 - baseH;
    const x = Math.sin(phi) * (R - 0.5);
    const z = -Math.cos(phi) * (R - 0.5);
    const rotY = Math.atan2(x, z) + Math.PI;
    const holder = new THREE.Group();
    holder.position.set(x, baseH, z);
    holder.rotation.y = rotY;
    const cab = new THREE.Mesh(new THREE.BoxGeometry(3.15, unitH, 0.55), woodMat);
    cab.position.set(0, unitH * 0.5, 0);
    holder.add(cab);
    if (Math.abs(Math.abs(phi) - 0.7) < 0.02 || Math.abs(Math.abs(phi) - 1.68) < 0.02) {
      const ladder = new THREE.Mesh(new THREE.BoxGeometry(0.68, unitH - 0.5, 0.72), woodMat);
      ladder.position.set(0, (unitH - 0.5) * 0.5, 0.68);
      holder.add(ladder);
    }
    group.add(holder);
  }

  // Principal's desk at (0, LANDING_H - 0.2, -4.5)
  const desk = new THREE.Mesh(new THREE.BoxGeometry(3.4, 1.15, 1.5), woodMat);
  desk.position.set(0, LANDING_H + 0.45, -4.5);
  group.add(desk);

  return group;
}
