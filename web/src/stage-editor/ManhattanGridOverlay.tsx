// 3D overlay that visualizes the Manhattan grid + path the CLI solver
// would compute for the currently-selected stage. Toggle via the editor
// sidebar. Renders:
//   • green semi-transparent quads for walkable cells (sparse — only every
//     Nth cell, to keep frame rate up on large grids)
//   • red dots for blocked cells next to walkable ones (the floor mesh's
//     boundary; what makes the grid an "outline" of the stage)
//   • a polyline through the corner waypoints of the solved path
//
// Click handlers on the wireframe stage canvas set the start/end of the
// path so the user can drag the goalposts and watch the path re-route.

import { useMemo } from 'react';
import * as THREE from 'three';
import { Line } from '@react-three/drei';
import type { NavGrid } from './manhattan/solver';
import type { ManhattanPath } from './manhattan/solver';

interface Props {
  grid: NavGrid;
  path: ManhattanPath | null;
  /** Y offset so the overlay floats just above the floor. */
  y?: number;
  /** Render every Nth walkable cell to bound the geometry count. */
  walkableStride?: number;
  /** Hide the per-cell quads (only show outline / path). */
  hideCells?: boolean;
}

export default function ManhattanGridOverlay({ grid, path, y = 0.15, walkableStride = 1, hideCells = false }: Props) {
  const { walkableMesh, edgeMesh } = useMemo(() => {
    if (grid.rows === 0 || grid.cols === 0 || hideCells) {
      return { walkableMesh: null, edgeMesh: null };
    }
    const res = grid.resolution;
    const inset = res * 0.85;

    // Pass 1: walkable cells.
    const walkPositions: number[] = [];
    const walkIndices: number[] = [];
    let v = 0;
    for (let r = 0; r < grid.rows; r += walkableStride) {
      for (let c = 0; c < grid.cols; c += walkableStride) {
        if (grid.walkable[r * grid.cols + c] !== 1) continue;
        const x = grid.minX + c * res;
        const z = grid.minZ + r * res;
        const h = inset / 2;
        walkPositions.push(
          x - h, y, z - h,
          x + h, y, z - h,
          x + h, y, z + h,
          x - h, y, z + h,
        );
        walkIndices.push(v, v + 1, v + 2, v, v + 2, v + 3);
        v += 4;
      }
    }
    const walkGeom = new THREE.BufferGeometry();
    walkGeom.setAttribute('position', new THREE.Float32BufferAttribute(walkPositions, 3));
    walkGeom.setIndex(walkIndices);

    // Pass 2: edge cells (blocked but adjacent to walkable). Renders as small
    // red dots so the outline of the playable floor is visible.
    const edgePositions: number[] = [];
    const edgeIndices: number[] = [];
    let ev = 0;
    for (let r = 0; r < grid.rows; r++) {
      for (let c = 0; c < grid.cols; c++) {
        if (grid.walkable[r * grid.cols + c] === 1) continue;
        let touchesWalkable = false;
        for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]] as const) {
          const nr = r + dr, nc = c + dc;
          if (nr < 0 || nr >= grid.rows || nc < 0 || nc >= grid.cols) continue;
          if (grid.walkable[nr * grid.cols + nc] === 1) { touchesWalkable = true; break; }
        }
        if (!touchesWalkable) continue;
        const x = grid.minX + c * res;
        const z = grid.minZ + r * res;
        const h = res * 0.15;
        edgePositions.push(
          x - h, y, z - h,
          x + h, y, z - h,
          x + h, y, z + h,
          x - h, y, z + h,
        );
        edgeIndices.push(ev, ev + 1, ev + 2, ev, ev + 2, ev + 3);
        ev += 4;
      }
    }
    const edgeGeom = new THREE.BufferGeometry();
    edgeGeom.setAttribute('position', new THREE.Float32BufferAttribute(edgePositions, 3));
    edgeGeom.setIndex(edgeIndices);

    return { walkableMesh: walkGeom, edgeMesh: edgeGeom };
  }, [grid, y, walkableStride, hideCells]);

  const pathPoints = useMemo<[number, number, number][]>(() => {
    if (!path || path.worldCorners.length < 2) return [];
    return path.worldCorners.map((c) => [c.x, y + 0.15, c.z]);
  }, [path, y]);

  return (
    <group>
      {walkableMesh && (
        <mesh geometry={walkableMesh}>
          <meshBasicMaterial color="#22c55e" transparent opacity={0.18} depthWrite={false} side={THREE.DoubleSide} />
        </mesh>
      )}
      {edgeMesh && (
        <mesh geometry={edgeMesh}>
          <meshBasicMaterial color="#ef4444" transparent opacity={0.7} depthWrite={false} side={THREE.DoubleSide} />
        </mesh>
      )}
      {pathPoints.length >= 2 && (
        <Line points={pathPoints} color="#fbbf24" lineWidth={3} dashed={path?.usedDiagonal ?? false} dashSize={0.5} gapSize={0.3} />
      )}
      {path?.worldCorners.map((c, i) => (
        <mesh key={i} position={[c.x, y + 0.18, c.z]}>
          <sphereGeometry args={[0.25, 12, 8]} />
          <meshBasicMaterial color={i === 0 ? '#22c55e' : i === path.worldCorners.length - 1 ? '#ef4444' : '#fbbf24'} />
        </mesh>
      ))}
    </group>
  );
}
