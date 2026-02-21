/**
 * PreviewMinimap — SVG-based minimap with player tracking dot
 *
 * Loads the pre-generated SVG minimap file for the current stage,
 * rotates it by cell rotation, and overlays a player tracking dot.
 *
 * Coordinate mapping: extracts gate diamond polygon centers from the SVG
 * and matches them with known world-space gate positions from the portal
 * config. This gives us the exact scale+offset transform that was used
 * to generate the SVG, without needing saved svgSettings.
 */

import { useState, useEffect, useMemo } from 'react';
import { assetUrl } from '../../utils/assets';
import { getStageSubfolder } from '../../stage-editor/constants';
import type { PortalData } from './StageScene';

// ============================================================================
// SVG polygon parsing + transform computation
// ============================================================================

/** Anchor point: a known (worldX, worldZ) ↔ (svgX, svgY) pair. */
interface AnchorPoint {
  worldX: number;
  worldZ: number;
  svgX: number;
  svgY: number;
}

/** Extract gate diamond polygon centers from SVG content.
 *  Gate diamonds are <polygon fill="#4a9eff" ...> with 4 points. */
function parseGateDiamonds(svgContent: string): [number, number][] {
  const centers: [number, number][] = [];
  // Match polygon elements — fill may come before or after points
  const polygonRe = /<polygon\s[^>]*?fill="#4a9eff"[^>]*?\/?>/gi;
  let match;
  while ((match = polygonRe.exec(svgContent)) !== null) {
    const pointsMatch = match[0].match(/points="([^"]*)"/);
    if (!pointsMatch) continue;
    const coords = pointsMatch[1].trim().split(/\s+/).map(p => {
      const [x, y] = p.split(',').map(Number);
      return [x, y] as [number, number];
    });
    if (coords.length < 3) continue;
    const cx = coords.reduce((s, p) => s + p[0], 0) / coords.length;
    const cy = coords.reduce((s, p) => s + p[1], 0) / coords.length;
    centers.push([cx, cy]);
  }
  return centers;
}

/** Parse the invisible origin marker (<circle data-origin="true" .../>).
 *  Returns [svgX, svgY] of the world origin (0,0), or null if not found. */
function parseOriginMarker(svgContent: string): [number, number] | null {
  const m = svgContent.match(/<circle[^>]*data-origin="true"[^>]*\/?>/i);
  if (!m) return null;
  const cxM = m[0].match(/cx="([^"]*)"/);
  const cyM = m[0].match(/cy="([^"]*)"/);
  if (!cxM || !cyM) return null;
  return [parseFloat(cxM[1]), parseFloat(cyM[1])];
}

interface SvgTransform {
  scale: number;
  offsetX: number;
  offsetY: number;
}

/** Extract the SVG viewBox size from content (default 400). */
function parseSvgSize(svgContent: string): number {
  const m = svgContent.match(/viewBox="0\s+0\s+([\d.]+)\s+([\d.]+)"/);
  return m ? parseFloat(m[1]) : 400;
}

/** Compute world→SVG affine transform from anchor points.
 *  Transform: svgX = worldX * scale + offsetX, svgY = worldZ * scale + offsetY
 *
 *  Anchors are pre-matched (worldX,worldZ) ↔ (svgX,svgY) pairs. The origin marker
 *  provides a guaranteed anchor at world (0,0); gate diamonds provide additional anchors
 *  that need permutation-matching against world portal positions.
 *
 *  With 1 anchor: estimates scale from svgSize, computes offset.
 *  With 2+ anchors: solves for scale+offset via least-squares. */
function computeTransformFromAnchors(
  anchors: AnchorPoint[],
  svgSize: number,
): SvgTransform | null {
  const n = anchors.length;
  if (n === 0) return null;

  if (n === 1) {
    // Single anchor — estimate scale from SVG size, compute offset from the one pair
    const padding = 20;
    const defaultGridSize = 40;
    const scale = (svgSize - padding * 2) / defaultGridSize;
    return {
      scale,
      offsetX: anchors[0].svgX - anchors[0].worldX * scale,
      offsetY: anchors[0].svgY - anchors[0].worldZ * scale,
    };
  }

  // 2+ anchors: solve for scale + offset via least-squares
  // scale = Σ(dSvg · dWorld) / Σ(dWorld · dWorld) across all pairs
  let sumNum = 0, sumDen = 0;
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const dwx = anchors[j].worldX - anchors[i].worldX;
      const dwz = anchors[j].worldZ - anchors[i].worldZ;
      const dsx = anchors[j].svgX - anchors[i].svgX;
      const dsy = anchors[j].svgY - anchors[i].svgY;
      sumNum += dsx * dwx + dsy * dwz;
      sumDen += dwx * dwx + dwz * dwz;
    }
  }
  if (Math.abs(sumDen) < 0.001) return null;
  const scale = sumNum / sumDen;
  if (scale <= 0) return null;

  // Offset = average of (svgPos - worldPos * scale)
  let offX = 0, offY = 0;
  for (const a of anchors) {
    offX += a.svgX - a.worldX * scale;
    offY += a.svgY - a.worldZ * scale;
  }
  return { scale, offsetX: offX / n, offsetY: offY / n };
}

/** Build anchor points by matching gate diamonds in SVG with portal world positions.
 *  Tries all permutations (n ≤ 4 gates, so ≤ 24 attempts) and picks the best match.
 *  Also includes the origin marker as a fixed anchor if present. */
function buildAnchors(
  worldGates: { x: number; z: number }[],
  svgDiamonds: [number, number][],
  originSvg: [number, number] | null,
  svgSize: number,
): AnchorPoint[] {
  const anchors: AnchorPoint[] = [];

  // Origin marker is always at world (0,0)
  if (originSvg) {
    anchors.push({ worldX: 0, worldZ: 0, svgX: originSvg[0], svgY: originSvg[1] });
  }

  // Match gate diamonds to world portals via permutation search
  const n = Math.min(worldGates.length, svgDiamonds.length);
  if (n === 0) return anchors;

  if (n === 1) {
    // Only one gate — direct match
    anchors.push({ worldX: worldGates[0].x, worldZ: worldGates[0].z, svgX: svgDiamonds[0][0], svgY: svgDiamonds[0][1] });
    return anchors;
  }

  // Try all permutations of assigning world gates to SVG diamonds
  const indices = Array.from({ length: n }, (_, i) => i);
  const perms = permutations(indices);
  let bestPerm = indices;
  let bestErr = Infinity;

  for (const perm of perms) {
    // Quick estimate: use origin anchor (if available) + this permutation's pairs
    // to compute a transform, then measure error
    const testAnchors = [...anchors];
    for (let i = 0; i < n; i++) {
      testAnchors.push({
        worldX: worldGates[perm[i]].x,
        worldZ: worldGates[perm[i]].z,
        svgX: svgDiamonds[i][0],
        svgY: svgDiamonds[i][1],
      });
    }
    const t = computeTransformFromAnchors(testAnchors, svgSize);
    if (!t) continue;

    let err = 0;
    for (const a of testAnchors) {
      const ex = a.worldX * t.scale + t.offsetX - a.svgX;
      const ey = a.worldZ * t.scale + t.offsetY - a.svgY;
      err += ex * ex + ey * ey;
    }
    if (err < bestErr) {
      bestErr = err;
      bestPerm = perm;
    }
  }

  // Add gates with best permutation
  for (let i = 0; i < n; i++) {
    anchors.push({
      worldX: worldGates[bestPerm[i]].x,
      worldZ: worldGates[bestPerm[i]].z,
      svgX: svgDiamonds[i][0],
      svgY: svgDiamonds[i][1],
    });
  }

  return anchors;
}

/** Generate all permutations of an array (n! — fine for n <= 4) */
function permutations<T>(arr: T[]): T[][] {
  if (arr.length <= 1) return [arr];
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i++) {
    const rest = [...arr.slice(0, i), ...arr.slice(i + 1)];
    for (const perm of permutations(rest)) {
      result.push([arr[i], ...perm]);
    }
  }
  return result;
}

// ============================================================================
// Component
// ============================================================================

interface PreviewMinimapProps {
  areaFolder: string;
  stageId: string;
  svgSettings: { gridSize: number; centerX: number; centerZ: number; svgSize: number; padding: number } | null;
  cellRotation: number;
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  /** Player position in model-local space (unrotated) */
  playerX: number;
  playerZ: number;
}

const DISPLAY_SIZE = 200;

export default function PreviewMinimap({
  areaFolder,
  stageId,
  svgSettings,
  cellRotation,
  portals,
  connections,
  playerX,
  playerZ,
}: PreviewMinimapProps) {
  const [svgContent, setSvgContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Load SVG file
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setSvgContent(null);

    const subfolder = getStageSubfolder(stageId, areaFolder);
    const svgPath = assetUrl(`assets/stages/${subfolder}/${stageId}/lndmd/${stageId}_minimap.svg`);

    fetch(svgPath)
      .then(resp => {
        if (!resp.ok) throw new Error('SVG not found');
        return resp.text();
      })
      .then(text => {
        if (!cancelled) {
          setSvgContent(text);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setSvgContent(null);
          setLoading(false);
        }
      });

    return () => { cancelled = true; };
  }, [stageId, areaFolder]);

  // Compute world→SVG transform by matching anchor points (origin marker + gate diamonds)
  const transform = useMemo(() => {
    if (!svgContent) return null;

    const svgDiamonds = parseGateDiamonds(svgContent);
    const originSvg = parseOriginMarker(svgContent);
    const svgSz = parseSvgSize(svgContent);

    // Get world-space gate positions (exclude 'default' portal)
    const worldGates = Object.entries(portals)
      .filter(([dir]) => dir !== 'default')
      .map(([, p]) => ({ x: p.gate[0], z: p.gate[2] }));

    // Build anchor points (origin + matched gate diamonds)
    const anchors = buildAnchors(worldGates, svgDiamonds, originSvg, svgSz);
    const anchorTransform = computeTransformFromAnchors(anchors, svgSz);
    if (anchorTransform) return { ...anchorTransform, svgSize: svgSz };

    // Fallback to svgSettings if available
    if (svgSettings) {
      const { gridSize, centerX, centerZ, svgSize: sz, padding } = svgSettings;
      const scale = (sz - padding * 2) / gridSize;
      const halfGrid = gridSize / 2;
      return {
        scale,
        offsetX: -(centerX - halfGrid) * scale + padding,
        offsetY: -(centerZ - halfGrid) * scale + padding,
        svgSize: sz,
      };
    }

    // Last resort: default settings
    const defaultScale = (svgSz - 40) / 40;
    return { scale: defaultScale, offsetX: 20, offsetY: 20, svgSize: svgSz };
  }, [svgContent, portals, svgSettings]);

  const svgSize = transform?.svgSize ?? 400;

  // Player position in SVG coordinates
  const playerSvgX = transform ? playerX * transform.scale + transform.offsetX : 0;
  const playerSvgY = transform ? playerZ * transform.scale + transform.offsetY : 0;

  // Gate markers in SVG coordinates (for direction labels)
  const gateMarkers = useMemo(() => {
    if (!transform) return [];
    return Object.entries(portals)
      .filter(([dir]) => dir !== 'default' && connections[dir])
      .map(([dir, portal]) => ({
        dir,
        x: portal.gate[0] * transform.scale + transform.offsetX,
        y: portal.gate[2] * transform.scale + transform.offsetY,
      }));
  }, [portals, connections, transform]);

  // CSS rotation for cell rotation (CW degrees)
  const rotDeg = -cellRotation;

  if (loading) {
    return (
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        background: 'rgba(26, 26, 46, 0.85)', borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#666', fontSize: 11,
      }}>
        Loading minimap...
      </div>
    );
  }

  if (!svgContent) {
    return (
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        background: 'rgba(26, 26, 46, 0.85)', borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#555', fontSize: 10,
      }}>
        No minimap SVG
      </div>
    );
  }

  return (
    <div style={{
      width: DISPLAY_SIZE, height: DISPLAY_SIZE,
      borderRadius: 8, overflow: 'hidden',
      boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
      position: 'relative',
    }}>
      {/* Rotated container for SVG + overlays */}
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
        transform: `rotate(${rotDeg}deg)`,
        transformOrigin: 'center center',
      }}>
        {/* SVG background (scaled to fit display size) */}
        <div
          style={{
            width: DISPLAY_SIZE, height: DISPLAY_SIZE,
            position: 'absolute', top: 0, left: 0,
          }}
          dangerouslySetInnerHTML={{
            __html: svgContent.replace(
              /viewBox="[^"]*"/,
              `viewBox="0 0 ${svgSize} ${svgSize}" width="${DISPLAY_SIZE}" height="${DISPLAY_SIZE}"`
            ),
          }}
        />

        {/* Overlay SVG for player dot + gate labels */}
        <svg
          viewBox={`0 0 ${svgSize} ${svgSize}`}
          width={DISPLAY_SIZE}
          height={DISPLAY_SIZE}
          style={{ position: 'absolute', top: 0, left: 0 }}
        >
          {/* Gate direction labels */}
          {gateMarkers.map(({ dir, x, y }) => (
            <text
              key={dir}
              x={x}
              y={y - 10}
              textAnchor="middle"
              fill="#4a9eff"
              fontSize={14}
              fontFamily="monospace"
              fontWeight="bold"
            >
              {dir[0].toUpperCase()}
            </text>
          ))}

          {/* Player dot */}
          <circle
            cx={playerSvgX}
            cy={playerSvgY}
            r={6}
            fill="#00ff00"
            stroke="#000"
            strokeWidth={1.5}
          />
        </svg>
      </div>
    </div>
  );
}
