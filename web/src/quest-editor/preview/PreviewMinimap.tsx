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

/** Compute world→SVG affine transform from matched gate pairs.
 *  Transform: svgX = worldX * scale + offsetX, svgY = worldZ * scale + offsetY
 *
 *  With 1 pair: uses svgSize to estimate scale, computes offset.
 *  With 2+ pairs: solves for scale+offset via least-squares across all permutations. */
function computeGateTransform(
  worldGates: { x: number; z: number }[],
  svgCenters: [number, number][],
  svgSize: number,
): SvgTransform | null {
  const n = Math.min(worldGates.length, svgCenters.length);
  if (n === 0) return null;

  if (n === 1) {
    // Can't determine scale from 1 pair — estimate from SVG size.
    // Typical padding=20, gridSize chosen so stage fills the SVG.
    // Most stages: scale ≈ (svgSize - 40) / gridSize, gridSize ≈ 40 → scale ≈ 9
    // We can't know gridSize, but we can assume center is near the middle
    // and scale from SVG dimension. Use a rough heuristic:
    // Place the single gate at its known SVG position and assume the
    // center of the SVG corresponds to world origin with default scale.
    const padding = 20;
    const defaultGridSize = 40;
    const scale = (svgSize - padding * 2) / defaultGridSize;
    const offX = svgCenters[0][0] - worldGates[0].x * scale;
    const offY = svgCenters[0][1] - worldGates[0].z * scale;
    return { scale, offsetX: offX, offsetY: offY };
  }

  // For 2+ pairs: try all permutations of matching world gates to SVG centers
  // and pick the assignment with minimum reprojection error.
  const indices = Array.from({ length: n }, (_, i) => i);
  const perms = permutations(indices);

  let best: SvgTransform | null = null;
  let bestErr = Infinity;

  for (const perm of perms) {
    // Solve for scale: collect (dWorld, dSvg) pairs across all adjacent pairs
    let sumNum = 0, sumDen = 0;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const dwx = worldGates[perm[j]].x - worldGates[perm[i]].x;
        const dwz = worldGates[perm[j]].z - worldGates[perm[i]].z;
        const dsx = svgCenters[j][0] - svgCenters[i][0];
        const dsy = svgCenters[j][1] - svgCenters[i][1];
        // scale = dot(dSvg, dWorld) / dot(dWorld, dWorld)
        sumNum += dsx * dwx + dsy * dwz;
        sumDen += dwx * dwx + dwz * dwz;
      }
    }
    if (Math.abs(sumDen) < 0.001) continue;
    const scale = sumNum / sumDen;
    if (scale <= 0) continue; // scale must be positive

    // Compute offset as average
    let offX = 0, offY = 0;
    for (let i = 0; i < n; i++) {
      offX += svgCenters[i][0] - worldGates[perm[i]].x * scale;
      offY += svgCenters[i][1] - worldGates[perm[i]].z * scale;
    }
    offX /= n;
    offY /= n;

    // Reprojection error
    let err = 0;
    for (let i = 0; i < n; i++) {
      const ex = worldGates[perm[i]].x * scale + offX - svgCenters[i][0];
      const ey = worldGates[perm[i]].z * scale + offY - svgCenters[i][1];
      err += ex * ex + ey * ey;
    }

    if (err < bestErr) {
      bestErr = err;
      best = { scale, offsetX: offX, offsetY: offY };
    }
  }

  return best;
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

  // Compute world→SVG transform by matching gate diamonds in SVG with portal world positions
  const transform = useMemo(() => {
    if (!svgContent) return null;

    // Extract gate diamond centers from SVG
    const svgDiamonds = parseGateDiamonds(svgContent);
    const svgSize = parseSvgSize(svgContent);

    // Get world-space gate positions (exclude 'default' portal)
    const worldGates = Object.entries(portals)
      .filter(([dir]) => dir !== 'default')
      .map(([, p]) => ({ x: p.gate[0], z: p.gate[2] }));

    // Try gate-anchored transform first
    const gateTransform = computeGateTransform(worldGates, svgDiamonds, svgSize);
    if (gateTransform) return { ...gateTransform, svgSize };

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
    const defaultScale = (svgSize - 40) / 40; // padding=20, gridSize=40
    return { scale: defaultScale, offsetX: 20, offsetY: 20, svgSize };
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
