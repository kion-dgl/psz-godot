// CompanionRoom — a tuning fixture for the COMPANION follow + combat locomotion
// (spec /states/companion, /states/companion-combat). Modeled on #/combat-room,
// but the point here is MOVEMENT: a WASD-driven player that actually walks/runs,
// a companion that follows using the EXACT Godot FOLLOW/ENGAGE/ATTACK/REGROUP
// FSM (trail replay + intent×speed animation), and target dummies to draw the
// companion out and back.
//
// Why it exists: two follow defects are hard to tune by round-tripping through
// the game — (1) the companion "slides in / gets pulled" returning to FOLLOW,
// and (2) it flickers walk↔run while the player runs steadily. This fixture
// reproduces both deterministically (manual drive or a demo path), exposes every
// constant as a slider, graphs the companion's measured speed vs the clip it
// picked, and exports the tuned values as GDScript to drop into companion_npc.gd.
//
// URL: /psz-godot/#/companion-room
// Controls: WASD move (world-relative), Shift = walk, drag = orbit, T = demo path.

import { useCallback, useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { assetUrl } from '../utils/assets';

// ---------------------------------------------------------------------------
// Tunables — defaults mirror companion_npc.gd / player.gd exactly, so a fresh
// load reproduces the current in-game behavior; sliders let us dial in a fix.
// ---------------------------------------------------------------------------
interface Params {
  playerRun: number;    // MOVE_SPEED
  playerWalk: number;   // WALK_SPEED
  trailDelay: number;   // TRAIL_DELAY — seconds the companion trails behind
  personalSpace: number;// min XZ gap the companion keeps from the player
  startDistance: number;// REGROUP → FOLLOW when within this of the player
  followSpeed: number;  // ENGAGE steer speed
  catchupSpeed: number; // REGROUP steer speed
  idleEps: number;      // IDLE_EPS — below this planar speed → wait
  runEnter: number;     // enter run above this measured speed
  runExit: number;      // drop out of run below this (hysteresis; = runEnter → none)
  animHold: number;     // ANIM_HOLD_TIME — walk↔run debounce
  resumeBlend: number;  // RESUME_BLEND_SPEED — 1/sec ramp resuming from a freeze
  leash: number;        // LEASH_RADIUS — target must be within this of the player
  engageReachFrac: number;
  attackCooldown: number;
  scanInterval: number;
}

const DEFAULTS: Params = {
  playerRun: 6.0, playerWalk: 2.5,
  trailDelay: 0.5, personalSpace: 1.5, startDistance: 3.0,
  followSpeed: 7.0, catchupSpeed: 10.0,
  idleEps: 0.15, runEnter: 4.0, runExit: 4.0,  // runExit=runEnter → current (no hysteresis)
  animHold: 0.30, resumeBlend: 3.0,
  leash: 12.0, engageReachFrac: 0.8, attackCooldown: 1.2, scanInterval: 0.25,
};

const STORAGE_KEY = 'psz-companion-room:v1';
const HIT_H_DIST = 2.4;         // saber-fallback cone reach (gunblade uses it)
const TELEPORT_DISTANCE = 20.0;
const SWING_TIME = 0.6;         // pmgb_atk1 length (approx; clip drives it in game)
const DAMAGING_FRAC = 0.4;

type Clip = 'wait' | 'walk' | 'run' | 'atk1';
type FsmState = 'FOLLOW' | 'ENGAGE' | 'ATTACK' | 'REGROUP';
type DemoMode = 'off' | 'straight' | 'circle' | 'zigzag' | 'strafe' | 'walkjog' | 'wander';
const DEMO_MODES: { id: DemoMode; label: string }[] = [
  { id: 'off', label: 'Manual (WASD)' },
  { id: 'straight', label: 'Run: stop–go' },
  { id: 'circle', label: 'Run in a circle' },
  { id: 'zigzag', label: 'Zig-zag' },
  { id: 'strafe', label: 'Strafe L/R' },
  { id: 'walkjog', label: 'Walk⇄run cycle' },
  { id: 'wander', label: 'Random wander' },
];

// The pure clip selector — the TS mirror of CompanionCombat.locomotion_clip,
// with an added run-threshold hysteresis band (runExit ≤ speed ≤ runEnter holds
// the current clip). intent=false or sub-idle always → wait.
function locomotionClip(intentMoving: boolean, speed: number, prev: Clip, P: Params): Clip {
  if (!intentMoving || speed < P.idleEps) return 'wait';
  if (prev === 'run') return speed < P.runExit ? 'walk' : 'run';
  return speed > P.runEnter ? 'run' : 'walk';
}

interface TrailEntry { x: number; z: number; yaw: number; moving: boolean; t: number }
interface Dummy { mesh: THREE.Mesh; x: number; z: number; radius: number; hp: number; maxHp: number; vx: number; vz: number }

interface Readout {
  state: FsmState; clip: Clip; compSpeed: number; playerSpeed: number;
  dist: number; hits: number;
}

// Rolling graph of the companion's measured speed, coloured by the clip chosen —
// this is where the walk↔run flicker shows up as a jagged colour band.
const CLIP_COLOR: Record<Clip, string> = { wait: '#6b7280', walk: '#38bdf8', run: '#34d399', atk1: '#f59e0b' };

function loadParams(): Params {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch { /* ignore */ }
  return { ...DEFAULTS };
}

export default function CompanionRoom() {
  const mountRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<HTMLCanvasElement>(null);
  const [params, setParams] = useState<Params>(loadParams);
  const paramsRef = useRef(params);
  const [status, setStatus] = useState('loading…');
  const [readout, setReadout] = useState<Readout>({ state: 'FOLLOW', clip: 'wait', compSpeed: 0, playerSpeed: 0, dist: 0, hits: 0 });
  const [demoMode, setDemoMode] = useState<DemoMode>('off');
  const demoModeRef = useRef<DemoMode>('off');
  const [movingTargets, setMovingTargets] = useState(false);
  const movingRef = useRef(false);
  const [autoRespawn, setAutoRespawn] = useState(true);
  const autoRespawnRef = useRef(true);
  const [targetCount, setTargetCount] = useState(3);
  const targetCountRef = useRef(3);
  const apiRef = useRef<{ randomize: () => void; reset: () => void } | null>(null);

  useEffect(() => { paramsRef.current = params; try { localStorage.setItem(STORAGE_KEY, JSON.stringify(params)); } catch { /* ignore */ } }, [params]);
  useEffect(() => { demoModeRef.current = demoMode; }, [demoMode]);
  useEffect(() => { movingRef.current = movingTargets; }, [movingTargets]);
  useEffect(() => { autoRespawnRef.current = autoRespawn; }, [autoRespawn]);
  useEffect(() => { targetCountRef.current = targetCount; apiRef.current?.randomize(); }, [targetCount]);

  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    const camera = new THREE.PerspectiveCamera(55, w / h, 0.1, 400);
    camera.position.set(0, 9, 12);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 1, 0);

    scene.add(new THREE.AmbientLight(0xffffff, 1.0));
    const dl = new THREE.DirectionalLight(0xffffff, 0.7);
    dl.position.set(20, 40, 20);
    scene.add(dl);
    scene.add(new THREE.GridHelper(60, 60, 0x2a3a55, 0x182233));

    // Player + companion capsules. Real skinned models load on top; if a model
    // fails, the capsule still shows the sim. Companion capsule is tinted by its
    // current clip so the flicker is visible even without watching the legs.
    const mkCapsule = (color: number) => {
      const m = new THREE.Mesh(
        new THREE.CapsuleGeometry(0.3, 1.0, 6, 12),
        new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.55 }),
      );
      m.position.y = 0.8;
      const g = new THREE.Group();
      g.add(m);
      scene.add(g);
      return g;
    };
    const playerGroup = mkCapsule(0x4ade80);
    const compGroup = mkCapsule(0xfacc15);
    const compCapsuleMat = (compGroup.children[0] as THREE.Mesh).material as THREE.MeshStandardMaterial;

    // A facing tick so orientation is readable.
    const mkNose = (parent: THREE.Group, color: number) => {
      const nose = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.12, 0.5), new THREE.MeshBasicMaterial({ color }));
      nose.position.set(0, 1.2, 0.45);
      parent.add(nose);
    };
    mkNose(playerGroup, 0x16a34a);
    mkNose(compGroup, 0xca8a04);

    // Target dummies — regenerated by spawnDummies: a fixed layout for "reset",
    // random positions/sizes/HP for "randomize". Optionally wander each frame.
    const DUMMY_AREA = 15;
    const DEFAULT_LAYOUT = [
      { x: 5, z: -6, radius: 0.5, maxHp: 80 },
      { x: -4, z: -8, radius: 0.5, maxHp: 80 },
      { x: 8, z: 2, radius: 0.6, maxHp: 120 },
      { x: -7, z: 3, radius: 0.45, maxHp: 70 },
      { x: 2, z: -12, radius: 0.55, maxHp: 100 },
      { x: -10, z: -4, radius: 0.4, maxHp: 60 },
    ];
    const dummies: Dummy[] = [];
    const rand = (a: number, b: number) => a + Math.random() * (b - a);
    function spawnDummies(n: number, randomize: boolean) {
      for (const d of dummies) { scene.remove(d.mesh); (d.mesh.geometry as THREE.BufferGeometry).dispose(); }
      dummies.length = 0;
      for (let i = 0; i < n; i++) {
        const base = DEFAULT_LAYOUT[i % DEFAULT_LAYOUT.length];
        const radius = randomize ? rand(0.35, 0.75) : base.radius;
        const maxHp = randomize ? Math.round(rand(50, 160)) : base.maxHp;
        const x = randomize ? rand(-DUMMY_AREA, DUMMY_AREA) : base.x;
        const z = randomize ? rand(-DUMMY_AREA, DUMMY_AREA) : base.z;
        const mesh = new THREE.Mesh(
          new THREE.CylinderGeometry(radius, radius, 1.6, 16),
          new THREE.MeshStandardMaterial({ color: 0xef4444 }),
        );
        mesh.position.set(x, 0.8, z);
        scene.add(mesh);
        const ang = Math.random() * Math.PI * 2;
        dummies.push({ mesh, x, z, radius, hp: maxHp, maxHp, vx: Math.sin(ang), vz: Math.cos(ang) });
      }
    }
    spawnDummies(targetCountRef.current, false);
    let respawnDelay = 1.5;

    // ----- skinned models (optional visual fidelity) -----
    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const mixers: THREE.AnimationMixer[] = [];
    let loadCount = 0;
    const bumpLoad = () => { loadCount++; if (loadCount >= 2) setStatus('WASD move · Shift walk · T demo path · drag orbit'); };

    // rig: { mixer, actions{clip->action}, current } filled per model
    interface Rig { mixer: THREE.AnimationMixer | null; actions: Record<string, THREE.AnimationAction>; current: Clip | null }
    const playerRig: Rig = { mixer: null, actions: {}, current: null };
    const compRig: Rig = { mixer: null, actions: {}, current: null };

    const stripRoot = (clip: THREE.AnimationClip) => {
      clip.tracks = clip.tracks.filter((t) => !(t.name.endsWith('.position') && /Hips|_root|Root|00_/i.test(t.name)));
    };

    // Load a character model + build its clip actions. locoGlb supplies
    // wait/walk/run (shared PSO saber pack, pmsa); swingGlb supplies atk1
    // (weapon pack, e.g. gunblade pmgb). Same split as player.gd / companion.
    function loadCharacter(
      modelUrl: string, texUrl: string, group: THREE.Group, rig: Rig,
      locoGlb: string, locoPrefix: string, swingGlb: string, swingPrefix: string,
      weaponGlb: string | null,
    ) {
      loader.load(modelUrl, (gltf) => {
        const tex = texLoader.load(texUrl, (tx) => { tx.magFilter = THREE.NearestFilter; tx.minFilter = THREE.NearestFilter; tx.flipY = false; tx.colorSpace = THREE.SRGBColorSpace; });
        gltf.scene.traverse((c) => {
          const m = c as THREE.Mesh;
          if (m.isMesh && m.material) { (m.material as THREE.MeshBasicMaterial).map = tex; (m.material as THREE.Material).needsUpdate = true; }
        });
        group.add(gltf.scene);
        (group.children[0] as THREE.Mesh).visible = false;  // hide the capsule, we have a model

        const mixer = new THREE.AnimationMixer(gltf.scene);
        mixers.push(mixer);
        rig.mixer = mixer;

        const addClip = (glbUrl: string, want: [Clip, string][], done?: () => void) => {
          loader.load(glbUrl, (ag) => {
            for (const [key, suffix] of want) {
              const clip = ag.animations.find((a) => a.name.endsWith(suffix));
              if (!clip) continue;
              stripRoot(clip);
              rig.actions[key] = mixer.clipAction(clip);
            }
            done?.();
          }, undefined, () => done?.());
        };
        // locomotion (loop) from the shared PSO pack; swing (once) from weapon pack
        addClip(locoGlb, [['wait', locoPrefix + '_wait'], ['walk', locoPrefix + '_walk'], ['run', locoPrefix + '_run_pso']], () => {
          addClip(swingGlb, [['atk1', swingPrefix + '_atk1']], bumpLoad);
        });

        // attach weapon to the right hand bone
        if (weaponGlb) {
          let handBone: THREE.Bone | null = null;
          gltf.scene.traverse((o) => { if ((o as THREE.Bone).isBone && o.name === '070_RArm02') handBone = o as THREE.Bone; });
          if (handBone) {
            loader.load(weaponGlb, (wg) => {
              const wtex = weaponGlb.replace(/\.glb$/, '.png');
              const wt = texLoader.load(wtex, (tx) => { tx.flipY = false; tx.colorSpace = THREE.SRGBColorSpace; });
              wg.scene.traverse((c) => { const m = c as THREE.Mesh; if (m.isMesh && m.material) { (m.material as THREE.MeshBasicMaterial).map = wt; } });
              wg.scene.position.set(0.31, 0, 0);
              wg.scene.rotation.set(0, Math.PI / 2, 0);
              handBone!.add(wg.scene);
            });
          }
        }
      }, undefined, () => bumpLoad());
    }

    const SABER = assetUrl('assets/player/animations/saber_m.glb');
    const SHOTGUN = assetUrl('assets/player/animations/shotgun_m.glb');
    const GUNBLADE = assetUrl('assets/weapons/wgbr02/wgbr02/wgbr02_1_o/wgbr02_1_o.glb');
    // Player: humar, saber loadout (locomotion + swing both from saber pack).
    loadCharacter(
      assetUrl('assets/player/pc_000/pc_000_000.glb'), assetUrl('assets/player/pc_000/textures/pc_000_000.png'),
      playerGroup, playerRig, SABER, 'pmsa', SABER, 'pmsa', null,
    );
    // Companion: Kai, gunblade — locomotion from saber PSO pack, swing from gunblade pack.
    loadCharacter(
      assetUrl('assets/npcs/kai/pc_a01_000.glb'), assetUrl('assets/npcs/kai/pc_a01_000.png'),
      compGroup, compRig, SABER, 'pmsa', SHOTGUN, 'pmgb', GUNBLADE,
    );

    function playRig(rig: Rig, clip: Clip, P: Params) {
      if (!rig.mixer || rig.current === clip || !rig.actions[clip]) return;
      const both = (rig.current === 'walk' || rig.current === 'run') && (clip === 'walk' || clip === 'run');
      // (debounce for the rig is handled by the sim's holdTimer; here we just crossfade)
      const prev = rig.current ? rig.actions[rig.current] : null;
      if (prev) prev.fadeOut(0.12);
      const a = rig.actions[clip];
      a.reset();
      a.setLoop(clip === 'atk1' ? THREE.LoopOnce : THREE.LoopRepeat, Infinity);
      a.clampWhenFinished = clip === 'atk1';
      a.fadeIn(0.12).play();
      rig.current = clip;
      void both; void P;
    }

    // ----- simulation state -----
    const player = { x: 0, z: 4, yaw: Math.PI, prevX: 0, prevZ: 4, speed: 0, clip: 'wait' as Clip };
    const trail: TrailEntry[] = [];
    let simTime = 0;
    const comp = {
      x: 1.6, z: 5.5, yaw: Math.PI, prevX: 1.6, prevZ: 5.5,
      state: 'FOLLOW' as FsmState, clip: 'wait' as Clip, holdTimer: 0,
      wasMoving: false, frozenX: 1.6, frozenZ: 5.5, resumeBlend: 0,
      target: -1, scanTimer: 0, swingElapsed: -1, swingHit: false, cooldown: 0,
      engageLastDist: Infinity, engageNoProgress: 0, hits: 0,
    };

    // Speed graph history: [{t, speed, clip}]
    const hist: { speed: number; clip: Clip }[] = [];
    const HIST_LEN = 240;

    // input
    const keys: Record<string, boolean> = {};
    const onKey = (e: KeyboardEvent, d: boolean) => {
      const k = e.key.toLowerCase();
      if (['w', 'a', 's', 'd', 'shift'].includes(k)) keys[k] = d;
      if (k === 't' && d) setDemoMode((m) => (m === 'off' ? 'straight' : 'off'));
      if (k === 'r' && d) apiRef.current?.randomize();
    };
    const kd = (e: KeyboardEvent) => onKey(e, true);
    const ku = (e: KeyboardEvent) => onKey(e, false);
    window.addEventListener('keydown', kd);
    window.addEventListener('keyup', ku);

    // demo path: idle → run fwd → idle → run back, loops. Reproduces the flicker
    // (steady run) and the resume-slide (stop after a run) hands-free.
    let demoT = 0;
    let wanderAngle = 0, wanderNext = 0;
    const IDLE = { mx: 0, mz: 0, walk: false };
    // Scripted player drives, each exercising a different follow condition:
    // straight (stop→run reproduces the resume-slide), circle/zigzag (turning
    // trail), strafe (lateral), walkjog (walk↔run transitions), wander (random).
    const demoDrive = (dt: number): { mx: number; mz: number; walk: boolean } => {
      demoT += dt;
      switch (demoModeRef.current) {
        case 'straight': {
          const c = demoT % 10;
          if (c < 1) return IDLE;
          if (c < 4.5) return { mx: 0, mz: -1, walk: false };
          if (c < 5.5) return IDLE;
          if (c < 9) return { mx: 0, mz: 1, walk: false };
          return IDLE;
        }
        case 'circle': { const a = demoT * 0.9; return { mx: Math.cos(a), mz: Math.sin(a), walk: false }; }
        case 'zigzag': { const seg = Math.floor(demoT / 1.3) % 2; return { mx: seg ? 0.7 : -0.7, mz: -0.7, walk: false }; }
        case 'strafe': { return { mx: Math.sin(demoT * 1.2) > 0 ? 1 : -1, mz: 0, walk: false }; }
        case 'walkjog': {
          const c = demoT % 8;
          if (c < 0.6) return IDLE;
          return { mx: 0, mz: -1, walk: Math.floor(demoT / 2) % 2 === 0 };
        }
        case 'wander': {
          if (demoT > wanderNext) { wanderNext = demoT + rand(1.2, 3.0); wanderAngle = Math.random() * Math.PI * 2; }
          // brief pauses so REGROUP→FOLLOW resume happens often
          if ((demoT % 5) < 0.8) return IDLE;
          return { mx: Math.sin(wanderAngle), mz: Math.cos(wanderAngle), walk: false };
        }
        default: return IDLE;
      }
    };

    const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
    const dist2 = (ax: number, az: number, bx: number, bz: number) => Math.hypot(ax - bx, az - bz);

    const clock = new THREE.Clock();
    let raf = 0;
    let readoutThrottle = 0;

    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      simTime += dt;
      const P = paramsRef.current;

      // ---- player ----
      let mx = 0, mz = 0, walk = keys['shift'];
      if (demoModeRef.current !== 'off') {
        const d = demoDrive(dt); mx = d.mx; mz = d.mz; walk = d.walk;
      } else {
        if (keys['w']) mz -= 1; if (keys['s']) mz += 1;
        if (keys['a']) mx -= 1; if (keys['d']) mx += 1;
      }
      const moving = mx !== 0 || mz !== 0;
      player.prevX = player.x; player.prevZ = player.z;
      if (moving) {
        const len = Math.hypot(mx, mz);
        const spd = walk ? P.playerWalk : P.playerRun;
        player.x += (mx / len) * spd * dt;
        player.z += (mz / len) * spd * dt;
        player.yaw = Math.atan2(mx, mz);
      }
      player.speed = dist2(player.prevX, player.prevZ, player.x, player.z) / dt;
      player.clip = locomotionClip(moving, player.speed, player.clip, P);

      // record trail (state: is the player in a locomotion state this frame)
      trail.push({ x: player.x, z: player.z, yaw: player.yaw, moving, t: simTime });
      while (trail.length > 200) trail.shift();

      // ---- companion FSM ----
      comp.prevX = comp.x; comp.prevZ = comp.z;
      comp.holdTimer = Math.max(comp.holdTimer - dt, 0);
      let moveIntent = false;

      const distToPlayer = dist2(comp.x, comp.z, player.x, player.z);

      if (comp.state === 'FOLLOW') {
        moveIntent = followStep(dt, P);
        // scan for a target
        comp.scanTimer -= dt;
        if (comp.scanTimer <= 0) {
          comp.scanTimer = P.scanInterval;
          const t = pickTarget(P);
          if (t >= 0) { comp.target = t; comp.state = 'ENGAGE'; comp.engageLastDist = Infinity; comp.engageNoProgress = 0; }
        }
      } else if (comp.state === 'ENGAGE') {
        moveIntent = engageStep(dt, P);
      } else if (comp.state === 'ATTACK') {
        moveIntent = attackStep(dt, P);
      } else if (comp.state === 'REGROUP') {
        moveIntent = regroupStep(dt, P);
      }

      // central animation resolve (mirror of _update_locomotion_anim)
      const compSpeed = dist2(comp.prevX, comp.prevZ, comp.x, comp.z) / dt;
      let desired: Clip;
      if (comp.swingElapsed >= 0) desired = 'atk1';
      else desired = locomotionClip(moveIntent, compSpeed, comp.clip, P);
      // apply with walk↔run-only debounce
      if (desired !== comp.clip) {
        const both = (comp.clip === 'walk' || comp.clip === 'run') && (desired === 'walk' || desired === 'run');
        if (!(both && comp.holdTimer > 0)) { comp.clip = desired; comp.holdTimer = P.animHold; }
      }

      // ---- push to visuals ----
      playerGroup.position.set(player.x, 0, player.z);
      playerGroup.rotation.y = player.yaw;
      compGroup.position.set(comp.x, 0, comp.z);
      compGroup.rotation.y = comp.yaw;
      compCapsuleMat.color.set(CLIP_COLOR[comp.clip]);
      // moving targets wander inside the arena, bouncing off the edges
      if (movingRef.current) {
        for (const d of dummies) {
          if (d.hp <= 0) continue;
          d.x += d.vx * 1.6 * dt; d.z += d.vz * 1.6 * dt;
          if (d.x < -DUMMY_AREA || d.x > DUMMY_AREA) { d.vx *= -1; d.x = clamp(d.x, -DUMMY_AREA, DUMMY_AREA); }
          if (d.z < -DUMMY_AREA || d.z > DUMMY_AREA) { d.vz *= -1; d.z = clamp(d.z, -DUMMY_AREA, DUMMY_AREA); }
          d.mesh.position.set(d.x, 0.8, d.z);
        }
      }
      // auto-respawn a fresh random wave once the field is cleared
      if (autoRespawnRef.current && dummies.length && dummies.every((d) => d.hp <= 0)) {
        respawnDelay -= dt;
        if (respawnDelay <= 0) { spawnDummies(targetCountRef.current, true); respawnDelay = 1.5; }
      } else respawnDelay = 1.5;
      for (const d of dummies) { d.mesh.visible = d.hp > 0; }

      playRig(playerRig, player.clip, P);
      playRig(compRig, comp.clip, P);
      for (const m of mixers) m.update(dt);

      // camera softly follows the player
      controls.target.lerp(new THREE.Vector3(player.x, 1, player.z), 0.1);
      controls.update();
      renderer.render(scene, camera);

      // graph history
      hist.push({ speed: compSpeed, clip: comp.clip });
      while (hist.length > HIST_LEN) hist.shift();
      drawGraph(P);

      readoutThrottle += dt;
      if (readoutThrottle > 0.1) {
        readoutThrottle = 0;
        setReadout({ state: comp.state, clip: comp.clip, compSpeed, playerSpeed: player.speed, dist: distToPlayer, hits: comp.hits });
      }
    };

    // --- FSM steps (ports of companion_npc.gd) ---
    function followStep(dt: number, P: Params): boolean {
      const d = dist2(comp.x, comp.z, player.x, player.z);
      if (d > TELEPORT_DISTANCE) {
        comp.x = player.x - Math.sin(player.yaw) * 3; comp.z = player.z - Math.cos(player.yaw) * 3;
        trail.length = 0; return false;
      }
      const targetT = simTime - P.trailDelay;
      let a: TrailEntry | null = null, b: TrailEntry | null = null;
      for (let i = trail.length - 1; i > 0; i--) {
        if (trail[i - 1].t <= targetT && trail[i].t >= targetT) { a = trail[i - 1]; b = trail[i]; break; }
      }
      if (!a || !b) return false;
      const span = b.t - a.t;
      const tt = span > 0.001 ? clamp((targetT - a.t) / span, 0, 1) : 0;
      let ix = a.x + (b.x - a.x) * tt;
      let iz = a.z + (b.z - a.z) * tt;
      const isMoving = a.moving;
      if (isMoving) {
        // personal-space clamp
        let tox = player.x - ix, toz = player.z - iz;
        const tl = Math.hypot(tox, toz);
        if (tl < P.personalSpace) {
          const awx = tl > 0.01 ? -tox / tl : -Math.sin(player.yaw);
          const awz = tl > 0.01 ? -toz / tl : -Math.cos(player.yaw);
          ix = player.x + awx * P.personalSpace; iz = player.z + awz * P.personalSpace;
        }
        if (!comp.wasMoving) { comp.frozenX = comp.x; comp.frozenZ = comp.z; comp.resumeBlend = 0; }
        if (comp.resumeBlend < 1) {
          comp.resumeBlend = Math.min(comp.resumeBlend + P.resumeBlend * dt, 1);
          ix = comp.frozenX + (ix - comp.frozenX) * comp.resumeBlend;
          iz = comp.frozenZ + (iz - comp.frozenZ) * comp.resumeBlend;
        }
        comp.x = ix; comp.z = iz;
        comp.yaw = a.yaw;
        comp.wasMoving = true;
        return true;
      } else {
        comp.wasMoving = false;
        return false;
      }
    }

    function combatStep(tx: number, tz: number, speed: number, dt: number) {
      let dx = tx - comp.x, dz = tz - comp.z;
      const l = Math.hypot(dx, dz);
      if (l < 0.01) return;
      dx /= l; dz /= l;
      comp.x += dx * speed * dt; comp.z += dz * speed * dt;
      comp.yaw = Math.atan2(dx, dz);
    }

    function targetValid(P: Params): boolean {
      if (comp.target < 0) return false;
      const d = dummies[comp.target];
      if (!d || d.hp <= 0) return false;
      return dist2(d.x, d.z, player.x, player.z) <= P.leash;
    }

    function pickTarget(P: Params): number {
      let best = -1, bestD = Infinity;
      for (let i = 0; i < dummies.length; i++) {
        const d = dummies[i];
        if (d.hp <= 0) continue;
        if (dist2(d.x, d.z, player.x, player.z) > P.leash) continue;
        const cd = dist2(d.x, d.z, comp.x, comp.z);
        if (cd < bestD) { bestD = cd; best = i; }
      }
      return best;
    }

    function engageStep(dt: number, P: Params): boolean {
      if (!targetValid(P)) { enterRegroup(); return false; }
      const d = dummies[comp.target];
      const dd = dist2(comp.x, comp.z, d.x, d.z);
      if (dd <= P.engageReachFrac * HIT_H_DIST + d.radius) { startSwing(); return false; }
      if (dd >= comp.engageLastDist - 0.05) { comp.engageNoProgress += dt; if (comp.engageNoProgress >= 8) { enterRegroup(); return false; } }
      else comp.engageNoProgress = 0;
      comp.engageLastDist = dd;
      combatStep(d.x, d.z, P.followSpeed, dt);
      return true;
    }

    function startSwing() {
      comp.state = 'ATTACK'; comp.swingElapsed = 0; comp.swingHit = false;
      const d = dummies[comp.target];
      if (d) comp.yaw = Math.atan2(d.x - comp.x, d.z - comp.z);
    }

    function attackStep(dt: number, P: Params): boolean {
      if (comp.swingElapsed >= 0) {
        const prev = comp.swingElapsed;
        comp.swingElapsed += dt;
        if (!comp.swingHit && prev < DAMAGING_FRAC * SWING_TIME && comp.swingElapsed >= DAMAGING_FRAC * SWING_TIME) {
          comp.swingHit = true;
          const d = dummies[comp.target];
          if (d) { d.hp = Math.max(0, d.hp - 30); comp.hits++; (d.mesh.material as THREE.MeshStandardMaterial).color.set(0xfca5a5); setTimeout(() => (d.mesh.material as THREE.MeshStandardMaterial)?.color.set(0xef4444), 90); }
        }
        if (comp.swingElapsed >= SWING_TIME) { comp.swingElapsed = -1; comp.cooldown = P.attackCooldown; }
        return false;
      }
      comp.cooldown -= dt;
      if (comp.cooldown > 0) return false;
      if (!targetValid(P)) { enterRegroup(); return false; }
      const d = dummies[comp.target];
      if (dist2(comp.x, comp.z, d.x, d.z) <= P.engageReachFrac * HIT_H_DIST + d.radius) startSwing();
      else comp.state = 'ENGAGE';
      return false;
    }

    function enterRegroup() { comp.state = 'REGROUP'; comp.target = -1; comp.swingElapsed = -1; }

    function regroupStep(dt: number, P: Params): boolean {
      const d = dist2(comp.x, comp.z, player.x, player.z);
      if (d <= P.startDistance) { comp.state = 'FOLLOW'; comp.wasMoving = false; return false; }
      combatStep(player.x, player.z, P.catchupSpeed, dt);
      return true;
    }

    // --- speed graph ---
    function drawGraph(P: Params) {
      const cv = graphRef.current; if (!cv) return;
      const ctx = cv.getContext('2d'); if (!ctx) return;
      const W = cv.width, H = cv.height;
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = '#0d1117'; ctx.fillRect(0, 0, W, H);
      const maxSpeed = Math.max(P.playerRun * 1.4, P.runEnter * 1.4, 8);
      const y = (s: number) => H - (s / maxSpeed) * H;
      // threshold lines
      const line = (s: number, color: string, label: string) => {
        ctx.strokeStyle = color; ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.moveTo(0, y(s)); ctx.lineTo(W, y(s)); ctx.stroke(); ctx.setLineDash([]);
        ctx.fillStyle = color; ctx.font = '9px monospace'; ctx.fillText(label, 2, y(s) - 2);
      };
      line(P.idleEps, '#6b7280', 'idle');
      line(P.runExit, '#38bdf8', 'runExit');
      if (P.runEnter !== P.runExit) line(P.runEnter, '#34d399', 'runEnter');
      // bars
      const bw = W / HIST_LEN;
      for (let i = 0; i < hist.length; i++) {
        const hgt = hist[i];
        ctx.fillStyle = CLIP_COLOR[hgt.clip];
        const yy = y(hgt.speed);
        ctx.fillRect(i * bw, yy, Math.max(1, bw), H - yy);
      }
    }

    // Expose randomize/reset to the sidebar buttons (the scene lives in this
    // closure). reset re-centres player + companion and restores the fixed
    // layout; randomize scatters a fresh wave.
    apiRef.current = {
      randomize: () => spawnDummies(targetCountRef.current, true),
      reset: () => {
        player.x = 0; player.z = 4; player.yaw = Math.PI; player.clip = 'wait';
        comp.x = 1.6; comp.z = 5.5; comp.yaw = Math.PI; comp.state = 'FOLLOW';
        comp.target = -1; comp.swingElapsed = -1; comp.wasMoving = false; comp.hits = 0;
        trail.length = 0; hist.length = 0;
        spawnDummies(targetCountRef.current, false);
      },
    };

    animate();

    const onResize = () => {
      if (!mountRef.current) return;
      const nw = mountRef.current.clientWidth, nh = mountRef.current.clientHeight;
      renderer.setSize(nw, nh); camera.aspect = nw / nh; camera.updateProjectionMatrix();
    };
    window.addEventListener('resize', onResize);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('keydown', kd);
      window.removeEventListener('keyup', ku);
      window.removeEventListener('resize', onResize);
      controls.dispose();
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const set = (k: keyof Params) => (e: React.ChangeEvent<HTMLInputElement>) => setParams((p) => ({ ...p, [k]: parseFloat(e.target.value) }));

  const gd = [
    '# Companion follow/locomotion tuning — from web #/companion-room',
    '# Paste into scripts/3d/elements/companion_npc.gd / companion_combat.gd',
    `const TRAIL_DELAY: float = ${params.trailDelay.toFixed(2)}`,
    `# personal-space cap (min XZ gap kept from player): ${params.personalSpace.toFixed(2)}`,
    `const START_DISTANCE: float = ${params.startDistance.toFixed(2)}`,
    `const FOLLOW_SPEED: float = ${params.followSpeed.toFixed(1)}`,
    `const CATCHUP_SPEED: float = ${params.catchupSpeed.toFixed(1)}`,
    `const RESUME_BLEND_SPEED: float = ${params.resumeBlend.toFixed(2)}`,
    `const ANIM_HOLD_TIME: float = ${params.animHold.toFixed(2)}`,
    '# CompanionCombat locomotion thresholds:',
    `const IDLE_EPS: float = ${params.idleEps.toFixed(2)}`,
    `const RUN_ENTER: float = ${params.runEnter.toFixed(2)}  # enter run above this`,
    `const RUN_EXIT: float = ${params.runExit.toFixed(2)}  # drop to walk below this (hysteresis)`,
  ].join('\n');

  const btnStyle: React.CSSProperties = { padding: '5px 9px', background: '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, cursor: 'pointer', fontSize: 12 };

  const sliders: [keyof Params, string, number, number, number][] = [
    ['playerRun', 'player run', 3, 10, 0.5],
    ['playerWalk', 'player walk', 1, 5, 0.5],
    ['trailDelay', 'trail delay (s)', 0.1, 1.5, 0.05],
    ['personalSpace', 'personal space', 0.5, 4, 0.1],
    ['startDistance', 'regroup→follow dist', 1, 6, 0.5],
    ['followSpeed', 'engage speed', 3, 12, 0.5],
    ['catchupSpeed', 'regroup speed', 3, 14, 0.5],
    ['idleEps', 'idle eps', 0.05, 1, 0.05],
    ['runEnter', 'run enter', 1, 8, 0.25],
    ['runExit', 'run exit', 1, 8, 0.25],
    ['animHold', 'anim hold (s)', 0, 0.6, 0.05],
    ['resumeBlend', 'resume blend', 0.5, 10, 0.5],
  ];

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0e1a', color: '#e6edf3' }}>
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={mountRef} style={{ width: '100%', height: '100%' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, background: 'rgba(0,0,0,0.65)', padding: '6px 10px', borderRadius: 4, fontSize: 12 }}>{status}</div>
        <div style={{ position: 'absolute', top: 8, right: 8, background: 'rgba(0,0,0,0.72)', padding: '8px 10px', borderRadius: 4, fontSize: 13, fontFamily: 'monospace', lineHeight: 1.5 }}>
          <div>state <b style={{ color: '#93c5fd' }}>{readout.state}</b> · clip <b style={{ color: CLIP_COLOR[readout.clip] }}>{readout.clip}</b></div>
          <div>comp speed <b>{readout.compSpeed.toFixed(2)}</b> · player <b>{readout.playerSpeed.toFixed(2)}</b></div>
          <div>dist to player <b>{readout.dist.toFixed(2)}</b> · hits <b>{readout.hits}</b></div>
        </div>
        <canvas ref={graphRef} width={520} height={120} style={{ position: 'absolute', bottom: 8, left: 8, border: '1px solid #30363d', borderRadius: 4, background: '#0d1117' }} />
        <div style={{ position: 'absolute', bottom: 8, right: 8, display: 'flex', gap: 6, alignItems: 'center', background: 'rgba(0,0,0,0.6)', padding: '6px 8px', borderRadius: 4 }}>
          <label style={{ fontSize: 11, color: '#8b949e', display: 'flex', alignItems: 'center', gap: 5 }}>drive
            <select value={demoMode} onChange={(e) => setDemoMode(e.target.value as DemoMode)} style={{ background: '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, fontSize: 12, padding: '3px 4px' }}>
              {DEMO_MODES.map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
            </select>
          </label>
          <button onClick={() => apiRef.current?.randomize()} style={btnStyle}>🎲 targets (R)</button>
          <button onClick={() => apiRef.current?.reset()} style={btnStyle}>⟲ reset</button>
        </div>
      </div>
      <aside style={{ width: 300, flexShrink: 0, padding: 16, background: '#161b22', borderLeft: '1px solid #30363d', overflowY: 'auto' }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16 }}>Companion room</h2>
        <p style={{ margin: '0 0 12px', fontSize: 12, color: '#8b949e' }}>
          Tune the FOLLOW/ENGAGE/REGROUP locomotion. Graph = companion measured speed, coloured by the clip it chose — a jagged walk/run band is the flicker. Widen the <b>run enter/exit</b> gap (hysteresis) or raise <b>trail delay</b> to steady it.
        </p>
        <div style={{ marginBottom: 14, padding: 10, background: '#0d1117', borderRadius: 4 }}>
          <h3 style={{ fontSize: 13, margin: '0 0 8px', color: '#8b949e' }}>Targets &amp; movement</h3>
          <label style={{ display: 'block', fontSize: 12, marginBottom: 8 }}>
            <span style={{ display: 'flex', justifyContent: 'space-between', color: '#8b949e' }}><span>count</span><b style={{ color: '#e6edf3' }}>{targetCount}</b></span>
            <input type="range" min={0} max={6} step={1} value={targetCount} onChange={(e) => setTargetCount(parseInt(e.target.value))} style={{ width: '100%' }} />
          </label>
          <label style={{ display: 'flex', gap: 6, fontSize: 12, marginBottom: 6, cursor: 'pointer', color: '#c9d1d9' }}>
            <input type="checkbox" checked={movingTargets} onChange={(e) => setMovingTargets(e.target.checked)} /> moving targets (wander)
          </label>
          <label style={{ display: 'flex', gap: 6, fontSize: 12, marginBottom: 8, cursor: 'pointer', color: '#c9d1d9' }}>
            <input type="checkbox" checked={autoRespawn} onChange={(e) => setAutoRespawn(e.target.checked)} /> auto-respawn when cleared
          </label>
          <div style={{ display: 'flex', gap: 6 }}>
            <button onClick={() => apiRef.current?.randomize()} style={{ ...btnStyle, flex: 1 }}>🎲 randomize</button>
            <button onClick={() => apiRef.current?.reset()} style={{ ...btnStyle, flex: 1 }}>⟲ reset</button>
          </div>
          <p style={{ margin: '8px 0 0', fontSize: 11, color: '#6e7681' }}>Drive via the dropdown on the viewport, or WASD (T = toggle path, R = randomize).</p>
        </div>
        {sliders.map(([k, label, min, max, step]) => (
          <label key={k} style={{ display: 'block', fontSize: 12, marginBottom: 9 }}>
            <span style={{ display: 'flex', justifyContent: 'space-between', color: '#8b949e' }}>
              <span>{label}</span><b style={{ color: '#e6edf3' }}>{(params[k] as number).toFixed(2)}</b>
            </span>
            <input type="range" min={min} max={max} step={step} value={params[k] as number} onChange={set(k)} style={{ width: '100%' }} />
          </label>
        ))}
        <button onClick={() => setParams({ ...DEFAULTS })} style={{ width: '100%', padding: '6px', marginBottom: 8, background: '#21262d', color: '#e6edf3', border: '1px solid #30363d', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}>reset to Godot defaults</button>
        <h3 style={{ fontSize: 13, margin: '10px 0 6px', color: '#8b949e' }}>GDScript</h3>
        <pre style={{ background: '#0d1117', padding: 8, borderRadius: 4, fontSize: 10, overflow: 'auto', maxHeight: 200 }}>{gd}</pre>
        <button onClick={() => navigator.clipboard?.writeText(gd)} style={{ width: '100%', padding: '6px', background: '#238636', color: '#fff', border: 'none', borderRadius: 4, fontSize: 12, cursor: 'pointer' }}>copy GDScript</button>
      </aside>
    </div>
  );
}
