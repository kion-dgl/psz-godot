// WallDebug — non-destructive preview for issue #534 (market outer wall seam).
//
// The market backdrop is two meshes: the original wall03 arc (dairon2.glb) with
// a baked dark-teal COLOR_0 gradient, and wall_extension.glb which was generated
// WITHOUT vertex colors AND with the texture as emissive (so it renders bright
// gray — the seam). This page renders both from R2 and lets us:
//
//   • Click any triangle on the ORIGINAL arc to read its true baked vertex color
//     (the ground-truth eyedropper — "identify an example triangle").
//   • Live-recolor the extension the way the baked fix will: MeshBasic, wall03
//     texture as map (albedo), a Y-lerped COLOR_0 between a base and top color.
//     Tune base/top until the seam disappears, THEN bake those exact numbers.
//
// Nothing here writes an asset — it only previews. Values shown are LINEAR RGB,
// matching the glTF COLOR_0 the bake will write.
import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

const ORIGINAL = assetUrl('assets/stages/city_e/market/dairon2.glb');
const EXTENSION = assetUrl('assets/stages/city_e/market/wall_extension.glb');

// Measured from dairon2.glb wall03 arc (Y −1.81 base → 23.65 top), linear RGB.
const DEFAULT_BASE: [number, number, number] = [0.0103, 0.1099, 0.1136];
const DEFAULT_TOP: [number, number, number] = [0.0036, 0.0087, 0.0083];

function isWall03(mat: THREE.Material | THREE.Material[]): boolean {
  const one = Array.isArray(mat) ? mat[0] : mat;
  return !!one && /wall03/i.test(one.name || '');
}

export default function WallDebug() {
  const mountRef = useRef<HTMLDivElement>(null);
  const extMeshRef = useRef<THREE.Mesh | null>(null);
  const [base, setBase] = useState<[number, number, number]>(DEFAULT_BASE);
  const [top, setTop] = useState<[number, number, number]>(DEFAULT_TOP);
  const [showExtColor, setShowExtColor] = useState(true);
  const [picked, setPicked] = useState<{ rgb: [number, number, number]; y: number } | null>(null);

  // ---- one-time scene setup ----
  useEffect(() => {
    const mount = mountRef.current!;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    const camera = new THREE.PerspectiveCamera(45, mount.clientWidth / mount.clientHeight, 0.1, 5000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(mount.clientWidth, mount.clientHeight);
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    mount.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;

    const loader = new GLTFLoader();
    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    let originalWall: THREE.Mesh | null = null;

    loader.load(ORIGINAL, (g) => {
      scene.add(g.scene);
      g.scene.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && m.material && isWall03(m.material)) originalWall = m;
      });
    });

    loader.load(EXTENSION, (g) => {
      scene.add(g.scene);
      g.scene.traverse((o) => {
        const m = o as THREE.Mesh;
        if (!m.isMesh) return;
        // Rebuild the extension material the way the baked fix will: wall03
        // texture as albedo (from the existing emissiveMap), unlit, vertex
        // colors as albedo multiply.
        const src = (Array.isArray(m.material) ? m.material[0] : m.material) as THREE.MeshStandardMaterial;
        const tex = src.emissiveMap || src.map || null;
        const basic = new THREE.MeshBasicMaterial({ map: tex, vertexColors: true, side: THREE.DoubleSide });
        m.material = basic;
        extMeshRef.current = m;
        applyGradient(m, base, top, showExtColor);
        // Frame the camera on the extension.
        const box = new THREE.Box3().setFromObject(m);
        const c = box.getCenter(new THREE.Vector3());
        const size = box.getSize(new THREE.Vector3()).length();
        controls.target.copy(c);
        camera.position.copy(c).add(new THREE.Vector3(0, size * 0.15, size * 0.6));
        camera.near = size / 100; camera.far = size * 10; camera.updateProjectionMatrix();
      });
    });

    // Eyedropper: click a triangle on the original arc, read its baked COLOR_0.
    const onClick = (e: MouseEvent) => {
      if (!originalWall) return;
      const r = renderer.domElement.getBoundingClientRect();
      pointer.x = ((e.clientX - r.left) / r.width) * 2 - 1;
      pointer.y = -((e.clientY - r.top) / r.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObject(originalWall, false)[0];
      if (!hit || hit.face == null) return;
      const col = originalWall.geometry.getAttribute('color');
      const pos = originalWall.geometry.getAttribute('position');
      if (!col) return;
      const { a, b, c } = hit.face;
      const avg = (attr: THREE.BufferAttribute, k: 0 | 1 | 2) =>
        (attr.getComponent(a, k) + attr.getComponent(b, k) + attr.getComponent(c, k)) / 3;
      setPicked({
        rgb: [avg(col as THREE.BufferAttribute, 0), avg(col as THREE.BufferAttribute, 1), avg(col as THREE.BufferAttribute, 2)],
        y: pos ? avg(pos as THREE.BufferAttribute, 1) : 0,
      });
    };
    renderer.domElement.addEventListener('click', onClick);

    let raf = 0;
    const tick = () => { controls.update(); renderer.render(scene, camera); raf = requestAnimationFrame(tick); };
    tick();

    const onResize = () => {
      camera.aspect = mount.clientWidth / mount.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(mount.clientWidth, mount.clientHeight);
    };
    window.addEventListener('resize', onResize);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      renderer.domElement.removeEventListener('click', onClick);
      renderer.dispose();
      mount.removeChild(renderer.domElement);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- re-apply gradient when sliders change ----
  useEffect(() => {
    if (extMeshRef.current) applyGradient(extMeshRef.current, base, top, showExtColor);
  }, [base, top, showExtColor]);

  return (
    <div style={{ display: 'flex', height: '100%', fontFamily: 'monospace', color: '#cdd6f4' }}>
      <div ref={mountRef} style={{ flex: 1, minWidth: 0 }} />
      <div style={{ width: 300, padding: 16, background: '#12122a', overflowY: 'auto', fontSize: 12 }}>
        <h3 style={{ margin: '0 0 8px' }}>Wall #534 preview</h3>
        <p style={{ color: '#8b97b4', lineHeight: 1.5 }}>
          Click a triangle on the <b>original</b> arc to read its baked vertex color. Tune base/top below to
          match; those linear values get baked into <code>wall_extension.glb</code>.
        </p>

        <label style={{ display: 'block', margin: '12px 0 4px' }}>
          <input type="checkbox" checked={showExtColor} onChange={(e) => setShowExtColor(e.target.checked)} />{' '}
          apply gradient to extension
        </label>

        <RgbInput label="base (bottom, Y≈−1.8)" value={base} onChange={setBase} />
        <RgbInput label="top (Y≈23.6)" value={top} onChange={setTop} />

        <div style={{ marginTop: 16, padding: 8, background: '#0a0e1a', borderRadius: 4 }}>
          <div style={{ color: '#8b97b4' }}>picked triangle</div>
          {picked ? (
            <>
              <Swatch rgb={picked.rgb} />
              <div>Y {picked.y.toFixed(2)}</div>
              <div>rgb {picked.rgb.map((n) => n.toFixed(4)).join(', ')}</div>
              <button style={btn} onClick={() => setBase(picked.rgb)}>→ set base</button>
              <button style={btn} onClick={() => setTop(picked.rgb)}>→ set top</button>
            </>
          ) : (
            <div style={{ color: '#666' }}>click the arc…</div>
          )}
        </div>

        <pre style={{ marginTop: 16, color: '#a6e3a1', whiteSpace: 'pre-wrap' }}>
{`bake values (linear):
base ${base.map((n) => n.toFixed(4)).join(', ')}
top  ${top.map((n) => n.toFixed(4)).join(', ')}`}
        </pre>
      </div>
    </div>
  );
}

// Per-vertex color = lerp(base, top) by normalized Y over the mesh's bounds.
function applyGradient(mesh: THREE.Mesh, base: number[], top: number[], enabled: boolean) {
  const geo = mesh.geometry;
  const pos = geo.getAttribute('position') as THREE.BufferAttribute;
  const n = pos.count;
  let ymin = Infinity, ymax = -Infinity;
  for (let i = 0; i < n; i++) { const y = pos.getY(i); if (y < ymin) ymin = y; if (y > ymax) ymax = y; }
  const span = ymax - ymin || 1;
  const arr = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const t = enabled ? (pos.getY(i) - ymin) / span : 1; // t=0 base(bottom) → t=1 top; disabled = white
    for (let k = 0; k < 3; k++) arr[i * 3 + k] = enabled ? base[k] + (top[k] - base[k]) * t : 1;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(arr, 3));
}

const btn: React.CSSProperties = {
  display: 'inline-block', margin: '6px 6px 0 0', padding: '3px 8px', fontSize: 11,
  background: '#1f1f3f', color: '#cdd6f4', border: '1px solid #2a2a4a', borderRadius: 3, cursor: 'pointer',
};

function Swatch({ rgb }: { rgb: number[] }) {
  // Approx sRGB for display only.
  const s = rgb.map((c) => Math.round(255 * Math.pow(Math.min(1, Math.max(0, c)), 1 / 2.2)));
  return <div style={{ width: '100%', height: 24, margin: '4px 0', borderRadius: 3, background: `rgb(${s[0]},${s[1]},${s[2]})`, border: '1px solid #333' }} />;
}

function RgbInput({ label, value, onChange }: { label: string; value: [number, number, number]; onChange: (v: [number, number, number]) => void }) {
  return (
    <div style={{ margin: '8px 0' }}>
      <div style={{ color: '#8b97b4', marginBottom: 3 }}>{label}</div>
      <Swatch rgb={value} />
      <div style={{ display: 'flex', gap: 4 }}>
        {(['r', 'g', 'b'] as const).map((_, i) => (
          <input
            key={i} type="number" step={0.001} min={0} max={1} value={value[i]}
            onChange={(e) => { const v = [...value] as [number, number, number]; v[i] = parseFloat(e.target.value) || 0; onChange(v); }}
            style={{ width: '33%', background: '#0a0e1a', color: '#cdd6f4', border: '1px solid #2a2a4a', borderRadius: 3, padding: '2px 4px', fontSize: 11 }}
          />
        ))}
      </div>
    </div>
  );
}
