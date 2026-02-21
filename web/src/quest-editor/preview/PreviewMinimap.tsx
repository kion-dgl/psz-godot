/**
 * PreviewMinimap — Floor-geometry minimap with player tracking dot
 *
 * Renders floor triangles extracted directly from the loaded GLB model,
 * projected to XZ (top-down). Portal markers and player dot use the same
 * world-space coordinates — no separate SVG files or affine transforms.
 */

import { useMemo } from 'react';
import type { PortalData } from './StageScene';

interface PreviewMinimapProps {
  /** Floor triangles in world space: [x1,z1, x2,z2, x3,z3][] */
  floorTriangles: number[][] | null;
  /** Portals already rotated to world space */
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  playerX: number;
  playerZ: number;
}

const SIZE = 200;
const PADDING = 16;

const COLORS = {
  bg: 'rgba(26, 26, 46, 0.85)',
  floor: '#28284e',
  boundary: 'rgba(255, 255, 255, 0.6)',
  gate: '#4a9eff',
  player: '#00ff00',
};

/** Build an edge key (order-independent) from two XZ points, rounded for float comparison */
function edgeKey(x1: number, z1: number, x2: number, z2: number): string {
  const a = `${x1.toFixed(1)},${z1.toFixed(1)}`;
  const b = `${x2.toFixed(1)},${z2.toFixed(1)}`;
  return a < b ? `${a}-${b}` : `${b}-${a}`;
}

export default function PreviewMinimap({
  floorTriangles,
  portals,
  connections,
  playerX,
  playerZ,
}: PreviewMinimapProps) {
  const { floorPath, boundaryPath, bounds } = useMemo(() => {
    if (!floorTriangles || floorTriangles.length === 0) {
      return { floorPath: '', boundaryPath: '', bounds: null };
    }

    // Compute bounding box
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const tri of floorTriangles) {
      for (let i = 0; i < 6; i += 2) {
        const x = tri[i], z = tri[i + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }

    const rangeX = maxX - minX || 1;
    const rangeZ = maxZ - minZ || 1;
    const maxRange = Math.max(rangeX, rangeZ);
    const scale = (SIZE - PADDING * 2) / maxRange;
    // Center on both axes
    const offsetX = -minX + (maxRange - rangeX) / 2;
    const offsetZ = -minZ + (maxRange - rangeZ) / 2;

    const toSvg = (wx: number, wz: number): [number, number] => [
      (wx + offsetX) * scale + PADDING,
      (wz + offsetZ) * scale + PADDING,
    ];

    // Build floor path (single <path> element for all triangles)
    const fp = floorTriangles.map(tri => {
      const [sx1, sz1] = toSvg(tri[0], tri[1]);
      const [sx2, sz2] = toSvg(tri[2], tri[3]);
      const [sx3, sz3] = toSvg(tri[4], tri[5]);
      return `M${sx1.toFixed(1)},${sz1.toFixed(1)}L${sx2.toFixed(1)},${sz2.toFixed(1)}L${sx3.toFixed(1)},${sz3.toFixed(1)}Z`;
    }).join('');

    // Find boundary edges (edges shared by exactly one triangle)
    const edgeCounts = new Map<string, { x1: number; z1: number; x2: number; z2: number }>();
    const edgeCountMap = new Map<string, number>();
    for (const tri of floorTriangles) {
      const verts = [[tri[0], tri[1]], [tri[2], tri[3]], [tri[4], tri[5]]];
      for (let i = 0; i < 3; i++) {
        const [ax, az] = verts[i];
        const [bx, bz] = verts[(i + 1) % 3];
        const key = edgeKey(ax, az, bx, bz);
        edgeCountMap.set(key, (edgeCountMap.get(key) || 0) + 1);
        if (!edgeCounts.has(key)) {
          edgeCounts.set(key, { x1: ax, z1: az, x2: bx, z2: bz });
        }
      }
    }

    const bp: string[] = [];
    for (const [key, count] of edgeCountMap.entries()) {
      if (count === 1) {
        const edge = edgeCounts.get(key)!;
        const [sx1, sz1] = toSvg(edge.x1, edge.z1);
        const [sx2, sz2] = toSvg(edge.x2, edge.z2);
        bp.push(`M${sx1.toFixed(1)},${sz1.toFixed(1)}L${sx2.toFixed(1)},${sz2.toFixed(1)}`);
      }
    }

    return {
      floorPath: fp,
      boundaryPath: bp.join(''),
      bounds: { scale, offsetX, offsetZ },
    };
  }, [floorTriangles]);

  if (!floorTriangles || floorTriangles.length === 0 || !bounds) {
    return (
      <div style={{
        width: SIZE, height: SIZE,
        background: COLORS.bg, borderRadius: 8,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#666', fontSize: 11,
      }}>
        Loading minimap...
      </div>
    );
  }

  const toSvg = (wx: number, wz: number): [number, number] => [
    (wx + bounds.offsetX) * bounds.scale + PADDING,
    (wz + bounds.offsetZ) * bounds.scale + PADDING,
  ];

  const [px, pz] = toSvg(playerX, playerZ);

  return (
    <div style={{
      width: SIZE, height: SIZE,
      borderRadius: 8, overflow: 'hidden',
      boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
    }}>
      <svg
        viewBox={`0 0 ${SIZE} ${SIZE}`}
        width={SIZE}
        height={SIZE}
        style={{ display: 'block' }}
      >
        <rect width={SIZE} height={SIZE} fill={COLORS.bg} />

        {/* Floor triangles */}
        <path d={floorPath} fill={COLORS.floor} stroke="none" />

        {/* Boundary outline */}
        {boundaryPath && (
          <path
            d={boundaryPath}
            fill="none"
            stroke={COLORS.boundary}
            strokeWidth={1.5}
            strokeLinecap="round"
          />
        )}

        {/* Portal gate markers */}
        {Object.entries(portals).map(([dir, portal]) => {
          if (dir === 'default') return null;
          const hasConnection = !!connections[dir];
          if (!hasConnection) return null;
          const [gx, gz] = toSvg(portal.gate[0], portal.gate[2]);
          const d = 5;
          return (
            <g key={dir}>
              <polygon
                points={`${gx},${gz - d} ${gx + d},${gz} ${gx},${gz + d} ${gx - d},${gz}`}
                fill={COLORS.gate}
              />
              <text
                x={gx}
                y={gz - 8}
                textAnchor="middle"
                fill={COLORS.gate}
                fontSize={9}
                fontFamily="monospace"
                fontWeight="bold"
              >
                {dir[0].toUpperCase()}
              </text>
            </g>
          );
        })}

        {/* Player dot */}
        <circle cx={px} cy={pz} r={4} fill={COLORS.player} stroke="#000" strokeWidth={1} />
      </svg>
    </div>
  );
}
