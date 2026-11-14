export type CityAreaId = 'market';

export const CITY_AREA_IDS: readonly CityAreaId[] = ['market'] as const;

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
  glbPath: string;
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
