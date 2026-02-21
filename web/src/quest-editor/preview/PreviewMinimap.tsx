/**
 * PreviewMinimap — SVG minimap overlay with player tracking dot
 *
 * Loads the stage minimap SVG, parses floor triangles + boundary lines + gate diamonds,
 * computes an affine transform from 3D local coords to SVG coords,
 * and renders everything as React SVG with a live player position arrow.
 */

import { useState, useEffect, useMemo } from 'react';
import { assetUrl } from '../../utils/assets';
import { getStageSubfolder, STAGE_AREAS } from '../../stage-editor/constants';
import type { PortalData } from './StageScene';

// ============================================================================
// Types
// ============================================================================

interface Vec2 { x: number; y: number }
interface Triangle { a: Vec2; b: Vec2; c: Vec2 }
interface LineSegment { a: Vec2; b: Vec2 }
interface GateEntry { center: Vec2; color: string; label: string }

interface ParsedSvg {
  floorTriangles: Triangle[];
  boundaryLines: LineSegment[];
  gateCenters: Vec2[];
}

interface AffineTransform {
  ax: number; bx: number;
  ay: number; by: number;
  valid: boolean;
}

interface PreviewMinimapProps {
  areaKey: string;
  stageId: string;
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  playerX: number;
  playerZ: number;
  /** Cell rotation in degrees — used to un-rotate world player pos back to model-local */
  playerRotation: number;
  /** Cell rotation in degrees — used for SVG display rotation */
  rotation: number;
}

const DISPLAY_SIZE = 180;
const SVG_SIZE = 400;

const COLORS = {
  bg: 'rgba(26, 26, 46, 0.85)',
  floor: '#28284e',
  boundary: 'rgba(255, 255, 255, 0.6)',
  gateOpen: '#44ff44',
  gateExit: '#4a9eff',
  gateWall: '#666666',
  player: '#00ff00',
};

// ============================================================================
// SVG Parsing
// ============================================================================

function parsePoint(s: string): Vec2 {
  const [x, y] = s.trim().split(',').map(Number);
  return { x: x || 0, y: y || 0 };
}

function parseSvgContent(svgText: string): ParsedSvg {
  const floorTriangles: Triangle[] = [];
  const boundaryLines: LineSegment[] = [];
  const gateCenters: Vec2[] = [];

  const lines = svgText.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();

    // Floor triangles: <path d="..." fill="#2a2a4e">
    if (trimmed.includes('fill="#2a2a4e"')) {
      const dMatch = trimmed.match(/d="([^"]+)"/);
      if (dMatch) {
        const chunks = dMatch[1].split(' Z ');
        for (let chunk of chunks) {
          chunk = chunk.trim().replace(/ Z$/, '');
          if (!chunk) continue;
          // Parse "M x,y L x,y L x,y" triangle
          const parts = chunk.replace(/^M\s*/, '').split(/\s+L\s+/);
          if (parts.length === 3) {
            const pts = parts.map(p => parsePoint(p));
            floorTriangles.push({ a: pts[0], b: pts[1], c: pts[2] });
          }
        }
      }
    }

    // Boundary lines: <path fill="none" stroke="white">
    if (trimmed.includes('stroke="white"') && trimmed.includes('fill="none"')) {
      const dMatch = trimmed.match(/d="([^"]+)"/);
      if (dMatch) {
        const segments = dMatch[1].split(' M ');
        for (let seg of segments) {
          seg = seg.trim().replace(/^M\s*/, '');
          if (!seg) continue;
          const parts = seg.split(' L ');
          if (parts.length === 2) {
            boundaryLines.push({
              a: parsePoint(parts[0]),
              b: parsePoint(parts[1]),
            });
          }
        }
      }
    }

    // Gate diamonds: <polygon points="...">
    if (trimmed.startsWith('<polygon')) {
      const ptsMatch = trimmed.match(/points="([^"]+)"/);
      if (ptsMatch) {
        const pts = ptsMatch[1].trim().split(/\s+/).map(p => parsePoint(p));
        if (pts.length > 0) {
          const center = pts.reduce(
            (acc, p) => ({ x: acc.x + p.x / pts.length, y: acc.y + p.y / pts.length }),
            { x: 0, y: 0 }
          );
          gateCenters.push(center);
        }
      }
    }
  }

  return { floorTriangles, boundaryLines, gateCenters };
}

// ============================================================================
// Gate Matching + Affine Computation
// ============================================================================

const DIRECTIONS = ['north', 'east', 'south', 'west'] as const;

function directionScore(svgCenter: Vec2, origDir: string): number {
  const dx = svgCenter.x - 200;
  const dy = svgCenter.y - 200;
  switch (origDir) {
    case 'north': return -dy;
    case 'south': return dy;
    case 'east': return -dx; // mirrored X in GLB convention
    case 'west': return dx;
    default: return 0;
  }
}

function reverseRotateDir(gridDir: string, rotation: number): string {
  if (rotation === 0) return gridDir;
  const idx = DIRECTIONS.indexOf(gridDir as any);
  if (idx < 0) return gridDir;
  const steps = ((360 - rotation) / 90) % 4;
  return DIRECTIONS[(idx + steps) % 4];
}

function findBestAssignment(
  scores: number[][], nDirs: number, nGates: number
): number[] {
  let bestScore = -Infinity;
  let bestPerm: number[] = [];

  function tryPerms(current: number[], used: Set<number>, dirIdx: number) {
    if (dirIdx === nDirs) {
      let total = 0;
      for (let i = 0; i < current.length; i++) total += scores[i][current[i]];
      if (total > bestScore) {
        bestScore = total;
        bestPerm = [...current];
      }
      return;
    }
    for (let g = 0; g < nGates; g++) {
      if (used.has(g)) continue;
      current.push(g);
      used.add(g);
      tryPerms(current, used, dirIdx + 1);
      current.pop();
      used.delete(g);
    }
  }

  tryPerms([], new Set(), 0);
  return bestPerm;
}

function matchGates(
  svgCenters: Vec2[],
  portals: Record<string, PortalData>,
  cellRotation: number,
): Record<number, string> {
  const dirs: { grid: string; orig: string }[] = [];
  for (const gridDir of Object.keys(portals)) {
    if (gridDir === 'default') continue;
    dirs.push({ grid: gridDir, orig: reverseRotateDir(gridDir, cellRotation) });
  }
  if (dirs.length === 0 || svgCenters.length === 0) return {};

  const scores: number[][] = dirs.map(d =>
    svgCenters.map(c => directionScore(c, d.orig))
  );

  const assignment = findBestAssignment(scores, dirs.length, svgCenters.length);

  const result: Record<number, string> = {};
  for (let di = 0; di < assignment.length; di++) {
    result[assignment[di]] = dirs[di].grid;
  }
  return result;
}

function computeAffine(
  svgCenters: Vec2[],
  gateMatch: Record<number, string>,
  portals: Record<string, PortalData>,
  floorTriangles: Triangle[],
): AffineTransform {
  // Build matched pairs: SVG center ↔ 3D gate position
  const pairs: { svg: Vec2; localX: number; localZ: number }[] = [];
  for (const [gateIdxStr, gridDir] of Object.entries(gateMatch)) {
    const gateIdx = parseInt(gateIdxStr);
    const portal = portals[gridDir];
    if (!portal) continue;
    pairs.push({
      svg: svgCenters[gateIdx],
      localX: portal.gate[0],
      localZ: portal.gate[2],
    });
  }

  if (pairs.length < 2) {
    if (pairs.length === 1 && floorTriangles.length > 0) {
      // Use floor centroid as virtual second point
      let sumX = 0, sumY = 0, totalArea = 0;
      for (const tri of floorTriangles) {
        const area = Math.abs((tri.b.x - tri.a.x) * (tri.c.y - tri.a.y) - (tri.c.x - tri.a.x) * (tri.b.y - tri.a.y)) * 0.5;
        sumX += (tri.a.x + tri.b.x + tri.c.x) / 3 * area;
        sumY += (tri.a.y + tri.b.y + tri.c.y) / 3 * area;
        totalArea += area;
      }
      const centroid = totalArea > 0
        ? { x: sumX / totalArea, y: sumY / totalArea }
        : { x: 200, y: 200 };
      pairs.push({ svg: centroid, localX: 0, localZ: 0 });
    } else {
      return { ax: 0, bx: 0, ay: 0, by: 0, valid: false };
    }
  }

  // Pick pair with max spread in X for solving X affine
  let bestXSpread = 0, xi = 0, xj = 1;
  for (let i = 0; i < pairs.length; i++) {
    for (let j = i + 1; j < pairs.length; j++) {
      const s = Math.abs(pairs[j].localX - pairs[i].localX);
      if (s > bestXSpread) { bestXSpread = s; xi = i; xj = j; }
    }
  }

  let bestZSpread = 0, zi = 0, zj = 1;
  for (let i = 0; i < pairs.length; i++) {
    for (let j = i + 1; j < pairs.length; j++) {
      const s = Math.abs(pairs[j].localZ - pairs[i].localZ);
      if (s > bestZSpread) { bestZSpread = s; zi = i; zj = j; }
    }
  }

  let ax = 0, bx = 0, ay = 0, by = 0;

  if (bestXSpread > 0.1) {
    ax = (pairs[xj].svg.x - pairs[xi].svg.x) / (pairs[xj].localX - pairs[xi].localX);
    bx = pairs[xi].svg.x - pairs[xi].localX * ax;
  }
  if (bestZSpread > 0.1) {
    ay = (pairs[zj].svg.y - pairs[zi].svg.y) / (pairs[zj].localZ - pairs[zi].localZ);
    by = pairs[zi].svg.y - pairs[zi].localZ * ay;
  }

  // Enforce positive scale
  if (ax < 0) { ax = -ax; bx = pairs[0].svg.x - pairs[0].localX * ax; }
  if (ay < 0) { ay = -ay; by = pairs[0].svg.y - pairs[0].localZ * ay; }

  // Fallback: use same scale for both axes if only one solved
  let valid = false;
  if (bestXSpread > 0.1 && bestZSpread > 0.1) {
    valid = true;
  } else if (bestXSpread > 0.1) {
    ay = ax;
    by = pairs[0].svg.y - pairs[0].localZ * ay;
    valid = true;
  } else if (bestZSpread > 0.1) {
    ax = ay;
    bx = pairs[0].svg.x - pairs[0].localX * ax;
    valid = true;
  }

  return { ax, bx, ay, by, valid };
}

// ============================================================================
// SVG coordinate transforms
// ============================================================================

function svgToDisplay(svgX: number, svgY: number, cellRotation: number): Vec2 {
  let x = svgX, y = svgY;
  if (cellRotation !== 0) {
    const cx = 200, cy = 200;
    const rad = (cellRotation * Math.PI) / 180;
    const cos = Math.cos(rad), sin = Math.sin(rad);
    const dx = x - cx, dy = y - cy;
    x = dx * cos - dy * sin + cx;
    y = dx * sin + dy * cos + cy;
  }
  const scale = DISPLAY_SIZE / SVG_SIZE;
  return { x: x * scale, y: y * scale };
}

// ============================================================================
// Component
// ============================================================================

export default function PreviewMinimap({
  areaKey,
  stageId,
  portals,
  connections,
  playerX,
  playerZ,
  playerRotation,
  rotation,
}: PreviewMinimapProps) {
  const [svgData, setSvgData] = useState<ParsedSvg | null>(null);

  // Load and parse SVG
  useEffect(() => {
    const area = STAGE_AREAS[areaKey];
    if (!area) return;
    const subfolder = getStageSubfolder(stageId, area.folder);
    const svgPath = assetUrl(`assets/stages/${subfolder}/${stageId}/lndmd/${stageId}_minimap.svg`);

    fetch(svgPath)
      .then(r => r.ok ? r.text() : '')
      .then(text => {
        if (text) setSvgData(parseSvgContent(text));
        else setSvgData(null);
      })
      .catch(() => setSvgData(null));
  }, [areaKey, stageId]);

  // Compute gate matching + affine transform
  const { affine, gateEntries } = useMemo(() => {
    if (!svgData) return { affine: null, gateEntries: [] };

    const gateMatch = matchGates(svgData.gateCenters, portals, rotation);
    const aff = computeAffine(svgData.gateCenters, gateMatch, portals, svgData.floorTriangles);

    const entries: GateEntry[] = svgData.gateCenters.map((center, i) => {
      const gridDir = gateMatch[i];
      if (!gridDir) return { center, color: COLORS.gateWall, label: '' };
      const portal = portals[gridDir];
      const hasConnection = !!connections[gridDir];
      return {
        center,
        color: hasConnection ? COLORS.gateOpen : COLORS.gateWall,
        label: hasConnection ? (portal?.compass_label || gridDir[0].toUpperCase()) : '',
      };
    });

    return { affine: aff, gateEntries: entries };
  }, [svgData, portals, connections, rotation]);

  if (!svgData) {
    return (
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        background: COLORS.bg, borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#666', fontSize: 11,
      }}>
        No minimap
      </div>
    );
  }

  // Player position in SVG coords
  // playerX/playerZ are in world (rotated) space — un-rotate back to model-local
  // for the affine transform which maps model-local → SVG.
  let playerDisplay: Vec2 | null = null;
  if (affine?.valid) {
    let localX = playerX, localZ = playerZ;
    if (playerRotation !== 0) {
      const rad = (-playerRotation * Math.PI) / 180; // reverse rotation
      const cos = Math.cos(rad), sin = Math.sin(rad);
      localX = playerX * cos + playerZ * sin;
      localZ = -playerX * sin + playerZ * cos;
    }
    const svgX = localX * affine.ax + affine.bx;
    const svgY = localZ * affine.ay + affine.by;
    playerDisplay = svgToDisplay(svgX, svgY, rotation);
  }

  return (
    <div style={{
      width: DISPLAY_SIZE,
      height: DISPLAY_SIZE,
      borderRadius: 8,
      overflow: 'hidden',
      boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
    }}>
      <svg
        viewBox={`0 0 ${DISPLAY_SIZE} ${DISPLAY_SIZE}`}
        width={DISPLAY_SIZE}
        height={DISPLAY_SIZE}
        style={{ display: 'block' }}
      >
        {/* Background */}
        <rect width={DISPLAY_SIZE} height={DISPLAY_SIZE} fill={COLORS.bg} />

        {/* Floor triangles */}
        {svgData.floorTriangles.map((tri, i) => {
          const a = svgToDisplay(tri.a.x, tri.a.y, rotation);
          const b = svgToDisplay(tri.b.x, tri.b.y, rotation);
          const c = svgToDisplay(tri.c.x, tri.c.y, rotation);
          return (
            <polygon
              key={`f${i}`}
              points={`${a.x},${a.y} ${b.x},${b.y} ${c.x},${c.y}`}
              fill={COLORS.floor}
            />
          );
        })}

        {/* Boundary lines */}
        {svgData.boundaryLines.map((seg, i) => {
          const a = svgToDisplay(seg.a.x, seg.a.y, rotation);
          const b = svgToDisplay(seg.b.x, seg.b.y, rotation);
          return (
            <line
              key={`b${i}`}
              x1={a.x} y1={a.y} x2={b.x} y2={b.y}
              stroke={COLORS.boundary}
              strokeWidth={1.5}
              strokeLinecap="round"
            />
          );
        })}

        {/* Gate diamonds */}
        {gateEntries.map((gate, i) => {
          const c = svgToDisplay(gate.center.x, gate.center.y, rotation);
          const d = 5;
          return (
            <g key={`g${i}`}>
              <polygon
                points={`${c.x},${c.y - d} ${c.x + d},${c.y} ${c.x},${c.y + d} ${c.x - d},${c.y}`}
                fill={gate.color}
              />
              {gate.label && (
                <text
                  x={c.x}
                  y={c.y - 8}
                  textAnchor="middle"
                  fill={gate.color}
                  fontSize={9}
                  fontFamily="monospace"
                  fontWeight="bold"
                >
                  {gate.label}
                </text>
              )}
            </g>
          );
        })}

        {/* Player dot */}
        {playerDisplay && (
          <circle
            cx={playerDisplay.x}
            cy={playerDisplay.y}
            r={4}
            fill={COLORS.player}
            stroke="#000"
            strokeWidth={1}
          />
        )}
      </svg>
    </div>
  );
}
