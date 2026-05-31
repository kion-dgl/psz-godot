import type { NavMesh } from '../nav-mesh';
import type { TileCache } from '../tile-cache';
export declare const exportNavMesh: (navMesh: NavMesh) => Uint8Array;
export declare const exportTileCache: (navMesh: NavMesh, tileCache: TileCache) => Uint8Array;
