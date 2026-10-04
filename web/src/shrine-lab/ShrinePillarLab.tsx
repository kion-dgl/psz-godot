import { Suspense, useEffect, useMemo, useState } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { OrbitControls, useTexture, useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import { localAssetUrl } from '../utils/assets';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import './shrine-pillar-lab.css';

type View = 'compare' | 'original' | 'rebuilt' | 'insets' | 'lantern';
type Focus = 'whole' | 'lower' | 'shaft' | 'lantern';
interface Surface {
  material: string; positions: number[]; normals: number[]; uvs: number[];
  colors: number[]; inset: boolean; texture: string;
  repeat: [number, number]; offset: [number, number]; mirrorS: boolean; mirrorT: boolean;
}
interface Preview { stage: string; original: Surface[]; rebuilt: Surface[] }
interface Appearance { wireframe: boolean; emission: number; baked: boolean; glowing?: boolean; bandHeight: number; bandWidth: number; isolated?: boolean }
const PREVIEW = 'assets/stages/shrine_b/s07b_ga1/lndmd/s07b_ga1_pillar_preview.json';

function makeGeometry(surface: Surface) {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(surface.positions, 3));
  geometry.setAttribute('normal', new THREE.Float32BufferAttribute(surface.normals, 3));
  geometry.setAttribute('uv', new THREE.Float32BufferAttribute(surface.uvs, 2));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(surface.colors, 3));
  geometry.computeBoundingSphere();
  return geometry;
}

function Stone({ surface, geometry, appearance }: { surface: Surface; geometry: THREE.BufferGeometry; appearance: Appearance }) {
  const source = useTexture(localAssetUrl(surface.texture));
  const texture = useMemo(() => {
    const copy = source.clone();
    copy.colorSpace = THREE.SRGBColorSpace;
    copy.flipY = false; // Exported UVs retain the glTF/Godot convention.
    copy.wrapS = surface.mirrorS ? THREE.MirroredRepeatWrapping : THREE.RepeatWrapping;
    copy.wrapT = surface.mirrorT ? THREE.MirroredRepeatWrapping : THREE.RepeatWrapping;
    copy.repeat.set(...surface.repeat);
    copy.offset.set(...surface.offset);
    copy.magFilter = THREE.NearestFilter;
    copy.minFilter = THREE.NearestMipmapNearestFilter;
    copy.needsUpdate = true;
    return copy;
  }, [source, surface]);
  useEffect(() => () => texture.dispose(), [texture]);
  const material = useMemo(() => {
    const mat = new THREE.MeshStandardMaterial({ map: texture, vertexColors: appearance.baked,
      roughness: .95, wireframe: appearance.wireframe, side: THREE.DoubleSide, alphaTest: .1 });
    if (appearance.glowing) {
      mat.onBeforeCompile = shader => {
        shader.uniforms.potEmission = { value: appearance.emission };
        shader.uniforms.bandHeight = { value: appearance.bandHeight };
        shader.uniforms.bandWidth = { value: appearance.bandWidth };
        shader.vertexShader = 'varying vec3 potPosition;\n' + shader.vertexShader;
        shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>',
          '#include <begin_vertex>\npotPosition = position;');
        shader.fragmentShader = `varying vec3 potPosition;
          uniform float potEmission;
          uniform float bandHeight;
          uniform float bandWidth;\n` + shader.fragmentShader;
        shader.fragmentShader = shader.fragmentShader.replace('#include <emissivemap_fragment>', `
          #include <emissivemap_fragment>
          float band = exp(-2.0 * pow((potPosition.y - bandHeight) / bandWidth, 2.0));
          float vessel = smoothstep(0.44, 0.75, potPosition.y) * (1.0-smoothstep(1.5, 2.2, potPosition.y));
          float grain = 0.4 + 0.6 * clamp(dot(diffuseColor.rgb, vec3(0.333)) * 2.0, 0.0, 1.0);
          float glow = (band + vessel * 0.12) * grain;
          ${appearance.isolated ? 'if (glow < 0.025) discard; diffuseColor.rgb *= 0.1;' : ''}
          totalEmissiveRadiance += diffuseColor.rgb * vec3(0.55, 0.65, 0.68) * 0.065;
          totalEmissiveRadiance += vec3(0.025, 0.42, 0.34) * potEmission * glow;
        `);
      };
      mat.customProgramCacheKey = () => `pot-glow-dark-teal-${appearance.isolated ? 'isolated' : 'full'}`;
    }
    return mat;
  }, [texture, appearance.baked, appearance.wireframe, appearance.glowing, appearance.emission,
    appearance.bandHeight, appearance.bandWidth, appearance.isolated]);
  useEffect(() => () => material.dispose(), [material]);
  return <mesh geometry={geometry} material={material} castShadow receiveShadow />;
}

function Piece({ surface, appearance }: { surface: Surface; appearance: Appearance }) {
  const geometry = useMemo(() => makeGeometry(surface), [surface]);
  useEffect(() => () => geometry.dispose(), [geometry]);
  if (!surface.inset && surface.texture) return <Stone surface={surface} geometry={geometry} appearance={appearance} />;
  return <mesh geometry={geometry}>
    <meshStandardMaterial color={new THREE.Color(.3, .95, .9)}
      emissive={new THREE.Color(.3, .95, .9)} emissiveIntensity={appearance.emission}
      roughness={.3} wireframe={appearance.wireframe} side={THREE.DoubleSide} />
  </mesh>;
}

function SoftGlow() {
  const { gl, scene, camera, size } = useThree();
  const pipeline = useMemo(() => {
    const composer = new EffectComposer(gl);
    const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), .55, .65, .75);
    const output = new OutputPass();
    composer.addPass(new RenderPass(scene, camera));
    composer.addPass(bloom);
    composer.addPass(output);
    return { composer, bloom, output };
  }, [gl, scene, camera]);
  useEffect(() => { pipeline.composer.setSize(size.width, size.height); }, [pipeline, size]);
  useEffect(() => () => { pipeline.bloom.dispose(); pipeline.output.dispose(); pipeline.composer.dispose(); }, [pipeline]);
  useFrame((_, delta) => pipeline.composer.render(delta), 1);
  return null;
}

function Camera({ focus, compare, reset }: { focus: Focus; compare: boolean; reset: number }) {
  const { camera } = useThree();
  const targetY = focus === 'lantern' ? 1.2 : focus === 'lower' ? 2.1 : focus === 'shaft' ? 9.0 : 7.5;
  useEffect(() => {
    const distance = focus === 'lantern' ? 5.5 : focus === 'whole' ? 24 : compare ? 16 : 7;
    camera.position.set(distance * .42, targetY + distance * .18, distance);
    camera.lookAt(0, targetY, 0);
    camera.updateProjectionMatrix();
  }, [camera, focus, compare, reset, targetY]);
  return <OrbitControls makeDefault target={[0, targetY, 0]} minDistance={1.5} maxDistance={70} />;
}

function Pillar({ surfaces, x, appearance, pool }: { surfaces: Surface[]; x: number; appearance: Appearance; pool: boolean }) {
  return <group position={[x, 0, 0]}>
    {surfaces.map((surface, i) => <Piece key={`${surface.material}-${i}`} surface={surface} appearance={appearance} />)}
    {pool && <pointLight position={[-.4, 1.5, -.4]} color="#2cae9e" intensity={2 * appearance.emission} distance={7} decay={2} />}
  </group>;
}

function LanternModel() {
  const { scene } = useGLTF(localAssetUrl('assets/stages/shrine_b/s07b_ga1/lndmd/shrine_lantern_preview.glb'));
  const model = useMemo(() => scene.clone(true), [scene]);
  return <primitive object={model} />;
}

export default function ShrinePillarLab() {
  const [data, setData] = useState<Preview | null>(null);
  const [error, setError] = useState('');
  const [view, setView] = useState<View>(() => window.location.hash.includes('view=lantern') ? 'lantern' : 'compare');
  const [focus, setFocus] = useState<Focus>(() => window.location.hash.includes('view=lantern') ? 'lantern' : 'lower');
  const [wireframe, setWireframe] = useState(false);
  const [emission, setEmission] = useState(.36);
  const [baked, setBaked] = useState(true);
  const [pool, setPool] = useState(true);
  const [dark, setDark] = useState(() => !window.location.hash.includes('view=lantern'));
  const [bandHeight, setBandHeight] = useState(.95);
  const [bandWidth, setBandWidth] = useState(.22);
  const [reset, setReset] = useState(0);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const abort = new AbortController();
    setError('');
    fetch(localAssetUrl(PREVIEW) + `?reload=${revision}`, { signal: abort.signal, cache: 'no-store' })
      .then(res => { if (!res.ok) throw new Error('Export the pillar preview from the local stage assets first.'); return res.json(); })
      .then((preview: Preview) => { if (!preview.original || !preview.rebuilt) throw new Error('Invalid pillar preview.'); setData(preview); })
      .catch((e: Error) => { if (e.name !== 'AbortError') setError(e.message); });
    return () => abort.abort();
  }, [revision]);
  const appearance = { wireframe, emission, baked, bandHeight, bandWidth };
  const triangles = (surfaces: Surface[]) => surfaces.reduce((sum, surface) => sum + surface.positions.length / 9, 0);

  return <div className="shrine-lab">
    <header className="shrine-lab-header">
      <div><span className="shrine-eyebrow">DARK SHRINE B · MESH STUDY</span><h1>Haunted vessel</h1></div>
      <p>A dark teal glow seeping from the stone near the base.</p>
      <button onClick={() => setRevision(v => v + 1)}>Reload export</button>
    </header>
    <div className="shrine-lab-body">
      <aside className="shrine-panel">
        <label className="shrine-label">View</label>
        <div className="shrine-modes">{([['compare', 'Side by side'], ['original', 'Original'], ['rebuilt', 'Glowing pot'], ['insets', 'Glow region'], ['lantern', '3D lantern']] as [View, string][]).map(([value, label]) =>
          <button key={value} aria-pressed={view === value} onClick={() => { setView(value); if (value === 'lantern') { setFocus('lantern'); setDark(false); } else if (focus === 'lantern') setFocus('lower'); }}>{label}</button>)}</div>
        <label className="shrine-label" htmlFor="shrine-focus">Focus</label>
        <select id="shrine-focus" value={focus} onChange={e => setFocus(e.target.value as Focus)}>
          <option value="whole">Whole pillar</option><option value="lower">Lower ornament</option><option value="shaft">Upper shaft</option><option value="lantern">Lantern</option>
        </select>
        <button className="shrine-reset" onClick={() => setReset(v => v + 1)}>Reset camera</button>
        <label className="shrine-label">Inspect</label>
        <label className="shrine-check"><input type="checkbox" checked={wireframe} onChange={e => setWireframe(e.target.checked)} />Wireframe</label>
        <label className="shrine-check"><input type="checkbox" checked={baked} onChange={e => setBaked(e.target.checked)} />Original vertex shading</label>
        <label className="shrine-label" htmlFor="shrine-emission">Teal glow <output>{emission.toFixed(1)}</output></label>
        <input id="shrine-emission" type="range" min="0" max="4" step="0.1" value={emission} onChange={e => setEmission(Number(e.target.value))} />
        <label className="shrine-label" htmlFor="band-height">Band height <output>{bandHeight.toFixed(2)}</output></label>
        <input id="band-height" type="range" min="0.6" max="2.2" step="0.05" value={bandHeight} onChange={e => setBandHeight(Number(e.target.value))} />
        <label className="shrine-label" htmlFor="band-width">Band softness</label>
        <input id="band-width" type="range" min="0.06" max="0.6" step="0.02" value={bandWidth} onChange={e => setBandWidth(Number(e.target.value))} />
        <label className="shrine-check"><input type="checkbox" checked={dark} onChange={e => setDark(e.target.checked)} />Dark lighting</label>
        <label className="shrine-check"><input type="checkbox" checked={pool} onChange={e => setPool(e.target.checked)} />Teal spill light</label>
        <div className="shrine-note"><strong>What changed</strong><p>A soft dark teal band wraps the lower vessel, with a faint glow through the surrounding stone. The upper shaft stays dark. This is a Three.js material study before updating Godot.</p><p>Lighting here is for inspection; it does not reproduce Godot’s fog or light intensity.</p></div>
        {data && <dl className="shrine-stats"><dt>Original triangles</dt><dd>{triangles(data.original)}</dd><dt>Study triangles</dt><dd>{triangles(data.original)}</dd></dl>}
      </aside>
      <main className="shrine-viewport">
        {error ? <div className="shrine-error">{error}<code>Godot --headless --path . --script scripts/tools/export_shrine_pillar_preview.gd</code></div> : !data ? <div className="shrine-error">Loading pillar geometry…</div> : <>
          <div className="shrine-view-labels">{view === 'compare' ? <><span>ORIGINAL</span><span>DARK TEAL GLOW · LOWER VESSEL</span></> : <span>{view === 'insets' ? 'GLOW REGION' : view.toUpperCase()}</span>}</div>
          <Canvas shadows camera={{ fov: 42, near: .05, far: 150 }} dpr={[1, 2]} gl={{ antialias: true }}>
            <color attach="background" args={[dark ? '#090f16' : '#25303d']} />
            <ambientLight intensity={dark ? .28 : 1.3} />
            {dark && <directionalLight position={[4, 10, 8]} color="#bac8bd" intensity={.35} />}
            {!dark && <><directionalLight position={[7, 18, 10]} intensity={2.2} /><directionalLight position={[-8, 10, -8]} color="#91c9ff" intensity={1.3} /></>}
            <Suspense fallback={null}>
              {(view === 'compare' || view === 'original') && <Pillar surfaces={data.original} x={view === 'compare' ? -3 : 0} appearance={appearance} pool={false} />}
              {view !== 'original' && view !== 'lantern' && <Pillar surfaces={data.original} x={view === 'compare' ? 3 : 0} appearance={{ ...appearance, glowing: true, isolated: view === 'insets' }} pool={pool} />}
              {view === 'lantern' && <LanternModel />}
            </Suspense>
            <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -.03, 0]} receiveShadow>
              <planeGeometry args={[40, 40]} /><meshStandardMaterial color="#333b32" roughness={1} />
            </mesh>
            <SoftGlow />
            <gridHelper args={[40, 40, '#526879', '#344350']} position={[0, -.02, 0]} />
            <Camera focus={focus} compare={view === 'compare'} reset={reset} />
          </Canvas>
          <div className="shrine-view-hint">Drag to orbit · Scroll to zoom · Right-drag to pan</div>
        </>}
      </main>
    </div>
  </div>;
}
