import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Texture-animation authoring tool for city stage models — the guild counter
 * + teleporter merge (s00e_sa2_m.glb) first. Shows the model, lets you set
 * per-material UV scroll / wrap / repeat / offset with a LIVE preview, and
 * copies a `global-texture-fixes.json` snippet to paste into
 * data/stage_configs/.
 *
 * The preview mirrors the in-game path (city_area_base._fix_materials_recursive
 * → texture_fix_shader / waterfall shader): scroll animates
 * `uv += uv_scroll * time`, wrap maps repeat/mirror/clamp, repeat = uv_scale,
 * offset = uv_offset. A material with any scrollX/scrollY becomes a
 * "waterfall" (animated) entry in-game; the rest use the static fix shader.
 *
 * The exported KEY is the texture's filename as Godot extracts it from the
 * GLB (`<glb>_<image>.png`), matching `_find_global_fix_for_material`'s
 * `albedo_texture.resource_path.get_file()` lookup (tries `#1`, `#0`, ``).
 */

const STORAGE_KEY = 'psz-texture-anim:v1';

// Available city stage models (extend as more are authored). glb basename is
// the prefix Godot puts on extracted textures — used to build the config key.
interface ModelDef { id: string; label: string; path: string; glbBase: string }
const MODELS: ModelDef[] = [
  {
    id: 's00e_sa2',
    label: 'Guild Counter + Teleport (s00e_sa2)',
    path: 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb',
    glbBase: 's00e_sa2_m',
  },
];

type WrapMode = 'repeat' | 'mirror' | 'clamp';

interface Fix {
  scrollX: number;
  scrollY: number;
  repeatX: number;
  repeatY: number;
  offsetX: number;
  offsetY: number;
  wrapS: WrapMode;
  wrapT: WrapMode;
}

const DEFAULT_FIX: Fix = {
  scrollX: 0, scrollY: 0, repeatX: 1, repeatY: 1,
  offsetX: 0, offsetY: 0, wrapS: 'repeat', wrapT: 'repeat',
};

function isDefault(f: Fix): boolean {
  return f.scrollX === 0 && f.scrollY === 0 && f.repeatX === 1 && f.repeatY === 1
    && f.offsetX === 0 && f.offsetY === 0 && f.wrapS === 'repeat' && f.wrapT === 'repeat';
}

/** Only scroll and wrap need the in-game shader; a material with a scroll is
 * a "waterfall" (animated) entry. Static-only (repeat/offset) still exports. */
function isAnimated(f: Fix): boolean {
  return f.scrollX !== 0 || f.scrollY !== 0;
}

type Config = Record<string, Partial<Fix>>;  // texKey → fix (per model)

interface Store { modelId: string; perModel: Record<string, Config> }

function loadStore(): Store {
  const base: Store = { modelId: MODELS[0].id, perModel: {} };
  if (typeof window === 'undefined') return base;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return base;
    const parsed = JSON.parse(raw) as Partial<Store>;
    return { modelId: parsed.modelId || MODELS[0].id, perModel: parsed.perModel || {} };
  } catch {
    return base;
  }
}

const WRAP_THREE: Record<WrapMode, THREE.Wrapping> = {
  repeat: THREE.RepeatWrapping,
  mirror: THREE.MirroredRepeatWrapping,
  clamp: THREE.ClampToEdgeWrapping,
};

interface MatEntry {
  key: string;              // config key (Godot filename + we add #1 on export)
  texName: string;         // raw three.js texture/image name (for display)
  mat: THREE.MeshBasicMaterial | THREE.MeshStandardMaterial;
  baseMap: THREE.Texture;
  meshes: THREE.Mesh[];
  baseColor: THREE.Color;  // material tint; highlight lerps toward orange
}

const HIGHLIGHT = new THREE.Color(0xff8a2a);

interface SceneRefs {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  model: THREE.Group | null;
  mats: MatEntry[];
}

/** The filename Godot extracts a GLB texture to: `<glbBase>_<image>.png`.
 * three.js exposes the glTF image name on texture.name / image.name. */
function godotTexFilename(tex: THREE.Texture, glbBase: string): string {
  let n = tex.name || '';
  if (!n && tex.image && (tex.image as { name?: string }).name) n = (tex.image as { name: string }).name;
  n = n.replace(/\.(png|jpg|jpeg)$/i, '');
  if (!n) n = 'unnamed';
  // Godot prefixes extracted embedded textures with the glb basename unless
  // the image name already carries it.
  const file = n.startsWith(glbBase + '_') || n.startsWith(glbBase) ? `${n}.png` : `${glbBase}_${n}.png`;
  return file;
}

export default function TextureAnimEditor() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const fixRef = useRef<Config>({});      // live config for the current model
  const selectedRef = useRef<string | null>(null);

  const [store, setStore] = useState<Store>(loadStore);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [mats, setMats] = useState<{ key: string; texName: string }[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [copied, setCopied] = useState('');

  const modelDef = MODELS.find((m) => m.id === store.modelId)!;
  const config: Config = store.perModel[store.modelId] || {};
  fixRef.current = config;
  selectedRef.current = selected;

  useEffect(() => {
    try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(store)); } catch { /* ignore */ }
  }, [store]);

  const getFix = (key: string): Fix => ({ ...DEFAULT_FIX, ...(config[key] || {}) });

  const setFix = (key: string, patch: Partial<Fix>) => {
    setStore((s) => {
      const cfg = { ...(s.perModel[s.modelId] || {}) };
      cfg[key] = { ...DEFAULT_FIX, ...(cfg[key] || {}), ...patch };
      return { ...s, perModel: { ...s.perModel, [s.modelId]: cfg } };
    });
  };

  const resetMat = (key: string) => {
    setStore((s) => {
      const cfg = { ...(s.perModel[s.modelId] || {}) };
      delete cfg[key];
      return { ...s, perModel: { ...s.perModel, [s.modelId]: cfg } };
    });
  };

  // Apply a fix's static params to a texture (wrap/repeat/base offset). The
  // scroll part is animated in the rAF loop.
  const applyStatic = useCallback((m: MatEntry, f: Fix) => {
    const t = m.baseMap;
    t.wrapS = WRAP_THREE[f.wrapS];
    t.wrapT = WRAP_THREE[f.wrapT];
    t.repeat.set(f.repeatX, f.repeatY);
    if (!isAnimated(f)) t.offset.set(f.offsetX, f.offsetY);
    t.needsUpdate = true;
  }, []);

  // -------------------------------------------------------------------------
  // Scene
  // -------------------------------------------------------------------------
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const w = container.clientWidth;
    const h = container.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x141422);
    const camera = new THREE.PerspectiveCamera(50, w / h, 0.1, 2000);
    camera.position.set(0, 12, 20);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 1.0));
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(5, 12, 8);
    scene.add(dir);
    scene.add(new THREE.GridHelper(60, 30, 0x334, 0x223));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;

    sceneRef.current = { scene, camera, renderer, controls, model: null, mats: [] };

    const clock = new THREE.Clock();
    let raf = 0;
    let pulse = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const t = clock.getElapsedTime();
      const dt = clock.getDelta();
      pulse = (pulse + dt) % 1;
      const s = sceneRef.current;
      if (s) {
        // Scroll animation (uv += scroll * time), matching the Godot shader.
        for (const m of s.mats) {
          const f = { ...DEFAULT_FIX, ...(fixRef.current[m.key] || {}) };
          if (isAnimated(f)) {
            m.baseMap.offset.set(f.offsetX + f.scrollX * t, f.offsetY + f.scrollY * t);
          }
          // Highlight the selected material by pulsing its tint toward orange
          // (MeshBasicMaterial is unlit — no emissive channel to use).
          if (m.mat.color) {
            if (selectedRef.current === m.key) {
              const glow = 0.35 + 0.35 * Math.sin(t * 5);
              m.mat.color.copy(m.baseColor).lerp(HIGHLIGHT, glow);
            } else {
              m.mat.color.copy(m.baseColor);
            }
          }
        }
      }
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const onResize = () => {
      const cw = container.clientWidth;
      const ch = container.clientHeight;
      camera.aspect = cw / ch;
      camera.updateProjectionMatrix();
      renderer.setSize(cw, ch);
    };
    window.addEventListener('resize', onResize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
      sceneRef.current = null;
    };
  }, []);

  // -------------------------------------------------------------------------
  // Load model
  // -------------------------------------------------------------------------
  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setIsLoading(true);
    setLoadError(null);
    setSelected(null);
    if (s.model) { s.scene.remove(s.model); s.model = null; }
    s.mats = [];

    const loader = new GLTFLoader();
    let cancelled = false;
    loader.load(assetUrl(modelDef.path), (gltf) => {
      if (cancelled || !sceneRef.current) return;
      const root = gltf.scene;
      // Collect unique materials (by config key) and their meshes.
      const byKey = new Map<string, MatEntry>();
      root.traverse((child) => {
        const mesh = child as THREE.Mesh;
        if (!mesh.isMesh) return;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        for (const raw of materials) {
          const mat = raw as THREE.MeshStandardMaterial;
          if (!mat) continue;
          // PSO GLB meshes carry vertex alpha = 0, so GLTFLoader's transparent
          // materials render invisible (the same trap city_area_base's shader
          // works around: use COLOR.rgb, ignore its alpha). Force opaque +
          // double-sided so the whole model shows in the preview.
          mat.transparent = false;
          mat.alphaTest = 0;
          mat.depthWrite = true;
          mat.side = THREE.DoubleSide;
          if (!mat.map) continue;
          const key = godotTexFilename(mat.map, modelDef.glbBase);
          let entry = byKey.get(key);
          if (!entry) {
            entry = {
              key,
              texName: mat.map.name || '(embedded)',
              mat,
              baseMap: mat.map,
              meshes: [],
              baseColor: (mat.color || new THREE.Color(0xffffff)).clone(),
            };
            byKey.set(key, entry);
          }
          entry.meshes.push(mesh);
        }
      });

      // Center + frame the model.
      const box = new THREE.Box3().setFromObject(root);
      const center = box.getCenter(new THREE.Vector3());
      const size = box.getSize(new THREE.Vector3());
      root.position.sub(center);
      s.scene.add(root);
      s.model = root;
      s.mats = [...byKey.values()];

      // Apply any saved fixes.
      for (const m of s.mats) applyStatic(m, { ...DEFAULT_FIX, ...(fixRef.current[m.key] || {}) });

      const maxDim = Math.max(size.x, size.y, size.z) || 10;
      s.camera.position.set(0, maxDim * 0.5, maxDim * 1.4);
      s.camera.near = maxDim / 1000;
      s.camera.far = maxDim * 100;
      s.camera.updateProjectionMatrix();
      s.controls.target.set(0, 0, 0);
      s.controls.update();

      setMats(s.mats.map((m) => ({ key: m.key, texName: m.texName })));
      setIsLoading(false);
    }, undefined, (err) => {
      setLoadError(`Failed to load ${modelDef.path}: ${err}`);
      setIsLoading(false);
    });
    return () => { cancelled = true; };
  }, [store.modelId, modelDef.path, modelDef.glbBase, applyStatic]);

  // Re-apply static params whenever the config changes.
  useEffect(() => {
    const s = sceneRef.current;
    if (!s) return;
    for (const m of s.mats) applyStatic(m, { ...DEFAULT_FIX, ...(config[m.key] || {}) });
  }, [config, applyStatic]);

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------
  const buildConfigJson = useCallback((): string => {
    // Emit only non-default materials, keyed <file>#1, matching the game's
    // lookup order. Field order mirrors the existing global-texture-fixes.json.
    const out: Record<string, Record<string, number | string>> = {};
    for (const m of mats) {
      const f = getFix(m.key);
      if (isDefault(f)) continue;
      const entry: Record<string, number | string> = {
        offsetX: f.offsetX, offsetY: f.offsetY,
        repeatX: f.repeatX, repeatY: f.repeatY,
        wrapS: f.wrapS, wrapT: f.wrapT,
      };
      if (isAnimated(f)) { entry.scrollX = f.scrollX; entry.scrollY = f.scrollY; }
      out[`${m.key}#1`] = entry;
    }
    return JSON.stringify(out, null, 2);
  }, [mats, config]);  // eslint-disable-line react-hooks/exhaustive-deps

  const copyConfig = useCallback(() => {
    const json = buildConfigJson();
    navigator.clipboard.writeText(json);
    setCopied('Copied — merge these keys into data/stage_configs/global-texture-fixes.json');
    setTimeout(() => setCopied(''), 4000);
  }, [buildConfigJson]);

  // -------------------------------------------------------------------------
  const sel = selected;
  const selFix = sel ? getFix(sel) : null;
  const animCount = mats.filter((m) => isAnimated(getFix(m.key))).length;
  const fixCount = mats.filter((m) => !isDefault(getFix(m.key))).length;

  const numRow = (label: string, val: number, min: number, max: number, step: number, on: (v: number) => void) => (
    <div style={{ marginBottom: 7 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: '#aaa' }}>
        <span>{label}</span><span style={{ color: '#fff', fontVariantNumeric: 'tabular-nums' }}>{val.toFixed(2)}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={val}
        onChange={(e) => on(parseFloat(e.target.value))} style={{ width: '100%' }} />
    </div>
  );

  const wrapRow = (label: string, val: WrapMode, on: (v: WrapMode) => void) => (
    <div style={{ marginBottom: 7 }}>
      <div style={{ fontSize: 11, color: '#aaa', marginBottom: 2 }}>{label}</div>
      <div style={{ display: 'flex', gap: 4 }}>
        {(['repeat', 'mirror', 'clamp'] as WrapMode[]).map((wm) => (
          <button key={wm} onClick={() => on(wm)} style={{
            flex: 1, padding: '4px 2px', fontSize: 11, cursor: 'pointer', borderRadius: 3,
            background: val === wm ? '#2a4a6a' : '#1a1a2e',
            border: `1px solid ${val === wm ? '#6b8afd' : '#444'}`,
            color: val === wm ? '#fff' : '#999',
          }}>{wm}</button>
        ))}
      </div>
    </div>
  );

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: 16, boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: 16, height: '100%' }}>
        {/* Viewport */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
          <div style={{
            background: '#2d2d44', borderRadius: 8, padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16,
          }}>
            <span style={{ fontSize: 14, fontWeight: 'bold', color: '#6bf' }}>
              Texture Animation — {modelDef.label}
            </span>
            <span style={{ fontSize: 12, color: '#888' }}>
              {mats.length} materials · {animCount} animated · {fixCount} with fixes
            </span>
            {isLoading && <span style={{ color: '#888', fontSize: 12 }}>(loading…)</span>}
            {loadError && <span style={{ color: '#f88', fontSize: 12 }}>{loadError}</span>}
          </div>
          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: 8, overflow: 'hidden', position: 'relative' }} ref={containerRef}>
            <div style={{
              position: 'absolute', left: 10, bottom: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              drag-orbit · scroll-zoom · selected material glows orange · scroll animates live
            </div>
          </div>
        </div>

        {/* Right panel */}
        <div style={{
          width: 340, background: '#2d2d44', borderRadius: 8, padding: 12,
          overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          {/* Model */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Model</h3>
            <select value={store.modelId}
              onChange={(e) => setStore((s) => ({ ...s, modelId: e.target.value }))}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12 }}>
              {MODELS.map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
            </select>
          </div>

          {/* Material list */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Materials ({mats.length})
            </h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2, maxHeight: 200, overflowY: 'auto' }}>
              {mats.map((m) => {
                const f = getFix(m.key);
                const active = selected === m.key;
                const anim = isAnimated(f);
                const fixed = !isDefault(f);
                return (
                  <button key={m.key} onClick={() => setSelected(m.key)} style={{
                    textAlign: 'left', padding: '5px 8px', fontSize: 11, cursor: 'pointer', borderRadius: 3,
                    background: active ? '#2a4a6a' : '#1a1a2e',
                    border: `1px solid ${active ? '#6b8afd' : '#2a2a3e'}`,
                    color: active ? '#fff' : '#bbb',
                    display: 'flex', justifyContent: 'space-between', gap: 6,
                  }}>
                    <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.key}</span>
                    <span style={{ flexShrink: 0 }}>{anim ? '▶' : fixed ? '◆' : ''}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Selected material controls */}
          {sel && selFix && (
            <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
              <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 4px 0', textTransform: 'uppercase' }}>Fix</h3>
              <div style={{ fontSize: 10, color: '#778', marginBottom: 8, wordBreak: 'break-all' }}>
                key: <code style={{ color: '#9bf' }}>{sel}#1</code>
              </div>
              <div style={{ fontSize: 10, color: '#8a8', margin: '0 0 6px 0' }}>Scroll (animates — makes it a waterfall entry)</div>
              {numRow('scrollX', selFix.scrollX, -2, 2, 0.01, (v) => setFix(sel, { scrollX: v }))}
              {numRow('scrollY', selFix.scrollY, -2, 2, 0.01, (v) => setFix(sel, { scrollY: v }))}
              <div style={{ fontSize: 10, color: '#88a', margin: '8px 0 6px 0' }}>Tiling / offset</div>
              {numRow('repeatX', selFix.repeatX, 0.1, 8, 0.1, (v) => setFix(sel, { repeatX: v }))}
              {numRow('repeatY', selFix.repeatY, 0.1, 8, 0.1, (v) => setFix(sel, { repeatY: v }))}
              {numRow('offsetX', selFix.offsetX, -1, 1, 0.01, (v) => setFix(sel, { offsetX: v }))}
              {numRow('offsetY', selFix.offsetY, -1, 1, 0.01, (v) => setFix(sel, { offsetY: v }))}
              <div style={{ margin: '8px 0 6px 0' }} />
              {wrapRow('wrapS', selFix.wrapS, (v) => setFix(sel, { wrapS: v }))}
              {wrapRow('wrapT', selFix.wrapT, (v) => setFix(sel, { wrapT: v }))}
              <button onClick={() => resetMat(sel)} style={{
                marginTop: 6, width: '100%', padding: 6, fontSize: 11, cursor: 'pointer', borderRadius: 3,
                background: '#1a1a2e', border: '1px solid #444', color: '#aaa',
              }}>Reset this material</button>
            </div>
          )}

          {/* Export */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <button onClick={copyConfig} disabled={fixCount === 0} style={{
              padding: 10, borderRadius: 4, fontSize: 12, fontWeight: 'bold',
              cursor: fixCount > 0 ? 'pointer' : 'not-allowed',
              background: fixCount > 0 ? '#2a4a6a' : '#1a1a2e',
              border: `1px solid ${fixCount > 0 ? '#6b8afd' : '#444'}`,
              color: fixCount > 0 ? '#fff' : '#555',
            }}>Copy global-texture-fixes ({fixCount})</button>
            {copied && <div style={{ fontSize: 10, color: '#6f9' }}>{copied}</div>}
            <div style={{ fontSize: 10, color: '#666' }}>
              Keys are the Godot-extracted texture filename + <code>#1</code>, matching
              <code> city_area_base._find_global_fix_for_material</code>. A scroll makes
              a material an animated (waterfall) entry; static repeat/offset/wrap use the
              texture-fix shader. Verify the key matches the on-disk
              <code> s00e_sa2_m_*.png</code> names.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
