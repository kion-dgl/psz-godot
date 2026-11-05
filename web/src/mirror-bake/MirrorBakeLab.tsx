import { useEffect, useRef, useState } from 'react';
import * as T from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { assetUrl } from '../utils/assets';
import { foldBake, type BakeSettings } from './foldBake';
import './mirror-bake.css';
import { godotFixture } from './godotFixture';

// Reproducible comparison preset: s01_0_pass1.png#1 in global-texture-fixes.json.
const pathSettings: BakeSettings = { repeat: [2, 1], offset: [0, 0], mirror: [true, false] };
const syntheticSettings: BakeSettings = { repeat: [2.1, 1.3], offset: [.17, -.3], mirror: [true, true] };
type Source = 'stage' | 'synthetic';
type Filter = 'linear' | 'mipmap' | 'nearest';
interface Controls { compare: () => void; export: () => Promise<void>; reset: () => void; fixture: () => void }

function checker() {
  const canvas = document.createElement('canvas'); canvas.width = canvas.height = 128;
  const c = canvas.getContext('2d')!;
  c.fillStyle = '#164568'; c.fillRect(0, 0, 128, 128);
  c.fillStyle = '#edb54c'; c.fillRect(0, 0, 28, 128);
  c.fillStyle = '#dc5265'; c.fillRect(28, 0, 100, 20);
  c.fillStyle = '#faf1d6'; c.font = 'bold 60px sans-serif'; c.fillText('R', 43, 88);
  c.fillStyle = '#57dba6'; c.fillRect(70, 110, 58, 18);
  const texture = new T.CanvasTexture(canvas); texture.colorSpace = T.SRGBColorSpace;
  return texture;
}

function disposeTree(root: T.Object3D) {
  const geometries = new Set<T.BufferGeometry>(), materials = new Set<T.Material>(), textures = new Set<T.Texture>();
  root.traverse(o => {
    if (!(o instanceof T.Mesh)) return;
    geometries.add(o.geometry);
    for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
      materials.add(m);
      for (const v of Object.values(m)) if (v instanceof T.Texture) textures.add(v);
    }
    if (o instanceof T.SkinnedMesh) o.skeleton.dispose();
  });
  geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose()); textures.forEach(t => t.dispose());
}

async function loadSource(source: Source) {
  if (source === 'synthetic') {
    const geometry = new T.PlaneGeometry(4, 3);
    const uv = geometry.getAttribute('uv');
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 4 - 1.8, uv.getY(i) * 3 - 1.2);
    return { geometry, texture: checker(), dispose: () => {} };
  }
  const gltf = await new GLTFLoader().loadAsync(assetUrl('assets/stages/valley_a/s01a_ga1/lndmd/s01a_ga1_m.glb'));
  try {
    gltf.scene.updateMatrixWorld(true);
    let mesh: T.Mesh | undefined;
    gltf.scene.traverse(o => {
      if (o instanceof T.Mesh && !Array.isArray(o.material) && o.material.name === '1_pass1') mesh = o;
    });
    if (!mesh) throw new Error('Valley pass1 surface was not found');
    const surface = mesh as T.Mesh;
    const map = (surface.material as T.MeshStandardMaterial).map;
    if (!map) throw new Error('Valley pass1 texture was not found');
    // This lab compares a STATIC rest-pose snapshot, not an animation bake.
    if (surface instanceof T.SkinnedMesh) surface.skeleton.update();
    const geometry = surface.geometry.clone(), position = geometry.getAttribute('position');
    const v = new T.Vector3();
    for (let i = 0; i < position.count; i++) {
      surface.getVertexPosition(i, v).applyMatrix4(surface.matrixWorld);
      position.setXYZ(i, v.x, v.y, v.z);
    }
    geometry.deleteAttribute('skinIndex'); geometry.deleteAttribute('skinWeight');
    geometry.clearGroups(); geometry.computeVertexNormals();
    // Normalize the same static snapshot for both views. Preserve source UVs.
    geometry.rotateX(-Math.PI / 2);
    geometry.computeBoundingBox();
    const center = geometry.boundingBox!.getCenter(new T.Vector3());
    const size = geometry.boundingBox!.getSize(new T.Vector3());
    geometry.translate(-center.x, -center.y, -center.z);
    const scale = 4 / Math.max(size.x, size.y, size.z); geometry.scale(scale, scale, scale);
    return { geometry, texture: map.clone(), dispose: () => disposeTree(gltf.scene) };
  } catch (e) { disposeTree(gltf.scene); throw e; }
}

export default function MirrorBakeLab() {
  const host = useRef<HTMLDivElement>(null), actions = useRef<Controls | null>(null);
  const [source, setSource] = useState<Source>('stage');
  const [settings, setSettings] = useState<BakeSettings>(pathSettings);
  const [filter, setFilter] = useState<Filter>('linear');
  const [lit, setLit] = useState(true), [wire, setWire] = useState(false);
  const [light, setLight] = useState(40);
  const [status, setStatus] = useState('Loading…'), [diff, setDiff] = useState('');
  const [ready, setReady] = useState(false);
  const cameraPose = useRef<{ position: T.Vector3; target: T.Vector3 } | null>(null);
  useEffect(() => {
    const container = host.current!;
    let cancelled = false, cleanup = () => {};
    setReady(false); setStatus('Loading and baking…'); setDiff(''); actions.current = null;
    loadSource(source).then(input => {
      if (cancelled) { input.geometry.dispose(); input.texture.dispose(); input.dispose(); return; }
      let renderer: T.WebGLRenderer | undefined;
      let baked: T.BufferGeometry | undefined;
      try {
        baked = foldBake(input.geometry, settings);
        renderer = new T.WebGLRenderer({ antialias: true });
        renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
        renderer.outputColorSpace = T.SRGBColorSpace;
        container.appendChild(renderer.domElement);
        const textures = [input.texture.clone(), input.texture.clone()];
        textures.forEach((tex, i) => {
          tex.wrapS = settings.mirror[0] ? (i ? T.ClampToEdgeWrapping : T.MirroredRepeatWrapping) : T.RepeatWrapping;
          tex.wrapT = settings.mirror[1] ? (i ? T.ClampToEdgeWrapping : T.MirroredRepeatWrapping) : T.RepeatWrapping;
          tex.repeat.set(i ? 1 : settings.repeat[0], i ? 1 : settings.repeat[1]);
          tex.offset.set(i ? 0 : settings.offset[0], i ? 0 : settings.offset[1]);
          tex.magFilter = filter === 'nearest' ? T.NearestFilter : T.LinearFilter;
          tex.minFilter = filter === 'mipmap' ? T.LinearMipmapLinearFilter : filter === 'nearest' ? T.NearestFilter : T.LinearFilter;
          tex.generateMipmaps = filter === 'mipmap'; tex.needsUpdate = true;
        });
        const materials = textures.map(map => lit
          ? new T.MeshStandardMaterial({ map, roughness: .85, side: T.DoubleSide, wireframe: wire })
          : new T.MeshBasicMaterial({ map, side: T.DoubleSide, wireframe: wire }));
        const geometries = [input.geometry, baked];
        const scenes = geometries.map((g, i) => {
          const scene = new T.Scene(); scene.background = new T.Color('#101927');
          scene.add(new T.Mesh(g, materials[i]));
          scene.add(new T.HemisphereLight(0xcce7ff, 0x5e4535, 1));
          const sun = new T.DirectionalLight(0xffffff, 2.5);
          const angle = light * Math.PI / 180; sun.position.set(Math.sin(angle) * 4, 3, Math.cos(angle) * 4); scene.add(sun);
          return scene;
        });
        const camera = new T.PerspectiveCamera(42, 1, .01, 100);
        camera.position.copy(cameraPose.current?.position ?? new T.Vector3(0, 0, 6));
        const orbit = new OrbitControls(camera, renderer.domElement);
        orbit.target.copy(cameraPose.current?.target ?? new T.Vector3()); orbit.update();
        const reset = () => { camera.position.set(0, 0, 6); orbit.target.set(0, 0, 0); orbit.update(); };
        const draw = () => {
          if (!renderer) return;
          const w = container.clientWidth, h = container.clientHeight;
          renderer.setSize(w, h, false);
          const half = Math.floor(w / 2);
          camera.aspect = half / h; camera.updateProjectionMatrix();
          renderer.setScissorTest(true);
          scenes.forEach((scene, i) => {
            renderer!.setViewport(i * half, 0, half, h); renderer!.setScissor(i * half, 0, half, h); renderer!.render(scene, camera);
          });
          renderer.setScissorTest(false);
        };
        orbit.addEventListener('change', draw);
        const observer = new ResizeObserver(draw); observer.observe(container);
        draw();
        actions.current = {
          reset,
          compare: () => {
            const size = 512, target = new T.WebGLRenderTarget(size, size, { depthBuffer: true });
            const oldAspect = camera.aspect;
            try {
              const pixels = scenes.map(scene => {
                camera.aspect = 1; camera.updateProjectionMatrix();
                renderer!.setRenderTarget(target); renderer!.setViewport(0, 0, size, size);
                renderer!.setScissorTest(false); renderer!.render(scene, camera);
                const data = new Uint8Array(size * size * 4);
                renderer!.readRenderTargetPixels(target, 0, 0, size, size, data); return data;
              });
              let total = 0, max = 0, changed = 0;
              for (let p = 0; p < pixels[0].length; p += 4) {
                let peak = 0;
                for (let c = 0; c < 3; c++) {
                  const d = Math.abs(pixels[0][p+c] - pixels[1][p+c]); total += d; max = Math.max(max, d); peak = Math.max(peak, d);
                }
                if (peak > 2) changed++;
              }
              setDiff(`512² pixels · mean RGB error ${(total / (size * size * 3)).toFixed(4)}/255 · max ${max}/255 · ${(100 * changed / (size * size)).toFixed(3)}% pixels differ by >2`);
            } finally {
              renderer!.setRenderTarget(null); camera.aspect = oldAspect; camera.updateProjectionMatrix(); target.dispose(); draw();
            }
          },
          fixture: () => {
            const fixture = godotFixture(source, input.geometry, baked!, input.texture, settings);
            const url = URL.createObjectURL(new Blob([JSON.stringify(fixture)], { type: 'application/json' }));
            const a = document.createElement('a'); a.href = url; a.download = `${source}.json`; a.click();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
          },
          export: async () => {
            const root = new T.Group(); root.add(new T.Mesh(baked!, materials[1]));
            root.userData = { mirrorBake: { version: 1, source, settings, staticSnapshot: true } };
            const glb = await new GLTFExporter().parseAsync(root, { binary: true });
            const url = URL.createObjectURL(new Blob([glb as ArrayBuffer], { type: 'model/gltf-binary' }));
            const a = document.createElement('a'); a.href = url; a.download = `mirror-baked-${source}.glb`; a.click();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
          },
        };
        setStatus(`${(input.geometry.index?.count ?? input.geometry.getAttribute('position').count) / 3} → ${baked.getAttribute('position').count / 3} triangles · standard Three.js materials · no custom shader`);
        setReady(true);
        cleanup = () => {
          cameraPose.current = { position: camera.position.clone(), target: orbit.target.clone() };
          observer.disconnect(); orbit.dispose(); renderer!.dispose(); renderer!.domElement.remove();
          textures.forEach(t => t.dispose()); materials.forEach(m => m.dispose());
          input.geometry.dispose(); baked!.dispose(); input.texture.dispose(); input.dispose();
        };
      } catch (e) {
        baked?.dispose(); renderer?.dispose(); renderer?.domElement.remove();
        input.geometry.dispose(); input.texture.dispose(); input.dispose();
        setStatus(`Cannot compare: ${e instanceof Error ? e.message : String(e)}`);
      }
    }).catch(e => { if (!cancelled) setStatus(`Cannot load asset: ${String(e)}`); });
    return () => { cancelled = true; actions.current = null; cleanup(); };
  }, [source, settings, filter, lit, wire, light]);

  const changeSource = (value: Source) => {
    cameraPose.current = null; setSource(value); setSettings(value === 'stage' ? pathSettings : syntheticSettings);
  };
  const number = (key: 'repeat' | 'offset', axis: number, value: number) => {
    if (!Number.isFinite(value)) return;
    setSettings(s => ({ ...s, [key]: s[key].map((v, i) => i === axis ? value : v) }));
  };
  return <div className="mirror-lab">
    <header><div><h1>Mirror UV bake</h1><p>Compare the same surface and camera. Drag to orbit · scroll to zoom.</p></div>
      <select aria-label="Source" value={source} onChange={e => changeSource(e.target.value as Source)}>
        <option value="stage">Gurhacia Valley · pass1 path</option><option value="synthetic">Asymmetric test card</option>
      </select>
    </header>
    <div className="mirror-toolbar">
      {[0, 1].map(axis => <fieldset key={axis}><legend>{axis ? 'V axis' : 'U axis'}</legend>
        <label><input type="checkbox" checked={settings.mirror[axis]} onChange={e => setSettings(s => ({ ...s, mirror: s.mirror.map((v,i) => i === axis ? e.target.checked : v) as [boolean,boolean] }))} />Mirror</label>
        <label>Scale <input aria-label={`${axis ? 'V' : 'U'} scale`} type="number" step="0.1" value={settings.repeat[axis]} onChange={e => number('repeat', axis, e.target.valueAsNumber)} /></label>
        <label>Offset <input aria-label={`${axis ? 'V' : 'U'} offset`} type="number" step="0.1" value={settings.offset[axis]} onChange={e => number('offset', axis, e.target.valueAsNumber)} /></label>
      </fieldset>)}
      <label>Filter <select aria-label="Filter" value={filter} onChange={e => setFilter(e.target.value as Filter)}><option value="linear">Linear · no mips</option><option value="mipmap">Linear + mipmaps</option><option value="nearest">Nearest</option></select></label>
      <label><input type="checkbox" checked={lit} onChange={e => setLit(e.target.checked)} />Native lighting</label>
      <label>Light angle <input aria-label="Light angle" type="range" min="-180" max="180" value={light} onChange={e => setLight(+e.target.value)} /></label>
      <label><input type="checkbox" checked={wire} onChange={e => setWire(e.target.checked)} />Wireframe</label>
    </div>
    <div className="mirror-labels"><span>Original · hardware mirrored repeat</span><span>Baked UVs · clamp mirrored axes</span></div>
    <div className="mirror-canvas" ref={host} />
    <footer><p role="status">{status}</p><div className="mirror-buttons">
      <button disabled={!ready} onClick={() => actions.current?.compare()}>Measure pixel difference</button>
      <button disabled={!ready} onClick={() => actions.current?.reset()}>Reset camera</button>
      <button disabled={!ready} onClick={() => actions.current?.export().catch(e => setDiff(`Export failed: ${String(e)}`))}>Download baked GLB</button>
      <button disabled={!ready} onClick={() => actions.current?.fixture()}>Download Godot fixture</button>
    </div><p data-testid="pixel-diff">{diff || 'Measure both renders offscreen at the same camera, resolution and lighting.'}</p>
      <p className="mirror-note">Prototype: Valley is a static rest-pose snapshot of one surface. No game assets are changed. The independent Godot proof uses reflected texture periods for mixed-axis wrapping; its texture-memory tradeoff needs review before rollout. Mipmap differences remain visible in the comparison.</p>
    </footer>
  </div>;
}
