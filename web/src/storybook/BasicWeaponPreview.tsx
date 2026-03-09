import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, useGLTF } from '@react-three/drei';
import { Suspense, useState, useMemo, useEffect, useRef } from 'react';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';

// All basic weapon GLBs (no _bullet variants)
const BASIC_WEAPONS = [
  'Saber',
  'Sword',
  'Dagger',
  'Partisan',
  'Rod',
  'Handgun',
  'Mechgun',
  'Rifle',
  'Akiko',
  'Akiko Wok',
  'Anti-Android Rifle',
  'Orotiagito',
  'Yasminkov 2000h',
  'Yasminkov 3000r',
  'Yasminkov 7000v',
  'Yasminkov 9000m',
];

interface MaterialInfo {
  index: number;
  name: string;
  type: string;
  color: string;
  textureName: string | null;
  textureSize: string | null;
  blending: string;
  transparent: boolean;
  opacity: number;
  side: string;
  emissive: string | null;
}

interface MeshInfo {
  name: string;
  vertexCount: number;
  materials: MaterialInfo[];
}

function getGlbUrl(name: string): string {
  return assetUrl(`assets/weapons/basic/${name}.glb`);
}

function getSideLabel(side: THREE.Side): string {
  switch (side) {
    case THREE.FrontSide: return 'Front';
    case THREE.BackSide: return 'Back';
    case THREE.DoubleSide: return 'Double';
    default: return 'Unknown';
  }
}

function getBlendingLabel(blending: THREE.Blending): string {
  switch (blending) {
    case THREE.NoBlending: return 'None';
    case THREE.NormalBlending: return 'Normal';
    case THREE.AdditiveBlending: return 'Additive';
    case THREE.SubtractiveBlending: return 'Subtractive';
    case THREE.MultiplyBlending: return 'Multiply';
    case THREE.CustomBlending: return 'Custom';
    default: return 'Unknown';
  }
}

function colorToHex(color: THREE.Color): string {
  return '#' + color.getHexString();
}

function WeaponModel({ name, onMeshInfo, tintIndex, tintColor, additiveIndices }: {
  name: string;
  onMeshInfo: (info: MeshInfo[]) => void;
  tintIndex: number | null;
  tintColor: string;
  additiveIndices: Set<number>;
}) {
  const glbUrl = getGlbUrl(name);
  const { scene } = useGLTF(glbUrl);
  const reportedRef = useRef<string>('');

  const clonedScene = useMemo(() => {
    const clone = scene.clone();
    clone.traverse((obj) => {
      if (obj instanceof THREE.Mesh && obj.geometry) {
        obj.geometry.computeVertexNormals();
        // Deep clone materials so we can modify per-instance
        if (Array.isArray(obj.material)) {
          obj.material = obj.material.map((m: THREE.Material) => m.clone());
        } else {
          obj.material = obj.material.clone();
        }
      }
    });
    const box = new THREE.Box3().setFromObject(clone);
    const center = box.getCenter(new THREE.Vector3());
    clone.position.sub(center);
    return clone;
  }, [scene]);

  // Extract mesh/material info
  useEffect(() => {
    const key = name;
    if (reportedRef.current === key) return;
    reportedRef.current = key;

    const meshes: MeshInfo[] = [];
    clonedScene.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh)) return;
      const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
      const matInfos: MaterialInfo[] = materials.map((mat: THREE.Material, idx: number) => {
        const info: MaterialInfo = {
          index: idx,
          name: mat.name || `Material ${idx}`,
          type: mat.type,
          color: '#ffffff',
          textureName: null,
          textureSize: null,
          blending: getBlendingLabel(mat.blending),
          transparent: mat.transparent,
          opacity: mat.opacity,
          side: getSideLabel(mat.side),
          emissive: null,
        };
        if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial || mat instanceof THREE.MeshPhongMaterial) {
          info.color = colorToHex((mat as any).color || new THREE.Color(1, 1, 1));
          if ((mat as any).map) {
            const tex = (mat as any).map as THREE.Texture;
            info.textureName = tex.name || tex.image?.src?.split('/').pop() || 'unnamed';
            if (tex.image) {
              info.textureSize = `${tex.image.width}x${tex.image.height}`;
            }
          }
          if ('emissive' in mat && (mat as any).emissive) {
            const e = (mat as any).emissive as THREE.Color;
            if (e.r > 0 || e.g > 0 || e.b > 0) {
              info.emissive = colorToHex(e);
            }
          }
        }
        return info;
      });

      meshes.push({
        name: obj.name || 'Mesh',
        vertexCount: obj.geometry.attributes.position?.count || 0,
        materials: matInfos,
      });
    });
    onMeshInfo(meshes);
  }, [clonedScene, name, onMeshInfo]);

  // Apply tint and additive blending
  useEffect(() => {
    clonedScene.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh)) return;
      const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
      materials.forEach((mat: THREE.Material, idx: number) => {
        if (mat instanceof THREE.MeshStandardMaterial || mat instanceof THREE.MeshBasicMaterial) {
          // Reset to original first
          const origColor = mat.userData.origColor || (mat as any).color.clone();
          const origBlending = mat.userData.origBlending ?? mat.blending;
          const origTransparent = mat.userData.origTransparent ?? mat.transparent;
          const origDepthWrite = mat.userData.origDepthWrite ?? mat.depthWrite;
          if (!mat.userData.origColor) {
            mat.userData.origColor = origColor.clone();
            mat.userData.origBlending = origBlending;
            mat.userData.origTransparent = origTransparent;
            mat.userData.origDepthWrite = origDepthWrite;
          }

          // Apply tint
          if (tintIndex === idx) {
            (mat as any).color.set(tintColor);
          } else {
            (mat as any).color.copy(origColor);
          }

          // Apply additive blending
          if (additiveIndices.has(idx)) {
            mat.blending = THREE.AdditiveBlending;
            mat.transparent = true;
            mat.depthWrite = false;
          } else {
            mat.blending = origBlending;
            mat.transparent = origTransparent;
            mat.depthWrite = origDepthWrite;
          }
        }
      });
    });
  }, [clonedScene, tintIndex, tintColor, additiveIndices]);

  return <primitive object={clonedScene} />;
}

function AutoFit() {
  const { camera } = useThree();
  useEffect(() => {
    camera.position.set(1.5, 0.8, 1.5);
    camera.lookAt(0, 0, 0);
  }, [camera]);
  return null;
}

export default function BasicWeaponPreview() {
  const [selected, setSelected] = useState<string>(BASIC_WEAPONS[0]);
  const [meshInfo, setMeshInfo] = useState<MeshInfo[]>([]);
  const [tintIndex, setTintIndex] = useState<number | null>(null);
  const [tintColor, setTintColor] = useState('#00ff00');
  const [additiveIndices, setAdditiveIndices] = useState<Set<number>>(new Set());

  const handleMeshInfo = useMemo(() => (info: MeshInfo[]) => {
    setMeshInfo(info);
  }, []);

  const toggleAdditive = (idx: number) => {
    setAdditiveIndices((prev) => {
      const next = new Set(prev);
      if (next.has(idx)) next.delete(idx);
      else next.add(idx);
      return next;
    });
  };

  // Reset material overrides when weapon changes
  useEffect(() => {
    setTintIndex(null);
    setAdditiveIndices(new Set());
  }, [selected]);

  // Flatten all materials across meshes for display
  const allMaterials = useMemo(() => {
    const result: (MaterialInfo & { meshName: string })[] = [];
    for (const mesh of meshInfo) {
      for (const mat of mesh.materials) {
        result.push({ ...mat, meshName: mesh.name });
      }
    }
    return result;
  }, [meshInfo]);

  return (
    <div style={{
      width: '100%', height: '100%', background: '#0a0a12', color: 'white',
      display: 'flex', overflow: 'hidden',
    }}>
      {/* Weapon list */}
      <div style={{
        width: '200px', flexShrink: 0, borderRight: '1px solid #333',
        padding: '8px', overflowY: 'auto',
      }}>
        <h3 style={{ margin: '0 0 8px 0', fontSize: '12px', color: '#4a9eff' }}>
          PSO Weapons ({BASIC_WEAPONS.length})
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
          {BASIC_WEAPONS.map((name) => (
            <button
              key={name}
              onClick={() => setSelected(name)}
              style={{
                display: 'block', width: '100%', padding: '8px',
                background: selected === name ? '#2a3a5e' : 'transparent',
                border: selected === name ? '1px solid #4a9eff' : '1px solid transparent',
                borderRadius: '4px', cursor: 'pointer', textAlign: 'left',
                fontSize: '12px', color: selected === name ? '#fff' : '#ccc',
              }}
            >
              {name}
            </button>
          ))}
        </div>
      </div>

      {/* 3D Preview */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{
          padding: '8px 12px', background: '#111', borderBottom: '1px solid #333',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        }}>
          <span style={{ fontWeight: 'bold', fontSize: '16px' }}>{selected}</span>
          <span style={{ fontSize: '10px', color: '#666' }}>
            {meshInfo.reduce((sum, m) => sum + m.vertexCount, 0)} verts |{' '}
            {allMaterials.length} materials
          </span>
        </div>
        <div style={{ flex: 1, position: 'relative' }}>
          <Canvas camera={{ position: [1.5, 0.8, 1.5], fov: 45 }}>
            <ambientLight intensity={0.6} />
            <directionalLight position={[5, 5, 5]} intensity={1} />
            <directionalLight position={[-3, -3, -3]} intensity={0.3} />
            <Suspense fallback={null}>
              <WeaponModel
                key={selected}
                name={selected}
                onMeshInfo={handleMeshInfo}
                tintIndex={tintIndex}
                tintColor={tintColor}
                additiveIndices={additiveIndices}
              />
            </Suspense>
            <OrbitControls makeDefault />
            <AutoFit />
            <gridHelper args={[4, 8, '#333', '#222']} />
          </Canvas>
        </div>
      </div>

      {/* Material Inspector */}
      <div style={{
        width: '320px', flexShrink: 0, borderLeft: '1px solid #333',
        overflowY: 'auto', padding: '12px',
      }}>
        <h3 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#4a9eff' }}>
          Materials
        </h3>

        {/* Tint controls */}
        <div style={{
          padding: '8px', background: '#1a1a2e', borderRadius: '6px',
          marginBottom: '12px', border: '1px solid #333',
        }}>
          <div style={{ fontSize: '11px', color: '#888', marginBottom: '6px' }}>Tint Preview</div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <input
              type="color"
              value={tintColor}
              onChange={(e) => setTintColor(e.target.value)}
              style={{ width: '32px', height: '24px', border: 'none', cursor: 'pointer' }}
            />
            <span style={{ fontSize: '11px', color: '#ccc', fontFamily: 'monospace' }}>{tintColor}</span>
            {tintIndex !== null && (
              <button
                onClick={() => setTintIndex(null)}
                style={{
                  marginLeft: 'auto', padding: '2px 8px', background: '#333',
                  border: 'none', borderRadius: '4px', color: '#ccc',
                  fontSize: '10px', cursor: 'pointer',
                }}
              >
                Clear tint
              </button>
            )}
          </div>
        </div>

        {allMaterials.map((mat, idx) => (
          <div
            key={`${mat.meshName}-${mat.index}-${idx}`}
            style={{
              padding: '10px', marginBottom: '8px',
              background: '#111', borderRadius: '6px',
              border: tintIndex === mat.index ? '1px solid #4a9eff' : '1px solid #333',
            }}
          >
            <div style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              marginBottom: '6px',
            }}>
              <span style={{ fontSize: '13px', fontWeight: 'bold' }}>
                [{mat.index}] {mat.name}
              </span>
              <span style={{
                fontSize: '9px', padding: '2px 6px',
                background: '#222', borderRadius: '4px', color: '#888',
              }}>
                {mat.type}
              </span>
            </div>

            <div style={{ fontSize: '11px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
              {/* Color */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ color: '#888', width: '70px' }}>Color:</span>
                <div style={{
                  width: '16px', height: '16px', borderRadius: '3px',
                  background: mat.color, border: '1px solid #555',
                }} />
                <span style={{ fontFamily: 'monospace', color: '#ccc' }}>{mat.color}</span>
              </div>

              {/* Texture */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ color: '#888', width: '70px' }}>Texture:</span>
                <span style={{ color: mat.textureName ? '#4a9eff' : '#666' }}>
                  {mat.textureName || 'none'}
                </span>
                {mat.textureSize && (
                  <span style={{ color: '#666', fontSize: '10px' }}>({mat.textureSize})</span>
                )}
              </div>

              {/* Blending */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ color: '#888', width: '70px' }}>Blending:</span>
                <span style={{ color: additiveIndices.has(mat.index) ? '#ff8800' : '#ccc' }}>
                  {additiveIndices.has(mat.index) ? 'Additive' : mat.blending}
                </span>
              </div>

              {/* Side */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ color: '#888', width: '70px' }}>Side:</span>
                <span style={{ color: '#ccc' }}>{mat.side}</span>
              </div>

              {/* Transparent / Opacity */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <span style={{ color: '#888', width: '70px' }}>Opacity:</span>
                <span style={{ color: '#ccc' }}>{mat.opacity.toFixed(2)}</span>
                {mat.transparent && (
                  <span style={{ color: '#ff8800', fontSize: '10px' }}>(transparent)</span>
                )}
              </div>

              {/* Emissive */}
              {mat.emissive && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <span style={{ color: '#888', width: '70px' }}>Emissive:</span>
                  <div style={{
                    width: '16px', height: '16px', borderRadius: '3px',
                    background: mat.emissive, border: '1px solid #555',
                  }} />
                  <span style={{ fontFamily: 'monospace', color: '#ccc' }}>{mat.emissive}</span>
                </div>
              )}
            </div>

            {/* Action buttons */}
            <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
              <button
                onClick={() => setTintIndex(tintIndex === mat.index ? null : mat.index)}
                style={{
                  padding: '4px 10px', fontSize: '10px', cursor: 'pointer',
                  background: tintIndex === mat.index ? '#4a9eff' : '#333',
                  color: tintIndex === mat.index ? '#fff' : '#ccc',
                  border: 'none', borderRadius: '4px',
                }}
              >
                {tintIndex === mat.index ? 'Tinted' : 'Apply Tint'}
              </button>
              <button
                onClick={() => toggleAdditive(mat.index)}
                style={{
                  padding: '4px 10px', fontSize: '10px', cursor: 'pointer',
                  background: additiveIndices.has(mat.index) ? '#ff8800' : '#333',
                  color: additiveIndices.has(mat.index) ? '#fff' : '#ccc',
                  border: 'none', borderRadius: '4px',
                }}
              >
                {additiveIndices.has(mat.index) ? 'Additive ON' : 'Additive'}
              </button>
            </div>
          </div>
        ))}

        {allMaterials.length === 0 && (
          <div style={{ color: '#666', fontSize: '11px' }}>
            Loading material info...
          </div>
        )}
      </div>
    </div>
  );
}
