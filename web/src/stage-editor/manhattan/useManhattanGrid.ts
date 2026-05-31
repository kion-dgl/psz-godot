// useManhattanGrid — load the stage's floor.glb, build the same NavGrid
// our CLI Manhattan solver uses, and return the walkable mask + a sample
// path between two world XZ positions.

import { useEffect, useState } from 'react';
import {
  buildNavGrid,
  filterFloorTriangles,
  loadGlbTriangles,
  solveManhattan,
  tri3dToTri2d,
  type NavGrid,
  type ManhattanPath,
  type Tri3D,
} from './solver';
import { getGlbPath, getAreaFromMapId } from '../constants';

export interface UseManhattanGridResult {
  loading: boolean;
  error: string | null;
  grid: NavGrid | null;
  trisRaw: number;
  trisFiltered: number;
  bounds: { minX: number; maxX: number; minZ: number; maxZ: number } | null;
  path: ManhattanPath | null;
}

interface Args {
  mapId: string;
  enabled: boolean;
  floorCollisionTriangles?: Record<string, boolean>;
  /** Path start (world XZ). If both start+end are provided, hook runs A*. */
  pathStart?: { x: number; z: number } | null;
  pathEnd?: { x: number; z: number } | null;
  resolution?: number;
  /** Also fuse the visual mesh (-m.glb) into the floor triangles. Useful when
   *  -floor.glb has holes the player walks across in-game. */
  fuseVisualMesh?: boolean;
}

export function useManhattanGrid({
  mapId,
  enabled,
  floorCollisionTriangles,
  pathStart,
  pathEnd,
  resolution = 0.5,
  fuseVisualMesh = false,
}: Args): UseManhattanGridResult {
  const [state, setState] = useState<UseManhattanGridResult>({
    loading: false,
    error: null,
    grid: null,
    trisRaw: 0,
    trisFiltered: 0,
    bounds: null,
    path: null,
  });

  useEffect(() => {
    if (!enabled || !mapId) {
      setState((s) => ({ ...s, loading: false }));
      return;
    }
    let cancelled = false;
    setState((s) => ({ ...s, loading: true, error: null }));

    const area = getAreaFromMapId(mapId);
    const floorPath = getGlbPath(area ?? 'valley', mapId).replace('_m.glb', '-floor.glb');
    const visualPath = getGlbPath(area ?? 'valley', mapId);

    (async () => {
      try {
        const floorRaw = await loadGlbTriangles(floorPath).catch(() => [] as Tri3D[]);
        const filtered = filterFloorTriangles(floorRaw, floorCollisionTriangles ?? {});
        let tris3d = filtered;
        if (fuseVisualMesh) {
          const m = await loadGlbTriangles(visualPath).catch(() => [] as Tri3D[]);
          tris3d = [...filtered, ...m];
        }
        const tris2d = tris3d.map(tri3dToTri2d);
        if (cancelled) return;
        const grid = buildNavGrid(tris2d, { resolution });
        const bounds = {
          minX: grid.minX,
          maxX: grid.minX + (grid.cols - 1) * grid.resolution,
          minZ: grid.minZ,
          maxZ: grid.minZ + (grid.rows - 1) * grid.resolution,
        };
        let path: ManhattanPath | null = null;
        if (pathStart && pathEnd) {
          path = solveManhattan(grid, pathStart, pathEnd);
        }
        setState({
          loading: false,
          error: null,
          grid,
          trisRaw: floorRaw.length,
          trisFiltered: tris3d.length,
          bounds,
          path,
        });
      } catch (e) {
        if (cancelled) return;
        setState({
          loading: false,
          error: e instanceof Error ? e.message : String(e),
          grid: null,
          trisRaw: 0,
          trisFiltered: 0,
          bounds: null,
          path: null,
        });
      }
    })();

    return () => { cancelled = true; };
    // Stringify the override map so we don't recompute on every render when
    // the parent passes a new object literal with the same contents.
  }, [
    mapId,
    enabled,
    resolution,
    fuseVisualMesh,
    JSON.stringify(floorCollisionTriangles ?? {}),
    pathStart?.x, pathStart?.z,
    pathEnd?.x, pathEnd?.z,
  ]);

  return state;
}
