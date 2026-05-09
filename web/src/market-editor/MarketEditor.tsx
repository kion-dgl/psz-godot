import { useCallback, useEffect, useMemo, useState } from 'react';
import * as THREE from 'three';
import { GLTFExporter } from 'three-stdlib';
import MarketCanvas from './MarketCanvas';
import {
  type ActionEntry,
  type CartTransform,
  type FaceMark,
  type Mode,
  type TransformMode,
  DEFAULT_CART_TRANSFORM,
  faceKey,
} from './types';

const STORAGE_KEY = 'market-editor-actions-v4';
const MODE_KEY = 'market-editor-mode-v5';
const CART_KEY = 'market-editor-cart-transform-v1';
const TRANSFORM_MODE_KEY = 'market-editor-transform-mode-v1';

function loadActions(): ActionEntry[] {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (!saved) return [];
    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed)) return [];
    const out: ActionEntry[] = [];
    for (const a of parsed) {
      if (a && a.kind === 'mesh' && typeof a.name === 'string') {
        out.push({ kind: 'mesh', name: a.name });
      } else if (
        a &&
        a.kind === 'face' &&
        a.mark &&
        typeof a.mark.meshName === 'string' &&
        typeof a.mark.faceIndex === 'number' &&
        isVec3(a.mark.v0) &&
        isVec3(a.mark.v1) &&
        isVec3(a.mark.v2)
      ) {
        out.push({ kind: 'face', mark: a.mark as FaceMark });
      }
    }
    return out;
  } catch {
    return [];
  }
}

function loadMode(): Mode {
  const v = localStorage.getItem(MODE_KEY);
  return v === 'mesh' || v === 'face' || v === 'place' ? v : 'place';
}

function isVec3(v: unknown): v is [number, number, number] {
  return (
    Array.isArray(v) &&
    v.length === 3 &&
    v.every((n) => typeof n === 'number' && Number.isFinite(n))
  );
}

function loadTransformMode(): TransformMode {
  const v = localStorage.getItem(TRANSFORM_MODE_KEY);
  return v === 'rotate' || v === 'scale' ? v : 'translate';
}

function loadCartTransform(): CartTransform {
  try {
    const saved = localStorage.getItem(CART_KEY);
    if (!saved) return DEFAULT_CART_TRANSFORM;
    const parsed = JSON.parse(saved);
    if (
      Array.isArray(parsed.pos) && parsed.pos.length === 3 &&
      Array.isArray(parsed.rot) && parsed.rot.length === 3 &&
      Array.isArray(parsed.scale) && parsed.scale.length === 3
    ) {
      return parsed as CartTransform;
    }
  } catch {
    // fall through
  }
  return DEFAULT_CART_TRANSFORM;
}

/** Build a Godot Transform3D 12-float string from position + euler XYZ +
 *  scale. Both engines are right-handed Y-up so no axis flipping; we
 *  just reuse three.js's matrix composition and read the column vectors
 *  in the order Godot's tscn-style constructor expects (x_axis,
 *  y_axis, z_axis, origin). */
function buildTransform3D(t: CartTransform): string {
  const m = new THREE.Matrix4();
  const pos = new THREE.Vector3(...t.pos);
  const quat = new THREE.Quaternion().setFromEuler(
    new THREE.Euler(t.rot[0], t.rot[1], t.rot[2], 'XYZ')
  );
  const scale = new THREE.Vector3(...t.scale);
  m.compose(pos, quat, scale);
  const e = m.elements;
  // Three.js Matrix4 is column-major: e[0..3]=col0, e[4..7]=col1, etc.
  // Godot's 12-float Transform3D ctor wants x_axis, y_axis, z_axis,
  // origin — exactly columns 0, 1, 2, 3 of a right-handed transform.
  // Always keep at least one decimal digit so GDScript sees these as
  // floats — its Transform3D ctor signature is all-float, and "0" reads
  // as int in GDScript and trips a parse error.
  const fmt = (n: number) => {
    let s = n.toFixed(4);
    if (s.includes('.')) {
      s = s.replace(/(\.\d*?)0+$/, '$1');
      if (s.endsWith('.')) s += '0';
    }
    return s;
  };
  // GDScript's runtime Transform3D ctor takes four Vector3s (x_axis,
  // y_axis, z_axis, origin) — the 12-float form is .tscn-only and
  // raises a parse error from a script.
  const v3 = (a: number, b: number, c: number) =>
    `Vector3(${fmt(a)}, ${fmt(b)}, ${fmt(c)})`;
  return [
    v3(e[0], e[1], e[2]),
    v3(e[4], e[5], e[6]),
    v3(e[8], e[9], e[10]),
    v3(e[12], e[13], e[14]),
  ].join(', ');
}

export default function MarketEditor() {
  const [actions, setActions] = useState<ActionEntry[]>(loadActions);
  const [mode, setMode] = useState<Mode>(loadMode);
  const [transformMode, setTransformMode] = useState<TransformMode>(loadTransformMode);
  const [cartTransform, setCartTransform] = useState<CartTransform>(loadCartTransform);
  // Reference to the loaded market THREE.Scene — populated by
  // MarketCanvas once the GLB finishes loading. Used by the export
  // button to feed the scene into GLTFExporter, which respects the
  // live `visible` flags + filtered geometry indices.
  const [marketScene, setMarketScene] = useState<THREE.Object3D | null>(null);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(actions));
  }, [actions]);
  useEffect(() => {
    localStorage.setItem(MODE_KEY, mode);
  }, [mode]);
  useEffect(() => {
    localStorage.setItem(TRANSFORM_MODE_KEY, transformMode);
  }, [transformMode]);
  useEffect(() => {
    localStorage.setItem(CART_KEY, JSON.stringify(cartTransform));
  }, [cartTransform]);

  const markedMeshes = useMemo(() => {
    const s = new Set<string>();
    for (const a of actions) if (a.kind === 'mesh') s.add(a.name);
    return s;
  }, [actions]);

  const markedFaces = useMemo(() => {
    const m = new Map<string, FaceMark>();
    for (const a of actions) if (a.kind === 'face') m.set(faceKey(a.mark), a.mark);
    return m;
  }, [actions]);

  const onMeshPick = useCallback((name: string) => {
    setActions((prev) => {
      if (prev.some((a) => a.kind === 'mesh' && a.name === name)) return prev;
      return [...prev, { kind: 'mesh', name }];
    });
  }, []);

  const onFacePick = useCallback((mark: FaceMark) => {
    setActions((prev) => {
      const k = faceKey(mark);
      if (prev.some((a) => a.kind === 'face' && faceKey(a.mark) === k)) return prev;
      return [...prev, { kind: 'face', mark }];
    });
  }, []);

  const undo = useCallback(() => {
    setActions((prev) => (prev.length === 0 ? prev : prev.slice(0, -1)));
  }, []);

  const removeAt = useCallback((idx: number) => {
    setActions((prev) => prev.filter((_, i) => i !== idx));
  }, []);

  const clear = useCallback(() => setActions([]), []);

  const resetCart = useCallback(() => setCartTransform(DEFAULT_CART_TRANSFORM), []);

  /** Export the live market scene as a binary glTF (.glb), with hidden
   *  meshes skipped (`onlyVisible: true` is GLTFExporter's default) and
   *  the current geometry.index — which the editor has been mutating in
   *  place to filter out flagged faces — used as-is. The user gets a
   *  file download they can drop into assets/.../*_no_cart.glb and
   *  reference from city_market.tscn. */
  const downloadGLB = useCallback(() => {
    if (!marketScene) return;
    const exporter = new GLTFExporter();
    exporter.parse(
      marketScene,
      (result) => {
        if (!(result instanceof ArrayBuffer)) return;
        const blob = new Blob([result], { type: 'model/gltf-binary' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 's00e_sa1_m_no_cart.glb';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        // Defer revoke so the download has time to start in all browsers.
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      },
      (err) => {
        // eslint-disable-next-line no-console
        console.error('[market-editor] GLTFExporter failed:', err);
      },
      { binary: true, onlyVisible: true }
    );
  }, [marketScene]);

  // Hotkeys: ⌘Z undo (mesh/face mode), G/R/S to pick gizmo (place mode).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
      if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        undo();
        return;
      }
      if (mode === 'place' && !e.ctrlKey && !e.metaKey) {
        if (e.key === 'g' || e.key === 't') setTransformMode('translate');
        else if (e.key === 'r') setTransformMode('rotate');
        else if (e.key === 's') setTransformMode('scale');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [undo, mode]);

  const facesByMesh = useMemo(() => {
    const m = new Map<string, number[]>();
    for (const f of markedFaces.values()) {
      let arr = m.get(f.meshName);
      if (!arr) {
        arr = [];
        m.set(f.meshName, arr);
      }
      arr.push(f.faceIndex);
    }
    for (const arr of m.values()) arr.sort((a, b) => a - b);
    return m;
  }, [markedFaces]);

  const sortedMeshNames = useMemo(() => Array.from(markedMeshes).sort(), [markedMeshes]);
  const sortedFaceMeshNames = useMemo(
    () => Array.from(facesByMesh.keys()).filter((n) => !markedMeshes.has(n)).sort(),
    [facesByMesh, markedMeshes]
  );

  const hideSnippet = useMemo(() => {
    const lines: string[] = [];
    if (sortedMeshNames.length > 0) {
      const meshList = sortedMeshNames.map((n) => `\t"${n}",`).join('\n');
      lines.push(`const HIDDEN_MARKET_MESHES := [`, meshList, `]`);
    }
    if (sortedFaceMeshNames.length > 0) {
      if (lines.length > 0) lines.push('');
      const rows = sortedFaceMeshNames.map((name) => {
        const faces = facesByMesh.get(name)!;
        return `\t{"mesh": "${name}", "faces": [${faces.join(', ')}]},`;
      });
      lines.push(`const HIDDEN_MARKET_FACES := [`, ...rows, `]`);
    }
    return lines.join('\n');
  }, [sortedMeshNames, sortedFaceMeshNames, facesByMesh]);

  const placeSnippet = useMemo(() => {
    const t3d = buildTransform3D(cartTransform);
    // Split the four Vector3 args onto their own lines so a long, dense
    // transform stays scannable when pasted into the controller.
    const args = t3d.split(', V').map((s, i) => (i === 0 ? s : 'V' + s));
    return [
      `## Weapon-shop replacement cart. Generated by /market-editor.`,
      `## Drop into city_market_controller.gd:`,
      `const WEAPON_SHOP_CART_SCENE := preload("res://assets/stages/city_e/market/weapon_shop/weapon_shop_cart.glb")`,
      ``,
      `func _add_weapon_shop_cart() -> void:`,
      `\tvar cart: Node3D = WEAPON_SHOP_CART_SCENE.instantiate()`,
      `\tcart.transform = Transform3D(`,
      ...args.map((a, i) => `\t\t${a}${i < args.length - 1 ? ',' : ''}`),
      `\t)`,
      `\tadd_child(cart)`,
    ].join('\n');
  }, [cartTransform]);

  const activeSnippet = mode === 'place' ? placeSnippet : hideSnippet;

  const copy = useCallback(async () => {
    if (!activeSnippet) return;
    try {
      await navigator.clipboard.writeText(activeSnippet);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = activeSnippet;
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand('copy');
      } finally {
        document.body.removeChild(ta);
      }
    }
  }, [activeSnippet]);

  const reversedActions = useMemo(() => {
    const arr = actions.map((a, i) => ({ a, i }));
    arr.reverse();
    return arr;
  }, [actions]);

  return (
    <div style={{ display: 'flex', height: '100%' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <MarketCanvas
          mode={mode}
          markedMeshes={markedMeshes}
          markedFaces={markedFaces}
          onMeshPick={onMeshPick}
          onFacePick={onFacePick}
          cartTransform={cartTransform}
          transformMode={transformMode}
          onCartChange={setCartTransform}
          onSceneReady={setMarketScene}
        />
      </div>
      <aside
        style={{
          width: 380,
          background: '#12122a',
          borderLeft: '1px solid #2a2a4a',
          color: '#cfd0e8',
          display: 'flex',
          flexDirection: 'column',
          padding: 12,
          gap: 12,
          overflow: 'auto',
        }}
      >
        <div>
          <h2 style={{ margin: 0, fontSize: 16, color: '#fff' }}>Market Editor</h2>
        </div>

        <div
          style={{
            display: 'flex',
            background: '#0e0e22',
            borderRadius: 4,
            padding: 2,
            gap: 2,
          }}
        >
          {(['mesh', 'face', 'place'] as const).map((m) => (
            <button
              key={m}
              onClick={() => setMode(m)}
              style={{
                flex: 1,
                background: mode === m ? '#3a3a66' : 'transparent',
                color: mode === m ? '#fff' : '#888',
                border: 'none',
                borderRadius: 3,
                padding: '6px 0',
                fontSize: 12,
                fontWeight: mode === m ? 600 : 400,
                cursor: 'pointer',
                textTransform: 'capitalize',
              }}
            >
              {m}
            </button>
          ))}
        </div>

        {mode === 'place' ? (
          <PlacePanel
            transform={cartTransform}
            onChange={setCartTransform}
            transformMode={transformMode}
            setTransformMode={setTransformMode}
            onReset={resetCart}
            snippet={placeSnippet}
            onCopy={copy}
          />
        ) : (
          <HidePanel
            mode={mode}
            actions={actions}
            reversedActions={reversedActions}
            markedMeshes={markedMeshes}
            markedFaces={markedFaces}
            onUndo={undo}
            onClear={clear}
            onRemoveAt={removeAt}
            snippet={hideSnippet}
            onCopy={copy}
            onDownloadGLB={downloadGLB}
            canDownloadGLB={marketScene != null}
          />
        )}
      </aside>
    </div>
  );
}

// ── Panels ────────────────────────────────────────────────────────────────

interface PlacePanelProps {
  transform: CartTransform;
  onChange: (t: CartTransform) => void;
  transformMode: TransformMode;
  setTransformMode: (m: TransformMode) => void;
  onReset: () => void;
  snippet: string;
  onCopy: () => void;
}

const RAD2DEG = 180 / Math.PI;

function PlacePanel({
  transform,
  onChange,
  transformMode,
  setTransformMode,
  onReset,
  snippet,
  onCopy,
}: PlacePanelProps) {
  const setAxis = (axis: 'pos' | 'rot' | 'scale', i: number, value: number) => {
    const next: CartTransform = {
      pos: [...transform.pos] as [number, number, number],
      rot: [...transform.rot] as [number, number, number],
      scale: [...transform.scale] as [number, number, number],
    };
    next[axis][i] = value;
    onChange(next);
  };

  return (
    <>
      <p style={{ margin: 0, fontSize: 12, color: '#888' }}>
        Drag the gizmo to position the new cart over the existing weapon shop.
        Hotkeys: <kbd style={kbdStyle}>G</kbd> translate · <kbd style={kbdStyle}>R</kbd> rotate ·{' '}
        <kbd style={kbdStyle}>S</kbd> scale.
      </p>

      <div
        style={{
          display: 'flex',
          background: '#0e0e22',
          borderRadius: 4,
          padding: 2,
          gap: 2,
        }}
      >
        {(['translate', 'rotate', 'scale'] as const).map((m) => (
          <button
            key={m}
            onClick={() => setTransformMode(m)}
            style={{
              flex: 1,
              background: transformMode === m ? '#3a3a66' : 'transparent',
              color: transformMode === m ? '#fff' : '#888',
              border: 'none',
              borderRadius: 3,
              padding: '6px 0',
              fontSize: 11,
              fontWeight: transformMode === m ? 600 : 400,
              cursor: 'pointer',
              textTransform: 'capitalize',
            }}
          >
            {m}
          </button>
        ))}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <NumberRow
          label="Position"
          values={transform.pos}
          onChange={(i, v) => setAxis('pos', i, v)}
          step={0.1}
        />
        <NumberRow
          label="Rotation (°)"
          values={transform.rot.map((r) => r * RAD2DEG) as [number, number, number]}
          onChange={(i, v) => setAxis('rot', i, v / RAD2DEG)}
          step={5}
        />
        <NumberRow
          label="Scale"
          values={transform.scale}
          onChange={(i, v) => setAxis('scale', i, v)}
          step={0.1}
        />
      </div>

      <button
        onClick={onReset}
        style={{
          background: 'transparent',
          color: '#ff8888',
          border: '1px solid #552222',
          borderRadius: 4,
          padding: '4px 10px',
          fontSize: 11,
          cursor: 'pointer',
          alignSelf: 'flex-start',
        }}
      >
        reset to default
      </button>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: 13 }}>Godot snippet</span>
          <button
            onClick={onCopy}
            style={{
              background: '#3a3a66',
              color: '#fff',
              border: 'none',
              borderRadius: 4,
              padding: '4px 10px',
              fontSize: 12,
              cursor: 'pointer',
            }}
          >
            copy
          </button>
        </div>
        <pre
          style={{
            background: '#0e0e22',
            color: '#cfd0e8',
            padding: 8,
            borderRadius: 4,
            fontSize: 11,
            margin: 0,
            overflow: 'auto',
            maxHeight: 280,
          }}
        >
          {snippet}
        </pre>
      </div>
    </>
  );
}

interface HidePanelProps {
  mode: Mode;
  actions: ActionEntry[];
  reversedActions: { a: ActionEntry; i: number }[];
  markedMeshes: Set<string>;
  markedFaces: Map<string, FaceMark>;
  onUndo: () => void;
  onClear: () => void;
  onRemoveAt: (idx: number) => void;
  snippet: string;
  onCopy: () => void;
  onDownloadGLB: () => void;
  canDownloadGLB: boolean;
}

function HidePanel({
  mode,
  actions,
  reversedActions,
  markedMeshes,
  markedFaces,
  onUndo,
  onClear,
  onRemoveAt,
  snippet,
  onCopy,
  onDownloadGLB,
  canDownloadGLB,
}: HidePanelProps) {
  return (
    <>
      <p style={{ margin: 0, fontSize: 12, color: '#888' }}>
        <b>Mesh mode</b>: click hides an entire submesh. <b>Face mode</b>: click hides one
        triangle. <kbd style={kbdStyle}>⌘Z</kbd> undoes the last click.
      </p>

      <div style={{ display: 'flex', gap: 6 }}>
        <button
          onClick={onUndo}
          disabled={actions.length === 0}
          style={{
            flex: 1,
            background: actions.length === 0 ? '#1a1a35' : '#3a3a66',
            color: actions.length === 0 ? '#555' : '#fff',
            border: 'none',
            borderRadius: 4,
            padding: '6px 10px',
            fontSize: 13,
            cursor: actions.length === 0 ? 'default' : 'pointer',
          }}
        >
          ↶ Undo
        </button>
        <button
          onClick={onClear}
          disabled={actions.length === 0}
          style={{
            background: 'transparent',
            color: actions.length === 0 ? '#444' : '#ff8888',
            border: '1px solid',
            borderColor: actions.length === 0 ? '#2a2a4a' : '#552222',
            borderRadius: 4,
            padding: '6px 10px',
            fontSize: 12,
            cursor: actions.length === 0 ? 'default' : 'pointer',
          }}
        >
          clear
        </button>
      </div>

      <div style={{ fontSize: 12, color: '#888' }}>
        {actions.length === 0
          ? `Click a ${mode} in the canvas to flag it.`
          : `${markedMeshes.size} mesh${markedMeshes.size === 1 ? '' : 'es'} • ${markedFaces.size} face${markedFaces.size === 1 ? '' : 's'} flagged`}
      </div>

      <button
        onClick={onDownloadGLB}
        disabled={!canDownloadGLB}
        style={{
          background: canDownloadGLB ? '#2a4d3a' : '#1a1a35',
          color: canDownloadGLB ? '#fff' : '#555',
          border: '1px solid',
          borderColor: canDownloadGLB ? '#3d6650' : '#2a2a4a',
          borderRadius: 4,
          padding: '8px 12px',
          fontSize: 12,
          cursor: canDownloadGLB ? 'pointer' : 'default',
          fontWeight: 600,
        }}
        title="Bake current visibility + face filters into a new s00e_sa1_m_no_cart.glb"
      >
        ↓ Download s00e_sa1_m_no_cart.glb
      </button>

      {actions.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <div style={{ fontSize: 11, color: '#666', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Recent first
          </div>
          <ul
            style={{
              listStyle: 'none',
              margin: 0,
              padding: 0,
              display: 'flex',
              flexDirection: 'column',
              gap: 2,
              maxHeight: 200,
              overflow: 'auto',
            }}
          >
            {reversedActions.map(({ a, i }, displayIdx) => (
              <li
                key={`${i}-${a.kind === 'mesh' ? a.name : faceKey(a.mark)}`}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 6,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  background: displayIdx === 0 ? '#1f2040' : '#1a1a35',
                  padding: '3px 8px',
                  borderRadius: 3,
                }}
              >
                <span
                  style={{
                    flex: 1,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                    color: '#cfd0e8',
                  }}
                >
                  <span
                    style={{ color: a.kind === 'mesh' ? '#88c0ff' : '#ffaa66', marginRight: 6 }}
                  >
                    {a.kind === 'mesh' ? 'M' : 'F'}
                  </span>
                  {a.kind === 'mesh' ? (
                    a.name
                  ) : (
                    <>
                      {a.mark.meshName}
                      <span style={{ color: '#666' }}> #{a.mark.faceIndex}</span>
                    </>
                  )}
                </span>
                <button
                  onClick={() => onRemoveAt(i)}
                  style={{
                    background: 'transparent',
                    color: '#888',
                    border: 'none',
                    cursor: 'pointer',
                    fontSize: 14,
                    padding: 0,
                    lineHeight: 1,
                  }}
                  title="restore"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {snippet && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 13 }}>Godot snippet</span>
            <button
              onClick={onCopy}
              style={{
                background: '#3a3a66',
                color: '#fff',
                border: 'none',
                borderRadius: 4,
                padding: '4px 10px',
                fontSize: 12,
                cursor: 'pointer',
              }}
            >
              copy
            </button>
          </div>
          <pre
            style={{
              background: '#0e0e22',
              color: '#cfd0e8',
              padding: 8,
              borderRadius: 4,
              fontSize: 11,
              margin: 0,
              overflow: 'auto',
              maxHeight: 240,
            }}
          >
            {snippet}
          </pre>
        </div>
      )}
    </>
  );
}

// ── Small bits ────────────────────────────────────────────────────────────

const kbdStyle = {
  padding: '0 4px',
  background: '#2a2a4a',
  borderRadius: 2,
  fontSize: 10,
  fontFamily: 'monospace',
} as const;

interface NumberRowProps {
  label: string;
  values: [number, number, number];
  onChange: (i: number, v: number) => void;
  step: number;
}

function NumberRow({ label, values, onChange, step }: NumberRowProps) {
  const axes = ['X', 'Y', 'Z'];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
      <div style={{ fontSize: 11, color: '#888' }}>{label}</div>
      <div style={{ display: 'flex', gap: 4 }}>
        {values.map((v, i) => (
          <label
            key={i}
            style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              gap: 4,
              background: '#0e0e22',
              padding: '4px 6px',
              borderRadius: 3,
              fontSize: 11,
              fontFamily: 'monospace',
            }}
          >
            <span style={{ color: '#888' }}>{axes[i]}</span>
            <input
              type="number"
              value={v.toFixed(3)}
              step={step}
              onChange={(e) => {
                const n = parseFloat(e.target.value);
                if (!isNaN(n)) onChange(i, n);
              }}
              style={{
                flex: 1,
                width: '100%',
                background: 'transparent',
                color: '#cfd0e8',
                border: 'none',
                fontSize: 11,
                fontFamily: 'monospace',
                outline: 'none',
                padding: 0,
              }}
            />
          </label>
        ))}
      </div>
    </div>
  );
}
