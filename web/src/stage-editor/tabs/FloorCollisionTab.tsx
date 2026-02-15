import { useState, useEffect, useMemo } from 'react';
import * as THREE from 'three';
import type { UnifiedStageConfig, FloorTriangle } from '../types';

interface FloorCollisionTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  stageScene: THREE.Group | null;
}

// Extract floor triangles from scene
function extractFloorTriangles(
  scene: THREE.Object3D,
  yTolerance: number,
  meshFilter: string
): FloorTriangle[] {
  const triangles: FloorTriangle[] = [];
  let triangleId = 0;

  scene.traverse((object) => {
    if (!(object as THREE.Mesh).isMesh) return;

    const mesh = object as THREE.Mesh;

    // Apply mesh filter if provided
    if (meshFilter && !mesh.name.toLowerCase().includes(meshFilter.toLowerCase())) {
      return;
    }

    const geometry = mesh.geometry;
    const positions = geometry.attributes.position;
    const index = geometry.index;

    if (!positions) return;

    // Get texture name from material
    const material = Array.isArray(mesh.material) ? mesh.material[0] : mesh.material;
    let textureName = 'unknown';
    if ((material as any).map?.name) {
      textureName = (material as any).map.name;
    } else if ((material as any).map?.image?.src) {
      const src = (material as any).map.image.src;
      const match = src.match(/\/([^/]+)\.(png|jpg)$/i);
      textureName = match ? match[1] : 'unknown';
    }

    const processTriangle = (i0: number, i1: number, i2: number) => {
      const v0 = new THREE.Vector3(positions.getX(i0), positions.getY(i0), positions.getZ(i0));
      const v1 = new THREE.Vector3(positions.getX(i1), positions.getY(i1), positions.getZ(i1));
      const v2 = new THREE.Vector3(positions.getX(i2), positions.getY(i2), positions.getZ(i2));

      // Transform to world space
      v0.applyMatrix4(mesh.matrixWorld);
      v1.applyMatrix4(mesh.matrixWorld);
      v2.applyMatrix4(mesh.matrixWorld);

      // Check if floor triangle (all vertices near y=0)
      if (
        Math.abs(v0.y) < yTolerance &&
        Math.abs(v1.y) < yTolerance &&
        Math.abs(v2.y) < yTolerance
      ) {
        // Calculate area
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

// Get unique mesh names from triangles
function getUniqueMeshNames(triangles: FloorTriangle[]): string[] {
  const names = new Set(triangles.map((t) => t.meshName));
  return Array.from(names).sort();
}

export default function FloorCollisionTab({
  config,
  updateConfig,
  stageScene,
}: FloorCollisionTabProps) {
  const [yTolerance, setYTolerance] = useState(config.floorCollision.yTolerance);
  const [meshFilter, setMeshFilter] = useState('');
  const [triangles, setTriangles] = useState<FloorTriangle[]>([]);
  const [selectedMesh, setSelectedMesh] = useState<string | null>(null);

  // Extract triangles when scene or tolerance changes
  useEffect(() => {
    if (!stageScene) return;

    const extracted = extractFloorTriangles(stageScene, yTolerance, meshFilter);

    // Apply saved include/exclude state
    extracted.forEach((tri) => {
      if (config.floorCollision.triangles[tri.id] === false) {
        tri.included = false;
      }
    });

    setTriangles(extracted);
  }, [stageScene, yTolerance, meshFilter, config.floorCollision.triangles]);

  // Get unique mesh names
  const meshNames = useMemo(() => getUniqueMeshNames(triangles), [triangles]);

  // Calculate stats
  const stats = useMemo(() => {
    const total = triangles.length;
    const included = triangles.filter((t) => t.included).length;
    const excluded = total - included;
    const totalArea = triangles.filter((t) => t.included).reduce((sum, t) => sum + t.area, 0);
    return { total, included, excluded, totalArea };
  }, [triangles]);

  // Handle tolerance change
  const handleToleranceChange = (value: number) => {
    setYTolerance(value);
    updateConfig((prev) => ({
      ...prev,
      floorCollision: {
        ...prev.floorCollision,
        yTolerance: value,
      },
    }));
  };

  // Toggle all triangles for a mesh
  const toggleMesh = (meshName: string, include: boolean) => {
    const meshTriangles = triangles.filter((t) => t.meshName === meshName);
    const updates: Record<string, boolean> = {};
    meshTriangles.forEach((t) => {
      updates[t.id] = include;
    });

    updateConfig((prev) => ({
      ...prev,
      floorCollision: {
        ...prev.floorCollision,
        triangles: {
          ...prev.floorCollision.triangles,
          ...updates,
        },
      },
    }));
  };

  // Include/exclude all triangles
  const setAllTriangles = (include: boolean) => {
    const updates: Record<string, boolean> = {};
    triangles.forEach((t) => {
      updates[t.id] = include;
    });

    updateConfig((prev) => ({
      ...prev,
      floorCollision: {
        ...prev.floorCollision,
        triangles: updates,
      },
    }));
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>
        Floor Collision
      </h3>

      {/* Y-Tolerance slider */}
      <div>
        <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px', color: '#888' }}>
          Y-Tolerance: {yTolerance.toFixed(2)}
        </label>
        <input
          type="range"
          min="0.1"
          max="1.0"
          step="0.05"
          value={yTolerance}
          onChange={(e) => handleToleranceChange(parseFloat(e.target.value))}
          style={{ width: '100%' }}
        />
      </div>

      {/* Mesh filter */}
      <div>
        <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px', color: '#888' }}>
          Mesh Name Filter:
        </label>
        <input
          type="text"
          value={meshFilter}
          onChange={(e) => setMeshFilter(e.target.value)}
          placeholder="Filter by mesh name..."
          style={{
            width: '100%',
            padding: '8px',
            background: '#1a1a2e',
            color: 'white',
            border: '1px solid #444',
            borderRadius: '4px',
          }}
        />
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
        <div>Total Triangles: {stats.total}</div>
        <div style={{ color: '#4a4' }}>Included: {stats.included}</div>
        <div style={{ color: '#a44' }}>Excluded: {stats.excluded}</div>
        <div>Total Area: {stats.totalArea.toFixed(2)} sq units</div>
      </div>

      {/* Bulk actions */}
      <div style={{ display: 'flex', gap: '8px' }}>
        <button
          onClick={() => setAllTriangles(true)}
          style={{
            flex: 1,
            padding: '8px',
            background: '#4a4',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
          }}
        >
          Include All
        </button>
        <button
          onClick={() => setAllTriangles(false)}
          style={{
            flex: 1,
            padding: '8px',
            background: '#a44',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
          }}
        >
          Exclude All
        </button>
      </div>

      {/* Mesh list */}
      <div>
        <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
          Meshes ({meshNames.length}):
        </label>
        <div
          style={{
            maxHeight: '300px',
            overflow: 'auto',
            background: '#1a1a2e',
            borderRadius: '4px',
          }}
        >
          {meshNames.map((name) => {
            const meshTris = triangles.filter((t) => t.meshName === name);
            const includedCount = meshTris.filter((t) => t.included).length;
            const isSelected = selectedMesh === name;

            return (
              <div
                key={name}
                onClick={() => setSelectedMesh(isSelected ? null : name)}
                style={{
                  padding: '8px 12px',
                  borderBottom: '1px solid #333',
                  cursor: 'pointer',
                  background: isSelected ? '#333' : 'transparent',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                }}
              >
                <span style={{ fontSize: '11px', fontFamily: 'monospace' }}>
                  {name || '(unnamed)'}
                </span>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                  <span style={{ fontSize: '10px', color: '#888' }}>
                    {includedCount}/{meshTris.length}
                  </span>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleMesh(name, true);
                    }}
                    style={{
                      padding: '2px 6px',
                      background: '#4a4',
                      color: 'white',
                      border: 'none',
                      borderRadius: '2px',
                      cursor: 'pointer',
                      fontSize: '10px',
                    }}
                  >
                    +
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleMesh(name, false);
                    }}
                    style={{
                      padding: '2px 6px',
                      background: '#a44',
                      color: 'white',
                      border: 'none',
                      borderRadius: '2px',
                      cursor: 'pointer',
                      fontSize: '10px',
                    }}
                  >
                    -
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Instructions */}
      <div style={{ fontSize: '11px', color: '#666', marginTop: '8px' }}>
        <p style={{ margin: '4px 0' }}>Click triangles in 3D view to toggle include/exclude</p>
        <p style={{ margin: '4px 0' }}>Green = included, Red = excluded</p>
        <p style={{ margin: '4px 0' }}>Adjust Y-tolerance to capture more/fewer floor triangles</p>
        <p style={{ margin: '4px 0' }}>Use +/- buttons to include/exclude entire meshes</p>
      </div>
    </div>
  );
}
