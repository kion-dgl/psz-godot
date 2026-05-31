import type { NavMesh } from './nav-mesh';
import type { NavMeshQuery } from './nav-mesh-query';
import type { RecastCompactHeightfield, RecastContourSet, RecastHeightfield, RecastHeightfieldLayer, RecastHeightfieldLayerSet, RecastPolyMesh, RecastPolyMeshDetail } from './recast';
export type DebugDrawerPrimitiveType = 'lines' | 'tris' | 'quads' | 'points';
export type DebugDrawerPrimitive = {
    type: DebugDrawerPrimitiveType;
    vertices: [
        x: number,
        y: number,
        z: number,
        r: number,
        g: number,
        b: number,
        a: number
    ][];
};
/**
 * Represents a helper class to visualize navigation cur and related data in PlayCanvas.
 */
export declare class DebugDrawerUtils {
    private debugDrawImpl;
    private currentPrimitiveType;
    private currentVertices;
    private primitives;
    constructor();
    private flush;
    drawHeightfieldSolid(hf: RecastHeightfield): DebugDrawerPrimitive[];
    drawHeightfieldWalkable(hf: RecastHeightfield): DebugDrawerPrimitive[];
    drawCompactHeightfieldSolid(chf: RecastCompactHeightfield): DebugDrawerPrimitive[];
    drawCompactHeightfieldRegions(chf: RecastCompactHeightfield): DebugDrawerPrimitive[];
    drawCompactHeightfieldDistance(chf: RecastCompactHeightfield): DebugDrawerPrimitive[];
    drawHeightfieldLayer(layer: RecastHeightfieldLayer, idx: number): DebugDrawerPrimitive[];
    drawHeightfieldLayers(lset: RecastHeightfieldLayerSet): DebugDrawerPrimitive[];
    drawRegionConnections(cset: RecastContourSet, alpha?: number): DebugDrawerPrimitive[];
    drawRawContours(cset: RecastContourSet, alpha?: number): DebugDrawerPrimitive[];
    drawContours(cset: RecastContourSet, alpha?: number): DebugDrawerPrimitive[];
    drawPolyMesh(mesh: RecastPolyMesh): DebugDrawerPrimitive[];
    drawPolyMeshDetail(dmesh: RecastPolyMeshDetail): DebugDrawerPrimitive[];
    drawNavMesh(mesh: NavMesh, flags?: number): DebugDrawerPrimitive[];
    drawNavMeshWithClosedList(mesh: NavMesh, query: NavMeshQuery, flags?: number): DebugDrawerPrimitive[];
    drawNavMeshNodes(query: NavMeshQuery): DebugDrawerPrimitive[];
    drawNavMeshBVTree(mesh: NavMesh): DebugDrawerPrimitive[];
    drawNavMeshPortals(mesh: NavMesh): DebugDrawerPrimitive[];
    drawNavMeshPolysWithFlags(mesh: NavMesh, flags: number, col: number): DebugDrawerPrimitive[];
    drawNavMeshPoly(mesh: NavMesh, ref: number, col: number): DebugDrawerPrimitive[];
    /**
     * Disposes of the debug drawer and releases resources.
     */
    dispose(): void;
    private vertex;
}
/**
 * Converts a color in 0xRRGGBBAA format to a duRGBA format.
 */
export declare const rgbToDuRgba: (hexColor: number) => number;
