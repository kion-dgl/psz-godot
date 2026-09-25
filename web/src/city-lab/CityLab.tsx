import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { GLTFExporter } from 'three-stdlib';
import * as THREE from 'three';
import { localAssetUrl, checkAssetDrift } from '../utils/assets';
import CityLabCanvas, { type FacePick } from './CityLabCanvas';
import {
  STAGES,
  stageById,
  type AuditStats,
  type CityLabMode,
  type LightSpec,
  type TriangleIssue,
  type Vec3,
} from './types';
import { auditTriangles, faceArea, type TriFace } from './triangleAudit';
import { lightsGdscript, parseLightsDoc, toLightsDoc } from './lightExport';
import { PRESET_INTERIOR, PRESET_POOL, legacyCounterLights, newLight } from './lightingRig';

/**
 * City Lab — one tool view for the custom city maps.
 *
 *  Inspect    click anything: mesh/material/face reference values.
 *  Triangles  audit malformed faces (market), mark + export a fixed GLB.
 *  Lighting   author the guild-counter rig (#656) in Godot units, A/B
 *             against the live scene rig, save the data-driven sidecar
 *             that city_area_base._add_authored_lights loads.
 */

const LS_STAGE = 'city-lab-stage';
const LS_MODE = 'city-lab-mode';
const lsMarksKey = (id: string) => `city-lab-marks-${id}`;
const lsLightsKey = (id: string) => `city-lab-lights-${id}`;

interface MarkEntry {
  mesh: string;
  face: number;
}

interface LightsDraft {
  ambient: { color: Vec3; energy: number };
  sunEnergy: number;
  lights: LightSpec[];
}

function loadJson<T>(key: string, guard: (v: unknown) => v is T): T | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return guard(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

const isMarkArray = (v: unknown): v is MarkEntry[] =>
  Array.isArray(v) &&
  v.every((e) => e && typeof (e as MarkEntry).mesh === 'string' && typeof (e as MarkEntry).face === 'number');

const isLightsDraft = (v: unknown): v is LightsDraft =>
  typeof v === 'object' && v !== null && Array.isArray((v as LightsDraft).lights);

const fmt = (n: number): string =>
  Number.isFinite(n) ? n.toFixed(Math.abs(n) < 0.01 ? 6 : 3) : String(n);

/** Stable empty map — passing inline `new Map()` would re-run the stage's
 *  index-restore effect on every render outside triangles mode. */
const NO_MARKS = new Map<string, Set<number>>();

/** Keeps the toolbar alive when a stage GLB fails to load (the R2 dev URL
 *  is CORS-locked to the GitHub Pages origin — a local dev server without
 *  web/public/assets symlinks shows exactly that). */
class CanvasBoundary extends React.Component<
  { children: React.ReactNode },
  { error: string | null }
> {
  state = { error: null as string | null };

  static getDerivedStateFromError(err: unknown) {
    return { error: err instanceof Error ? err.message : String(err) };
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ ...panelStyle, borderLeft: 'none', width: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <div style={{ color: '#f66', fontSize: 14, marginBottom: 8 }}>stage GLB failed to load</div>
          <div style={{ color: '#aaa', fontSize: 12, lineHeight: 1.6 }}>{this.state.error}</div>
          <div style={{ color: '#666', fontSize: 11, marginTop: 12, lineHeight: 1.6 }}>
            Dev serving of stage assets needs the web/public/assets symlinks and a local
            assets tree (see scripts/tools/fetch_assets_dev.sh), or run against the
            published CDN origin. The toolbar and panels stay usable.
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

const panelStyle: React.CSSProperties = {
  width: 400,
  flexShrink: 0,
  background: '#12122a',
  borderLeft: '1px solid #2a2a4a',
  color: '#ccc',
  fontSize: 13,
  padding: 12,
  overflowY: 'auto',
};

const sectionTitle: React.CSSProperties = {
  margin: '14px 0 6px',
  fontSize: 11,
  letterSpacing: 1,
  textTransform: 'uppercase',
  color: '#88aaff',
  fontWeight: 600,
};

const btn = (bg: string): React.CSSProperties => ({
  background: bg,
  color: '#fff',
  border: 'none',
  borderRadius: 4,
  fontSize: 12,
  padding: '6px 10px',
  cursor: 'pointer',
  marginRight: 6,
});

const input: React.CSSProperties = {
  background: '#1b1c38',
  border: '1px solid #2a2a4a',
  borderRadius: 3,
  color: '#ddd',
  fontSize: 12,
  padding: '4px 6px',
  width: 70,
  fontFamily: 'monospace',
};

export default function CityLab() {
  const [stageId, setStageId] = useState<string>(
    () => localStorage.getItem(LS_STAGE) ?? STAGES[0].id,
  );
  const [mode, setMode] = useState<CityLabMode>(
    () => (localStorage.getItem(LS_MODE) as CityLabMode) ?? 'inspect',
  );
  const def = useMemo(() => stageById(stageId), [stageId]);

  const [pick, setPick] = useState<FacePick | null>(null);
  const [auditByStage, setAuditByStage] = useState<Record<string, { issues: TriangleIssue[]; stats: AuditStats }>>({});
  const [marksByStage, setMarksByStage] = useState<Record<string, MarkEntry[]>>({});
  const [focusKey, setFocusKey] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [drift, setDrift] = useState<string | null>(null);

  const rootRef = useRef<THREE.Object3D | null>(null);
  const gltfsRef = useRef<Record<string, THREE.Object3D> | null>(null);

  /* ------------------------------------------------------------ */
  /* Persistence                                                   */
  /* ------------------------------------------------------------ */
  useEffect(() => localStorage.setItem(LS_STAGE, stageId), [stageId]);
  useEffect(() => localStorage.setItem(LS_MODE, mode), [mode]);

  const marks = useMemo(() => marksByStage[def.id] ?? loadJson(lsMarksKey(def.id), isMarkArray) ?? [], [marksByStage, def.id]);
  const setMarks = useCallback(
    (update: MarkEntry[] | ((prev: MarkEntry[]) => MarkEntry[])) => {
      // Functional form so rapid marks (e.g. scripting the ⨯ row buttons
      // in sequence) don't each compute from the same stale array.
      setMarksByStage((prev) => {
        const current = prev[def.id] ?? loadJson(lsMarksKey(def.id), isMarkArray) ?? [];
        const next = typeof update === 'function' ? update(current) : update;
        localStorage.setItem(lsMarksKey(def.id), JSON.stringify(next));
        return { ...prev, [def.id]: next };
      });
    },
    [def.id],
  );

  const defaultDraft = useCallback(
    (): LightsDraft => ({
      ambient: { color: [...def.sceneRig.ambientColor] as Vec3, energy: def.sceneRig.ambientEnergy },
      sunEnergy: def.sceneRig.sunEnergy,
      lights: [],
    }),
    [def],
  );
  const [draftByStage, setDraftByStage] = useState<Record<string, LightsDraft>>({});
  const draft = useMemo(
    () => draftByStage[def.id] ?? loadJson(lsLightsKey(def.id), isLightsDraft) ?? defaultDraft(),
    [draftByStage, def.id, defaultDraft],
  );
  const setDraft = useCallback(
    (next: LightsDraft) => {
      setDraftByStage((prev) => ({ ...prev, [def.id]: next }));
      localStorage.setItem(lsLightsKey(def.id), JSON.stringify(next));
    },
    [def.id],
  );

  /* ------------------------------------------------------------ */
  /* Lighting state                                                */
  /* ------------------------------------------------------------ */
  const [selectedLightId, setSelectedLightId] = useState<string | null>(null);
  const [rigView, setRigView] = useState<'authored' | 'scene'>('authored');
  const [placeArmed, setPlaceArmed] = useState(false);
  const selected = draft.lights.find((l) => l.id === selectedLightId) ?? null;

  // Load an existing sidecar once per stage so the tool starts from what
  // the game renders — but only when there's no local draft to protect.
  useEffect(() => {
    if (!def.lightStageId) return;
    if (localStorage.getItem(lsLightsKey(def.id))) return;
    let alive = true;
    fetch(localAssetUrl(`data/stage_configs/city-lights/${def.lightStageId}.json`))
      .then((r) => (r.ok ? r.text() : null))
      .then((text) => {
        if (!alive || !text) return;
        const doc = parseLightsDoc(text);
        if (!doc || doc.lights.length === 0) return;
        setDraft({ ambient: doc.ambient, sunEnergy: def.sceneRig.sunEnergy, lights: doc.lights });
        setStatus(`loaded sidecar: ${doc.lights.length} lights from ${def.lightStageId}.json`);
      })
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [def, setDraft]);

  // Asset-drift advisory: what Godot renders (repo assets) vs what this
  // tool renders (R2) — the s00e_sa2 counter incident, made loud.
  useEffect(() => {
    setDrift(null);
    checkAssetDrift(def.models[0].path).then((d) => {
      if (d) setDrift(`${d.path}: local ${d.localSize}B vs CDN ${d.cdnSize}B — re-publish or fetch before trusting positions`);
    });
  }, [def]);

  /* ------------------------------------------------------------ */
  /* Audit                                                         */
  /* ------------------------------------------------------------ */
  const runAudit = useCallback(() => {
    const cache = gltfsRef.current;
    if (!cache) return;
    const faces: TriFace[] = [];
    for (const m of def.models) {
      const scene = cache[m.path];
      if (!scene) continue;
      scene.updateMatrixWorld(true);
      scene.traverse((obj) => {
        if (!(obj instanceof THREE.Mesh)) return;
        const idx = obj.geometry.index;
        const pos = obj.geometry.attributes.position;
        const uv = obj.geometry.attributes.uv;
        if (!idx || !pos) return;
        const matrix = obj.matrixWorld;
        const world = (i: number): Vec3 => {
          const v = new THREE.Vector3().fromBufferAttribute(pos as THREE.BufferAttribute, i).applyMatrix4(matrix);
          return [v.x, v.y, v.z];
        };
        const uvOf = uv
          ? (i: number): [number, number] => [uv.getX(i), uv.getY(i)]
          : null;
        for (let f = 0; f < idx.count / 3; f++) {
          faces.push({
            meshName: obj.name,
            faceIndex: f,
            v0: world(idx.getX(f * 3)),
            v1: world(idx.getX(f * 3 + 1)),
            v2: world(idx.getX(f * 3 + 2)),
            ...(uvOf
              ? { uvs: [uvOf(idx.getX(f * 3)), uvOf(idx.getX(f * 3 + 1)), uvOf(idx.getX(f * 3 + 2))] as [[number, number], [number, number], [number, number]] }
              : {}),
          });
        }
      });
    }
    const result = auditTriangles(faces);
    setAuditByStage((prev) => ({ ...prev, [def.id]: result }));
    setStatus(`audit: ${result.stats.issues} issues across ${result.stats.faces} faces / ${result.stats.meshes} meshes`);
  }, [def]);

  // Auto-run once per stage when entering triangles mode.
  const audit = auditByStage[def.id];
  useEffect(() => {
    if (mode === 'triangles' && !audit && gltfsRef.current) runAudit();
  }, [mode, audit, runAudit]);

  const markedFaces = useMemo(() => {
    const map = new Map<string, Set<number>>();
    for (const m of marks) {
      let set = map.get(m.mesh);
      if (!set) {
        set = new Set();
        map.set(m.mesh, set);
      }
      set.add(m.face);
    }
    return map;
  }, [marks]);

  const toggleMark = (mesh: string, face: number) => {
    setMarks((prev) =>
      prev.some((m) => m.mesh === mesh && m.face === face)
        ? prev.filter((m) => !(m.mesh === mesh && m.face === face))
        : [...prev, { mesh, face }],
    );
  };

  const focusedIssue = audit?.issues.find((i) => i.key === focusKey) ?? null;
  /** A double-clicked face to fly to (inspect navigation). */
  const [framePick, setFramePick] = useState<FacePick | null>(null);

  /** Tight camera frame for the focused triangle (audit list ⇄ scene). */
  const issueFrame = useMemo(() => {
    if (!focusedIssue) return null;
    const edge = (a: Vec3, b: Vec3) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    const longest = Math.max(
      edge(focusedIssue.v0, focusedIssue.v1),
      edge(focusedIssue.v1, focusedIssue.v2),
      edge(focusedIssue.v0, focusedIssue.v2),
    );
    return { center: focusedIssue.centroid, radius: longest * 1.5, key: focusedIssue.key };
  }, [focusedIssue]);

  const pickFrame = useMemo(() => {
    if (!framePick) return null;
    const edge = (a: Vec3, b: Vec3) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    const longest = Math.max(
      edge(framePick.v0, framePick.v1),
      edge(framePick.v1, framePick.v2),
      edge(framePick.v0, framePick.v2),
    );
    const center: Vec3 = [
      (framePick.v0[0] + framePick.v1[0] + framePick.v2[0]) / 3,
      (framePick.v0[1] + framePick.v1[1] + framePick.v2[1]) / 3,
      (framePick.v0[2] + framePick.v1[2] + framePick.v2[2]) / 3,
    ];
    return { center, radius: longest * 1.5, key: `pick:${framePick.meshName}#${framePick.faceIndex}` };
  }, [framePick]);

  const focusFrame = issueFrame ?? pickFrame;

  /** The selected triangle's outline: cyan when driven from the audit
   *  list, white when picked straight off the mesh. */
  const outline = useMemo(() => {
    if (focusedIssue) {
      return {
        v0: focusedIssue.v0,
        v1: focusedIssue.v1,
        v2: focusedIssue.v2,
        color: '#00e5ff',
      };
    }
    if (pick && mode !== 'lighting') {
      return { v0: pick.v0, v1: pick.v1, v2: pick.v2, color: '#ffffff' };
    }
    return null;
  }, [focusedIssue, pick, mode]);

  /* ------------------------------------------------------------ */
  /* Pick routing                                                  */
  /* ------------------------------------------------------------ */
  const handlePick = useCallback(
    (p: FacePick | null, worldPoint?: Vec3) => {
      if (mode === 'lighting' && placeArmed && selected && worldPoint) {
        setDraft({ ...draft, lights: draft.lights.map((l) => (l.id === selected.id ? { ...l, pos: [...worldPoint] as Vec3 } : l)) });
        setPlaceArmed(false);
        setStatus(`${selected.name} → ${worldPoint.map((n) => n.toFixed(2)).join(', ')}`);
        return;
      }
      setPick(p);
      // A fresh scene pick supersedes the audit-list focus.
      if (p) setFocusKey(null);
    },
    [mode, placeArmed, selected, draft, setDraft],
  );

  /* ------------------------------------------------------------ */
  /* Export                                                        */
  /* ------------------------------------------------------------ */
  const exportFixedGlb = useCallback(async () => {
    const root = rootRef.current;
    if (!root || !def.exportPath) return;
    const exporter = new GLTFExporter();
    try {
      const buf = await new Promise<ArrayBuffer>((resolve, reject) => {
        exporter.parse(root, (r) => resolve(r as ArrayBuffer), reject, { binary: true, onlyVisible: true });
      });
      try {
        const res = await fetch(`/api/city-lab/export-glb?path=${encodeURIComponent(def.exportPath)}`, {
          method: 'POST',
          headers: { 'content-type': 'model/gltf-binary' },
          body: buf,
        });
        setStatus(res.ok ? `wrote ${def.exportPath} (${buf.byteLength} B) — commit it, then point city_market.tscn at dairon3` : `write-back failed: ${await res.text()}`);
      } catch {
        // No dev middleware (prod build) — fall back to a download.
        const url = URL.createObjectURL(new Blob([buf], { type: 'model/gltf-binary' }));
        const a = document.createElement('a');
        a.href = url;
        a.download = def.exportPath.split('/').pop() ?? 'fixed.glb';
        a.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
        setStatus('dev server unreachable — downloaded the GLB instead');
      }
    } catch (err) {
      setStatus(`GLTFExporter failed: ${(err as Error).message}`);
    }
  }, [def]);

  const saveSidecar = useCallback(async () => {
    if (!def.lightStageId) return;
    const doc = toLightsDoc(def.lightStageId, draft.lights, draft.ambient);
    try {
      const res = await fetch('/api/city-lab/save-lights', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ stageId: def.lightStageId, json: doc }),
      });
      setStatus(res.ok ? `wrote data/stage_configs/city-lights/${def.lightStageId}.json (${doc.lights.length} lights)` : `save failed: ${await res.text()}`);
    } catch {
      setStatus('save failed: dev server unreachable');
    }
  }, [def, draft]);

  const gdscriptPreview = useMemo(
    () => (def.lightStageId ? lightsGdscript(toLightsDoc(def.lightStageId, draft.lights, draft.ambient)) : ''),
    [def, draft],
  );

  /* ------------------------------------------------------------ */
  /* Light editing helpers                                         */
  /* ------------------------------------------------------------ */
  const addLight = (preset: typeof PRESET_INTERIOR | typeof PRESET_POOL) => {
    const light = { ...newLight(preset), pos: [...(draft.lights.length ? draft.lights[draft.lights.length - 1].pos : ([0, 0, 0] as Vec3))] as Vec3 };
    setDraft({ ...draft, lights: [...draft.lights, light] });
    setSelectedLightId(light.id);
  };
  const updateLight = (id: string, patch: Partial<LightSpec>) =>
    setDraft({ ...draft, lights: draft.lights.map((l) => (l.id === id ? { ...l, ...patch } : l)) });
  const removeLight = (id: string) => {
    setDraft({ ...draft, lights: draft.lights.filter((l) => l.id !== id) });
    if (selectedLightId === id) setSelectedLightId(null);
  };

  const vecField = (label: string, value: Vec3, onChange: (v: Vec3) => void) => (
    <div style={{ display: 'flex', gap: 4, alignItems: 'center', marginBottom: 4 }}>
      <span style={{ width: 52, color: '#888', fontSize: 11 }}>{label}</span>
      {value.map((n, i) => (
        <input
          key={i}
          type="number"
          step={0.1}
          style={input}
          value={n}
          onChange={(e) => {
            const next = [...value] as Vec3;
            next[i] = parseFloat(e.target.value) || 0;
            onChange(next);
          }}
        />
      ))}
    </div>
  );

  /* ------------------------------------------------------------ */
  /* Render                                                        */
  /* ------------------------------------------------------------ */
  const previewLights = rigView === 'scene' && def.id === 'counter' ? legacyCounterLights() : draft.lights;
  const previewAmbient = rigView === 'scene' && def.id === 'counter'
    ? { color: [0.9, 0.88, 0.82] as Vec3, energy: 1.5 }
    : draft.ambient;
  const previewSun = rigView === 'scene' && def.id === 'counter' ? 0.3 : draft.sunEnergy;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '8px 14px',
          background: '#12122a',
          borderBottom: '1px solid #2a2a4a',
          fontSize: 13,
          color: '#ccc',
        }}
      >
        <strong style={{ color: '#88aaff' }}>City Lab</strong>
        <select
          value={stageId}
          onChange={(e) => {
            setStageId(e.target.value);
            setPick(null);
            setFocusKey(null);
            setFramePick(null);
            setSelectedLightId(null);
            setPlaceArmed(false);
          }}
          style={input}
        >
          {STAGES.map((s) => (
            <option key={s.id} value={s.id}>
              {s.label}
            </option>
          ))}
        </select>
        {(['inspect', 'triangles', 'lighting'] as CityLabMode[]).map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            style={btn(mode === m ? '#3a4a8f' : '#25264a')}
          >
            {m}
          </button>
        ))}
        <span style={{ color: '#8a8', fontSize: 12, flex: 1 }}>{status}</span>
      </div>

      {drift && (
        <div style={{ background: '#4a2a1a', color: '#ffb27f', fontSize: 12, padding: '4px 14px' }}>
          drift: {drift}
        </div>
      )}

      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <CanvasBoundary>
          <CityLabCanvas
            def={def}
            mode={mode}
            markedFaces={mode === 'triangles' ? markedFaces : NO_MARKS}
            issues={audit?.issues ?? []}
            focus={focusedIssue ? focusedIssue.centroid : null}
            outline={outline}
            focusFrame={focusFrame}
            onFramePick={setFramePick}
            lights={mode === 'lighting' ? previewLights : []}
            selectedLightId={selectedLightId}
            ambientColor={previewAmbient.color}
            ambientEnergy={previewAmbient.energy}
            sunEnergy={previewSun}
            onPick={handlePick}
            onSelectLight={setSelectedLightId}
            onMoveLight={(id, pos) => updateLight(id, { pos })}
            onRootReady={(root) => {
              rootRef.current = root;
            }}
            onGltfsReady={(cache) => {
              gltfsRef.current = cache;
            }}
          />
          </CanvasBoundary>
        </div>

        <div style={panelStyle}>
          {/* ------------------------- INSPECT ------------------------ */}
          {mode === 'inspect' && (
            <>
              <div style={sectionTitle}>Reference</div>
              <div style={{ color: '#888', fontSize: 12, lineHeight: 1.5 }}>
                Click any surface. Mesh and material names are the keys the
                Godot pipeline uses (post_lights, lit_surfaces, texture
                configs all key off material names).
              </div>
              {pick ? (
                <div style={{ marginTop: 10, fontFamily: 'monospace', fontSize: 12, lineHeight: 1.7 }}>
                  <div><span style={{ color: '#88aaff' }}>mesh</span> {pick.meshName}</div>
                  <div><span style={{ color: '#88aaff' }}>material</span> {pick.materialName}</div>
                  <div><span style={{ color: '#88aaff' }}>face</span> #{pick.faceIndex}</div>
                  <div><span style={{ color: '#88aaff' }}>area</span> {fmt(faceArea(pick.v0, pick.v1, pick.v2))} m²</div>
                  <div style={{ color: '#666' }}>
                    v0 {pick.v0.map(fmt).join(', ')}
                    <br />
                    v1 {pick.v1.map(fmt).join(', ')}
                    <br />
                    v2 {pick.v2.map(fmt).join(', ')}
                  </div>
                  <div style={{ color: '#666' }}>hit {pick.point.map(fmt).join(', ')}</div>
                </div>
              ) : (
                <div style={{ color: '#555', marginTop: 10, fontSize: 12 }}>nothing picked</div>
              )}
            </>
          )}

          {/* ------------------------ TRIANGLES ----------------------- */}
          {mode === 'triangles' && (
            <>
              <div style={sectionTitle}>Triangle audit</div>
              <button onClick={runAudit} style={btn('#3a4a8f')}>
                re-run audit
              </button>
              {audit && (
                <div style={{ fontSize: 12, color: '#888', marginTop: 6, lineHeight: 1.6 }}>
                  {audit.stats.faces} faces / {audit.stats.meshes} meshes ·{' '}
                  <span style={{ color: '#f66' }}>{audit.stats.byClass.nonfinite} nonfinite</span>{' '}
                  <span style={{ color: '#f80' }}>{audit.stats.byClass['zero-area'] + audit.stats.byClass['duplicate-vertex']} degenerate</span>{' '}
                  <span style={{ color: '#fc0' }}>{audit.stats.byClass.sliver} sliver</span>{' '}
                  <span style={{ color: '#c6f' }}>{audit.stats.byClass['uv-degenerate']} uv-deg</span>
                </div>
              )}
              <div style={{ marginTop: 8, maxHeight: 260, overflowY: 'auto' }}>
                {(audit?.issues ?? []).slice(0, 400).map((iss) => (
                  <div
                    key={iss.key}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 6,
                      padding: '3px 6px',
                      borderRadius: 3,
                      cursor: 'pointer',
                      background: focusKey === iss.key ? '#1f2f5f' : 'transparent',
                      fontFamily: 'monospace',
                      fontSize: 11,
                    }}
                    onClick={() => setFocusKey(iss.key)}
                  >
                    <span
                      style={{
                        width: 8,
                        height: 8,
                        borderRadius: 4,
                        background: iss.severity >= 3 ? '#f22' : iss.severity === 2 ? '#f80' : '#fc0',
                      }}
                    />
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {iss.cls} · {iss.key}
                    </span>
                    <span style={{ color: '#666' }}>{iss.cls === 'sliver' ? `a${fmt(iss.aspect)}` : ''}</span>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleMark(iss.meshName, iss.faceIndex);
                      }}
                      style={{ ...btn(marks.some((m) => m.mesh === iss.meshName && m.face === iss.faceIndex) ? '#8f3a3a' : '#2a2a4a'), padding: '2px 6px', fontSize: 10 }}
                    >
                      ⨯
                    </button>
                  </div>
                ))}
              </div>

              <div style={sectionTitle}>Marked for deletion ({marks.length})</div>
              {marks.length > 0 && (
                <>
                  <div style={{ fontFamily: 'monospace', fontSize: 11, color: '#999', maxHeight: 120, overflowY: 'auto' }}>
                    {marks.map((m) => (
                      <div key={`${m.mesh}#${m.face}`}>
                        {m.mesh}#{m.face}
                      </div>
                    ))}
                  </div>
                  <button onClick={() => setMarks([])} style={{ ...btn('#4a2a2a'), marginTop: 6 }}>
                    clear marks
                  </button>
                </>
              )}
              {pick && (
                <div style={{ marginTop: 8, fontSize: 12, color: '#aaa' }}>
                  picked {pick.meshName}#{pick.faceIndex}
                  <button
                    onClick={() => toggleMark(pick.meshName, pick.faceIndex)}
                    style={{ ...btn('#2a2a4a'), marginLeft: 8 }}
                  >
                    {marks.some((m) => m.mesh === pick.meshName && m.face === pick.faceIndex) ? 'unmark' : 'mark for deletion'}
                  </button>
                </div>
              )}

              <div style={sectionTitle}>Export</div>
              <button
                onClick={exportFixedGlb}
                disabled={marks.length === 0 || !def.exportPath}
                style={btn(marks.length > 0 && def.exportPath ? '#2f6f4f' : '#25264a')}
              >
                export fixed GLB → {def.exportPath?.split('/').pop() ?? '(this stage has none)'}
              </button>
              <div style={{ color: '#666', fontSize: 11, marginTop: 4, lineHeight: 1.5 }}>
                Drops the marked faces and writes a new GLB via the dev
                server (dairon2 stays untouched as rollback). After
                committing, point city_market.tscn at the new file and
                re-publish assets.
              </div>
            </>
          )}

          {/* ------------------------- LIGHTING ----------------------- */}
          {mode === 'lighting' && (
            <>
              {def.id === 'counter' && (
                <>
                  <div style={sectionTitle}>A/B</div>
                  <button onClick={() => setRigView('scene')} style={btn(rigView === 'scene' ? '#8f5a2f' : '#25264a')}>
                    current scene rig
                  </button>
                  <button onClick={() => setRigView('authored')} style={btn(rigView === 'authored' ? '#3a4a8f' : '#25264a')}>
                    authored
                  </button>
                  <div style={{ color: '#666', fontSize: 11, marginTop: 4, lineHeight: 1.5 }}>
                    "current" = the live 7 omnis at y=4 (≈14.7 m above the
                    floor) — the #656 before. Values are Godot units; the
                    final read happens in the Godot scene boot.
                  </div>
                </>
              )}

              <div style={sectionTitle}>Ambient (Environment)</div>
              {vecField('color', draft.ambient.color, (color) => setDraft({ ...draft, ambient: { ...draft.ambient, color } }))}
              <div style={{ display: 'flex', gap: 4, alignItems: 'center', marginBottom: 4 }}>
                <span style={{ width: 52, color: '#888', fontSize: 11 }}>energy</span>
                <input
                  type="number"
                  step={0.05}
                  style={input}
                  value={draft.ambient.energy}
                  onChange={(e) => setDraft({ ...draft, ambient: { ...draft.ambient, energy: parseFloat(e.target.value) || 0 } })}
                />
                <span style={{ width: 52, color: '#888', fontSize: 11 }}>sun</span>
                <input
                  type="number"
                  step={0.05}
                  style={input}
                  value={draft.sunEnergy}
                  onChange={(e) => setDraft({ ...draft, sunEnergy: parseFloat(e.target.value) || 0 })}
                />
              </div>

              <div style={sectionTitle}>Lights ({draft.lights.length})</div>
              <button onClick={() => addLight(PRESET_INTERIOR)} style={btn('#2f4f6f')}>
                + interior warm
              </button>
              <button onClick={() => addLight(PRESET_POOL)} style={btn('#6f4f2f')}>
                + lantern pool
              </button>
              <button
                onClick={() => {
                  if (def.id === 'counter' && draft.lights.length === 0) {
                    setDraft({ ...draft, lights: legacyCounterLights() });
                  }
                }}
                style={btn('#25264a')}
              >
                seed legacy 7
              </button>

              {selected && (
                <div style={{ marginTop: 10, padding: 8, background: '#181a30', borderRadius: 4 }}>
                  <div style={{ display: 'flex', gap: 6, marginBottom: 6 }}>
                    <input
                      style={{ ...input, width: 140 }}
                      value={selected.name}
                      onChange={(e) => updateLight(selected.id, { name: e.target.value })}
                    />
                    <button
                      onClick={() => setPlaceArmed(!placeArmed)}
                      style={btn(placeArmed ? '#8f2f5f' : '#2a2a4a')}
                    >
                      {placeArmed ? 'click on the map…' : 'snap to click'}
                    </button>
                    <button onClick={() => removeLight(selected.id)} style={btn('#4a2a2a')}>
                      delete
                    </button>
                  </div>
                  {vecField('pos', selected.pos, (pos) => updateLight(selected.id, { pos }))}
                  {vecField('color', selected.color, (color) => updateLight(selected.id, { color }))}
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', alignItems: 'center' }}>
                    {(['energy', 'range', 'attenuation'] as const).map((k) => (
                      <label key={k} style={{ color: '#888', fontSize: 11, display: 'flex', gap: 4, alignItems: 'center' }}>
                        {k.slice(0, 3)}
                        <input
                          type="number"
                          step={k === 'energy' ? 0.25 : k === 'range' ? 1 : 0.5}
                          style={{ ...input, width: 58 }}
                          value={selected[k]}
                          onChange={(e) => updateLight(selected.id, { [k]: parseFloat(e.target.value) || 0 } as Partial<LightSpec>)}
                        />
                      </label>
                    ))}
                    <label style={{ color: '#888', fontSize: 11, display: 'flex', gap: 4, alignItems: 'center' }}>
                      shadows
                      <input
                        type="checkbox"
                        checked={selected.shadows}
                        onChange={(e) => updateLight(selected.id, { shadows: e.target.checked })}
                      />
                    </label>
                  </div>
                </div>
              )}

              {def.lightStageId && (
                <>
                  <div style={sectionTitle}>Sidecar</div>
                  <button onClick={saveSidecar} style={btn('#2f6f4f')}>
                    save → data/stage_configs/city-lights/{def.lightStageId}.json
                  </button>
                  <button
                    onClick={() => navigator.clipboard?.writeText(gdscriptPreview)}
                    style={btn('#25264a')}
                  >
                    copy GDScript
                  </button>
                  <pre
                    style={{
                      marginTop: 8,
                      background: '#0d0e20',
                      border: '1px solid #2a2a4a',
                      borderRadius: 4,
                      padding: 8,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: '#9ab',
                      whiteSpace: 'pre-wrap',
                      maxHeight: 200,
                      overflowY: 'auto',
                    }}
                  >
                    {gdscriptPreview}
                  </pre>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
