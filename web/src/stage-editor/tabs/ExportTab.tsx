import { useState, useMemo } from 'react';
import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import JSZip from 'jszip';
import type { UnifiedStageConfig, FloorTriangle, PortalData, SpawnPointData, TextureFix } from '../types';
import { STAGE_AREAS, getGlbPath, getAreaFromMapId } from '../constants';
import { DIRECTION_ROTATIONS, getPortalRotation } from '../types';
import { loadGlobalFixes } from './TextureTab';
import { loadAllConfigs } from '../useStageConfig';

// Helper to compute spawn and trigger positions from portal position and direction
// Matches PortalEditor's calculatePortalPositions offsets
function computePortalPositions(portal: PortalData): {
  gate: [number, number, number];
  spawn: [number, number, number];
  trigger: [number, number, number];
  rotation: number;
} {
  const [x, , z] = portal.position;
  const rotation = getPortalRotation(portal);

  // Match PortalOverlay's offsets:
  // Order from outside to inside: trigger -> spawn -> gate
  // - Trigger is 7 units outside (player hits this first when entering)
  // - Spawn is 3 units outside (player spawns behind gate)
  const spawnOutset = 3;
  const triggerOutset = 7;

  // Direction vectors based on rotation
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);

  return {
    gate: portal.position,
    // Spawn is outside the gate (player spawns behind gate)
    spawn: [x - sin * spawnOutset, 1, z - cos * spawnOutset],
    // Trigger is even further outside (player hits this first when entering), bottom at y=0
    trigger: [x - sin * triggerOutset, 0, z - cos * triggerOutset],
    rotation,
  };
}

// Gate dimensions (from PortalEditor)
const GATE_WIDTH = 6.0;
const GATE_HEIGHT = 1.5;
const GATE_DEPTH = 0.2;

interface ExportTabProps {
  config: UnifiedStageConfig;
  stageScene: THREE.Group | null;
  mapId: string;
}

// Extract floor triangles from scene
function extractFloorTriangles(scene: THREE.Object3D, yTolerance: number): FloorTriangle[] {
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

// Build textureFixes array from scene meshes + global fixes in localStorage
function buildTextureFixes(scene: THREE.Object3D): TextureFix[] {
  const globalFixes = loadGlobalFixes();
  if (Object.keys(globalFixes).length === 0) return [];

  // Scan scene for texture->mesh mappings, same pattern as TextureTab's extractTextures
  const textureInstanceCounts: Record<string, number> = {};
  const keyToMeshNames: Record<string, string[]> = {};
  const keyToFilename: Record<string, string> = {};

  scene.traverse((object) => {
    if (!(object as THREE.Mesh).isMesh) return;
    const mesh = object as THREE.Mesh;
    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];

    materials.forEach((mat) => {
      const m = mat as any;
      if (m.map && m.map instanceof THREE.Texture) {
        let filename = 'unknown';
        if (m.map.name) {
          const parts = m.map.name.split('/');
          filename = parts[parts.length - 1];
        } else if (m.map.image?.src) {
          const parts = m.map.image.src.split('/');
          filename = parts[parts.length - 1];
        }

        textureInstanceCounts[filename] = (textureInstanceCounts[filename] || 0) + 1;
        const instanceNum = textureInstanceCounts[filename];
        const key = `${filename}#${instanceNum}`;

        keyToFilename[key] = filename;
        if (!keyToMeshNames[key]) keyToMeshNames[key] = [];
        keyToMeshNames[key].push(mesh.name);
      }
    });
  });

  // Match each texture key against global fixes
  const fixes: TextureFix[] = [];
  for (const [key, fix] of Object.entries(globalFixes)) {
    if (!keyToFilename[key]) continue;

    // Skip entries that are all defaults
    const isDefault =
      fix.repeatX === 1 && fix.repeatY === 1 &&
      fix.offsetX === 0 && fix.offsetY === 0 &&
      (!fix.wrapS || fix.wrapS === 'repeat') &&
      (!fix.wrapT || fix.wrapT === 'repeat');
    if (isDefault) continue;

    const entry: TextureFix = {
      textureFile: keyToFilename[key],
      meshNames: keyToMeshNames[key] || [],
      repeatX: fix.repeatX,
      repeatY: fix.repeatY,
      offsetX: fix.offsetX,
      offsetY: fix.offsetY,
    };
    if (fix.wrapS && fix.wrapS !== 'repeat') entry.wrapS = fix.wrapS;
    if (fix.wrapT && fix.wrapT !== 'repeat') entry.wrapT = fix.wrapT;
    fixes.push(entry);
  }

  return fixes;
}

// Convert MeshBasicMaterial to MeshLambertMaterial
function convertToLambert(scene: THREE.Object3D) {
  scene.traverse((obj) => {
    if (!(obj as THREE.Mesh).isMesh) return;
    const mesh = obj as THREE.Mesh;

    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const newMaterials = materials.map((mat) => {
      if (mat instanceof THREE.MeshBasicMaterial) {
        const lambert = new THREE.MeshLambertMaterial({
          color: mat.color,
          map: mat.map,
          transparent: mat.transparent,
          opacity: mat.opacity,
          side: mat.side,
          alphaTest: mat.alphaTest,
        });
        if (lambert.map) {
          lambert.map.colorSpace = THREE.SRGBColorSpace;
          lambert.map.needsUpdate = true;
        }
        return lambert;
      }
      return mat;
    });

    mesh.material = Array.isArray(mesh.material) ? newMaterials : newMaterials[0];
  });
}

// Strip skinning data to fix Blender import
function stripSkinningData(scene: THREE.Object3D) {
  scene.traverse((object) => {
    if ((object as THREE.SkinnedMesh).isSkinnedMesh) {
      const skinnedMesh = object as THREE.SkinnedMesh;
      skinnedMesh.skeleton = undefined as any;
      skinnedMesh.bindMatrix = undefined as any;
      skinnedMesh.bindMatrixInverse = undefined as any;
    }
    if ((object as THREE.Mesh).isMesh) {
      const mesh = object as THREE.Mesh;
      if (mesh.geometry) {
        mesh.geometry.deleteAttribute('skinIndex');
        mesh.geometry.deleteAttribute('skinWeight');
      }
    }
  });
}

// Create gate marker (box shape matching gate dimensions)
function createGateMarker(
  name: string,
  position: [number, number, number],
  rotation: number,
  color: number = 0x4a9eff
): THREE.Group {
  const group = new THREE.Group();
  group.name = name;
  group.position.set(...position);
  group.rotation.y = rotation;

  // Gate box
  const gateGeometry = new THREE.BoxGeometry(GATE_WIDTH, GATE_HEIGHT, GATE_DEPTH);
  const gateMaterial = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.5 });
  const gateMesh = new THREE.Mesh(gateGeometry, gateMaterial);
  gateMesh.name = `${name}_box`;
  group.add(gateMesh);

  // Gate wireframe
  const wireGeometry = new THREE.EdgesGeometry(gateGeometry);
  const wireMaterial = new THREE.LineBasicMaterial({ color });
  const wireframe = new THREE.LineSegments(wireGeometry, wireMaterial);
  wireframe.name = `${name}_wire`;
  group.add(wireframe);

  return group;
}

// Create spawn point marker (sphere with ring and direction arrow)
function createSpawnMarker(
  name: string,
  position: [number, number, number],
  rotation: number,
  color: number = 0x00ff00
): THREE.Group {
  const group = new THREE.Group();
  group.name = name;
  group.position.set(...position);

  // Main sphere
  const sphereGeometry = new THREE.SphereGeometry(0.8, 16, 16);
  const sphereMaterial = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7 });
  const sphere = new THREE.Mesh(sphereGeometry, sphereMaterial);
  sphere.name = `${name}_sphere`;
  group.add(sphere);

  // Ring around spawn point
  const ringGeometry = new THREE.RingGeometry(1, 1.3, 32);
  const ringMaterial = new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide });
  const ring = new THREE.Mesh(ringGeometry, ringMaterial);
  ring.rotation.x = -Math.PI / 2;
  ring.name = `${name}_ring`;
  group.add(ring);

  // Direction arrow (shows which way player faces)
  const arrowGroup = new THREE.Group();
  arrowGroup.rotation.y = rotation;

  // Arrow shaft
  const shaftGeometry = new THREE.BoxGeometry(0.2, 0.2, 1.5);
  const shaftMaterial = new THREE.MeshBasicMaterial({ color });
  const shaft = new THREE.Mesh(shaftGeometry, shaftMaterial);
  shaft.position.set(0, 0.3, 1);
  shaft.name = `${name}_shaft`;
  arrowGroup.add(shaft);

  // Arrow head
  const headGeometry = new THREE.ConeGeometry(0.4, 0.6, 8);
  const headMaterial = new THREE.MeshBasicMaterial({ color });
  const head = new THREE.Mesh(headGeometry, headMaterial);
  head.position.set(0, 0.3, 2);
  head.rotation.x = Math.PI / 2;
  head.name = `${name}_head`;
  arrowGroup.add(head);

  arrowGroup.name = `${name}_arrow`;
  group.add(arrowGroup);

  return group;
}

// Create trigger zone marker (box volume)
// Uses -area suffix for Godot Area3D auto-import
function createTriggerMarker(
  name: string,
  position: [number, number, number],
  rotation: number,
  color: number = 0xff6600
): THREE.Group {
  const group = new THREE.Group();
  group.name = name + '-area';
  group.position.set(...position);
  group.rotation.y = rotation;

  // Trigger box (matches gate width, 3 units tall, 2 units deep)
  const boxGeometry = new THREE.BoxGeometry(GATE_WIDTH, 3, 2);

  // Visible mesh (Godot strips -colonly meshes visually, and LINES aren't supported)
  const visMaterial = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.3 });
  const visMesh = new THREE.Mesh(boxGeometry, visMaterial);
  visMesh.position.y = 1.5;
  visMesh.name = `${name}_vis`;
  group.add(visMesh);

  // Collision mesh (Godot auto-imports as StaticBody3D)
  const colMaterial = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.0 });
  const colMesh = new THREE.Mesh(boxGeometry, colMaterial);
  colMesh.position.y = 1.5;
  colMesh.name = `${name}_box-colonly`;
  group.add(colMesh);

  return group;
}

// Generate SVG minimap
function generateSvgMinimap(
  triangles: FloorTriangle[],
  config: UnifiedStageConfig,
  padding: number = 20
): string {
  if (triangles.length === 0) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50" y="50" text-anchor="middle" fill="#666">No floor data</text></svg>';
  }

  // Calculate bounds
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  triangles.forEach((tri) => {
    tri.vertices.forEach((v) => {
      minX = Math.min(minX, v.x);
      maxX = Math.max(maxX, v.x);
      minZ = Math.min(minZ, v.z);
      maxZ = Math.max(maxZ, v.z);
    });
  });

  const width = maxX - minX;
  const height = maxZ - minZ;
  const svgWidth = 400;
  const svgHeight = 400;
  const scale = Math.min((svgWidth - padding * 2) / width, (svgHeight - padding * 2) / height);

  // Transform functions
  const toSvgX = (x: number) => (x - minX) * scale + padding;
  const toSvgY = (z: number) => (z - minZ) * scale + padding;

  // Build triangle paths
  const trianglePaths = triangles
    .map((tri) => {
      const points = tri.vertices.map((v) => `${toSvgX(v.x).toFixed(1)},${toSvgY(v.z).toFixed(1)}`);
      return `M ${points.join(' L ')} Z`;
    })
    .join(' ');

  // Find boundary edges (edges shared by only 1 triangle)
  const edgeMap = new Map<string, number>();
  const edgeVertices = new Map<string, [[number, number], [number, number]]>();

  triangles.forEach((tri) => {
    const verts = tri.vertices.map((v) => [v.x, v.z] as [number, number]);
    for (let i = 0; i < 3; i++) {
      const v1 = verts[i];
      const v2 = verts[(i + 1) % 3];
      // Create consistent key regardless of order
      const key =
        v1[0] < v2[0] || (v1[0] === v2[0] && v1[1] < v2[1])
          ? `${v1[0].toFixed(3)},${v1[1].toFixed(3)}-${v2[0].toFixed(3)},${v2[1].toFixed(3)}`
          : `${v2[0].toFixed(3)},${v2[1].toFixed(3)}-${v1[0].toFixed(3)},${v1[1].toFixed(3)}`;
      edgeMap.set(key, (edgeMap.get(key) || 0) + 1);
      edgeVertices.set(key, [v1, v2]);
    }
  });

  // Build boundary path
  const boundaryEdges: string[] = [];
  edgeMap.forEach((count, key) => {
    if (count === 1) {
      const [v1, v2] = edgeVertices.get(key)!;
      boundaryEdges.push(
        `M ${toSvgX(v1[0]).toFixed(1)},${toSvgY(v1[1]).toFixed(1)} L ${toSvgX(v2[0]).toFixed(1)},${toSvgY(v2[1]).toFixed(1)}`
      );
    }
  });

  // Gate markers - use single color since gate type is determined at runtime
  const gateMarkers = config.portals
    .map((portal) => {
      const x = toSvgX(portal.position[0]);
      const y = toSvgY(portal.position[2]);
      const color = '#4a9eff'; // Single color for all portals
      // Diamond shape
      const size = 8;
      return `<polygon points="${x},${y - size} ${x + size},${y} ${x},${y + size} ${x - size},${y}" fill="${color}" stroke="white" stroke-width="1"/>`;
    })
    .join('\n');

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${svgWidth} ${svgHeight}">
  <rect width="${svgWidth}" height="${svgHeight}" fill="#1a1a2e"/>
  <path d="${trianglePaths}" fill="#2a2a4e" stroke="none"/>
  <path d="${boundaryEdges.join(' ')}" fill="none" stroke="white" stroke-width="2" stroke-linecap="round"/>
  ${gateMarkers}
</svg>`;
}

// Build export scene from loaded GLB and config
async function buildExportScene(
  scene: THREE.Group,
  stageConfig: UnifiedStageConfig,
  options: { useLambert: boolean; includeCollision: boolean; includeObstacles: boolean; includeMarkers: boolean }
): Promise<{ exportScene: THREE.Group; floorTriangles: FloorTriangle[] }> {
  const exportScene = new THREE.Group();
  exportScene.name = stageConfig.mapId;

  // Clone and process visual mesh
  const visualMesh = scene.clone();
  visualMesh.name = 'terrain_visual';

  // Strip skinning data
  stripSkinningData(visualMesh);

  // Convert to Lambert if enabled
  if (options.useLambert) {
    convertToLambert(visualMesh);
  }

  exportScene.add(visualMesh);

  // Extract floor triangles
  const extracted = extractFloorTriangles(scene, stageConfig.floorCollision.yTolerance);
  const floorTriangles = extracted.filter((tri) => stageConfig.floorCollision.triangles[tri.id] !== false);

  // Add collision floor mesh
  if (options.includeCollision && floorTriangles.length > 0) {
    const collisionGeometry = new THREE.BufferGeometry();
    const vertices: number[] = [];

    floorTriangles.forEach((tri) => {
      tri.vertices.forEach((v) => {
        vertices.push(v.x, v.y, v.z);
      });
    });

    collisionGeometry.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
    collisionGeometry.computeVertexNormals();

    const collisionMaterial = new THREE.MeshBasicMaterial({
      color: 0x00ff00,
      transparent: true,
      opacity: 0.3,
      side: THREE.DoubleSide,
    });

    const collisionMesh = new THREE.Mesh(collisionGeometry, collisionMaterial);
    collisionMesh.name = 'collision_floor-colonly';
    exportScene.add(collisionMesh);
  }

  // Add obstacle collision volumes
  if (options.includeObstacles && stageConfig.obstacles.length > 0) {
    const obstaclesGroup = new THREE.Group();
    obstaclesGroup.name = 'collision_obstacles';

    stageConfig.obstacles.forEach((obs) => {
      let geometry: THREE.BufferGeometry;
      if (obs.type === 'box') {
        geometry = new THREE.BoxGeometry(obs.width || 1, obs.height || 1, obs.depth || 1);
      } else {
        geometry = new THREE.CylinderGeometry(obs.radius || 1, obs.radius || 1, obs.cylinderHeight || 1, 16);
      }

      const material = new THREE.MeshBasicMaterial({ color: 0xff0000, transparent: true, opacity: 0.3 });
      const mesh = new THREE.Mesh(geometry, material);
      // Add -colonly suffix for Godot auto-collision import
      mesh.name = obs.label.replace(/\s+/g, '_').toLowerCase() + '-colonly';
      mesh.position.set(...obs.position);
      mesh.rotation.set(...obs.rotation);
      obstaclesGroup.add(mesh);
    });

    exportScene.add(obstaclesGroup);
  }

  // Add portal markers with full debug geometry
  if (options.includeMarkers) {
    const portalsGroup = new THREE.Group();
    portalsGroup.name = 'portals';

    stageConfig.portals.forEach((portal) => {
      const positions = computePortalPositions(portal);
      const labelSlug = portal.label.replace(/\s+/g, '_').toLowerCase();

      // Gate marker (blue box at gate position)
      const gateMarker = createGateMarker(
        `gate_${labelSlug}`,
        positions.gate,
        positions.rotation
      );
      portalsGroup.add(gateMarker);

      // Spawn marker (green sphere with direction arrow)
      const spawnMarker = createSpawnMarker(
        `spawn_${labelSlug}`,
        positions.spawn,
        positions.rotation
      );
      portalsGroup.add(spawnMarker);

      // Trigger marker (orange box volume)
      const triggerMarker = createTriggerMarker(
        `trigger_${labelSlug}`,
        positions.trigger,
        positions.rotation
      );
      portalsGroup.add(triggerMarker);
    });

    // Export default spawn point (for boss rooms / gateless areas)
    if (stageConfig.defaultSpawn) {
      const rotation = DIRECTION_ROTATIONS[stageConfig.defaultSpawn.direction];
      const pos: [number, number, number] = [
        stageConfig.defaultSpawn.position[0],
        1, // Match portal spawn height so marker is above ground
        stageConfig.defaultSpawn.position[2],
      ];
      const spawnMarker = createSpawnMarker(
        'spawn_default',
        pos,
        rotation,
        0xffff00 // Yellow to distinguish from portal spawns
      );
      portalsGroup.add(spawnMarker);
    }

    exportScene.add(portalsGroup);
  }

  return { exportScene, floorTriangles };
}

export default function ExportTab({ config, stageScene, mapId }: ExportTabProps) {
  const [exportStatus, setExportStatus] = useState<string>('');
  const [useLambert, setUseLambert] = useState(true);
  const [includeCollision, setIncludeCollision] = useState(true);
  const [includeMarkers, setIncludeMarkers] = useState(true);
  const [includeObstacles, setIncludeObstacles] = useState(true);
  const [isExportingAll, setIsExportingAll] = useState(false);
  const [exportAllProgress, setExportAllProgress] = useState<{ current: number; total: number; mapId: string } | null>(null);

  // Extract floor triangles
  const floorTriangles = useMemo(() => {
    if (!stageScene) return [];
    const extracted = extractFloorTriangles(stageScene, config.floorCollision.yTolerance);
    // Apply include/exclude from config
    return extracted.filter((tri) => config.floorCollision.triangles[tri.id] !== false);
  }, [stageScene, config.floorCollision]);

  // Generate SVG preview
  const svgPreview = useMemo(() => {
    return generateSvgMinimap(floorTriangles, config);
  }, [floorTriangles, config]);

  // Export GLB
  const exportGlb = async () => {
    if (!stageScene) {
      setExportStatus('Error: No scene loaded');
      return;
    }

    setExportStatus('Exporting GLB...');

    try {
      // Clone scene for export
      const exportScene = new THREE.Group();
      exportScene.name = mapId;

      // Clone and process visual mesh
      const visualMesh = stageScene.clone();
      visualMesh.name = 'terrain_visual';

      // Strip skinning data
      stripSkinningData(visualMesh);

      // Convert to Lambert if enabled
      if (useLambert) {
        convertToLambert(visualMesh);
      }

      exportScene.add(visualMesh);

      // Add collision floor mesh
      if (includeCollision && floorTriangles.length > 0) {
        const collisionGeometry = new THREE.BufferGeometry();
        const vertices: number[] = [];

        floorTriangles.forEach((tri) => {
          tri.vertices.forEach((v) => {
            vertices.push(v.x, v.y, v.z);
          });
        });

        collisionGeometry.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
        collisionGeometry.computeVertexNormals();

        const collisionMaterial = new THREE.MeshBasicMaterial({
          color: 0x00ff00,
          transparent: true,
          opacity: 0.3,
          side: THREE.DoubleSide,
        });

        const collisionMesh = new THREE.Mesh(collisionGeometry, collisionMaterial);
        collisionMesh.name = 'collision_floor-colonly';
        exportScene.add(collisionMesh);
      }

      // Add obstacle collision volumes
      if (includeObstacles && config.obstacles.length > 0) {
        const obstaclesGroup = new THREE.Group();
        obstaclesGroup.name = 'collision_obstacles';

        config.obstacles.forEach((obs) => {
          let geometry: THREE.BufferGeometry;
          if (obs.type === 'box') {
            geometry = new THREE.BoxGeometry(obs.width || 1, obs.height || 1, obs.depth || 1);
          } else {
            geometry = new THREE.CylinderGeometry(
              obs.radius || 1,
              obs.radius || 1,
              obs.cylinderHeight || 1,
              16
            );
          }

          const material = new THREE.MeshBasicMaterial({
            color: 0xff0000,
            transparent: true,
            opacity: 0.3,
          });

          const mesh = new THREE.Mesh(geometry, material);
          // Add -colonly suffix for Godot auto-collision import
          mesh.name = obs.label.replace(/\s+/g, '_').toLowerCase() + '-colonly';
          mesh.position.set(...obs.position);
          mesh.rotation.set(...obs.rotation);

          obstaclesGroup.add(mesh);
        });

        exportScene.add(obstaclesGroup);
      }

      // Add portal markers with full debug geometry
      if (includeMarkers) {
        const portalsGroup = new THREE.Group();
        portalsGroup.name = 'portals';

        config.portals.forEach((portal) => {
          const positions = computePortalPositions(portal);
          const labelSlug = portal.label.replace(/\s+/g, '_').toLowerCase();

          // Gate marker (blue box at gate position)
          const gateMarker = createGateMarker(
            `gate_${labelSlug}`,
            positions.gate,
            positions.rotation
          );
          portalsGroup.add(gateMarker);

          // Spawn marker (green sphere with direction arrow)
          const spawnMarker = createSpawnMarker(
            `spawn_${labelSlug}`,
            positions.spawn,
            positions.rotation
          );
          portalsGroup.add(spawnMarker);

          // Trigger marker (orange box volume)
          const triggerMarker = createTriggerMarker(
            `trigger_${labelSlug}`,
            positions.trigger,
            positions.rotation
          );
          portalsGroup.add(triggerMarker);
        });

        // Export default spawn point (for boss rooms / gateless areas)
        if (config.defaultSpawn) {
          const rotation = DIRECTION_ROTATIONS[config.defaultSpawn.direction];
          const pos: [number, number, number] = [
            config.defaultSpawn.position[0],
            1, // Match portal spawn height so marker is above ground
            config.defaultSpawn.position[2],
          ];
          const spawnMarker = createSpawnMarker(
            'spawn_default',
            pos,
            rotation,
            0xffff00 // Yellow to distinguish from portal spawns
          );
          portalsGroup.add(spawnMarker);
        }

        exportScene.add(portalsGroup);
      }

      // Export using GLTFExporter
      const exporter = new GLTFExporter();
      const glb = await new Promise<ArrayBuffer>((resolve, reject) => {
        exporter.parse(
          exportScene,
          (result) => resolve(result as ArrayBuffer),
          reject,
          { binary: true }
        );
      });

      // Download
      const blob = new Blob([glb], { type: 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `${mapId}.glb`;
      link.click();
      URL.revokeObjectURL(url);

      setExportStatus(`Exported ${mapId}.glb (${(glb.byteLength / 1024).toFixed(1)} KB)`);
    } catch (error) {
      setExportStatus(`Export error: ${error}`);
      console.error('Export error:', error);
    }
  };

  // Export SVG
  const exportSvg = () => {
    const blob = new Blob([svgPreview], { type: 'image/svg+xml' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${mapId}_minimap.svg`;
    link.click();
    URL.revokeObjectURL(url);
    setExportStatus(`Exported ${mapId}_minimap.svg`);
  };

  // Export config JSON
  const exportConfig = () => {
    const textureFixes = stageScene ? buildTextureFixes(stageScene) : config.textureFixes;
    const exportData = {
      ...config,
      textureFixes,
      exportedAt: new Date().toISOString(),
    };
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${mapId}_config.json`;
    link.click();
    URL.revokeObjectURL(url);
    setExportStatus(`Exported ${mapId}_config.json`);
  };

  // Export All - loop through all configured stages and export to zip
  const exportAll = async () => {
    setIsExportingAll(true);
    setExportStatus('Starting bulk export...');

    try {
      const zip = new JSZip();
      const savedConfigs = loadAllConfigs();
      const configuredMapIds = Object.keys(savedConfigs);

      if (configuredMapIds.length === 0) {
        setExportStatus('No configured maps found');
        setIsExportingAll(false);
        return;
      }

      const loader = new GLTFLoader();
      const exporter = new GLTFExporter();
      const options = { useLambert, includeCollision, includeObstacles, includeMarkers };

      let successCount = 0;
      let errorCount = 0;

      for (let i = 0; i < configuredMapIds.length; i++) {
        const currentMapId = configuredMapIds[i];
        const stageConfig = savedConfigs[currentMapId];

        setExportAllProgress({ current: i + 1, total: configuredMapIds.length, mapId: currentMapId });

        try {
          // Get GLB path for this map
          const areaKey = getAreaFromMapId(currentMapId);
          if (!areaKey) {
            console.warn(`Unknown area for map: ${currentMapId}`);
            errorCount++;
            continue;
          }

          const glbPath = getGlbPath(areaKey, currentMapId);

          // Load the GLB
          const gltf = await new Promise<any>((resolve, reject) => {
            loader.load(glbPath, resolve, undefined, reject);
          });

          const scene = gltf.scene as THREE.Group;

          // Build export scene
          const { exportScene, floorTriangles: tris } = await buildExportScene(scene, stageConfig, options);

          // Export GLB
          const glb = await new Promise<ArrayBuffer>((resolve, reject) => {
            exporter.parse(exportScene, (result) => resolve(result as ArrayBuffer), reject, { binary: true });
          });

          // Generate SVG
          const svg = generateSvgMinimap(tris, stageConfig);

          // Generate config JSON (populate textureFixes from scene + global fixes)
          const textureFixes = buildTextureFixes(scene);
          const configJson = JSON.stringify({ ...stageConfig, textureFixes, exportedAt: new Date().toISOString() }, null, 2);

          // Add to zip (organized by area)
          const folder = zip.folder(areaKey) || zip;
          folder.file(`${currentMapId}.glb`, glb);
          folder.file(`${currentMapId}_minimap.svg`, svg);
          folder.file(`${currentMapId}_config.json`, configJson);

          successCount++;

          // Cleanup
          scene.traverse((obj) => {
            const mesh = obj as THREE.Mesh;
            if (mesh.geometry) mesh.geometry.dispose();
            if (mesh.material) {
              const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
              materials.forEach((m) => {
                if (m && typeof (m as any).dispose === 'function') {
                  (m as any).dispose();
                }
              });
            }
          });
        } catch (err) {
          console.error(`Failed to export ${currentMapId}:`, err);
          errorCount++;
        }
      }

      // Generate and download zip
      setExportStatus('Generating zip file...');
      const zipBlob = await zip.generateAsync({ type: 'blob' });
      const url = URL.createObjectURL(zipBlob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `stage-exports-${new Date().toISOString().slice(0, 10)}.zip`;
      link.click();
      URL.revokeObjectURL(url);

      setExportStatus(`Exported ${successCount} maps (${errorCount} errors) to zip`);
    } catch (error) {
      setExportStatus(`Export all error: ${error}`);
      console.error('Export all error:', error);
    } finally {
      setIsExportingAll(false);
      setExportAllProgress(null);
    }
  };

  // Count configured maps
  const configuredMapsCount = useMemo(() => {
    return Object.keys(loadAllConfigs()).length;
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>Export</h3>

      {/* Export options */}
      <div
        style={{
          padding: '12px',
          background: '#1a1a2e',
          borderRadius: '4px',
        }}
      >
        <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>GLB Options</h4>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '8px',
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={useLambert}
            onChange={(e) => setUseLambert(e.target.checked)}
          />
          <span style={{ fontSize: '12px' }}>Convert to Lambert materials</span>
        </label>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '8px',
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={includeCollision}
            onChange={(e) => setIncludeCollision(e.target.checked)}
          />
          <span style={{ fontSize: '12px' }}>Include collision_floor mesh</span>
        </label>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '8px',
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={includeObstacles}
            onChange={(e) => setIncludeObstacles(e.target.checked)}
          />
          <span style={{ fontSize: '12px' }}>Include collision_obstacles group</span>
        </label>

        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            cursor: 'pointer',
          }}
        >
          <input
            type="checkbox"
            checked={includeMarkers}
            onChange={(e) => setIncludeMarkers(e.target.checked)}
          />
          <span style={{ fontSize: '12px' }}>Include gate/spawn/trigger markers</span>
        </label>
      </div>

      {/* Stats */}
      <div
        style={{
          padding: '12px',
          background: '#1a1a2e',
          borderRadius: '4px',
          fontSize: '12px',
        }}
      >
        <div>Floor triangles: {floorTriangles.length}</div>
        <div>Portals: {config.portals.length}</div>
        <div>Obstacles: {config.obstacles.length}</div>
        <div>Texture fixes: {config.textureFixes.length}</div>
      </div>

      {/* Export buttons */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        <button
          onClick={exportGlb}
          disabled={!stageScene}
          style={{
            padding: '12px',
            background: stageScene ? '#4a9eff' : '#333',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: stageScene ? 'pointer' : 'not-allowed',
            fontWeight: 'bold',
            fontSize: '14px',
          }}
        >
          Export GLB
        </button>

        <button
          onClick={exportSvg}
          disabled={floorTriangles.length === 0}
          style={{
            padding: '12px',
            background: floorTriangles.length > 0 ? '#4a4' : '#333',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: floorTriangles.length > 0 ? 'pointer' : 'not-allowed',
            fontWeight: 'bold',
            fontSize: '14px',
          }}
        >
          Export SVG Minimap
        </button>

        <button
          onClick={exportConfig}
          style={{
            padding: '12px',
            background: '#555',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
            fontWeight: 'bold',
            fontSize: '14px',
          }}
        >
          Export Config JSON
        </button>
      </div>

      {/* Export All Section */}
      <div
        style={{
          padding: '12px',
          background: '#1a1a2e',
          borderRadius: '4px',
          borderTop: '2px solid #4a9eff',
        }}
      >
        <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#888' }}>
          Bulk Export ({configuredMapsCount} configured maps)
        </h4>

        {exportAllProgress && (
          <div style={{ marginBottom: '12px' }}>
            <div style={{ fontSize: '11px', color: '#888', marginBottom: '4px' }}>
              {exportAllProgress.current}/{exportAllProgress.total}: {exportAllProgress.mapId}
            </div>
            <div
              style={{
                width: '100%',
                height: '4px',
                background: '#333',
                borderRadius: '2px',
                overflow: 'hidden',
              }}
            >
              <div
                style={{
                  width: `${(exportAllProgress.current / exportAllProgress.total) * 100}%`,
                  height: '100%',
                  background: '#4a9eff',
                  transition: 'width 0.2s',
                }}
              />
            </div>
          </div>
        )}

        <button
          onClick={exportAll}
          disabled={isExportingAll || configuredMapsCount === 0}
          style={{
            width: '100%',
            padding: '12px',
            background: isExportingAll ? '#333' : configuredMapsCount > 0 ? '#9e4aff' : '#333',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: isExportingAll || configuredMapsCount === 0 ? 'not-allowed' : 'pointer',
            fontWeight: 'bold',
            fontSize: '14px',
          }}
        >
          {isExportingAll ? 'Exporting...' : 'Export All to ZIP'}
        </button>

        <p style={{ margin: '8px 0 0 0', fontSize: '10px', color: '#666' }}>
          Exports GLB, SVG minimap, and config JSON for each configured map
        </p>
      </div>

      {/* Status */}
      {exportStatus && (
        <div
          style={{
            padding: '8px 12px',
            background: exportStatus.startsWith('Error') ? '#4a2' : '#1a1a2e',
            borderRadius: '4px',
            fontSize: '12px',
            color: exportStatus.startsWith('Error') ? '#f88' : '#8f8',
          }}
        >
          {exportStatus}
        </div>
      )}

      {/* SVG Preview */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Minimap Preview:
        </label>
        <div
          style={{
            background: '#1a1a2e',
            borderRadius: '4px',
            padding: '8px',
            display: 'flex',
            justifyContent: 'center',
          }}
          dangerouslySetInnerHTML={{ __html: svgPreview }}
        />
      </div>

      {/* GLB Structure Documentation */}
      <div
        style={{
          padding: '12px',
          background: '#1a1a2e',
          borderRadius: '4px',
          fontSize: '11px',
          color: '#ccc',
        }}
      >
        <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#4a9eff' }}>
          GLB Structure
        </h4>

        <div style={{ marginBottom: '12px' }}>
          <div style={{ color: '#888', marginBottom: '4px' }}>Components (Godot-compatible naming):</div>
          <pre style={{ margin: 0, fontSize: '10px', color: '#aaa', lineHeight: '1.6' }}>
{`terrain_visual          - Stage mesh with Lambert materials
collision_floor-colonly - Walkable floor (-> StaticBody3D)
collision_obstacles/
  *-colonly             - Blocking volumes (-> StaticBody3D)
portals/
  gate_*                - Gate position + dimensions
  spawn_*               - Player spawn point + direction
  trigger_*-area        - Warp trigger zone (-> Area3D)`}
          </pre>
        </div>

        <div style={{ marginBottom: '12px' }}>
          <div style={{ color: '#888', marginBottom: '4px' }}>Loading in Three.js:</div>
          <pre style={{ margin: 0, fontSize: '10px', color: '#aaa', lineHeight: '1.6', overflowX: 'auto' }}>
{`const { scene } = useGLTF('/path/to/stage.glb');

// Visual mesh (has Lambert materials)
const terrain = scene.getObjectByName('terrain_visual');

// Floor collision mesh
const floor = scene.getObjectByName('collision_floor-colonly');

// Obstacles group
const obstacles = scene.getObjectByName('collision_obstacles');

// Find all triggers (now with -area suffix)
const triggers = [];
scene.traverse((obj) => {
  if (obj.name.includes('trigger_') && obj.name.endsWith('-area')) {
    triggers.push(obj);
  }
});`}
          </pre>
        </div>

        <div style={{ marginBottom: '12px' }}>
          <div style={{ color: '#888', marginBottom: '4px' }}>Loading in Godot (auto-imported):</div>
          <pre style={{ margin: 0, fontSize: '10px', color: '#aaa', lineHeight: '1.6', overflowX: 'auto' }}>
{`# -colonly meshes become StaticBody3D with collision
var floor = $"collision_floor-colonly"  # StaticBody3D

# -area groups become Area3D nodes
var trigger = $"portals/trigger_north-area"  # Area3D
trigger.body_entered.connect(_on_trigger_entered)`}
          </pre>
        </div>

        <div style={{ marginBottom: '12px' }}>
          <div style={{ color: '#888', marginBottom: '4px' }}>Marker Dimensions:</div>
          <pre style={{ margin: 0, fontSize: '10px', color: '#aaa', lineHeight: '1.6' }}>
{`gate_*     - Box: 6.0w x 1.5h x 0.2d
spawn_*    - Sphere r=0.8, Ring r=1.0-1.3
trigger_*  - Box: 6.0w x 3.0h x 2.0d`}
          </pre>
        </div>

        <div>
          <div style={{ color: '#888', marginBottom: '4px' }}>Position Layout:</div>
          <pre style={{ margin: 0, fontSize: '10px', color: '#aaa', lineHeight: '1.6' }}>
{`Outside <-------------------------------> Inside
         trigger (7u)  spawn (3u)  gate
              ^           ^         ^
         player      player    visual
         enters      spawns     gate`}
          </pre>
        </div>
      </div>

      {/* Instructions */}
      <div style={{ fontSize: '11px', color: '#666', marginTop: '8px' }}>
        <p style={{ margin: '4px 0' }}>GLB includes visual mesh, collision, and markers</p>
        <p style={{ margin: '4px 0' }}>Lambert materials respond to scene lighting</p>
        <p style={{ margin: '4px 0' }}>SVG minimap shows floor outline and gate positions</p>
        <p style={{ margin: '4px 0' }}>Config JSON saves all editor settings</p>
      </div>
    </div>
  );
}
