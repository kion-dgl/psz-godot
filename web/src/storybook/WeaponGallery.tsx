import { Canvas } from '@react-three/fiber';
import { OrbitControls, useGLTF, Environment } from '@react-three/drei';
import { Suspense, useState, useEffect, useMemo } from 'react';
import * as THREE from 'three';
import {
  WEAPON_CATEGORIES,
  ALL_WEAPON_IDS,
  getWeaponCategory,
  getWeaponRarity,
  getWeaponGlbPath,
  getWeaponInfoPath,
  getWeaponTexturePath,
  type WeaponInfo,
  type WeaponCategory,
} from './weaponData';

type MaterialMode = 'textured' | 'normal' | 'wireframe';
type SideMode = 'front' | 'back' | 'double';

interface MaterialSettings {
  materialMode: MaterialMode;
  sideMode: SideMode;
  wrapS: THREE.Wrapping;
  wrapT: THREE.Wrapping;
  offsetX: number;
  offsetY: number;
  repeatX: number;
  repeatY: number;
}

const DEFAULT_MATERIAL_SETTINGS: MaterialSettings = {
  materialMode: 'textured', sideMode: 'double',
  wrapS: THREE.RepeatWrapping, wrapT: THREE.RepeatWrapping,
  offsetX: 0, offsetY: 0, repeatX: 1, repeatY: 1,
};

const SIDE_MAP: Record<SideMode, THREE.Side> = {
  front: THREE.FrontSide, back: THREE.BackSide, double: THREE.DoubleSide,
};

interface WeaponVariant {
  weaponId: string;
  variant: string;
  displayName: string;
}

function WeaponModel({ weaponId, variant, settings }: {
  weaponId: string; variant: string; settings: MaterialSettings;
}) {
  const glbPath = getWeaponGlbPath(weaponId, variant);
  const { scene } = useGLTF(glbPath);

  const clonedScene = useMemo(() => {
    const clone = scene.clone();
    clone.traverse((obj) => {
      if (obj instanceof THREE.Mesh && obj.geometry) obj.geometry.computeVertexNormals();
    });
    const box = new THREE.Box3().setFromObject(clone);
    const center = box.getCenter(new THREE.Vector3());
    clone.position.sub(center);
    return clone;
  }, [scene]);

  useEffect(() => {
    clonedScene.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh)) return;
      const side = SIDE_MAP[settings.sideMode];
      if (settings.materialMode === 'normal') {
        obj.material = new THREE.MeshNormalMaterial({ wireframe: false, side });
      } else if (settings.materialMode === 'wireframe') {
        obj.material = new THREE.MeshBasicMaterial({ wireframe: true, color: 0x00ff00, side });
      } else {
        const original = obj.userData.originalMaterial || obj.material;
        if (!obj.userData.originalMaterial) obj.userData.originalMaterial = obj.material;
        if (original instanceof THREE.MeshBasicMaterial ||
            original instanceof THREE.MeshStandardMaterial ||
            original instanceof THREE.MeshPhongMaterial) {
          const mat = original.clone();
          mat.wireframe = false;
          mat.side = side;
          if (mat.map) {
            mat.map = mat.map.clone();
            mat.map.wrapS = settings.wrapS;
            mat.map.wrapT = settings.wrapT;
            mat.map.offset.set(settings.offsetX, settings.offsetY);
            mat.map.repeat.set(settings.repeatX, settings.repeatY);
            mat.map.needsUpdate = true;
          }
          obj.material = mat;
        }
      }
    });
  }, [clonedScene, settings]);

  return <primitive object={clonedScene} />;
}

function LoadingSpinner() {
  return (
    <mesh>
      <boxGeometry args={[0.5, 0.5, 0.5]} />
      <meshBasicMaterial color="#4a9eff" wireframe />
    </mesh>
  );
}

const RARITY_COLORS: Record<number, string> = {
  1: '#888888', 2: '#888888', 3: '#4a9eff', 4: '#4a9eff',
  5: '#ffcc00', 6: '#ffcc00', 7: '#ff4444',
};

const WRAP_OPTIONS: { label: string; value: THREE.Wrapping }[] = [
  { label: 'Repeat', value: THREE.RepeatWrapping },
  { label: 'Clamp', value: THREE.ClampToEdgeWrapping },
  { label: 'Mirror', value: THREE.MirroredRepeatWrapping },
];

export default function WeaponGallery() {
  const [selectedCategory, setSelectedCategory] = useState<string>('sword');
  const [selectedVariant, setSelectedVariant] = useState<WeaponVariant | null>(null);
  const [allVariants, setAllVariants] = useState<WeaponVariant[]>([]);
  const [loading, setLoading] = useState(true);
  const [weaponInfoMap, setWeaponInfoMap] = useState<Record<string, WeaponInfo>>({});
  const [materialSettings, setMaterialSettings] = useState<MaterialSettings>(DEFAULT_MATERIAL_SETTINGS);

  // Load weapon info files and build variant list
  useEffect(() => {
    async function loadAll() {
      const variants: WeaponVariant[] = [];
      const infoMap: Record<string, WeaponInfo> = {};

      await Promise.all(
        ALL_WEAPON_IDS.map(async (id) => {
          try {
            const res = await fetch(getWeaponInfoPath(id));
            const info: WeaponInfo = await res.json();
            infoMap[id] = info;
            for (const v of info.variants) {
              variants.push({ weaponId: id, variant: v, displayName: `${info.name} (${v})` });
            }
          } catch { /* skip */ }
        })
      );

      setAllVariants(variants);
      setWeaponInfoMap(infoMap);
      setLoading(false);
    }
    loadAll();
  }, []);

  const variantsByCategory = useMemo(() => {
    const grouped: Record<string, WeaponVariant[]> = {};
    for (const cat of WEAPON_CATEGORIES) grouped[cat.id] = [];
    grouped['other'] = [];
    for (const wv of allVariants) {
      const cat = getWeaponCategory(wv.weaponId);
      if (cat) grouped[cat.id].push(wv);
      else grouped['other'].push(wv);
    }
    return grouped;
  }, [allVariants]);

  const displayedVariants = variantsByCategory[selectedCategory] || [];
  const selectedWeaponInfo = selectedVariant ? weaponInfoMap[selectedVariant.weaponId] : null;

  const updateSetting = <K extends keyof MaterialSettings>(key: K, value: MaterialSettings[K]) => {
    setMaterialSettings((prev) => ({ ...prev, [key]: value }));
  };

  return (
    <div style={{
      width: '100%', height: '100%', background: '#0a0a12', color: 'white',
      display: 'flex', overflow: 'hidden',
    }}>
      {/* Categories */}
      <div style={{
        width: '140px', flexShrink: 0, borderRight: '1px solid #333',
        padding: '8px', overflowY: 'auto', display: 'flex', flexDirection: 'column',
      }}>
        <h3 style={{ margin: '0 0 8px 0', fontSize: '12px', color: '#4a9eff' }}>Categories</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1px' }}>
          {WEAPON_CATEGORIES.map((cat) => (
            <button key={cat.id} onClick={() => setSelectedCategory(cat.id)} style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              padding: '6px 8px', background: selectedCategory === cat.id ? '#4a9eff' : 'transparent',
              color: selectedCategory === cat.id ? 'white' : '#ccc',
              border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '11px',
              textAlign: 'left', width: '100%',
            }}>
              <span>{cat.label}</span>
              <span style={{ opacity: 0.6, fontSize: '10px' }}>{variantsByCategory[cat.id]?.length || 0}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Weapon List */}
      <div style={{
        width: '180px', flexShrink: 0, borderRight: '1px solid #333',
        padding: '8px', overflowY: 'auto',
      }}>
        <h3 style={{ margin: '0 0 8px 0', fontSize: '12px' }}>
          Weapons <span style={{ color: '#666', fontWeight: 'normal' }}>({displayedVariants.length})</span>
        </h3>
        {loading ? (
          <div style={{ color: '#666', fontSize: '11px' }}>Loading...</div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
            {displayedVariants.map((wv, idx) => {
              const rarity = getWeaponRarity(wv.weaponId);
              return (
                <button key={`${wv.weaponId}-${wv.variant}-${idx}`}
                  onClick={() => setSelectedVariant(wv)}
                  style={{
                    display: 'block', width: '100%', padding: '6px 8px',
                    background: selectedVariant?.variant === wv.variant && selectedVariant?.weaponId === wv.weaponId ? '#2a3a5e' : 'transparent',
                    border: selectedVariant?.variant === wv.variant && selectedVariant?.weaponId === wv.weaponId ? '1px solid #4a9eff' : '1px solid transparent',
                    borderRadius: '4px', cursor: 'pointer', textAlign: 'left',
                    fontSize: '10px', color: rarity.color,
                  }}>
                  <span style={{ fontWeight: 'bold' }}>{wv.displayName}</span>
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* 3D Preview */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {selectedVariant && (
          <div style={{ padding: '8px 12px', background: '#111', borderBottom: '1px solid #333' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <span style={{ fontWeight: 'bold', fontSize: '14px' }}>{selectedVariant.displayName}</span>
              <span style={{ padding: '2px 6px', background: '#333', borderRadius: '4px', fontSize: '10px' }}>
                {getWeaponCategory(selectedVariant.weaponId)?.label}
              </span>
            </div>
            <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
              Model: {selectedVariant.variant} | ID: {selectedVariant.weaponId.toUpperCase()}
            </div>
          </div>
        )}
        <div style={{ flex: 1, background: '#0a0a12' }}>
          {selectedVariant ? (
            <Canvas camera={{ position: [2, 1, 2], fov: 45 }}>
              <ambientLight intensity={0.5} />
              <directionalLight position={[5, 5, 5]} intensity={1} />
              <directionalLight position={[-5, -5, -5]} intensity={0.3} />
              <Suspense fallback={<LoadingSpinner />}>
                <WeaponModel
                  key={`${selectedVariant.weaponId}-${selectedVariant.variant}-${JSON.stringify(materialSettings)}`}
                  weaponId={selectedVariant.weaponId}
                  variant={selectedVariant.variant}
                  settings={materialSettings} />
              </Suspense>
              <OrbitControls makeDefault />
              <Environment preset="studio" />
              <gridHelper args={[10, 10, '#333', '#222']} />
            </Canvas>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#666' }}>
              Select a weapon to preview
            </div>
          )}
        </div>
      </div>

      {/* Right Panel - Controls */}
      <div style={{
        width: '280px', flexShrink: 0, borderLeft: '1px solid #333',
        display: 'flex', flexDirection: 'column', overflowY: 'auto',
      }}>
        {/* Material Mode */}
        <div style={{ padding: '12px', borderBottom: '1px solid #333' }}>
          <h3 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#4a9eff' }}>Material Mode</h3>
          {(['textured', 'normal', 'wireframe'] as MaterialMode[]).map((mode) => (
            <label key={mode} style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px', fontSize: '11px', cursor: 'pointer' }}>
              <input type="radio" name="materialMode" checked={materialSettings.materialMode === mode}
                onChange={() => updateSetting('materialMode', mode)} />
              {mode === 'textured' ? 'Textured' : mode === 'normal' ? 'Normal Material' : 'Wireframe'}
            </label>
          ))}

          <h3 style={{ margin: '12px 0 8px 0', fontSize: '12px', color: '#4a9eff' }}>Face Culling</h3>
          {(['front', 'back', 'double'] as SideMode[]).map((mode) => (
            <label key={mode} style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px', fontSize: '11px', cursor: 'pointer' }}>
              <input type="radio" name="sideMode" checked={materialSettings.sideMode === mode}
                onChange={() => updateSetting('sideMode', mode)} />
              {mode === 'front' ? 'Front Side' : mode === 'back' ? 'Back Side' : 'Double Sided'}
            </label>
          ))}
        </div>

        {/* Texture Controls */}
        <div style={{ padding: '12px', borderBottom: '1px solid #333' }}>
          <h3 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#4a9eff' }}>Texture</h3>
          {(['wrapS', 'wrapT'] as const).map((prop) => (
            <div key={prop} style={{ marginBottom: '12px' }}>
              <label style={{ fontSize: '10px', color: '#888', display: 'block', marginBottom: '4px' }}>
                {prop === 'wrapS' ? 'Wrap S' : 'Wrap T'}
              </label>
              <select value={materialSettings[prop]}
                onChange={(e) => updateSetting(prop, parseInt(e.target.value) as THREE.Wrapping)}
                style={{ width: '100%', padding: '4px', background: '#1a1a2e', border: '1px solid #333', borderRadius: '4px', color: 'white', fontSize: '11px' }}>
                {WRAP_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </div>
          ))}

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', marginBottom: '12px' }}>
            {(['offsetX', 'offsetY'] as const).map((prop) => (
              <div key={prop}>
                <label style={{ fontSize: '10px', color: '#888', display: 'block', marginBottom: '4px' }}>
                  {prop === 'offsetX' ? 'Offset X' : 'Offset Y'}
                </label>
                <input type="number" step="0.1" value={materialSettings[prop]}
                  onChange={(e) => updateSetting(prop, parseFloat(e.target.value) || 0)}
                  style={{ width: '100%', padding: '4px', background: '#1a1a2e', border: '1px solid #333', borderRadius: '4px', color: 'white', fontSize: '11px' }} />
              </div>
            ))}
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
            {(['repeatX', 'repeatY'] as const).map((prop) => (
              <div key={prop}>
                <label style={{ fontSize: '10px', color: '#888', display: 'block', marginBottom: '4px' }}>
                  {prop === 'repeatX' ? 'Repeat X' : 'Repeat Y'}
                </label>
                <input type="number" step="0.1" min="0.1" value={materialSettings[prop]}
                  onChange={(e) => updateSetting(prop, parseFloat(e.target.value) || 1)}
                  style={{ width: '100%', padding: '4px', background: '#1a1a2e', border: '1px solid #333', borderRadius: '4px', color: 'white', fontSize: '11px' }} />
              </div>
            ))}
          </div>

          <button onClick={() => setMaterialSettings(DEFAULT_MATERIAL_SETTINGS)}
            style={{ marginTop: '12px', width: '100%', padding: '6px', background: '#333', border: 'none', borderRadius: '4px', color: '#ccc', fontSize: '11px', cursor: 'pointer' }}>
            Reset to Defaults
          </button>
        </div>

        {/* Texture Preview */}
        {selectedVariant && selectedWeaponInfo && (
          <div style={{ padding: '12px' }}>
            <h3 style={{ margin: '0 0 12px 0', fontSize: '12px', color: '#4a9eff' }}>
              Textures ({selectedWeaponInfo.variants.length})
            </h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {selectedWeaponInfo.variants.map((v) => (
                <div key={v}>
                  <div style={{ fontSize: '9px', color: '#888', marginBottom: '4px' }}>{v}</div>
                  <img src={getWeaponTexturePath(selectedVariant.weaponId, v)}
                    alt={`${v} texture`}
                    style={{
                      width: '100%',
                      border: v === selectedVariant.variant ? '2px solid #4a9eff' : '1px solid #333',
                      borderRadius: '4px', background: '#000',
                    }}
                    onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
