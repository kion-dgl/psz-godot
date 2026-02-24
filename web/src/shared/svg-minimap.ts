/**
 * Shared SVG minimap generation utilities.
 * Extracted from stage-editor/tabs/ExportTab.tsx for reuse.
 */
import * as THREE from 'three';
import type { FloorTriangle, UnifiedStageConfig } from '../stage-editor/types';
import { rotateDirection } from '../quest-editor/hooks/useStageConfigs';
import type { Direction } from '../quest-editor/types';

/** Extract floor triangles from a Three.js scene */
export function extractFloorTriangles(scene: THREE.Object3D, yTolerance: number): FloorTriangle[] {
  const triangles: FloorTriangle[] = [];
  let triangleId = 0;

  scene.traverse((object) => {
    if (!(object as THREE.Mesh).isMesh) return;

    const mesh = object as THREE.Mesh;
    const geometry = mesh.geometry;
    const positions = geometry.attributes.position;
    const index = geometry.index;

    if (!positions) return;

    const material = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
    let textureName = 'unknown';
    if ((material as any).map?.name) {
      textureName = (material as any).map.name;
    }

    const processTriangle = (i0: number, i1: number, i2: number) => {
      const v0 = new THREE.Vector3(positions.getX(i0), positions.getY(i0), positions.getZ(i0));
      const v1 = new THREE.Vector3(positions.getX(i1), positions.getY(i1), positions.getZ(i1));
      const v2 = new THREE.Vector3(positions.getX(i2), positions.getY(i2), positions.getZ(i2));

      v0.applyMatrix4(mesh.matrixWorld);
      v1.applyMatrix4(mesh.matrixWorld);
      v2.applyMatrix4(mesh.matrixWorld);

      if (
        Math.abs(v0.y) < yTolerance &&
        Math.abs(v1.y) < yTolerance &&
        Math.abs(v2.y) < yTolerance
      ) {
        const edge1 = new THREE.Vector3().subVectors(v1, v0);
        const edge2 = new THREE.Vector3().subVectors(v2, v0);
        const area = new THREE.Vector3().crossVectors(edge1, edge2).length() / 2;

        triangles.push({
          id: `tri_${triangleId++}`,
          vertices: [v0.clone(), v1.clone(), v2.clone()],
          meshName: mesh.name,
          textureName,
          included: true,
          area,
        });
      }
    };

    if (index) {
      for (let i = 0; i < index.count; i += 3) {
        processTriangle(index.getX(i), index.getX(i + 1), index.getX(i + 2));
      }
    } else {
      for (let i = 0; i < positions.count; i += 3) {
        processTriangle(i, i + 1, i + 2);
      }
    }
  });

  return triangles;
}

/** Apply config's triangle inclusion/exclusion and mesh pattern filters */
export function applyTriangleFilters(triangles: FloorTriangle[], config: UnifiedStageConfig): FloorTriangle[] {
  let result = triangles;

  if (config.floorCollision?.triangles) {
    result = result.filter((tri) => config.floorCollision.triangles[tri.id] !== false);
  }

  if (config.floorCollision?.excludedMeshPatterns?.length > 0) {
    const patterns = config.floorCollision.excludedMeshPatterns;
    result = result.filter((tri) => !patterns.some((p) => tri.meshName.includes(p)));
  }

  return result;
}

/** Generate SVG minimap with optional rotation (0, 90, 180, 270) */
export function generateSvgMinimap(
  triangles: FloorTriangle[],
  config: UnifiedStageConfig,
  rotation: number = 0,
  padding: number = 20
): string {
  if (triangles.length === 0) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="50" text-anchor="middle" fill="#666">No floor data</text></svg>';
  }

  const svgWidth = config.svgSettings?.svgSize ?? 400;
  const svgHeight = svgWidth;
  const svgPadding = config.svgSettings?.padding ?? padding;

  let minX: number, maxX: number, minZ: number, maxZ: number;
  if (config.svgSettings) {
    const halfGrid = config.svgSettings.gridSize / 2;
    minX = config.svgSettings.centerX - halfGrid;
    maxX = config.svgSettings.centerX + halfGrid;
    minZ = config.svgSettings.centerZ - halfGrid;
    maxZ = config.svgSettings.centerZ + halfGrid;
  } else {
    minX = Infinity; maxX = -Infinity; minZ = Infinity; maxZ = -Infinity;
    triangles.forEach((tri) => {
      tri.vertices.forEach((v) => {
        minX = Math.min(minX, v.x);
        maxX = Math.max(maxX, v.x);
        minZ = Math.min(minZ, v.z);
        maxZ = Math.max(maxZ, v.z);
      });
    });
  }

  const width = maxX - minX;
  const height = maxZ - minZ;
  const scale = Math.min((svgWidth - svgPadding * 2) / width, (svgHeight - svgPadding * 2) / height);

  // Normal X: east (+X) is right, west (-X) is left
  const toSvgX = (x: number) => (x - minX) * scale + svgPadding;
  const toSvgY = (z: number) => (z - minZ) * scale + svgPadding;

  const cx = svgWidth / 2;
  const cy = svgHeight / 2;

  // Triangle paths
  const trianglePaths = triangles
    .map((tri) => {
      const points = tri.vertices.map((v) => `${toSvgX(v.x).toFixed(1)},${toSvgY(v.z).toFixed(1)}`);
      return `M ${points.join(' L ')} Z`;
    })
    .join(' ');

  // Boundary edges (edges shared by only 1 triangle)
  const edgeMap = new Map<string, number>();
  const edgeVertices = new Map<string, [[number, number], [number, number]]>();

  triangles.forEach((tri) => {
    const verts = tri.vertices.map((v) => [v.x, v.z] as [number, number]);
    for (let i = 0; i < 3; i++) {
      const v1 = verts[i];
      const v2 = verts[(i + 1) % 3];
      const key =
        v1[0] < v2[0] || (v1[0] === v2[0] && v1[1] < v2[1])
          ? `${v1[0].toFixed(3)},${v1[1].toFixed(3)}-${v2[0].toFixed(3)},${v2[1].toFixed(3)}`
          : `${v2[0].toFixed(3)},${v2[1].toFixed(3)}-${v1[0].toFixed(3)},${v1[1].toFixed(3)}`;
      edgeMap.set(key, (edgeMap.get(key) || 0) + 1);
      edgeVertices.set(key, [v1, v2]);
    }
  });

  const boundaryEdges: string[] = [];
  edgeMap.forEach((count, key) => {
    if (count === 1) {
      const [v1, v2] = edgeVertices.get(key)!;
      boundaryEdges.push(
        `M ${toSvgX(v1[0]).toFixed(1)},${toSvgY(v1[1]).toFixed(1)} L ${toSvgX(v2[0]).toFixed(1)},${toSvgY(v2[1]).toFixed(1)}`
      );
    }
  });

  // Gate markers
  const gateMarkers = config.portals
    .map((portal) => {
      const x = toSvgX(portal.position[0]);
      const y = toSvgY(portal.position[2]);
      const isHorizontal = portal.direction === 'north' || portal.direction === 'south';
      const rectW = isHorizontal ? 48 : 8;
      const rectH = isHorizontal ? 8 : 48;

      // Use compass_label (visual truth, fixed) if set; otherwise fall back to rotated direction
      const gridDir = rotateDirection(portal.direction as Direction, rotation);
      const labelText = portal.compass_label ?? gridDir[0].toUpperCase();

      let labelX = x;
      let labelY = y;
      let anchor = 'middle';
      const labelOffset = 16;
      switch (portal.direction) {
        case 'north': labelY = y - labelOffset; break;
        case 'south': labelY = y + labelOffset + 8; break;
        case 'east': labelX = x + labelOffset + 4; anchor = 'start'; break;
        case 'west': labelX = x - labelOffset - 4; anchor = 'end'; break;
      }

      const gateId = portal.id || '';
      const rect = `<rect x="${(x - rectW / 2).toFixed(1)}" y="${(y - rectH / 2).toFixed(1)}" width="${rectW}" height="${rectH}" fill="#ff4444" stroke="white" stroke-width="1" data-gate="true" data-gate-id="${gateId}" data-gate-dir="${labelText}"/>`;
      const textRotate = rotation !== 0 ? ` transform="rotate(${-rotation}, ${labelX.toFixed(1)}, ${labelY.toFixed(1)})"` : '';
      const label = `<text x="${labelX.toFixed(1)}" y="${labelY.toFixed(1)}" text-anchor="${anchor}" font-size="18" font-weight="bold" fill="#ffaaaa" font-family="sans-serif"${textRotate}>${labelText}</text>`;
      return rect + '\n' + label;
    })
    .join('\n');

  // Invisible origin marker
  const originX = toSvgX(0);
  const originY = toSvgY(0);
  const originMarker = `<circle cx="${originX.toFixed(1)}" cy="${originY.toFixed(1)}" r="0" data-origin="true" fill="none"/>`;

  const offsetX = svgPadding - minX * scale;
  const offsetY = svgPadding - minZ * scale;

  // toSvgX(x) = x * scale + offsetX, toSvgY(z) = z * scale + offsetY
  const dataAttrs = `data-rotation="${rotation}" data-scale="${scale.toFixed(6)}" data-offset-x="${offsetX.toFixed(2)}" data-offset-y="${offsetY.toFixed(2)}" data-center-x="${cx.toFixed(1)}" data-center-y="${cy.toFixed(1)}"`;


  const rotateOpen = rotation !== 0 ? `<g transform="rotate(${rotation}, ${cx.toFixed(1)}, ${cy.toFixed(1)})">` : '';
  const rotateClose = rotation !== 0 ? '</g>' : '';

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${svgWidth} ${svgHeight}" ${dataAttrs}>
  <rect width="${svgWidth}" height="${svgHeight}" fill="#1a1a2e"/>
  ${rotateOpen}
  <path d="${trianglePaths}" fill="#2a2a4e" stroke="none"/>
  <path d="${boundaryEdges.join(' ')}" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
  ${gateMarkers}
  ${originMarker}
  ${rotateClose}
</svg>`;
}
