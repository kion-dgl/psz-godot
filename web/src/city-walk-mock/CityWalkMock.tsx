// CityWalkMock — walk a capsule around the merged city model + its floor
// collider, in the SAME frame Godot uses, to verify the floor is solid and to
// place NPC / warp / spawn / trigger markers. Export the positions as GDScript
// so Godot just has to match the mock.
//
// URL: /psz-godot/#/city-walk-mock?glb=<model.glb>&floor=<floor.glb>
//   - glb:   textured visual model (defaults to s00e_sa2_m.glb)
//   - floor: collision mesh the capsule walks on (defaults to s00e_sa2-floor.glb)
//
// Controls: WASD move (camera-relative), drag to orbit, scroll to zoom,
// Space = jump. Click "place: <thing>" then click the floor to drop that marker.

import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

const DEFAULT_MODEL = '/psz-godot/assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb';
const DEFAULT_FLOOR = '/psz-godot/assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2-floor.glb';

const MARKER_KINDS = [
  { key: 'spawn', label: 'spawn', color: 0xffffff },
  { key: 'storage', label: 'storage NPC', color: 0x22d3ee },
  { key: 'guild', label: 'guild NPC', color: 0xfacc15 },
  { key: 'warp', label: 'warp pad', color: 0xf87171 },
  { key: 'market_exit', label: 'market exit', color: 0x4ade80 },
  { key: 'office_exit', label: 'office exit', color: 0xc084fc },
] as const;
type MarkerKey = (typeof MARKER_KINDS)[number]['key'];

const RADIUS = 0.4;
const HEIGHT = 1.8;          // total capsule height (feet→head)
const SPEED = 10.0;          // units/sec
const TURN = 2.6;            // radians/sec (tank turn rate)
const GRAVITY = 20.0;
const JUMP = 8.0;
const STEP_UP = 1.0;         // max stair/slope step the capsule snaps up
const CAM_DIST = 9.0;        // follow-cam distance behind
const CAM_HEIGHT = 5.0;      // follow-cam height
const FALL_LIMIT = 40.0;     // respawn if you fall this far below the floor

export default function CityWalkMock() {
  const [params] = useSearchParams();
  const modelUrl = params.get('glb') || DEFAULT_MODEL;
  const floorUrl = params.get('floor') || DEFAULT_FLOOR;

  const mountRef = useRef<HTMLDivElement>(null);
  const placeKindRef = useRef<MarkerKey | null>(null);
  const markersRef = useRef<Record<string, { mesh: THREE.Object3D; pos: THREE.Vector3 }>>({});

  const [status, setStatus] = useState('loading…');
  const [placeKind, setPlaceKind] = useState<MarkerKey | null>(null);
  const [placed, setPlaced] = useState<Record<string, [number, number, number]>>({});
  const [feetPos, setFeetPos] = useState<[number, number, number]>([0, 0, 0]);

  useEffect(() => { placeKindRef.current = placeKind; }, [placeKind]);

  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 4000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    // Orbit controls — used only while placing a marker (disabled when walking).
    const orbit = new OrbitControls(camera, renderer.domElement);
    orbit.enableDamping = true;
    orbit.enabled = false;
    scene.add(new THREE.AmbientLight(0xffffff, 1.1));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(40, 80, 40);
    scene.add(dir);
    scene.add(new THREE.GridHelper(400, 80, 0x223044, 0x16202e));

    // Capsule (the "player"). Tracks FEET position.
    const capsule = new THREE.Mesh(
      new THREE.CapsuleGeometry(RADIUS, HEIGHT - 2 * RADIUS, 6, 12),
      new THREE.MeshStandardMaterial({ color: 0x4ade80, transparent: true, opacity: 0.85 }),
    );
    scene.add(capsule);
    const feet = new THREE.Vector3(0, 50, 100);
    const spawn = new THREE.Vector3(0, 50, 100);
    let heading = Math.PI;   // yaw; faces -Z by default
    let velY = 0;

    let floorMesh: THREE.Object3D | null = null;
    let modelMesh: THREE.Object3D | null = null;  // visual geometry — markers raycast against this
    const raycaster = new THREE.Raycaster();
    const DOWN = new THREE.Vector3(0, -1, 0);

    const loader = new GLTFLoader();
    let loaded = 0;
    const done = () => { loaded++; if (loaded === 2) setStatus('W/S drive · A/D turn · Q/E strafe · Space jump'); };

    // Visual model (textured). The model is a static mesh (skin stripped), so
    // GLTFLoader applies its node transform directly — same world frame as the
    // baked floor + Godot. No manual offset needed.
    loader.load(modelUrl, (g) => {
      scene.add(g.scene);
      modelMesh = g.scene;
      done();
    }, undefined, (e) => setStatus('model load failed: ' + (e as any).message));

    // Floor collider — the walkable surface; shown translucent green.
    loader.load(floorUrl, (g) => {
      g.scene.traverse((o) => {
        if ((o as THREE.Mesh).isMesh) {
          (o as THREE.Mesh).material = new THREE.MeshStandardMaterial({
            color: 0x22e06a, transparent: true, opacity: 0.35, side: THREE.DoubleSide,
            depthWrite: false,
          });
        }
      });
      scene.add(g.scene);
      floorMesh = g.scene;
      // Drop the capsule onto the floor near the model center.
      const box = new THREE.Box3().setFromObject(g.scene);
      const c = box.getCenter(new THREE.Vector3());
      spawn.set(c.x, box.max.y + 5, c.z);
      feet.copy(spawn);
      done();
    }, undefined, (e) => setStatus('floor load failed: ' + (e as any).message));

    // Input
    const keys: Record<string, boolean> = {};
    const onKey = (e: KeyboardEvent, d: boolean) => {
      const k = e.key.toLowerCase();
      if (['w', 'a', 's', 'd', 'q', 'e', ' '].includes(k)) { keys[k] = d; if (k === ' ') e.preventDefault(); }
    };
    const kd = (e: KeyboardEvent) => onKey(e, true);
    const ku = (e: KeyboardEvent) => onKey(e, false);
    window.addEventListener('keydown', kd);
    window.addEventListener('keyup', ku);

    // Click to place a marker on the floor — but ignore drags (orbiting).
    let downX = 0, downY = 0;
    const onDown = (ev: PointerEvent) => { downX = ev.clientX; downY = ev.clientY; };
    renderer.domElement.addEventListener('pointerdown', onDown);
    const onClick = (ev: MouseEvent) => {
      const kind = placeKindRef.current;
      const target = modelMesh ?? floorMesh;  // markers land on any visible surface
      if (!kind || !target) return;
      if (Math.abs(ev.clientX - downX) > 4 || Math.abs(ev.clientY - downY) > 4) return; // was a drag
      const rect = renderer.domElement.getBoundingClientRect();
      const m = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      raycaster.setFromCamera(m, camera);
      const hits = raycaster.intersectObject(target, true);
      if (!hits.length) return;
      const p = hits[0].point.clone();
      placeMarker(kind, p);
      setPlaceKind(null);
    };
    renderer.domElement.addEventListener('click', onClick);

    function placeMarker(kind: MarkerKey, p: THREE.Vector3) {
      const def = MARKER_KINDS.find((m) => m.key === kind)!;
      const existing = markersRef.current[kind];
      if (existing) scene.remove(existing.mesh);
      const grp = new THREE.Group();
      const post = new THREE.Mesh(
        new THREE.CylinderGeometry(0.25, 0.25, 6, 10),
        new THREE.MeshBasicMaterial({ color: def.color }),
      );
      post.position.y = 3;
      grp.add(post);
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.8, 1.3, 24),
        new THREE.MeshBasicMaterial({ color: def.color, side: THREE.DoubleSide }),
      );
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.05;
      grp.add(ring);
      grp.position.copy(p);
      scene.add(grp);
      markersRef.current[kind] = { mesh: grp, pos: p.clone() };
      setPlaced((prev) => ({ ...prev, [kind]: [p.x, p.y, p.z] }));
    }

    // Movement (tank controls) + floor follow + chase cam
    const clock = new THREE.Clock();
    let raf = 0;
    const camPos = new THREE.Vector3();
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);

      const placing = placeKindRef.current != null;
      if (!placing) {
        // Tank controls: A/D turn, W/S drive along heading, Q/E strafe.
        if (keys['a']) heading += TURN * dt;
        if (keys['d']) heading -= TURN * dt;
        const fwd = new THREE.Vector3(Math.sin(heading), 0, Math.cos(heading));
        const right = new THREE.Vector3(Math.cos(heading), 0, -Math.sin(heading));
        const move = new THREE.Vector3();
        if (keys['w']) move.add(fwd);
        if (keys['s']) move.sub(fwd);
        if (keys['e']) move.add(right);
        if (keys['q']) move.sub(right);
        if (move.lengthSq() > 0) move.normalize().multiplyScalar(SPEED * dt);
        feet.x += move.x;
        feet.z += move.z;

        // Gravity + floor snap (raycast down against the collider).
        velY -= GRAVITY * dt;
        feet.y += velY * dt;
        let grounded = false;
        let floorY = -Infinity;
        if (floorMesh) {
          raycaster.set(new THREE.Vector3(feet.x, feet.y + STEP_UP, feet.z), DOWN);
          raycaster.far = STEP_UP + 200;
          const hits = raycaster.intersectObject(floorMesh, true);
          if (hits.length) {
            floorY = hits[0].point.y;
            if (feet.y <= floorY + 0.02) { feet.y = floorY; velY = 0; grounded = true; }
          }
        }
        if (keys[' '] && grounded) velY = JUMP;
        // Respawn if we walked off and fell.
        if (feet.y < (floorY === -Infinity ? spawn.y - 200 : floorY) - FALL_LIMIT || feet.y < -200) {
          feet.copy(spawn); velY = 0;
        }
      }

      capsule.position.set(feet.x, feet.y + HEIGHT / 2, feet.z);
      capsule.rotation.y = heading;

      if (placing) {
        // Orbit around the capsule to line up a marker placement.
        if (!orbit.enabled) {
          orbit.enabled = true;
          orbit.target.set(feet.x, feet.y + 1.0, feet.z);
        }
        orbit.update();
      } else {
        orbit.enabled = false;
        // Chase cam directly behind the heading.
        camPos.set(
          feet.x - Math.sin(heading) * CAM_DIST,
          feet.y + CAM_HEIGHT,
          feet.z - Math.cos(heading) * CAM_DIST,
        );
        camera.position.lerp(camPos, 0.18);
        camera.lookAt(feet.x, feet.y + 1.2, feet.z);
      }
      renderer.render(scene, camera);
      setFeetPosThrottled(feet.x, feet.y, feet.z);
    };

    const last = new THREE.Vector3(NaN, NaN, NaN);
    const setFeetPosThrottled = (x: number, y: number, z: number) => {
      if (last.distanceToSquared(new THREE.Vector3(x, y, z)) > 0.01 || isNaN(last.x)) {
        last.set(x, y, z);
        setFeetPos([x, y, z]);
      }
    };
    animate();

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
      window.removeEventListener('keydown', kd);
      window.removeEventListener('keyup', ku);
      window.removeEventListener('resize', onResize);
      renderer.domElement.removeEventListener('click', onClick);
      renderer.domElement.removeEventListener('pointerdown', onDown);
      orbit.dispose();
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [modelUrl, floorUrl]);

  const gdscript = MARKER_KINDS
    .filter((m) => placed[m.key])
    .map((m) => {
      const [x, y, z] = placed[m.key];
      return `${m.label.padEnd(14)}Vector3(${x.toFixed(2)}, ${y.toFixed(2)}, ${z.toFixed(2)})`;
    })
    .join('\n');

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0e1a', color: '#e6edf3' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, background: 'rgba(0,0,0,0.6)', padding: '6px 10px', borderRadius: 4, fontSize: 12 }}>
          {status}
        </div>
        <div style={{ position: 'absolute', top: 8, right: 8, background: 'rgba(0,0,0,0.7)', padding: '8px 10px', borderRadius: 4, fontSize: 13, fontFamily: 'monospace' }}>
          <span style={{ color: '#8b949e' }}>pos </span>
          <span style={{ color: '#22e06a' }}>
            Vector3({feetPos[0].toFixed(2)}, {feetPos[1].toFixed(2)}, {feetPos[2].toFixed(2)})
          </span>
          <button
            onClick={() => navigator.clipboard?.writeText(`Vector3(${feetPos[0].toFixed(2)}, ${feetPos[1].toFixed(2)}, ${feetPos[2].toFixed(2)})`)}
            style={{ marginLeft: 8, padding: '2px 7px', fontSize: 11, background: '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, cursor: 'pointer' }}
          >copy</button>
        </div>
      </div>
      <aside style={{ width: 300, flexShrink: 0, padding: 16, background: '#161b22', borderLeft: '1px solid #30363d', overflowY: 'auto' }}>
        <h2 style={{ margin: '0 0 6px', fontSize: 16 }}>City walk mock</h2>
        <p style={{ margin: '0 0 10px', fontSize: 12, color: '#8b949e' }}>
          Tank controls: <b>W/S</b> drive, <b>A/D</b> turn, <b>Q/E</b> strafe,
          <b> Space</b> jump. Green = floor collider — walk it to find gaps/slopes.
          Click a marker button to switch to <b>orbit</b> (drag to rotate, scroll
          to zoom), then click the floor to drop it.
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
          {MARKER_KINDS.map((m) => (
            <button key={m.key} onClick={() => setPlaceKind(placeKind === m.key ? null : m.key)}
              style={{
                textAlign: 'left', padding: '7px 10px', borderRadius: 4, fontSize: 12, cursor: 'pointer',
                border: '1px solid ' + (placeKind === m.key ? '#1f6feb' : '#30363d'),
                background: placeKind === m.key ? '#1f6feb' : '#21262d', color: '#e6edf3',
              }}>
              <span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 5, marginRight: 8, background: '#' + m.color.toString(16).padStart(6, '0') }} />
              place: {m.label}
              {placed[m.key] && <span style={{ float: 'right', color: '#22e06a', fontFamily: 'monospace', fontSize: 10 }}>
                {placed[m.key].map((v) => v.toFixed(1)).join(', ')}
              </span>}
            </button>
          ))}
        </div>
        {gdscript && (
          <>
            <h3 style={{ fontSize: 13, margin: '14px 0 6px', color: '#8b949e' }}>positions</h3>
            <pre style={{ background: '#0d1117', padding: 8, borderRadius: 4, fontSize: 11, overflow: 'auto' }}>{gdscript}</pre>
            <button onClick={() => navigator.clipboard?.writeText(gdscript)}
              style={{ width: '100%', padding: '6px 10px', background: '#238636', color: '#fff', border: 'none', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}>
              copy positions
            </button>
          </>
        )}
      </aside>
    </div>
  );
}
