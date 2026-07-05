// TeleporterMock — a focused debug tool for arranging the teleporter dressing
// (the special_c3 set: compass + city-warp variants) at the city's warp pad.
//
// Unlike #/city-walk-mock (walk a capsule to verify the floor), there's no
// walking here: the camera orbits a fixed target — the warp-pad center — and
// you place each object piece around it. Textures use mirrored wrapping
// (PSZ's warp/beam textures are authored to tile mirror-symmetrically).
//
// URL: /psz-godot/#/teleporter-mock?set=special_c3&target=x,y,z
//   - set:    object set under assets/objects/ (default special_c3)
//   - target: orbit center / default rig anchor (default the warp pad below)
//
// Controls: drag orbit · wheel zoom · click a piece row to select it, then
// click the stage to drop it there. Copy the layout JSON for Godot authoring.

import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { loadObjectSet, applyMirroredWrap, wrapAtBaseCenter, type ObjectSetPiece } from '../utils/objectSet';

const DEFAULT_MODEL = '/psz-godot/assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb';
const DEFAULT_FLOOR = '/psz-godot/assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2-floor.glb';
const DEFAULT_SET = 'special_c3';
// The warp-pad center in the city's world frame (found in city-walk-mock).
const WARP_PAD: [number, number, number] = [0.03, -7.08, 60.83];

// Per-piece transform in the rig's local frame: offset + yaw + uniform scale.
interface PieceXform { px: number; py: number; pz: number; ry: number; s: number }
type Layout = Record<string, PieceXform>;
const IDENTITY: PieceXform = { px: 0, py: 0, pz: 0, ry: 0, s: 1 };

// Per-piece UV scroll (units/sec on each axis). PSZ animates several of these
// textures in-game (the compass glow, warp beams) by scrolling UVs — the
// mirrored wrap set at load is what lets the scroll tile seamlessly.
interface PieceScroll { on: boolean; su: number; sv: number }
type ScrollMap = Record<string, PieceScroll>;
const DEFAULT_SCROLL: ScrollMap = { o00_compass2: { on: true, su: 0, sv: 0.25 } };
const NO_SCROLL: PieceScroll = { on: false, su: 0, sv: 0.25 };

// Per-piece UV sampling knobs — everything three.js exposes on a texture's
// UV path. Wrap = what happens when UVs overflow 0..1 (mirror is the PSZ
// default set at load); repeat = tiling count; offset = shift; rot = radians
// around the texture center.
type WrapMode = 'mirror' | 'repeat' | 'clamp';
interface PieceUV { wrapS: WrapMode; wrapT: WrapMode; ru: number; rv: number; ou: number; ov: number; rot: number }
type UVMap = Record<string, PieceUV>;
const DEFAULT_UV: PieceUV = { wrapS: 'mirror', wrapT: 'mirror', ru: 1, rv: 1, ou: 0, ov: 0, rot: 0 };
const WRAP_THREE: Record<WrapMode, THREE.Wrapping> = {
  mirror: THREE.MirroredRepeatWrapping,
  repeat: THREE.RepeatWrapping,
  clamp: THREE.ClampToEdgeWrapping,
};

function parseVec(s: string | null, fallback: [number, number, number]): [number, number, number] {
  if (!s) return fallback;
  const parts = s.split(',').map((v) => parseFloat(v));
  return parts.length === 3 && parts.every((v) => !isNaN(v)) ? (parts as [number, number, number]) : fallback;
}

export default function TeleporterMock() {
  const [params] = useSearchParams();
  const setId = params.get('set') || DEFAULT_SET;
  const modelUrl = params.get('glb') || DEFAULT_MODEL;
  const floorUrl = params.get('floor') || DEFAULT_FLOOR;
  const target = parseVec(params.get('target'), WARP_PAD);

  const mountRef = useRef<HTMLDivElement>(null);
  const rigRef = useRef<{ group: THREE.Group; pieces: ObjectSetPiece[] } | null>(null);
  const anchorRef = useRef<[number, number, number]>(target);
  const selectedRef = useRef<string | null>(null);
  const placeRef = useRef<((name: string, world: THREE.Vector3) => void) | null>(null);

  const [status, setStatus] = useState('loading…');
  const [rigNames, setRigNames] = useState<string[]>([]);
  const [layout, setLayout] = useState<Layout>({});
  const [anchor, setAnchor] = useState<[number, number, number]>(target);
  const [selected, setSelected] = useState<string | null>(null);
  const [hidden, setHidden] = useState<Record<string, boolean>>({});
  const [scroll, setScroll] = useState<ScrollMap>(DEFAULT_SCROLL);
  const [uv, setUv] = useState<UVMap>({});
  const [uvOpen, setUvOpen] = useState<Record<string, boolean>>({ o00_compass: true });
  const [showStage, setShowStage] = useState(true);
  // Read by the frame loop so toggling stage visibility never rebuilds the scene.
  const showStageRef = useRef(showStage);
  // Frame loop reads these each tick: scroll settings + each piece's textures.
  const scrollRef = useRef<ScrollMap>(scroll);
  const texturesRef = useRef<Record<string, THREE.Texture[]>>({});

  useEffect(() => { anchorRef.current = anchor; }, [anchor]);
  useEffect(() => { selectedRef.current = selected; }, [selected]);
  useEffect(() => { showStageRef.current = showStage; }, [showStage]);
  useEffect(() => { scrollRef.current = scroll; }, [scroll]);

  // Apply layout + anchor + visibility to the loaded rig (also fires once the
  // rig loads — rigNames flips non-empty then).
  useEffect(() => {
    const rig = rigRef.current;
    if (!rig) return;
    rig.group.position.set(anchor[0], anchor[1], anchor[2]);
    for (const p of rig.pieces) {
      const x = layout[p.name] ?? IDENTITY;
      p.object.position.set(x.px, x.py, x.pz);
      p.object.rotation.set(0, x.ry, 0);
      p.object.scale.setScalar(x.s);
      p.object.visible = !hidden[p.name];
    }
  }, [layout, anchor, rigNames, hidden]);

  // Apply UV knobs to each piece's textures. Wrap-mode changes need a GPU
  // re-upload (needsUpdate); repeat/offset/rot ride the texture matrix.
  // Scroll (frame loop) keeps adding on top of whatever offset is set here.
  useEffect(() => {
    for (const [name, u] of Object.entries(uv)) {
      for (const tex of texturesRef.current[name] ?? []) {
        tex.wrapS = WRAP_THREE[u.wrapS];
        tex.wrapT = WRAP_THREE[u.wrapT];
        tex.repeat.set(u.ru, u.rv);
        tex.offset.set(u.ou, u.ov);
        tex.center.set(0.5, 0.5);
        tex.rotation = u.rot;
        tex.needsUpdate = true;
      }
    }
  }, [uv, rigNames]);

  // ——— scene ———
  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 4000);
    camera.position.set(target[0], target[1] + 8, target[2] + 16);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);

    // Orbit locked on the warp pad.
    const orbit = new OrbitControls(camera, renderer.domElement);
    orbit.enableDamping = true;
    orbit.target.set(target[0], target[1], target[2]);

    scene.add(new THREE.AmbientLight(0xffffff, 1.1));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(40, 80, 40);
    scene.add(dir);
    const grid = new THREE.GridHelper(200, 100, 0x334, 0x1a2130);
    grid.position.y = target[1];
    scene.add(grid);

    // A small crosshair marking the warp-pad center (orbit target).
    const padMark = new THREE.Mesh(
      new THREE.SphereGeometry(0.4, 12, 8),
      new THREE.MeshBasicMaterial({ color: 0xf87171, wireframe: true }),
    );
    padMark.position.set(target[0], target[1], target[2]);
    scene.add(padMark);

    let stageMesh: THREE.Object3D | null = null;
    let floorMesh: THREE.Object3D | null = null;
    const raycaster = new THREE.Raycaster();

    const loader = new GLTFLoader();
    // Stage visual — raycast target for click-to-place.
    loader.load(modelUrl, (g) => {
      scene.add(g.scene);
      stageMesh = g.scene;
    }, undefined, () => setStatus('stage model failed'));
    // Floor collider — hidden, but used as a fallback raycast surface.
    loader.load(floorUrl, (g) => {
      g.scene.visible = false;
      scene.add(g.scene);
      floorMesh = g.scene;
    }, undefined, () => { /* floor optional */ });

    // Teleporter rig — load the set, mirror its textures, anchor at the pad.
    let rigGroup: THREE.Group | null = null;
    loadObjectSet(setId)
      .then((set) => {
        rigGroup = new THREE.Group();
        rigGroup.name = 'teleporter-rig';
        // Re-pivot each piece to its bottom-center so pos (0,0,0) means
        // "base sitting on the anchor" — the raw GLBs keep stage-baked
        // node offsets that would otherwise scatter them.
        const pieces: ObjectSetPiece[] = set.pieces.map((p) => {
          applyMirroredWrap(p.object);
          // Collect the piece's texture maps once so the frame loop can
          // scroll their UV offsets without re-traversing every tick.
          const texs: THREE.Texture[] = [];
          p.object.traverse((o) => {
            const mesh = o as THREE.Mesh;
            if (!mesh.isMesh) return;
            const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
            for (const mat of mats) {
              const map = (mat as THREE.MeshStandardMaterial)?.map;
              if (map && !texs.includes(map)) texs.push(map);
            }
          });
          texturesRef.current[p.name] = texs;
          const pivot = wrapAtBaseCenter(p.object);
          pivot.name = p.name;
          rigGroup!.add(pivot);
          return { name: p.name, object: pivot };
        });
        scene.add(rigGroup);
        rigRef.current = { group: rigGroup, pieces };
        setRigNames(pieces.map((p) => p.name));
        setStatus(`${pieces.length} pieces · drag orbit · wheel zoom · select a piece then click the stage`);
      })
      .catch((e) => setStatus(`set load failed: ${String(e)}`));

    // Click-to-place: drop the selected piece where the ray hits the stage.
    placeRef.current = (name, world) => {
      const a = anchorRef.current;
      setLayout((prev) => ({
        ...prev,
        [name]: { ...IDENTITY, ...prev[name], px: +(world.x - a[0]).toFixed(3), py: +(world.y - a[1]).toFixed(3), pz: +(world.z - a[2]).toFixed(3) },
      }));
    };
    let downX = 0, downY = 0;
    const onDown = (ev: PointerEvent) => { downX = ev.clientX; downY = ev.clientY; };
    renderer.domElement.addEventListener('pointerdown', onDown);
    const onClick = (ev: MouseEvent) => {
      const name = selectedRef.current;
      const surf = stageMesh ?? floorMesh;
      if (!name || !surf) return;
      if (Math.abs(ev.clientX - downX) > 4 || Math.abs(ev.clientY - downY) > 4) return; // drag, not click
      const rect = renderer.domElement.getBoundingClientRect();
      const m = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      raycaster.setFromCamera(m, camera);
      const wasVisible = surf.visible;
      surf.visible = true;
      const hits = raycaster.intersectObject(surf, true);
      surf.visible = wasVisible;
      if (!hits.length) return;
      placeRef.current?.(name, hits[0].point.clone());
    };
    renderer.domElement.addEventListener('click', onClick);

    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      if (stageMesh) stageMesh.visible = showStageRef.current;
      // UV-scroll any piece with scroll enabled. Offsets wrap mod 2 — one
      // full mirror period under MirroredRepeatWrapping.
      for (const [name, sc] of Object.entries(scrollRef.current)) {
        if (!sc.on) continue;
        for (const tex of texturesRef.current[name] ?? []) {
          tex.offset.x = (tex.offset.x + sc.su * dt) % 2;
          tex.offset.y = (tex.offset.y + sc.sv * dt) % 2;
        }
      }
      orbit.update();
      renderer.render(scene, camera);
    };
    animate();

    if (import.meta.env.DEV) {
      (window as any).__teleporterMock = { scene, textures: texturesRef };
    }

    const onResize = () => {
      if (!mountRef.current) return;
      const nw = mountRef.current.clientWidth, nh = mountRef.current.clientHeight;
      renderer.setSize(nw, nh);
      camera.aspect = nw / nh;
      camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', onResize);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      renderer.domElement.removeEventListener('click', onClick);
      renderer.domElement.removeEventListener('pointerdown', onDown);
      orbit.dispose();
      renderer.dispose();
      rigRef.current = null;
      placeRef.current = null;
      texturesRef.current = {};
      setRigNames([]);
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setId, modelUrl, floorUrl]);

  const setPieceXform = (name: string, patch: Partial<PieceXform>) =>
    setLayout((prev) => ({ ...prev, [name]: { ...IDENTITY, ...prev[name], ...patch } }));
  const setPieceScroll = (name: string, patch: Partial<PieceScroll>) =>
    setScroll((prev) => ({ ...prev, [name]: { ...NO_SCROLL, ...prev[name], ...patch } }));
  const setPieceUv = (name: string, patch: Partial<PieceUV>) =>
    setUv((prev) => ({ ...prev, [name]: { ...DEFAULT_UV, ...prev[name], ...patch } }));

  const exportJson = JSON.stringify(
    {
      set: setId,
      anchor: anchor.map((v) => +v.toFixed(2)),
      pieces: Object.fromEntries(
        rigNames.map((n) => {
          const x = layout[n] ?? IDENTITY;
          const sc = scroll[n] ?? NO_SCROLL;
          const u = uv[n];
          return [n, {
            pos: [x.px, x.py, x.pz].map((v) => +v.toFixed(3)),
            ry: +x.ry.toFixed(3),
            s: +x.s.toFixed(3),
            ...(sc.on ? { scroll: { u: sc.su, v: sc.sv } } : {}),
            ...(u ? { uv: { wrap: [u.wrapS, u.wrapT], repeat: [u.ru, u.rv], offset: [u.ou, u.ov], rot: u.rot } } : {}),
          }];
        }),
      ),
    },
    null,
    2,
  );

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0e1a', color: '#e6edf3' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, background: 'rgba(0,0,0,0.6)', padding: '6px 10px', borderRadius: 4, fontSize: 12, maxWidth: 520 }}>
          {status}
        </div>
      </div>
      <aside style={{ width: 300, flexShrink: 0, padding: 16, background: '#161b22', borderLeft: '1px solid #30363d', overflowY: 'auto' }}>
        <h2 style={{ margin: '0 0 6px', fontSize: 16 }}>Teleporter · {setId}</h2>
        <p style={{ margin: '0 0 10px', fontSize: 12, color: '#8b949e' }}>
          Orbit around the warp pad. Click a piece to <b>select</b> it, then click the
          stage to drop it there. Fine-tune with the number fields (x/y/z offset from
          anchor, yaw, scale). Textures use mirrored wrapping.
        </p>

        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, marginBottom: 8 }}>
          <input type="checkbox" checked={showStage} onChange={(e) => setShowStage(e.target.checked)} /> show stage
        </label>

        <div style={{ fontSize: 10, color: '#8b949e', fontFamily: 'monospace', marginBottom: 4 }}>
          anchor
        </div>
        <div style={{ display: 'flex', gap: 4, marginBottom: 10 }}>
          {(['x', 'y', 'z'] as const).map((axis, i) => (
            <label key={axis} style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
              {axis}
              <input type="number" step={0.5} value={anchor[i]}
                onChange={(e) => { const v = parseFloat(e.target.value) || 0; setAnchor((a) => { const n = [...a] as [number, number, number]; n[i] = v; return n; }); }}
                style={inputStyle} />
            </label>
          ))}
        </div>

        {rigNames.length === 0 ? (
          <p style={{ fontSize: 11, color: '#8b949e' }}>loading set…</p>
        ) : (
          <>
            {rigNames.map((name) => {
              const x = layout[name] ?? IDENTITY;
              const sc = scroll[name] ?? NO_SCROLL;
              const isSel = selected === name;
              const fields: [keyof PieceXform, string, number][] = [
                ['px', 'x', 0.5], ['py', 'y', 0.5], ['pz', 'z', 0.5], ['ry', 'ry', 0.1], ['s', 's', 0.05],
              ];
              return (
                <div key={name} style={{ marginBottom: 6, padding: '5px 6px', background: isSel ? '#1f2d1f' : '#0d1117', borderRadius: 4, border: '1px solid ' + (isSel ? '#4a4' : 'transparent'), cursor: 'pointer', opacity: hidden[name] ? 0.5 : 1 }}
                  onClick={() => setSelected(isSel ? null : name)}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 3 }}>
                    <span style={{ fontSize: 11, fontFamily: 'monospace', color: isSel ? '#9f9' : '#c9d1d9' }}>
                      {isSel ? '● ' : ''}{name}
                    </span>
                    <label style={{ fontSize: 9, color: '#8b949e', display: 'flex', alignItems: 'center', gap: 3, cursor: 'pointer' }}
                      onClick={(e) => e.stopPropagation()}>
                      <input type="checkbox" checked={!hidden[name]}
                        onChange={(e) => setHidden((prev) => ({ ...prev, [name]: !e.target.checked }))} />
                      show
                    </label>
                  </div>
                  <div style={{ display: 'flex', gap: 4 }} onClick={(e) => e.stopPropagation()}>
                    {fields.map(([key, lbl, step]) => (
                      <label key={key} style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
                        {lbl}
                        <input type="number" step={step} value={x[key]}
                          onChange={(e) => setPieceXform(name, { [key]: parseFloat(e.target.value) || 0 })}
                          style={inputStyle} />
                      </label>
                    ))}
                  </div>
                  <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginTop: 3 }} onClick={(e) => e.stopPropagation()}>
                    <label style={{ fontSize: 9, color: sc.on ? '#9f9' : '#8b949e', display: 'flex', alignItems: 'center', gap: 3, cursor: 'pointer' }}>
                      <input type="checkbox" checked={sc.on}
                        onChange={(e) => setPieceScroll(name, { on: e.target.checked })} />
                      scroll
                    </label>
                    <label style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
                      u/s
                      <input type="number" step={0.05} value={sc.su} disabled={!sc.on}
                        onChange={(e) => setPieceScroll(name, { su: parseFloat(e.target.value) || 0 })}
                        style={{ ...inputStyle, opacity: sc.on ? 1 : 0.4 }} />
                    </label>
                    <label style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
                      v/s
                      <input type="number" step={0.05} value={sc.sv} disabled={!sc.on}
                        onChange={(e) => setPieceScroll(name, { sv: parseFloat(e.target.value) || 0 })}
                        style={{ ...inputStyle, opacity: sc.on ? 1 : 0.4 }} />
                    </label>
                    <button
                      onClick={() => setUvOpen((prev) => ({ ...prev, [name]: !prev[name] }))}
                      style={{ fontSize: 9, padding: '2px 6px', background: uvOpen[name] ? '#1f6feb' : '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 3, cursor: 'pointer' }}>
                      uv {uvOpen[name] ? '▾' : '▸'}
                    </button>
                  </div>
                  {uvOpen[name] && (() => {
                    const u = uv[name] ?? DEFAULT_UV;
                    const numFields: [keyof PieceUV, string, number][] = [
                      ['ru', 'rep u', 0.25], ['rv', 'rep v', 0.25], ['ou', 'off u', 0.05], ['ov', 'off v', 0.05], ['rot', 'rot', 0.1],
                    ];
                    return (
                      <div style={{ marginTop: 4, padding: '4px 5px', background: '#161b22', borderRadius: 3 }} onClick={(e) => e.stopPropagation()}>
                        <div style={{ display: 'flex', gap: 4, marginBottom: 3 }}>
                          {(['wrapS', 'wrapT'] as const).map((axis) => (
                            <label key={axis} style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
                              {axis === 'wrapS' ? 'wrap u' : 'wrap v'}
                              <select value={u[axis]}
                                onChange={(e) => setPieceUv(name, { [axis]: e.target.value as WrapMode })}
                                style={{ ...inputStyle, width: '100%' }}>
                                <option value="mirror">mirror</option>
                                <option value="repeat">repeat</option>
                                <option value="clamp">clamp</option>
                              </select>
                            </label>
                          ))}
                        </div>
                        <div style={{ display: 'flex', gap: 4 }}>
                          {numFields.map(([key, lbl, step]) => (
                            <label key={key} style={{ flex: 1, fontSize: 9, color: '#8b949e' }}>
                              {lbl}
                              <input type="number" step={step} value={u[key] as number}
                                onChange={(e) => setPieceUv(name, { [key]: parseFloat(e.target.value) || 0 })}
                                style={inputStyle} />
                            </label>
                          ))}
                        </div>
                      </div>
                    );
                  })()}
                </div>
              );
            })}
            <pre style={{ background: '#0d1117', padding: 8, borderRadius: 4, fontSize: 10, overflow: 'auto', maxHeight: 180 }}>{exportJson}</pre>
            <button onClick={() => navigator.clipboard?.writeText(exportJson)}
              style={{ width: '100%', padding: '6px 10px', background: '#238636', color: '#fff', border: 'none', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}>
              copy layout
            </button>
          </>
        )}
      </aside>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: '100%', fontSize: 10, padding: '2px 3px', background: '#161b22',
  color: '#e6edf3', border: '1px solid #30363d', borderRadius: 3,
};
