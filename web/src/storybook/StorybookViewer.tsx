import { Canvas } from '@react-three/fiber';
import { OrbitControls, Grid } from '@react-three/drei';
import { Suspense, useState, useMemo, useRef, useEffect, useCallback } from 'react';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import {
  Gate, gateMeta,
  KeyGate, keyGateMeta,
  Fence, fenceMeta,
  Fence4, fence4Meta,
  Key, keyMeta,
  MessagePack, messagePackMeta,
  InteractSwitch, interactSwitchMeta,
  StepSwitch, stepSwitchMeta,
  RemoteSwitch, remoteSwitchMeta,
  DropMeseta, dropMesetaMeta,
  DropWeapon, dropWeaponMeta,
  DropArmor, dropArmorMeta,
  DropRare, dropRareMeta,
  DropItem, dropItemMeta,
  Waypoint, waypointMeta,
  Box, boxMeta,
  RareBox, rareBoxMeta,
  Wall, wallMeta,
  StartWarp, startWarpMeta,
  AreaWarp, areaWarpMeta,
  NpcSarisa, npcSarisaMeta,
  NpcKai, npcKaiMeta,
  DropshipCrash, dropshipCrashMeta,
  type StoryMeta,
} from '../elements';

// Registry of all elements with their components and metadata
interface ElementEntry {
  id: string;
  Component: React.ComponentType<{ state?: string }>;
  meta: StoryMeta;
}

interface CategoryEntry {
  name: string;
  elements: ElementEntry[];
}

const CATEGORIES: CategoryEntry[] = [
  {
    name: 'Gates',
    elements: [
      { id: 'gate', Component: Gate as React.ComponentType<{ state?: string }>, meta: gateMeta },
      { id: 'key-gate', Component: KeyGate as React.ComponentType<{ state?: string }>, meta: keyGateMeta },
    ],
  },
  {
    name: 'Fences',
    elements: [
      { id: 'fence', Component: Fence as React.ComponentType<{ state?: string }>, meta: fenceMeta },
      { id: 'fence-4', Component: Fence4 as React.ComponentType<{ state?: string }>, meta: fence4Meta },
    ],
  },
  {
    name: 'Switches',
    elements: [
      { id: 'interact-switch', Component: InteractSwitch as React.ComponentType<{ state?: string }>, meta: interactSwitchMeta },
      { id: 'step-switch', Component: StepSwitch as React.ComponentType<{ state?: string }>, meta: stepSwitchMeta },
      { id: 'remote-switch', Component: RemoteSwitch as React.ComponentType<{ state?: string }>, meta: remoteSwitchMeta },
    ],
  },
  {
    name: 'Pickups',
    elements: [
      { id: 'key', Component: Key as React.ComponentType<{ state?: string }>, meta: keyMeta },
      { id: 'message-pack', Component: MessagePack as React.ComponentType<{ state?: string }>, meta: messagePackMeta },
    ],
  },
  {
    name: 'Drops',
    elements: [
      { id: 'drop-meseta', Component: DropMeseta as React.ComponentType<{ state?: string }>, meta: dropMesetaMeta },
      { id: 'drop-weapon', Component: DropWeapon as React.ComponentType<{ state?: string }>, meta: dropWeaponMeta },
      { id: 'drop-armor', Component: DropArmor as React.ComponentType<{ state?: string }>, meta: dropArmorMeta },
      { id: 'drop-rare', Component: DropRare as React.ComponentType<{ state?: string }>, meta: dropRareMeta },
      { id: 'drop-item', Component: DropItem as React.ComponentType<{ state?: string }>, meta: dropItemMeta },
    ],
  },
  {
    name: 'Indicators',
    elements: [
      { id: 'waypoint', Component: Waypoint as React.ComponentType<{ state?: string }>, meta: waypointMeta },
    ],
  },
  {
    name: 'Containers',
    elements: [
      { id: 'box', Component: Box as React.ComponentType<{ state?: string }>, meta: boxMeta },
      { id: 'rare-box', Component: RareBox as React.ComponentType<{ state?: string }>, meta: rareBoxMeta },
    ],
  },
  {
    name: 'Walls',
    elements: [
      { id: 'wall', Component: Wall as React.ComponentType<{ state?: string }>, meta: wallMeta },
    ],
  },
  {
    name: 'Warps',
    elements: [
      { id: 'start-warp', Component: StartWarp as React.ComponentType<{ state?: string }>, meta: startWarpMeta },
      { id: 'area-warp', Component: AreaWarp as React.ComponentType<{ state?: string }>, meta: areaWarpMeta },
    ],
  },
  {
    name: 'NPCs',
    elements: [
      { id: 'npc-sarisa', Component: NpcSarisa as React.ComponentType<{ state?: string }>, meta: npcSarisaMeta },
      { id: 'npc-kai', Component: NpcKai as React.ComponentType<{ state?: string }>, meta: npcKaiMeta },
    ],
  },
  {
    name: 'Story Objects',
    elements: [
      { id: 'dropship-crash', Component: DropshipCrash as React.ComponentType<{ state?: string }>, meta: dropshipCrashMeta },
    ],
  },
];

// Flatten for lookup
const ALL_ELEMENTS = CATEGORIES.flatMap((cat) => cat.elements);

// --- Texture inspector types ---

interface TextureInfo {
  name: string;
  key: string;
  filename: string;
  texture: THREE.Texture;
  meshName: string;
}

interface AnimatedTextureEntry {
  key: string;
  texture: THREE.Texture;
  scrollX: number;
  scrollY: number;
}

type WrapMode = 'repeat' | 'mirror' | 'clamp';

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

function getWrapModeName(mode: number): WrapMode {
  if (mode === THREE.MirroredRepeatWrapping) return 'mirror';
  if (mode === THREE.ClampToEdgeWrapping) return 'clamp';
  return 'repeat';
}

function getThreeWrapMode(mode: WrapMode): THREE.Wrapping {
  if (mode === 'mirror') return THREE.MirroredRepeatWrapping;
  if (mode === 'clamp') return THREE.ClampToEdgeWrapping;
  return THREE.RepeatWrapping;
}

// --- Canvas-internal components ---

/** Scans a group for textures and reports them to the parent */
function TextureScanner({
  groupRef,
  elementId,
  state,
  onTexturesFound,
}: {
  groupRef: React.RefObject<THREE.Group | null>;
  elementId: string;
  state: string;
  onTexturesFound: (textures: TextureInfo[]) => void;
}) {
  const scanCount = useRef(0);

  useFrame(() => {
    // Scan on first few frames after element/state change to catch async GLB loads
    if (scanCount.current < 10) {
      scanCount.current++;
      if (scanCount.current === 5 && groupRef.current) {
        const instanceCounts: Record<string, number> = {};
        const textureList: TextureInfo[] = [];

        groupRef.current.traverse((object) => {
          if (!(object as THREE.Mesh).isMesh) return;
          const mesh = object as THREE.Mesh;
          const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];

          materials.forEach((mat) => {
            const m = mat as any;
            if (m.map && m.map instanceof THREE.Texture) {
              const filename = getTextureFilename(m.map);
              instanceCounts[filename] = (instanceCounts[filename] || 0) + 1;
              const num = instanceCounts[filename];
              const key = `${filename}#${num}`;

              textureList.push({
                name: `${filename} #${num}`,
                key,
                filename,
                texture: m.map,
                meshName: mesh.name,
              });
            }
          });
        });

        onTexturesFound(textureList);
      }
    }
  });

  // Reset scan counter when element or state changes
  useEffect(() => {
    scanCount.current = 0;
  }, [elementId, state]);

  return null;
}

/** Animates texture offsets each frame */
function TextureAnimator({ animatedTextures }: { animatedTextures: AnimatedTextureEntry[] }) {
  useFrame((_, delta) => {
    animatedTextures.forEach(({ texture, scrollX, scrollY }) => {
      texture.offset.x += scrollX * delta;
      texture.offset.y += scrollY * delta;
      if (texture.offset.x > 10) texture.offset.x -= 10;
      if (texture.offset.x < -10) texture.offset.x += 10;
      if (texture.offset.y > 10) texture.offset.y -= 10;
      if (texture.offset.y < -10) texture.offset.y += 10;
    });
  });
  return null;
}

/** Element IDs that should spin and bob */
const SPINNING_ELEMENTS = new Set([
  'key', 'drop-meseta', 'drop-weapon', 'drop-armor', 'drop-rare', 'drop-item',
]);

/** Spins the group for pickup/drop elements */
function ModelSpinner({
  groupRef,
  elementId,
  state,
}: {
  groupRef: React.RefObject<THREE.Group | null>;
  elementId: string;
  state: string;
}) {
  const timeRef = useRef(0);

  useFrame((_, delta) => {
    if (!groupRef.current) return;
    if (!SPINNING_ELEMENTS.has(elementId)) return;
    if (state !== 'available') return;

    timeRef.current += delta;
    groupRef.current.rotation.y += delta * 2;
    groupRef.current.position.y = Math.sin(timeRef.current * 3) * 0.1;
  });

  // Reset rotation/position when element changes
  useEffect(() => {
    if (groupRef.current) {
      groupRef.current.rotation.y = 0;
      groupRef.current.position.y = 0;
    }
    timeRef.current = 0;
  }, [elementId, groupRef]);

  return null;
}

function ElementPreview({ element, state }: { element: ElementEntry; state: string }) {
  const { Component } = element;

  return (
    <Suspense fallback={null}>
      <Component key={element.id} state={state} />
    </Suspense>
  );
}

// --- Shared styles ---
const WRAP_MODES: { value: WrapMode; label: string }[] = [
  { value: 'repeat', label: 'Repeat' },
  { value: 'mirror', label: 'Mirror' },
  { value: 'clamp', label: 'Clamp' },
];

// --- Main component ---

export default function StorybookViewer() {
  const [selectedId, setSelectedId] = useState<string>(ALL_ELEMENTS[0].id);
  const [states, setStates] = useState<Record<string, string>>(() => {
    const initial: Record<string, string> = {};
    ALL_ELEMENTS.forEach((el) => {
      initial[el.id] = el.meta.defaultState;
    });
    return initial;
  });

  const selectedElement = useMemo(() => {
    return ALL_ELEMENTS.find((el) => el.id === selectedId) || ALL_ELEMENTS[0];
  }, [selectedId]);

  const currentState = states[selectedId] || selectedElement.meta.defaultState;

  const handleStateChange = (newState: string) => {
    setStates((prev) => ({ ...prev, [selectedId]: newState }));
  };

  // Texture inspector state
  const groupRef = useRef<THREE.Group>(null);
  const [textures, setTextures] = useState<TextureInfo[]>([]);
  const [selectedTexIdx, setSelectedTexIdx] = useState(0);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);

  // Per-texture editing state
  const [repeatX, setRepeatX] = useState(1);
  const [repeatY, setRepeatY] = useState(1);
  const [offsetX, setOffsetX] = useState(0);
  const [offsetY, setOffsetY] = useState(0);
  const [scrollX, setScrollX] = useState(0);
  const [scrollY, setScrollY] = useState(0);
  const [wrapS, setWrapS] = useState<WrapMode>('repeat');
  const [wrapT, setWrapT] = useState<WrapMode>('repeat');

  const selectedTexture = textures[selectedTexIdx] || null;

  // Animated textures for TextureAnimator
  const [animatedTextures, setAnimatedTextures] = useState<AnimatedTextureEntry[]>([]);

  // When textures are found by scanner
  const handleTexturesFound = useCallback((newTextures: TextureInfo[]) => {
    setTextures(newTextures);
    setSelectedTexIdx(0);
    setAnimatedTextures([]);
  }, []);

  // When selected texture changes, load its current values
  useEffect(() => {
    if (!selectedTexture) {
      setPreviewUrl(null);
      return;
    }

    const tex = selectedTexture.texture;
    setRepeatX(tex.repeat.x);
    setRepeatY(tex.repeat.y);
    setOffsetX(tex.offset.x);
    setOffsetY(tex.offset.y);
    setWrapS(getWrapModeName(tex.wrapS));
    setWrapT(getWrapModeName(tex.wrapT));
    setScrollX(0);
    setScrollY(0);

    // Generate preview
    const image = tex.image as CanvasImageSource | null;
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
  }, [selectedTexture]);

  // Apply changes to texture in real-time
  useEffect(() => {
    if (!selectedTexture) return;
    const tex = selectedTexture.texture;
    tex.repeat.set(repeatX, repeatY);
    tex.offset.set(offsetX, offsetY);
    tex.wrapS = getThreeWrapMode(wrapS);
    tex.wrapT = getThreeWrapMode(wrapT);
    tex.needsUpdate = true;
  }, [repeatX, repeatY, offsetX, offsetY, wrapS, wrapT, selectedTexture]);

  // Update animated textures when scroll values change
  useEffect(() => {
    if (!selectedTexture) return;
    setAnimatedTextures((prev) => {
      // Remove this texture's old entry
      const filtered = prev.filter((a) => a.key !== selectedTexture.key);
      // Add if scrolling
      if (scrollX !== 0 || scrollY !== 0) {
        filtered.push({
          key: selectedTexture.key,
          texture: selectedTexture.texture,
          scrollX,
          scrollY,
        });
      }
      return filtered;
    });
  }, [scrollX, scrollY, selectedTexture]);

  // Reset animated textures when element changes
  useEffect(() => {
    setAnimatedTextures([]);
    setTextures([]);
    setSelectedTexIdx(0);
  }, [selectedId]);

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

  const [copied, setCopied] = useState(false);

  const handleCopyConfig = useCallback(() => {
    if (textures.length === 0) return;

    const lines: string[] = [];
    lines.push(`// Texture config for ${selectedElement.meta.title}`);
    lines.push('const TEXTURE_CONFIG: Record<string, {');
    lines.push('  offsetX?: number; offsetY?: number;');
    lines.push('  repeatX?: number; repeatY?: number;');
    lines.push('  wrapS?: string; wrapT?: string;');
    lines.push('  scrollX?: number; scrollY?: number;');
    lines.push('}> = {');

    // Deduplicate by filename (multiple instances of same texture share settings)
    const seen = new Set<string>();
    textures.forEach((t) => {
      if (seen.has(t.filename)) return;
      seen.add(t.filename);

      const tex = t.texture;
      const anim = animatedTextures.find((a) => a.key === t.key);

      const props: string[] = [];
      // Always include offset and repeat for clarity
      props.push(`offsetX: ${tex.offset.x.toFixed(2)}, offsetY: ${tex.offset.y.toFixed(2)}`);
      props.push(`repeatX: ${tex.repeat.x.toFixed(1)}, repeatY: ${tex.repeat.y.toFixed(1)}`);

      const ws = getWrapModeName(tex.wrapS);
      const wt = getWrapModeName(tex.wrapT);
      if (ws !== 'repeat' || wt !== 'repeat') {
        props.push(`wrapS: '${ws}', wrapT: '${wt}'`);
      }

      if (anim && (anim.scrollX !== 0 || anim.scrollY !== 0)) {
        props.push(`scrollX: ${anim.scrollX.toFixed(2)}, scrollY: ${anim.scrollY.toFixed(2)}`);
      }

      lines.push(`  '${t.filename}': { ${props.join(', ')} }, // mesh: ${t.meshName}`);
    });

    lines.push('};');

    const snippet = lines.join('\n');
    navigator.clipboard.writeText(snippet).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }, [textures, animatedTextures, selectedElement]);

  return (
    <div style={{
      display: 'flex',
      height: '100%',
      background: '#1a1a2e',
      color: 'white',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      {/* Left Panel - Element List */}
      <div style={{
        width: '220px',
        borderRight: '1px solid #333',
        overflow: 'auto',
        padding: '1rem',
        background: '#151525',
      }}>
        {CATEGORIES.map((category) => (
          <div key={category.name} style={{ marginBottom: '1.5rem' }}>
            <div style={{
              fontSize: '11px',
              color: '#666',
              textTransform: 'uppercase',
              letterSpacing: '1px',
              marginBottom: '0.5rem',
            }}>
              {category.name}
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
              {category.elements.map((element) => (
                <button
                  key={element.id}
                  onClick={() => setSelectedId(element.id)}
                  style={{
                    padding: '10px 12px',
                    background: selectedId === element.id ? '#3a3a6a' : 'transparent',
                    border: 'none',
                    borderRadius: '6px',
                    color: selectedId === element.id ? 'white' : '#aaa',
                    cursor: 'pointer',
                    textAlign: 'left',
                    fontSize: '13px',
                    fontWeight: selectedId === element.id ? '600' : '400',
                    transition: 'all 0.15s ease',
                  }}
                  onMouseEnter={(e) => {
                    if (selectedId !== element.id) {
                      e.currentTarget.style.background = '#2a2a4a';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (selectedId !== element.id) {
                      e.currentTarget.style.background = 'transparent';
                    }
                  }}
                >
                  {element.meta.title}
                </button>
              ))}
            </div>
          </div>
        ))}

      </div>

      {/* Center - 3D Viewer */}
      <div style={{ flex: 1, position: 'relative' }}>
        <Canvas camera={{ position: [3, 2, 3], fov: 50 }}>
          <ambientLight intensity={0.6} />
          <directionalLight position={[5, 10, 5]} intensity={0.8} />

          <group ref={groupRef}>
            <ElementPreview element={selectedElement} state={currentState} />
          </group>

          <TextureScanner
            groupRef={groupRef}
            elementId={selectedId}
            state={currentState}
            onTexturesFound={handleTexturesFound}
          />
          <TextureAnimator animatedTextures={animatedTextures} />
          <ModelSpinner
            groupRef={groupRef}
            elementId={selectedId}
            state={currentState}
          />

          <OrbitControls />
          <Grid
            infiniteGrid
            fadeDistance={30}
            fadeStrength={5}
            cellColor="#333355"
            sectionColor="#444477"
          />
        </Canvas>

        {/* Element title overlay */}
        <div style={{
          position: 'absolute',
          top: '1rem',
          left: '1rem',
          background: 'rgba(0, 0, 0, 0.7)',
          padding: '0.75rem 1rem',
          borderRadius: '8px',
          backdropFilter: 'blur(8px)',
        }}>
          <div style={{ fontSize: '18px', fontWeight: '600' }}>
            {selectedElement.meta.title}
          </div>
          <div style={{ fontSize: '12px', color: '#888', marginTop: '4px' }}>
            {selectedElement.meta.description}
          </div>
        </div>
      </div>

      {/* Right Panel - State Controls + Texture Inspector */}
      <div style={{
        width: '300px',
        borderLeft: '1px solid #333',
        overflow: 'auto',
        padding: '1.5rem',
        background: '#151525',
      }}>
        {/* State section */}
        <div style={{
          fontSize: '11px',
          color: '#666',
          textTransform: 'uppercase',
          letterSpacing: '1px',
          marginBottom: '1rem',
        }}>
          State
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {selectedElement.meta.states.map((stateOption) => {
            const isSelected = currentState === stateOption.name;

            return (
              <label
                key={stateOption.name}
                style={{
                  display: 'flex',
                  alignItems: 'flex-start',
                  gap: '12px',
                  padding: '12px',
                  background: isSelected ? '#3a3a6a' : '#2a2a4a',
                  borderRadius: '8px',
                  cursor: 'pointer',
                  transition: 'all 0.15s ease',
                  border: isSelected ? '1px solid #5a5a9a' : '1px solid transparent',
                }}
              >
                <input
                  type="radio"
                  name="element-state"
                  value={stateOption.name}
                  checked={isSelected}
                  onChange={() => handleStateChange(stateOption.name)}
                  style={{
                    width: '18px',
                    height: '18px',
                    marginTop: '2px',
                    accentColor: '#88aaff',
                  }}
                />
                <div>
                  <div style={{
                    fontWeight: '500',
                    fontSize: '14px',
                    color: isSelected ? 'white' : '#ccc',
                  }}>
                    {stateOption.label}
                  </div>
                  {stateOption.description && (
                    <div style={{
                      fontSize: '12px',
                      color: '#888',
                      marginTop: '4px',
                    }}>
                      {stateOption.description}
                    </div>
                  )}
                </div>
              </label>
            );
          })}
        </div>

        {/* Texture Inspector */}
        <div style={{ marginTop: '2rem', borderTop: '1px solid #333', paddingTop: '1rem' }}>
          <div style={{
            fontSize: '11px',
            color: '#666',
            textTransform: 'uppercase',
            letterSpacing: '1px',
            marginBottom: '1rem',
          }}>
            Textures {textures.length > 0 && `(${textures.length})`}
          </div>

          {textures.length === 0 ? (
            <div style={{ fontSize: '12px', color: '#555' }}>
              No textures found.
            </div>
          ) : (
            <>
              {/* Texture selector */}
              <select
                value={selectedTexIdx}
                onChange={(e) => setSelectedTexIdx(Number(e.target.value))}
                style={{
                  width: '100%',
                  padding: '8px',
                  background: '#252540',
                  color: 'white',
                  border: '1px solid #444',
                  borderRadius: '4px',
                  fontFamily: 'monospace',
                  fontSize: '11px',
                  marginBottom: '12px',
                }}
              >
                {textures.map((t, i) => (
                  <option key={i} value={i}>
                    {t.name} ({t.meshName})
                  </option>
                ))}
              </select>

              {/* Preview + info */}
              <div style={{ display: 'flex', gap: '12px', marginBottom: '12px' }}>
                {previewUrl && (
                  <img
                    src={previewUrl}
                    alt="Texture preview"
                    style={{
                      width: '96px',
                      height: '96px',
                      border: '2px solid #444',
                      borderRadius: '4px',
                      imageRendering: 'pixelated',
                      flexShrink: 0,
                    }}
                  />
                )}
                {selectedTexture && (
                  <div style={{ fontSize: '11px', color: '#888', lineHeight: '1.6' }}>
                    <div>Mesh: <span style={{ color: '#aaa' }}>{selectedTexture.meshName}</span></div>
                    <div>File: <span style={{ color: '#4a9eff' }}>{selectedTexture.filename}</span></div>
                    <div>Size: <span style={{ color: '#aaa' }}>
                      {(selectedTexture.texture.image as any)?.width || '?'}x{(selectedTexture.texture.image as any)?.height || '?'}
                    </span></div>
                  </div>
                )}
              </div>

              {/* Controls */}
              <div style={{ background: '#1a1a2e', padding: '12px', borderRadius: '4px', marginBottom: '12px' }}>
                {/* Offset X */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Offset X</span>
                    <span style={{ color: '#4a9eff' }}>{offsetX.toFixed(2)}</span>
                  </label>
                  <input type="range" min="-2" max="2" step="0.01" value={offsetX}
                    onChange={(e) => setOffsetX(Number(e.target.value))} style={{ width: '100%' }} />
                </div>

                {/* Offset Y */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Offset Y</span>
                    <span style={{ color: '#4a9eff' }}>{offsetY.toFixed(2)}</span>
                  </label>
                  <input type="range" min="-2" max="2" step="0.01" value={offsetY}
                    onChange={(e) => setOffsetY(Number(e.target.value))} style={{ width: '100%' }} />
                </div>

                {/* Repeat X */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Repeat X</span>
                    <span style={{ color: '#4a9eff' }}>{repeatX.toFixed(1)}</span>
                  </label>
                  <input type="range" min="0.1" max="10" step="0.1" value={repeatX}
                    onChange={(e) => setRepeatX(Number(e.target.value))} style={{ width: '100%' }} />
                </div>

                {/* Repeat Y */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Repeat Y</span>
                    <span style={{ color: '#4a9eff' }}>{repeatY.toFixed(1)}</span>
                  </label>
                  <input type="range" min="0.1" max="10" step="0.1" value={repeatY}
                    onChange={(e) => setRepeatY(Number(e.target.value))} style={{ width: '100%' }} />
                </div>

                {/* Wrap S */}
                <div style={{ marginBottom: '12px' }}>
                  <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Wrap S</label>
                  <div style={{ display: 'flex', gap: '4px' }}>
                    {WRAP_MODES.map((mode) => (
                      <button
                        key={mode.value}
                        onClick={() => setWrapS(mode.value)}
                        style={{
                          flex: 1,
                          padding: '5px',
                          background: wrapS === mode.value ? '#4a9eff' : '#333',
                          color: 'white',
                          border: 'none',
                          borderRadius: '4px',
                          cursor: 'pointer',
                          fontSize: '11px',
                        }}
                      >
                        {mode.label}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Wrap T */}
                <div style={{ marginBottom: '4px' }}>
                  <label style={{ display: 'block', marginBottom: '4px', fontSize: '12px' }}>Wrap T</label>
                  <div style={{ display: 'flex', gap: '4px' }}>
                    {WRAP_MODES.map((mode) => (
                      <button
                        key={mode.value}
                        onClick={() => setWrapT(mode.value)}
                        style={{
                          flex: 1,
                          padding: '5px',
                          background: wrapT === mode.value ? '#4a9eff' : '#333',
                          color: 'white',
                          border: 'none',
                          borderRadius: '4px',
                          cursor: 'pointer',
                          fontSize: '11px',
                        }}
                      >
                        {mode.label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              {/* Scroll animation */}
              <div style={{
                background: '#2a1a3e',
                padding: '12px',
                borderRadius: '4px',
                border: '1px solid #4a3a5e',
                marginBottom: '12px',
              }}>
                <div style={{ fontSize: '12px', color: '#a8f', marginBottom: '10px', fontWeight: 'bold' }}>
                  Scroll Animation
                </div>

                <div style={{ marginBottom: '10px' }}>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Scroll X</span>
                    <span style={{ color: scrollX !== 0 ? '#a8f' : '#666' }}>{scrollX.toFixed(2)}</span>
                  </label>
                  <input type="range" min="-2" max="2" step="0.05" value={scrollX}
                    onChange={(e) => setScrollX(Number(e.target.value))} style={{ width: '100%' }} />
                </div>

                <div>
                  <label style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '12px' }}>
                    <span>Scroll Y</span>
                    <span style={{ color: scrollY !== 0 ? '#a8f' : '#666' }}>{scrollY.toFixed(2)}</span>
                  </label>
                  <input type="range" min="-2" max="2" step="0.05" value={scrollY}
                    onChange={(e) => setScrollY(Number(e.target.value))} style={{ width: '100%' }} />
                </div>
              </div>

              {/* Reset + Copy */}
              <div style={{ display: 'flex', gap: '8px' }}>
                <button
                  onClick={handleReset}
                  style={{
                    flex: 1,
                    padding: '8px',
                    background: '#c86432',
                    color: 'white',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontWeight: 'bold',
                    fontSize: '12px',
                  }}
                >
                  Reset
                </button>
                <button
                  onClick={handleCopyConfig}
                  style={{
                    flex: 1,
                    padding: '8px',
                    background: copied ? '#4a4' : '#4a9eff',
                    color: 'white',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontWeight: 'bold',
                    fontSize: '12px',
                    transition: 'background 0.2s',
                  }}
                >
                  {copied ? 'Copied!' : 'Copy Config'}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
