/**
 * PreviewMinimap — SVG-based minimap with player tracking dot
 *
 * Always loads the base (unrotated) SVG minimap since the 3D preview view
 * is unrotated. Gate labels show grid-space directions at model-space positions,
 * matching the labels in the 3D view. Grid orientation is handled by PreviewGrid.
 *
 * SVGs with embedded transform metadata (data-scale, data-offset-x/y) use those
 * directly; legacy SVGs use anchor-point matching to compute the world→SVG transform.
 */

import { useState, useEffect, useMemo } from 'react';
import { assetUrl } from '../../utils/assets';
import { getStageSubfolder } from '../../stage-editor/constants';
import type { PortalData } from './StageScene';

// ============================================================================
// SVG parsing helpers
// ============================================================================

/** Embedded transform metadata from new SVG variants */
interface EmbeddedTransform {
  rotation: number;
  scale: number;
  offsetX: number;
  offsetY: number;
  centerX: number;
  centerY: number;
  svgSize: number;
}

/** Parse embedded data-* attributes from SVG root element.
 *  Returns null if the SVG doesn't have the new metadata. */
function parseEmbeddedTransform(svgContent: string): EmbeddedTransform | null {
  const rotM = svgContent.match(/data-rotation="([^"]*)"/);
  const scaleM = svgContent.match(/data-scale="([^"]*)"/);
  const offXM = svgContent.match(/data-offset-x="([^"]*)"/);
  const offYM = svgContent.match(/data-offset-y="([^"]*)"/);
  const cxM = svgContent.match(/data-center-x="([^"]*)"/);
  const cyM = svgContent.match(/data-center-y="([^"]*)"/);
  if (!rotM || !scaleM || !offXM || !offYM || !cxM || !cyM) return null;

  const svgSize = parseSvgSize(svgContent);
  return {
    rotation: parseFloat(rotM[1]),
    scale: parseFloat(scaleM[1]),
    offsetX: parseFloat(offXM[1]),
    offsetY: parseFloat(offYM[1]),
    centerX: parseFloat(cxM[1]),
    centerY: parseFloat(cyM[1]),
    svgSize,
  };
}

// ============================================================================
// Legacy SVG parsing + transform computation (for old SVGs without metadata)
// ============================================================================

/** Anchor point: a known (worldX, worldZ) ↔ (svgX, svgY) pair. */
interface AnchorPoint {
  worldX: number;
  worldZ: number;
  svgX: number;
  svgY: number;
}

/** Extract gate marker centers from SVG content.
 *  Supports two formats:
 *  - New: <rect ... data-gate="true" .../> (directional rects)
 *  - Legacy: <polygon fill="#4a9eff" .../> (diamond shapes) */
function parseGateMarkers(svgContent: string): [number, number][] {
  const centers: [number, number][] = [];

  // New format: <rect ... data-gate="true" .../>
  const rectRe = /<rect\s[^>]*?data-gate="true"[^>]*?\/?>/gi;
  let match;
  while ((match = rectRe.exec(svgContent)) !== null) {
    const xM = match[0].match(/\bx="([^"]*)"/);
    const yM = match[0].match(/\by="([^"]*)"/);
    const wM = match[0].match(/width="([^"]*)"/);
    const hM = match[0].match(/height="([^"]*)"/);
    if (xM && yM && wM && hM) {
      centers.push([
        parseFloat(xM[1]) + parseFloat(wM[1]) / 2,
        parseFloat(yM[1]) + parseFloat(hM[1]) / 2,
      ]);
    }
  }
  if (centers.length > 0) return centers;

  // Legacy format: <polygon fill="#4a9eff" .../> (diamond shapes)
  const polygonRe = /<polygon\s[^>]*?fill="#4a9eff"[^>]*?\/?>/gi;
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
 *  Transform: svgX = worldX * scale + offsetX, svgY = worldZ * scale + offsetY */
function computeTransformFromAnchors(
  anchors: AnchorPoint[],
  svgSize: number,
): SvgTransform | null {
  const n = anchors.length;
  if (n === 0) return null;

  if (n === 1) {
    const padding = 20;
    const defaultGridSize = 40;
    const scale = (svgSize - padding * 2) / defaultGridSize;
    return {
      scale,
      offsetX: anchors[0].svgX - anchors[0].worldX * scale,
      offsetY: anchors[0].svgY - anchors[0].worldZ * scale,
    };
  }

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

  let offX = 0, offY = 0;
  for (const a of anchors) {
    offX += a.svgX - a.worldX * scale;
    offY += a.svgY - a.worldZ * scale;
  }
  return { scale, offsetX: offX / n, offsetY: offY / n };
}

/** Build anchor points by matching gate diamonds in SVG with portal world positions. */
function buildAnchors(
  worldGates: { x: number; z: number }[],
  svgDiamonds: [number, number][],
  originSvg: [number, number] | null,
  svgSize: number,
): AnchorPoint[] {
  const anchors: AnchorPoint[] = [];

  if (originSvg) {
    anchors.push({ worldX: 0, worldZ: 0, svgX: originSvg[0], svgY: originSvg[1] });
  }

  const n = Math.min(worldGates.length, svgDiamonds.length);
  if (n === 0) return anchors;

  if (n === 1) {
    anchors.push({ worldX: worldGates[0].x, worldZ: worldGates[0].z, svgX: svgDiamonds[0][0], svgY: svgDiamonds[0][1] });
    return anchors;
  }

  const indices = Array.from({ length: n }, (_, i) => i);
  const perms = permutations(indices);
  let bestPerm = indices;
  let bestErr = Infinity;

  for (const perm of perms) {
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
  portals,
  connections,
  playerX,
  playerZ,
}: PreviewMinimapProps) {
  const [svgContent, setSvgContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Load base (unrotated) SVG — the 3D view is always unrotated,
  // so the minimap should match it. Grid orientation is shown by PreviewGrid.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setSvgContent(null);

    const subfolder = getStageSubfolder(stageId, areaFolder);
    const basePath = `assets/stages/${subfolder}/${stageId}/lndmd`;
    const svgUrl = assetUrl(`${basePath}/${stageId}_minimap.svg`);

    fetch(svgUrl).then(resp => {
      if (!resp.ok) throw new Error('not found');
      const ct = resp.headers.get('content-type') || '';
      if (ct.includes('text/html')) throw new Error('got HTML, not SVG');
      return resp.text();
    }).then(text => {
      if (!text.trimStart().startsWith('<svg')) throw new Error('not SVG content');
      if (!cancelled) {
        setSvgContent(text);
        setLoading(false);
      }
    }).catch(() => {
      if (!cancelled) {
        setSvgContent(null);
        setLoading(false);
      }
    });

    return () => { cancelled = true; };
  }, [stageId, areaFolder]);

  // Compute world→SVG transform from embedded metadata, anchors, or svgSettings
  const svgTransform = useMemo(() => {
    if (!svgContent) return null;

    // Try embedded metadata first (new SVGs have data-scale, data-offset-x/y)
    const emb = parseEmbeddedTransform(svgContent);
    if (emb) {
      return { scale: emb.scale, offsetX: emb.offsetX, offsetY: emb.offsetY, svgSize: emb.svgSize };
    }

    // Try anchor-based transform from gate markers
    const svgDiamonds = parseGateMarkers(svgContent);
    const originSvg = parseOriginMarker(svgContent);
    const svgSz = parseSvgSize(svgContent);

    const worldGates = Object.entries(portals)
      .filter(([dir]) => dir !== 'default')
      .map(([, p]) => ({ x: p.gate[0], z: p.gate[2] }));

    const anchors = buildAnchors(worldGates, svgDiamonds, originSvg, svgSz);
    const anchorTransform = computeTransformFromAnchors(anchors, svgSz);
    if (anchorTransform) return { ...anchorTransform, svgSize: svgSz };

    // Fall back to svgSettings
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

    const defaultScale = (svgSz - 40) / 40;
    return { scale: defaultScale, offsetX: 20, offsetY: 20, svgSize: svgSz };
  }, [svgContent, portals, svgSettings]);

  const svgSize = svgTransform?.svgSize ?? 400;

  // Player position in SVG coordinates (direct linear mapping — no rotation)
  const playerSvgX = svgTransform ? playerX * svgTransform.scale + svgTransform.offsetX : 0;
  const playerSvgY = svgTransform ? playerZ * svgTransform.scale + svgTransform.offsetY : 0;

  // Gate markers with grid-space direction labels at model-space positions
  // (matches the 3D view which shows grid directions at model-space portal positions)
  const gateMarkers = useMemo(() => {
    if (!svgTransform) return [];
    return Object.entries(portals)
      .filter(([dir]) => dir !== 'default' && connections[dir])
      .map(([dir, portal]) => ({
        dir,
        x: portal.gate[0] * svgTransform.scale + svgTransform.offsetX,
        y: portal.gate[2] * svgTransform.scale + svgTransform.offsetY,
      }));
  }, [portals, connections, svgTransform]);

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
      {/* Container — unrotated to match 3D view */}
      <div style={{
        width: DISPLAY_SIZE, height: DISPLAY_SIZE,
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

        {/* Overlay SVG for player dot + gate labels (legacy only) */}
        <svg
          viewBox={`0 0 ${svgSize} ${svgSize}`}
          width={DISPLAY_SIZE}
          height={DISPLAY_SIZE}
          style={{ position: 'absolute', top: 0, left: 0 }}
        >
          {/* Gate direction labels (grid-space, matching 3D view) */}
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
