import { useState, useEffect, useCallback, useRef } from 'react';
import * as THREE from 'three';
import type { UnifiedStageConfig } from '../types';
// Seeding is handled by useStageConfig.ensureSeeded() — texture fixes
// are in localStorage by the time this component mounts.

interface TextureTabProps {
  config: UnifiedStageConfig;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  stageScene: THREE.Group | null;
  onAnimatedTexturesChange?: (textures: AnimatedTextureInfo[]) => void;
}

interface TextureInfo {
  name: string;        // Display name like "texture.png #1"
  key: string;         // Unique key like "texture.png#1"
  filename: string;    // Original filename
  texture: THREE.Texture;
  meshName: string;    // Name of the mesh this texture is on
}

export interface AnimatedTextureInfo {
  key: string;
  texture: THREE.Texture;
  scrollX: number;
  scrollY: number;
}

export type WrapMode = 'repeat' | 'mirror' | 'clamp';

export interface GlobalTextureFix {
  repeatX: number;
  repeatY: number;
  offsetX: number;
  offsetY: number;
  scrollX?: number;
  scrollY?: number;
  wrapS?: WrapMode;
  wrapT?: WrapMode;
}

const WRAP_MODES: { value: WrapMode; label: string; threeValue: THREE.Wrapping }[] = [
  { value: 'repeat', label: 'Repeat', threeValue: THREE.RepeatWrapping },
  { value: 'mirror', label: 'Mirror', threeValue: THREE.MirroredRepeatWrapping },
  { value: 'clamp', label: 'Clamp', threeValue: THREE.ClampToEdgeWrapping },
];

function getThreeWrapMode(mode: WrapMode): THREE.Wrapping {
  return WRAP_MODES.find(m => m.value === mode)?.threeValue ?? THREE.RepeatWrapping;
}

const STORAGE_KEY = 'stage-editor-global-texture-fixes';

// Load from localStorage, merging committed defaults
export function loadGlobalFixes(): Record<string, GlobalTextureFix> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch {
    return {};
  }
}

function saveGlobalFixes(fixes: Record<string, GlobalTextureFix>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(fixes));
}

function getTextureFilename(texture: THREE.Texture): string {
  if (texture.name) {
    const parts = texture.name.split('/');
    return parts[parts.length - 1];
  }
  const image = texture.image as { src?: string } | null;
  if (image && image.src) {
    const parts = image.src.split('/');
    return parts[parts.length - 1];
  }
  return 'unknown';
}

export default function TextureTab({
  config,
  updateConfig,
  stageScene,
  onAnimatedTexturesChange,
}: TextureTabProps) {
  const [textures, setTextures] = useState<TextureInfo[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [repeatX, setRepeatX] = useState(1);
  const [repeatY, setRepeatY] = useState(1);
  const [offsetX, setOffsetX] = useState(0);
  const [offsetY, setOffsetY] = useState(0);
  const [scrollX, setScrollX] = useState(0);
  const [scrollY, setScrollY] = useState(0);
  const [wrapS, setWrapS] = useState<WrapMode>('repeat');
  const [wrapT, setWrapT] = useState<WrapMode>('repeat');
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [globalFixes, setGlobalFixes] = useState<Record<string, GlobalTextureFix>>({});

  const selectedTexture = textures[selectedIndex];

  // Build and report animated textures list
  const updateAnimatedTextures = useCallback((textureList: TextureInfo[], fixes: Record<string, GlobalTextureFix>) => {
    if (!onAnimatedTexturesChange) return;

    const animated: AnimatedTextureInfo[] = [];
    textureList.forEach(t => {
      const fix = fixes[t.key];
      if (fix && (fix.scrollX || fix.scrollY)) {
        animated.push({
          key: t.key,
          texture: t.texture,
          scrollX: fix.scrollX || 0,
          scrollY: fix.scrollY || 0,
        });
      }
    });
    onAnimatedTexturesChange(animated);
  }, [onAnimatedTexturesChange]);

  // Extract textures from scene and apply saved global fixes (from localStorage, already seeded)
  const extractTextures = useCallback(() => {
    if (!stageScene) {
      setTextures([]);
      return;
    }

    const currentGlobalFixes = loadGlobalFixes();
    setGlobalFixes(currentGlobalFixes);

    const textureInstanceCounts: Record<string, number> = {};
    const textureList: TextureInfo[] = [];

    stageScene.traverse((object) => {
      if (!(object as THREE.Mesh).isMesh) return;
      const mesh = object as THREE.Mesh;
      const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];

      materials.forEach((mat) => {
        const m = mat as any;
        if (m.map && m.map instanceof THREE.Texture) {
          const filename = getTextureFilename(m.map);
          textureInstanceCounts[filename] = (textureInstanceCounts[filename] || 0) + 1;
          const instanceNum = textureInstanceCounts[filename];
          const key = `${filename}#${instanceNum}`;

          // Apply saved global fix if exists, otherwise use defaults
          const savedFix = currentGlobalFixes[key];
          if (savedFix) {
            m.map.repeat.set(savedFix.repeatX, savedFix.repeatY);
            m.map.offset.set(savedFix.offsetX, savedFix.offsetY);
            m.map.wrapS = getThreeWrapMode((savedFix.wrapS as WrapMode) || 'repeat');
            m.map.wrapT = getThreeWrapMode((savedFix.wrapT as WrapMode) || 'repeat');
          } else {
            m.map.wrapS = THREE.RepeatWrapping;
            m.map.wrapT = THREE.RepeatWrapping;
          }
          m.map.needsUpdate = true;

          textureList.push({
            name: `${filename} #${instanceNum}`,
            key,
            filename,
            texture: m.map,
            meshName: mesh.name,
          });
        }
      });
    });

    setTextures(textureList);
    setSelectedIndex(0);
    updateAnimatedTextures(textureList, currentGlobalFixes);
  }, [stageScene, updateAnimatedTextures]);

  // Extract textures when scene changes
  useEffect(() => {
    extractTextures();
  }, [extractTextures]);

  // Update preview and slider values when selection changes
  useEffect(() => {
    if (!selectedTexture) {
      setPreviewUrl(null);
      return;
    }

    setRepeatX(selectedTexture.texture.repeat.x);
    setRepeatY(selectedTexture.texture.repeat.y);
    setOffsetX(selectedTexture.texture.offset.x);
    setOffsetY(selectedTexture.texture.offset.y);

    const fix = globalFixes[selectedTexture.key];
    setScrollX(fix?.scrollX || 0);
    setScrollY(fix?.scrollY || 0);
    setWrapS((fix?.wrapS as WrapMode) || 'repeat');
    setWrapT((fix?.wrapT as WrapMode) || 'repeat');

    const image = selectedTexture.texture.image as CanvasImageSource | null;
    if (image) {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = 128;
        canvas.height = 128;
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(image, 0, 0, 128, 128);
          setPreviewUrl(canvas.toDataURL());
        }
      } catch {
        setPreviewUrl(null);
      }
    } else {
      setPreviewUrl(null);
    }
  }, [selectedTexture, globalFixes]);

  // Debounce timer ref
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Apply changes to texture in real-time
  useEffect(() => {
    if (!selectedTexture) return;
    selectedTexture.texture.repeat.set(repeatX, repeatY);
    selectedTexture.texture.offset.set(offsetX, offsetY);
    selectedTexture.texture.wrapS = getThreeWrapMode(wrapS);
    selectedTexture.texture.wrapT = getThreeWrapMode(wrapT);
    selectedTexture.texture.needsUpdate = true;
  }, [repeatX, repeatY, offsetX, offsetY, wrapS, wrapT, selectedTexture]);

  // Debounced save to localStorage
  useEffect(() => {
    if (!selectedTexture) return;

    if (saveTimerRef.current) {
      clearTimeout(saveTimerRef.current);
    }

    saveTimerRef.current = setTimeout(() => {
      const isDefault = repeatX === 1 && repeatY === 1 && offsetX === 0 && offsetY === 0 &&
                        scrollX === 0 && scrollY === 0 && wrapS === 'repeat' && wrapT === 'repeat';

      const newFixes = { ...globalFixes };
      if (isDefault) {
        delete newFixes[selectedTexture.key];
      } else {
        newFixes[selectedTexture.key] = {
          repeatX,
          repeatY,
          offsetX,
          offsetY,
          scrollX: scrollX !== 0 ? scrollX : undefined,
          scrollY: scrollY !== 0 ? scrollY : undefined,
          wrapS: wrapS !== 'repeat' ? wrapS : undefined,
          wrapT: wrapT !== 'repeat' ? wrapT : undefined,
        };
      }
      saveGlobalFixes(newFixes);
      setGlobalFixes(newFixes);
      updateAnimatedTextures(textures, newFixes);
    }, 300);

    return () => {
      if (saveTimerRef.current) {
        clearTimeout(saveTimerRef.current);
      }
    };
  }, [repeatX, repeatY, offsetX, offsetY, scrollX, scrollY, wrapS, wrapT, selectedTexture?.key]);

  // Reset to default
  const handleReset = () => {
    setRepeatX(1);
    setRepeatY(1);
    setOffsetX(0);
    setOffsetY(0);
    setScrollX(0);
    setScrollY(0);
    setWrapS('repeat');
    setWrapT('repeat');
  };

  // Export global fixes as JSON
  const handleExport = () => {
    const json = JSON.stringify(globalFixes, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'global-texture-fixes.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  // Clear all global fixes
  const handleClearAll = () => {
    if (confirm('Clear all saved texture fixes?')) {
      setGlobalFixes({});
      saveGlobalFixes({});
      extractTextures();
    }
  };

  const fixCount = Object.keys(globalFixes).length;
  const hasAnimation = scrollX !== 0 || scrollY !== 0;
  const selectedHasFix = selectedTexture && globalFixes[selectedTexture.key];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', color: 'white' }}>
      <h3 style={{ margin: 0, borderBottom: '1px solid #444', paddingBottom: '8px' }}>
        Texture Editor
      </h3>

      <div style={{ fontSize: '11px', color: '#888', background: '#1a1a2e', padding: '8px', borderRadius: '4px' }}>
        Settings are saved globally by texture name and apply to all areas.
      </div>

      <button onClick={extractTextures} style={{ padding: '8px', background: '#333', color: 'white', border: '1px solid #555', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>
        Refresh Textures from Scene
      </button>

      {textures.length === 0 ? (
        <div style={{ padding: '20px', textAlign: 'center', color: '#666' }}>
          No textures found. Load a stage first.
        </div>
      ) : (
        <>
          <div>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '12px', color: '#888' }}>
              Select Texture ({textures.length} total):
            </label>
            <select value={selectedIndex} onChange={(e) => setSelectedIndex(Number(e.target.value))} style={{ width: '100%', padding: '8px', background: '#252540', color: 'white', border: '1px solid #444', borderRadius: '4px', fontFamily: 'monospace', fontSize: '11px' }}>
              {textures.map((t, i) => {
                const fix = globalFixes[t.key];
                const isAnimated = fix && (fix.scrollX || fix.scrollY);
                return (
                  <option key={i} value={i}>
                    {t.name} {fix ? (isAnimated ? '~' : '*') : ''} ({t.meshName})
                  </option>
                );
              })}
            </select>
          </div>

          {previewUrl && (
            <div style={{ textAlign: 'center' }}>
              <div style={{ marginBottom: '8px', fontSize: '12px', color: '#888' }}>Preview</div>
              <img src={previewUrl} alt="Texture preview" style={{ width: '128px', height: '128px', border: '2px solid #444', borderRadius: '4px', imageRendering: 'pixelated' }} />
            </div>
          )}

          {selectedTexture && (
            <div style={{ fontSize: '11px', color: '#666', background: '#1a1a2e', padding: '8px', borderRadius: '4px' }}>
              <div>Key: <span style={{ color: '#4a9eff' }}>{selectedTexture.key}</span></div>
              <div>Mesh: <span style={{ color: '#aaa' }}>{selectedTexture.meshName}</span></div>
              <div>Status: <span style={{ color: selectedHasFix ? (hasAnimation ? '#a8f' : '#4a4') : '#666' }}>
                {selectedHasFix ? (hasAnimation ? 'Animated' : 'Has saved fix') : 'Default'}
              </span></div>
            </div>
          )}

          {/* Sliders */}
          <div style={{ background: '#1a1a2e', padding: '12px', borderRadius: '4px' }}>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Repeat X</span><span style={{ color: '#4a9eff' }}>{repeatX.toFixed(1)}</span>
              </label>
              <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <button onClick={() => setRepeatX(Math.max(0.1, +(repeatX - 0.1).toFixed(1)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>-</button>
                <input type="range" min="0.1" max="10" step="0.1" value={repeatX} onChange={(e) => setRepeatX(Number(e.target.value))} style={{ flex: 1 }} />
                <button onClick={() => setRepeatX(Math.min(10, +(repeatX + 0.1).toFixed(1)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>+</button>
              </div>
            </div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Repeat Y</span><span style={{ color: '#4a9eff' }}>{repeatY.toFixed(1)}</span>
              </label>
              <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <button onClick={() => setRepeatY(Math.max(0.1, +(repeatY - 0.1).toFixed(1)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>-</button>
                <input type="range" min="0.1" max="10" step="0.1" value={repeatY} onChange={(e) => setRepeatY(Number(e.target.value))} style={{ flex: 1 }} />
                <button onClick={() => setRepeatY(Math.min(10, +(repeatY + 0.1).toFixed(1)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>+</button>
              </div>
            </div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Offset X</span><span style={{ color: '#4a9eff' }}>{offsetX.toFixed(2)}</span>
              </label>
              <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <button onClick={() => setOffsetX(Math.max(-5, +(offsetX - 0.01).toFixed(2)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>-</button>
                <input type="range" min="-5" max="5" step="0.01" value={offsetX} onChange={(e) => setOffsetX(Number(e.target.value))} style={{ flex: 1 }} />
                <button onClick={() => setOffsetX(Math.min(5, +(offsetX + 0.01).toFixed(2)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>+</button>
              </div>
            </div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Offset Y</span><span style={{ color: '#4a9eff' }}>{offsetY.toFixed(2)}</span>
              </label>
              <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <button onClick={() => setOffsetY(Math.max(-5, +(offsetY - 0.01).toFixed(2)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>-</button>
                <input type="range" min="-5" max="5" step="0.01" value={offsetY} onChange={(e) => setOffsetY(Number(e.target.value))} style={{ flex: 1 }} />
                <button onClick={() => setOffsetY(Math.min(5, +(offsetY + 0.01).toFixed(2)))} style={{ padding: '4px 8px', background: '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '12px' }}>+</button>
              </div>
            </div>

            {/* Wrap mode controls */}
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Wrap S (horizontal)</label>
              <div style={{ display: 'flex', gap: '4px' }}>
                {WRAP_MODES.map(mode => (
                  <button key={mode.value} onClick={() => setWrapS(mode.value)} style={{ flex: 1, padding: '6px', background: wrapS === mode.value ? '#4a9eff' : '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '11px' }}>{mode.label}</button>
                ))}
              </div>
            </div>
            <div style={{ marginBottom: '8px' }}>
              <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Wrap T (vertical)</label>
              <div style={{ display: 'flex', gap: '4px' }}>
                {WRAP_MODES.map(mode => (
                  <button key={mode.value} onClick={() => setWrapT(mode.value)} style={{ flex: 1, padding: '6px', background: wrapT === mode.value ? '#4a9eff' : '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '11px' }}>{mode.label}</button>
                ))}
              </div>
            </div>
          </div>

          {/* Animation section */}
          <div style={{ background: '#2a1a3e', padding: '12px', borderRadius: '4px', border: '1px solid #4a3a5e' }}>
            <div style={{ fontSize: '12px', color: '#a8f', marginBottom: '12px', fontWeight: 'bold' }}>Scroll Animation</div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Scroll X (units/sec)</span><span style={{ color: scrollX !== 0 ? '#a8f' : '#666' }}>{scrollX.toFixed(2)}</span>
              </label>
              <input type="range" min="-2" max="2" step="0.05" value={scrollX} onChange={(e) => setScrollX(Number(e.target.value))} style={{ width: '100%' }} />
            </div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                <span>Scroll Y (units/sec)</span><span style={{ color: scrollY !== 0 ? '#a8f' : '#666' }}>{scrollY.toFixed(2)}</span>
              </label>
              <input type="range" min="-2" max="2" step="0.05" value={scrollY} onChange={(e) => setScrollY(Number(e.target.value))} style={{ width: '100%' }} />
            </div>
            <div style={{ fontSize: '10px', color: '#666' }}>Negative Y = waterfall (scrolls down)</div>
          </div>

          <button onClick={handleReset} style={{ width: '100%', padding: '8px', background: '#c86432', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold', fontSize: '12px' }}>
            Reset to Default
          </button>

          {/* Global fixes summary */}
          <div style={{ fontSize: '11px', color: '#888' }}>
            <div style={{ marginBottom: '8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span>Global texture fixes: {fixCount}</span>
              <div style={{ display: 'flex', gap: '4px' }}>
                <button onClick={handleExport} disabled={fixCount === 0} style={{ padding: '4px 8px', background: fixCount > 0 ? '#4a4' : '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: fixCount > 0 ? 'pointer' : 'not-allowed', fontSize: '10px' }}>Export</button>
                <button onClick={handleClearAll} disabled={fixCount === 0} style={{ padding: '4px 8px', background: fixCount > 0 ? '#a44' : '#333', color: 'white', border: 'none', borderRadius: '4px', cursor: fixCount > 0 ? 'pointer' : 'not-allowed', fontSize: '10px' }}>Clear All</button>
              </div>
            </div>
            {fixCount > 0 && (
              <div style={{ maxHeight: '120px', overflow: 'auto', background: '#1a1a2e', borderRadius: '4px', padding: '8px' }}>
                {Object.entries(globalFixes).map(([key, fix]) => {
                  const isAnimated = fix.scrollX || fix.scrollY;
                  return (
                    <div key={key} style={{ marginBottom: '4px', fontFamily: 'monospace' }}>
                      <span style={{ color: isAnimated ? '#a8f' : '#4a9eff' }}>{key}</span>
                      <span style={{ color: '#666' }}> R[{fix.repeatX}, {fix.repeatY}]</span>
                      {isAnimated && (
                        <span style={{ color: '#a8f' }}> S[{fix.scrollX || 0}, {fix.scrollY || 0}]</span>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
