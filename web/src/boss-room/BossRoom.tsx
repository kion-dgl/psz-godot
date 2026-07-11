/**
 * Boss room (#493) — observe a boss inside its own arena.
 *
 * Unlike #/enemy-room (flat sandbox + behavior sim), boss behavior is bound
 * to arena geometry — fly passes, surfacing spots, fixed emplacements — so
 * this room loads the boss rig into the real stage (visual `_m.glb` + baked
 * `-floor.glb` collider, the same world frame Godot uses; see
 * city-walk-mock). There is NO behavior sim yet: this is the observation
 * instrument for taking phase/attack notes, which will land in
 * data/boss_arenas.json as arena-anchored tables.
 *
 * Controls: WASD move (camera-relative) · drag orbit · wheel zoom ·
 * Space jump · click floor to drop an anchor / move the boss.
 */
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { Link, useParams } from 'react-router-dom';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { assetUrl } from '../utils/assets';
import {
  arenaFloorUrl,
  arenaModelUrl,
  arenaSkyboxUrl,
  loadBossConfig,
  loadRoster,
  resolveBoss,
  resolveClipToken,
  segmentFamilies,
  type BossArenaConfig,
  type BossAttackDef,
  type RosterEntry,
  type SegmentFamily,
} from './types';
import { damageBoss, makeBossSim, stepBoss, type BossEvent, type BossSim, type BossStateName } from './sim';

const PLAYER_MAX_HP = 100;
const SWING_RANGE = 4.5;
const SWING_DAMAGE = 15;
const SWING_COOLDOWN = 0.5;

const STORAGE_KEY = 'psz-boss-room:v1';

// Player capsule — same dimensions/feel as city-walk-mock so distances read
// in the frame we already trust.
const RADIUS = 0.4;
const HEIGHT = 1.8;
const SPEED = 10.0;
const GRAVITY = 20.0;
const JUMP = 8.0;
const STEP_UP = 1.0;
const FALL_LIMIT = 40.0;

interface Marker {
  name: string;
  pos: [number, number, number];
}

interface Overrides {
  arena?: string;
  model_scale?: number;
}

function loadStore(): Record<string, Overrides> {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
  } catch {
    return {};
  }
}

function saveStore(store: Record<string, Overrides>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
}

/** Imperative bridge into the three.js scene (UI buttons → scene). */
interface SceneApi {
  playClip(name: string, loop: boolean): void;
  playChain(family: SegmentFamily, lpLoops: number): void;
  /** Behavior-draft attack playback: clip-token sequence, `lp` tokens loop. */
  playTokens(tokens: string[], lpLoops: number): void;
  /** Toggle the behavior sim (spec /states/bosses) — drives the boss against the player. */
  setSimulate(on: boolean): void;
  stopClips(): void;
  setSpeed(v: number): void;
  setPaused(p: boolean): void;
  scrub(t: number): void;
  setFacePlayer(v: boolean): void;
  setShowFloor(v: boolean): void;
  setBossScale(v: number): void;
  clearMarkers(): void;
}

export default function BossRoom() {
  const { bossId = '' } = useParams();
  const mountRef = useRef<HTMLDivElement>(null);
  const apiRef = useRef<SceneApi | null>(null);

  const [config, setConfig] = useState<BossArenaConfig | null>(null);
  const [roster, setRoster] = useState<Map<string, RosterEntry>>(new Map());
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('loading…');
  const [clips, setClips] = useState<string[]>([]);
  const [activeClip, setActiveClip] = useState<string | null>(null);
  const [clipDuration, setClipDuration] = useState(0);
  const [clipTime, setClipTime] = useState(0);
  const [loop, setLoop] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [paused, setPaused] = useState(false);
  const [lpLoops, setLpLoops] = useState(2);
  const [facePlayer, setFacePlayer] = useState(true);
  const [showFloor, setShowFloor] = useState(false);
  const [clickMode, setClickMode] = useState<'anchor' | 'boss' | null>(null);
  const clickModeRef = useRef(clickMode);
  const [markers, setMarkers] = useState<Marker[]>([]);
  const [readout, setReadout] = useState({ player: [0, 0, 0], boss: [0, 0, 0], dist: 0 });
  const [overrides, setOverrides] = useState<Record<string, Overrides>>(loadStore);
  const [simOn, setSimOn] = useState(false);
  const [simHud, setSimHud] = useState<{ bossHp: number; maxHp: number; playerHp: number; state: BossStateName } | null>(null);

  useEffect(() => {
    clickModeRef.current = clickMode;
  }, [clickMode]);

  useEffect(() => {
    loadBossConfig().then(setConfig, (e) => setError(String(e)));
    loadRoster().then(setRoster, (e) => setError(String(e)));
  }, []);

  const boss = config?.bosses[bossId];
  const ov = overrides[bossId] ?? {};
  const arenaId = ov.arena ?? boss?.arena ?? '';
  const arena = config?.arenas[arenaId];
  const modelScale = ov.model_scale ?? boss?.model_scale ?? 1;
  const families = useMemo(() => segmentFamilies(clips), [clips]);

  const setOverride = (patch: Overrides) => {
    const next = { ...overrides, [bossId]: { ...overrides[bossId], ...patch } };
    setOverrides(next);
    saveStore(next);
  };

  // Round-trip export: the whole config with this boss's clicked markers
  // merged into its authored anchors — paste over data/boss_arenas.json.
  // Markers only merge in the default arena (anchors ride that frame).
  const copyConfig = () => {
    if (!config || !boss) return;
    const merged =
      arenaId === boss.arena
        ? [...(boss.anchors ?? []), ...markers.map((m) => ({ name: m.name, pos: m.pos }))]
        : (boss.anchors ?? []);
    const cfg: BossArenaConfig = {
      ...config,
      bosses: { ...config.bosses, [bossId]: { ...boss, anchors: merged } },
    };
    navigator.clipboard?.writeText(JSON.stringify(cfg, null, 2) + '\n');
  };

  const attackMeta = (a: BossAttackDef) => {
    const range = ` · ${a.min_range ?? 0}–${a.max_range ?? '∞'}m`;
    const phases = a.phases ? ` · ${a.phases.join('/')}` : '';
    return `${a.kind ?? 'melee_arc'}${range}${phases}`;
  };

  // ——— scene ———
  useEffect(() => {
    const el = mountRef.current;
    if (!el || !config || !boss || !arena) return;
    const w = el.clientWidth;
    const h = el.clientHeight;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0e1a);
    const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 4000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(window.devicePixelRatio);
    el.appendChild(renderer.domElement);
    scene.add(new THREE.AmbientLight(0xffffff, 1.1));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(40, 80, 40);
    scene.add(dir);

    // Player capsule (feet-tracked, like city-walk-mock).
    const capsule = new THREE.Mesh(
      new THREE.CapsuleGeometry(RADIUS, HEIGHT - 2 * RADIUS, 6, 12),
      new THREE.MeshStandardMaterial({ color: 0x4ade80, transparent: true, opacity: 0.85 }),
    );
    scene.add(capsule);
    const feet = new THREE.Vector3(0, 50, 20);
    const spawn = feet.clone();
    let velY = 0;

    // Camera orbit state (drag to orbit around the player, wheel to zoom).
    let camYaw = Math.PI;
    let camPitch = 0.45;
    let camDist = 14;

    let floorMesh: THREE.Object3D | null = null;
    let floorMinY = 0; // lowest point of the floor collider (fall-guard floor)
    let arenaMesh: THREE.Object3D | null = null;
    const raycaster = new THREE.Raycaster();
    const DOWN = new THREE.Vector3(0, -1, 0);

    const bossGroup = new THREE.Group();
    scene.add(bossGroup);
    let mixer: THREE.AnimationMixer | null = null;
    let animations: THREE.AnimationClip[] = [];
    let currentAction: THREE.AnimationAction | null = null;
    let chain: { queue: THREE.AnimationClip[]; loops: number[] } | null = null;
    let animPaused = false;
    let facePlayerLocal = true;
    const bossPos = new THREE.Vector3();

    // Behavior sim (spec /states/bosses) — owns the boss transform while on.
    const entry = resolveBoss(boss);
    let sim: BossSim | null = null;
    let playerHp = PLAYER_MAX_HP;
    let swingCd = 0;
    const clipDur = (token: string): number | null => {
      const name = resolveClipToken(animations.map((a) => a.name), token);
      const clip = name ? animations.find((a) => a.name === name) : undefined;
      return clip ? clip.duration : null;
    };

    const markerGroup = new THREE.Group();
    scene.add(markerGroup);
    let markerSeq = 0;

    // Marker mesh (post + ground ring) — yellow for ad-hoc clicks, cyan for
    // config-authored anchors from boss_arenas.json.
    function buildMarker(color: number): THREE.Group {
      const grp = new THREE.Group();
      const post = new THREE.Mesh(
        new THREE.CylinderGeometry(0.15, 0.15, 4, 8),
        new THREE.MeshBasicMaterial({ color }),
      );
      post.position.y = 2;
      grp.add(post);
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.6, 1.0, 24),
        new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide }),
      );
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.05;
      grp.add(ring);
      return grp;
    }

    // Authored anchors are positions in the boss's DEFAULT arena frame —
    // meaningless in an override arena, so only render them at home.
    if (boss.anchors?.length && arenaId === boss.arena) {
      for (const a of boss.anchors) {
        const grp = buildMarker(0x22d3ee);
        grp.position.set(a.pos[0], a.pos[1], a.pos[2]);
        scene.add(grp);
      }
    }

    const loader = new GLTFLoader();
    let disposed = false;
    // arena + floor + boss, plus the optional skybox
    let pending = arenaSkyboxUrl(arenaId, arena) ? 4 : 3;
    const oneLoaded = () => {
      pending--;
      if (pending <= 0) setStatus('WASD move · drag orbit · wheel zoom · Space jump');
    };

    // Arena visual — committed stage GLBs are already skin-stripped static
    // meshes in the Godot world frame (see city-walk-mock), so no offset.
    loader.load(
      arenaModelUrl(arenaId, arena),
      (g) => {
        if (disposed) return;
        scene.add(g.scene);
        arenaMesh = g.scene;
        oneLoaded();
      },
      undefined,
      () => setStatus(`arena model failed: ${arenaId}`),
    );

    // Floor collider — walkable surface; hidden by default (toggle shows it).
    loader.load(
      arenaFloorUrl(arenaId, arena),
      (g) => {
        if (disposed) return;
        g.scene.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) {
            (o as THREE.Mesh).material = new THREE.MeshStandardMaterial({
              color: 0x22e06a,
              transparent: true,
              opacity: 0.3,
              side: THREE.DoubleSide,
              depthWrite: false,
            });
          }
        });
        g.scene.visible = false;
        scene.add(g.scene);
        floorMesh = g.scene;
        // Spawn the player near the floor center, boss a bit ahead. The
        // offset is probed against the actual floor — boss-arena colliders
        // vary wildly in extent (the shrine's is only 20×20, so a blind
        // center+12 lands past the edge and the player falls forever).
        const box = new THREE.Box3().setFromObject(g.scene);
        floorMinY = box.min.y;
        const c = box.getCenter(new THREE.Vector3());
        const back = Math.min(12, Math.max(2, (box.max.z - box.min.z) * 0.3));
        const side = Math.min(12, Math.max(2, (box.max.x - box.min.x) * 0.3));
        const candidates = [
          new THREE.Vector3(c.x, box.max.y + 5, c.z + back),
          new THREE.Vector3(c.x, box.max.y + 5, c.z - back),
          new THREE.Vector3(c.x + side, box.max.y + 5, c.z),
          new THREE.Vector3(c.x - side, box.max.y + 5, c.z),
          new THREE.Vector3(c.x, box.max.y + 5, c.z),
        ];
        spawn.copy(candidates.find((p) => dropToFloor(p) !== null) ?? candidates[candidates.length - 1]);
        feet.copy(spawn);
        bossPos.set(c.x, box.max.y + 5, c.z);
        settleBoss();
        oneLoaded();
      },
      undefined,
      () => setStatus(`arena floor failed: ${arenaId}`),
    );

    const skyUrl = arenaSkyboxUrl(arenaId, arena);
    if (skyUrl) {
      loader.load(skyUrl, (g) => {
        if (disposed) return;
        scene.add(g.scene);
        oneLoaded();
      }, undefined, oneLoaded); // skybox is decorative — missing is fine
    }

    // Boss rig — clips come from the loaded GLB, never assumed.
    loader.load(
      assetUrl(`assets/enemies/${boss.model_id}/${boss.model_id}.glb`),
      (g) => {
        if (disposed) return;
        bossGroup.add(g.scene);
        mixer = new THREE.AnimationMixer(g.scene);
        animations = g.animations;
        setClips(g.animations.map((a) => a.name).sort());
        mixer.addEventListener('finished', onActionFinished);
        settleBoss();
        oneLoaded();
      },
      undefined,
      () => setStatus(`boss model failed: ${boss.model_id}`),
    );

    function dropToFloor(p: THREE.Vector3): number | null {
      if (!floorMesh) return null;
      raycaster.set(new THREE.Vector3(p.x, p.y + STEP_UP + 100, p.z), DOWN);
      const hits = raycaster.intersectObject(floorMesh, true);
      return hits.length ? hits[0].point.y : null;
    }

    function settleBoss() {
      const y = dropToFloor(bossPos);
      if (y !== null) bossPos.y = y;
      bossGroup.position.copy(bossPos);
    }

    // ——— clip playback ———
    function stopClips() {
      mixer?.stopAllAction();
      currentAction = null;
      chain = null;
      setActiveClip(null);
      setClipDuration(0);
    }

    function startAction(clip: THREE.AnimationClip, loopMode: THREE.AnimationActionLoopStyles, reps: number) {
      if (!mixer) return null;
      mixer.stopAllAction();
      const action = mixer.clipAction(clip);
      action.reset();
      action.setLoop(loopMode, reps);
      action.clampWhenFinished = true;
      action.play();
      currentAction = action;
      setActiveClip(clip.name);
      setClipDuration(clip.duration);
      return action;
    }

    function playClip(name: string, loopClip: boolean) {
      const clip = animations.find((a) => a.name === name);
      if (!clip) return;
      chain = null;
      startAction(clip, loopClip ? THREE.LoopRepeat : THREE.LoopOnce, loopClip ? Infinity : 1);
    }

    function playChain(family: SegmentFamily, loops: number) {
      const seq = [family.st, family.lp, family.ed]
        .map((n) => n && animations.find((a) => a.name === n))
        .filter(Boolean) as THREE.AnimationClip[];
      if (!seq.length) return;
      const reps = seq.map((c) => (c.name === family.lp ? Math.max(1, loops) : 1));
      chain = { queue: seq.slice(1), loops: reps.slice(1) };
      startAction(seq[0], seq[0].name === family.lp ? THREE.LoopRepeat : THREE.LoopOnce, reps[0]);
    }

    function onActionFinished() {
      if (!chain || !chain.queue.length) {
        chain = null;
        return;
      }
      const next = chain.queue.shift()!;
      const reps = chain.loops.shift()!;
      startAction(next, reps > 1 ? THREE.LoopRepeat : THREE.LoopOnce, reps);
    }

    // Behavior-draft attack playback: resolve each token per the
    // /mechanics/enemy-attacks order, chain them, loop the `lp` pieces.
    function playTokens(tokens: string[], loops: number) {
      const names = animations.map((a) => a.name);
      const seq: THREE.AnimationClip[] = [];
      const reps: number[] = [];
      const missing: string[] = [];
      for (const t of tokens) {
        const name = resolveClipToken(names, t);
        const clip = name ? animations.find((a) => a.name === name) : undefined;
        if (!clip) {
          missing.push(t);
          continue;
        }
        seq.push(clip);
        reps.push(t.endsWith('lp') ? Math.max(1, loops) : 1);
      }
      if (missing.length) setStatus(`unresolved clip token(s): ${missing.join(', ')}`);
      if (!seq.length) return;
      chain = { queue: seq.slice(1), loops: reps.slice(1) };
      startAction(seq[0], reps[0] > 1 ? THREE.LoopRepeat : THREE.LoopOnce, reps[0]);
    }

    // Sim events → the existing playback machinery + player HP.
    function handleSimEvents(events: BossEvent[]) {
      for (const ev of events) {
        if (ev.type === 'anim') {
          if (ev.loop && ev.tokens.length === 1) {
            const name = resolveClipToken(animations.map((a) => a.name), ev.tokens[0]);
            if (name) playClip(name, true);
          } else {
            playTokens(ev.tokens, 2);
          }
        } else if (ev.type === 'player-hit') {
          playerHp = Math.max(0, playerHp - ev.damage);
          if (playerHp <= 0) {
            feet.copy(spawn); // downed → respawn with full HP, sim keeps running
            velY = 0;
            playerHp = PLAYER_MAX_HP;
          }
        }
      }
    }

    function setSimulate(on: boolean) {
      if (on && entry.attacks.length > 0) {
        sim = makeBossSim(entry, { x: bossPos.x, z: bossPos.z }, bossGroup.rotation.y);
        playerHp = PLAYER_MAX_HP;
        swingCd = 0;
      } else {
        sim = null;
        mixer?.stopAllAction();
        currentAction = null;
        chain = null;
        setActiveClip(null);
        setSimHud(null);
        settleBoss();
      }
    }

    apiRef.current = {
      playClip,
      playChain,
      playTokens,
      setSimulate,
      stopClips,
      setSpeed: (v) => {
        if (mixer) mixer.timeScale = v;
      },
      setPaused: (p) => {
        animPaused = p;
      },
      scrub: (t) => {
        if (!currentAction || !mixer) return;
        currentAction.time = t;
        mixer.update(0);
      },
      setFacePlayer: (v) => {
        facePlayerLocal = v;
      },
      setShowFloor: (v) => {
        if (floorMesh) floorMesh.visible = v;
      },
      setBossScale: (v) => {
        bossGroup.scale.setScalar(v);
      },
      clearMarkers: () => {
        markerGroup.clear();
        markerSeq = 0;
        setMarkers([]);
      },
    };
    apiRef.current.setBossScale(modelScale);

    // ——— input ———
    const keys: Record<string, boolean> = {};
    const onKey = (e: KeyboardEvent, d: boolean) => {
      if ((e.target as HTMLElement)?.tagName === 'INPUT') return;
      const k = e.key.toLowerCase();
      if (['w', 'a', 's', 'd', 'j', ' '].includes(k)) {
        keys[k] = d;
        if (k === ' ') e.preventDefault();
      }
    };
    const kd = (e: KeyboardEvent) => onKey(e, true);
    const ku = (e: KeyboardEvent) => onKey(e, false);
    window.addEventListener('keydown', kd);
    window.addEventListener('keyup', ku);

    let dragging = false;
    let downX = 0;
    let downY = 0;
    let lastX = 0;
    let lastY = 0;
    const onDown = (ev: PointerEvent) => {
      dragging = true;
      downX = lastX = ev.clientX;
      downY = lastY = ev.clientY;
    };
    const onMove = (ev: PointerEvent) => {
      if (!dragging) return;
      camYaw -= (ev.clientX - lastX) * 0.005;
      camPitch = Math.min(1.4, Math.max(0.05, camPitch + (ev.clientY - lastY) * 0.004));
      lastX = ev.clientX;
      lastY = ev.clientY;
    };
    const onUp = () => {
      dragging = false;
    };
    const onWheel = (ev: WheelEvent) => {
      camDist = Math.min(80, Math.max(4, camDist + ev.deltaY * 0.02));
      ev.preventDefault();
    };
    renderer.domElement.addEventListener('pointerdown', onDown);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    renderer.domElement.addEventListener('wheel', onWheel, { passive: false });

    const onClick = (ev: MouseEvent) => {
      const mode = clickModeRef.current;
      const target = floorMesh ?? arenaMesh;
      if (!mode || !target) return;
      if (Math.abs(ev.clientX - downX) > 4 || Math.abs(ev.clientY - downY) > 4) return; // drag
      const rect = renderer.domElement.getBoundingClientRect();
      const m = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      raycaster.setFromCamera(m, camera);
      const wasVisible = target.visible;
      target.visible = true; // raycast needs the floor even when hidden
      const hits = raycaster.intersectObject(target, true);
      target.visible = wasVisible;
      if (!hits.length) return;
      const p = hits[0].point;
      if (mode === 'boss') {
        bossPos.set(p.x, p.y, p.z);
        bossGroup.position.copy(bossPos);
      } else {
        markerSeq++;
        const name = `anchor_${markerSeq}`;
        const grp = buildMarker(0xfacc15);
        grp.position.copy(p);
        markerGroup.add(grp);
        setMarkers((ms) => [...ms, { name, pos: [+p.x.toFixed(2), +p.y.toFixed(2), +p.z.toFixed(2)] }]);
      }
      setClickMode(null);
    };
    renderer.domElement.addEventListener('click', onClick);

    // ——— frame loop ———
    const clock = new THREE.Clock();
    let raf = 0;
    let readoutAcc = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);

      // Player movement, camera-relative.
      const fwd = new THREE.Vector3(-Math.sin(camYaw), 0, -Math.cos(camYaw));
      const right = new THREE.Vector3(-fwd.z, 0, fwd.x);
      const move = new THREE.Vector3();
      if (keys['w']) move.add(fwd);
      if (keys['s']) move.sub(fwd);
      if (keys['d']) move.add(right);
      if (keys['a']) move.sub(right);
      if (move.lengthSq() > 0) {
        move.normalize().multiplyScalar(SPEED * dt);
        const nx = feet.x + move.x;
        const nz = feet.z + move.z;
        const y = dropToFloor(new THREE.Vector3(nx, feet.y, nz));
        // Only step where the floor exists and is within step range — walls
        // are wherever the baked floor mesh ends.
        if (y !== null && y - feet.y <= STEP_UP) {
          feet.x = nx;
          feet.z = nz;
        }
      }
      const gy = dropToFloor(feet);
      if (gy !== null && feet.y <= gy + 0.01 && velY <= 0) {
        feet.y = gy;
        velY = 0;
        if (keys[' ']) velY = JUMP;
      } else {
        velY -= GRAVITY * dt;
        feet.y += velY * dt;
        if (gy !== null && feet.y < gy) {
          feet.y = gy;
          velY = 0;
        }
      }
      // Fall guard — must also catch the off-floor case (gy === null, e.g.
      // walked/spawned past the collider's edge), or the fall never ends.
      if (floorMesh && feet.y < Math.min(gy ?? Infinity, floorMinY) - FALL_LIMIT) {
        feet.copy(spawn);
        velY = 0;
      }
      capsule.position.set(feet.x, feet.y + HEIGHT / 2, feet.z);

      // Behavior sim: step the FSM, apply its transform, take the J-swing.
      if (sim) {
        swingCd -= dt;
        if (keys['j'] && swingCd <= 0) {
          swingCd = SWING_COOLDOWN;
          if (Math.hypot(feet.x - sim.pos.x, feet.z - sim.pos.z) <= SWING_RANGE) {
            handleSimEvents(damageBoss(sim, entry, SWING_DAMAGE));
          }
        }
        handleSimEvents(stepBoss(sim, entry, { dt, player: { x: feet.x, z: feet.z }, clipDur, rng: Math.random }));
        const gy2 = dropToFloor(new THREE.Vector3(sim.pos.x, bossPos.y + 2, sim.pos.z));
        bossPos.set(sim.pos.x, (gy2 ?? bossPos.y) + sim.alt, sim.pos.z);
        bossGroup.position.copy(bossPos);
        bossGroup.rotation.y = sim.yaw;
      } else if (facePlayerLocal) {
        const dx = feet.x - bossPos.x;
        const dz = feet.z - bossPos.z;
        if (dx * dx + dz * dz > 1e-6) bossGroup.rotation.y = Math.atan2(dx, dz);
      }

      if (mixer && !animPaused) mixer.update(dt);

      // Follow cam orbiting the player.
      const cx = feet.x + Math.sin(camYaw) * Math.cos(camPitch) * camDist;
      const cz = feet.z + Math.cos(camYaw) * Math.cos(camPitch) * camDist;
      const cy = feet.y + HEIGHT + Math.sin(camPitch) * camDist;
      camera.position.set(cx, cy, cz);
      camera.lookAt(feet.x, feet.y + HEIGHT, feet.z);

      readoutAcc += dt;
      if (readoutAcc > 0.2) {
        readoutAcc = 0;
        if (currentAction) setClipTime(currentAction.time);
        const d = Math.hypot(feet.x - bossPos.x, feet.z - bossPos.z);
        setReadout({
          player: [+feet.x.toFixed(1), +feet.y.toFixed(1), +feet.z.toFixed(1)],
          boss: [+bossPos.x.toFixed(1), +bossPos.y.toFixed(1), +bossPos.z.toFixed(1)],
          dist: +d.toFixed(1),
        });
        if (sim) setSimHud({ bossHp: sim.hp, maxHp: sim.maxHp, playerHp, state: sim.state });
      }

      renderer.render(scene, camera);
    };
    animate();

    if (import.meta.env.DEV) {
      (window as any).__bossRoom = { scene, feet, bossPos, playClip, playChain, get mixer() { return mixer; } };
    }

    const onResize = () => {
      const nw = el.clientWidth;
      const nh = el.clientHeight;
      camera.aspect = nw / nh;
      camera.updateProjectionMatrix();
      renderer.setSize(nw, nh);
    };
    window.addEventListener('resize', onResize);

    return () => {
      disposed = true;
      cancelAnimationFrame(raf);
      mixer?.removeEventListener('finished', onActionFinished);
      window.removeEventListener('keydown', kd);
      window.removeEventListener('keyup', ku);
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('resize', onResize);
      renderer.dispose();
      el.removeChild(renderer.domElement);
      apiRef.current = null;
      setClips([]);
      setActiveClip(null);
      setMarkers([]);
      setSimOn(false);
      setSimHud(null);
      setStatus('loading…');
    };
    // modelScale applies live via apiRef — not a scene-rebuild dependency.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [config, bossId, arenaId]);

  // Live-apply UI state to the scene without rebuilding it.
  useEffect(() => {
    apiRef.current?.setSpeed(speed);
  }, [speed, activeClip]);
  useEffect(() => {
    apiRef.current?.setPaused(paused);
  }, [paused]);
  useEffect(() => {
    apiRef.current?.setFacePlayer(facePlayer);
  }, [facePlayer]);
  useEffect(() => {
    apiRef.current?.setShowFloor(showFloor);
  }, [showFloor]);
  useEffect(() => {
    apiRef.current?.setBossScale(modelScale);
  }, [modelScale]);

  if (error) return <div style={{ padding: 20, color: '#f66' }}>{error}</div>;
  if (config && !boss) {
    return (
      <div style={{ padding: 20, color: '#fff' }}>
        Unknown boss "{bossId}". <Link to="/boss-room" style={{ color: '#88aaff' }}>Back to index</Link>
      </div>
    );
  }

  const rosterName = roster.get(bossId)?.name ?? bossId;
  const label: CSSProperties = { color: '#9ab', fontSize: 11, display: 'block', marginTop: 8 };

  return (
    <div style={{ display: 'flex', height: '100%', background: '#0a0a1a', color: '#fff' }}>
      <div ref={mountRef} style={{ flex: 1, position: 'relative' }}>
        <div style={{ position: 'absolute', top: 8, left: 8, fontSize: 12, color: '#9ab', pointerEvents: 'none' }}>
          <div style={{ fontSize: 15, color: '#fff', fontWeight: 600 }}>
            {rosterName} <span style={{ color: '#667', fontWeight: 400 }}>({boss?.model_id})</span>
          </div>
          <div>{arena?.label} · {arenaId}{arena?.unassigned ? ' · unassigned arena' : ''}</div>
          <div>{status}</div>
          <div style={{ marginTop: 4 }}>
            player [{readout.player.join(', ')}] · boss [{readout.boss.join(', ')}] · dist {readout.dist}
          </div>
          {activeClip && (
            <div>
              clip {activeClip} · {clipTime.toFixed(2)} / {clipDuration.toFixed(2)}s
            </div>
          )}
        </div>
      </div>
      <div style={{ width: 320, overflowY: 'auto', padding: 12, background: '#12122a', fontSize: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <strong>Boss room</strong>
          <Link to="/boss-room" style={{ color: '#88aaff', fontSize: 11 }}>all bosses</Link>
        </div>
        {boss?.note && <div style={{ color: '#a86', fontSize: 11, marginTop: 6 }}>{boss.note}</div>}

        <span style={label}>Arena</span>
        <select
          value={arenaId}
          onChange={(e) => setOverride({ arena: e.target.value })}
          style={{ width: '100%', background: '#1a1a35', color: '#fff', border: '1px solid #334' }}
        >
          {config &&
            Object.entries(config.arenas).map(([id, a]) => (
              <option key={id} value={id}>
                {id} — {a.label}{a.unassigned ? ' (unassigned)' : ''}
              </option>
            ))}
        </select>
        {boss && arenaId !== boss.arena && (
          <button onClick={() => setOverride({ arena: undefined })} style={btn}>
            reset to default ({boss.arena})
          </button>
        )}

        <span style={label}>Model scale: {modelScale.toFixed(2)}</span>
        <input
          type="range"
          min={0.01}
          max={3}
          step={0.01}
          value={modelScale}
          onChange={(e) => setOverride({ model_scale: +e.target.value })}
          style={{ width: '100%' }}
        />

        <label style={{ ...label, cursor: 'pointer' }}>
          <input type="checkbox" checked={facePlayer} onChange={(e) => setFacePlayer(e.target.checked)} /> boss faces
          player
        </label>
        <label style={{ ...label, cursor: 'pointer' }}>
          <input type="checkbox" checked={showFloor} onChange={(e) => setShowFloor(e.target.checked)} /> show floor
          collider
        </label>

        <span style={label}>Place on click</span>
        <div style={{ display: 'flex', gap: 6 }}>
          <button onClick={() => setClickMode(clickMode === 'anchor' ? null : 'anchor')} style={{ ...btn, background: clickMode === 'anchor' ? '#facc15' : undefined, color: clickMode === 'anchor' ? '#000' : undefined }}>
            anchor
          </button>
          <button onClick={() => setClickMode(clickMode === 'boss' ? null : 'boss')} style={{ ...btn, background: clickMode === 'boss' ? '#f87171' : undefined, color: clickMode === 'boss' ? '#000' : undefined }}>
            move boss
          </button>
        </div>
        {markers.length > 0 && (
          <div style={{ marginTop: 6 }}>
            {markers.map((m) => (
              <div key={m.name} style={{ color: '#cb8', fontSize: 11 }}>
                {m.name}: [{m.pos.join(', ')}]
              </div>
            ))}
            <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
              <button
                onClick={() => navigator.clipboard?.writeText(JSON.stringify({ arena: arenaId, anchors: markers }, null, 2))}
                style={btn}
              >
                copy anchors JSON
              </button>
              <button onClick={() => apiRef.current?.clearMarkers()} style={btn}>
                clear
              </button>
            </div>
          </div>
        )}

        {boss && ((boss.phases?.length ?? 0) > 0 || (boss.attacks?.length ?? 0) > 0) && (
          <>
            <span style={label}>Behavior draft (schema v2 — verify by observation)</span>
            {(boss.attacks?.length ?? 0) > 0 && (
              <label style={{ ...label, cursor: 'pointer', color: simOn ? '#7c9' : undefined }}>
                <input
                  type="checkbox"
                  checked={simOn}
                  onChange={(e) => {
                    setSimOn(e.target.checked);
                    apiRef.current?.setSimulate(e.target.checked);
                  }}
                />{' '}
                simulate behavior (draft) — J swings ({SWING_DAMAGE} dmg)
              </label>
            )}
            {simOn && simHud && (
              <div style={{ fontSize: 11, marginTop: 4 }}>
                <div style={{ color: '#f88' }}>
                  boss {Math.ceil(simHud.bossHp)}/{simHud.maxHp} · <code>{simHud.state}</code>
                </div>
                <div style={{ background: '#311', borderRadius: 3, height: 6, marginTop: 2 }}>
                  <div style={{ background: '#e55', borderRadius: 3, height: 6, width: `${(simHud.bossHp / simHud.maxHp) * 100}%` }} />
                </div>
                <div style={{ color: '#8c8', marginTop: 4 }}>player {Math.ceil(simHud.playerHp)}/{PLAYER_MAX_HP}</div>
                <div style={{ background: '#131', borderRadius: 3, height: 6, marginTop: 2 }}>
                  <div style={{ background: '#5e5', borderRadius: 3, height: 6, width: `${(simHud.playerHp / PLAYER_MAX_HP) * 100}%` }} />
                </div>
              </div>
            )}
            {boss.phases?.map((p) => (
              <div key={p.id} title={p.note} style={{ color: '#9ab', fontSize: 11, marginTop: 2 }}>
                <code style={{ color: '#cdf' }}>{p.id}</code> — {p.label}
                {p.hp_frac !== undefined && <span style={{ color: '#889' }}> (≤{Math.round(p.hp_frac * 100)}% HP)</span>}
              </div>
            ))}
            {boss.attacks?.map((a) => (
              <button
                key={a.id}
                title={a.note}
                onClick={() => apiRef.current?.playTokens(a.chain ?? [a.clip], lpLoops)}
                style={{ ...btn, display: 'block', width: '100%', textAlign: 'left', marginTop: 4 }}
              >
                ▶ {a.id} <span style={{ color: '#889' }}>{attackMeta(a)}</span>
              </button>
            ))}
            {(boss.anchors?.length ?? 0) > 0 && (
              <div style={{ color: '#2cd', fontSize: 11, marginTop: 4 }}>
                {boss.anchors!.length} authored anchor(s){arenaId !== boss.arena ? ' (hidden — default arena only)' : ''}
              </div>
            )}
          </>
        )}
        {boss && (
          <button
            onClick={copyConfig}
            title="Copies data/boss_arenas.json with this boss's clicked markers merged into its anchors — paste over the file (rename anchors by hand)."
            style={{ ...btn, display: 'block', width: '100%' }}
          >
            copy boss_arenas.json (markers → anchors)
          </button>
        )}

        <span style={label}>Playback</span>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          <label style={{ cursor: 'pointer' }}>
            <input type="checkbox" checked={loop} onChange={(e) => setLoop(e.target.checked)} /> loop
          </label>
          <label style={{ cursor: 'pointer' }}>
            <input type="checkbox" checked={paused} onChange={(e) => setPaused(e.target.checked)} /> pause
          </label>
          <button onClick={() => apiRef.current?.stopClips()} style={btn}>
            stop
          </button>
        </div>
        <span style={label}>Speed: {speed.toFixed(2)}×</span>
        <input type="range" min={0.1} max={2} step={0.05} value={speed} onChange={(e) => setSpeed(+e.target.value)} style={{ width: '100%' }} />
        {paused && activeClip && (
          <>
            <span style={label}>Scrub: {clipTime.toFixed(2)}s</span>
            <input
              type="range"
              min={0}
              max={clipDuration}
              step={0.01}
              value={Math.min(clipTime, clipDuration)}
              onChange={(e) => apiRef.current?.scrub(+e.target.value)}
              style={{ width: '100%' }}
            />
          </>
        )}

        {families.length > 0 && (
          <>
            <span style={label}>Segment chains (st → lp ×{lpLoops} → ed)</span>
            <input type="range" min={1} max={6} step={1} value={lpLoops} onChange={(e) => setLpLoops(+e.target.value)} style={{ width: '100%' }} />
            {families.map((f) => (
              <button key={f.prefix} onClick={() => apiRef.current?.playChain(f, lpLoops)} style={{ ...btn, display: 'block', width: '100%', textAlign: 'left', marginTop: 4 }}>
                ▶ {f.prefix}: {[f.st && 'st', f.lp && 'lp', f.ed && 'ed'].filter(Boolean).join(' → ')}
              </button>
            ))}
          </>
        )}

        <span style={label}>Clips ({clips.length})</span>
        {clips.map((c) => (
          <div key={c} style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 2 }}>
            <button
              onClick={() => apiRef.current?.playClip(c, loop)}
              style={{
                ...btn,
                flex: 1,
                textAlign: 'left',
                background: activeClip === c ? '#2a4a2a' : undefined,
                borderColor: activeClip === c ? '#4a4' : '#334',
              }}
            >
              {c}
            </button>
          </div>
        ))}
        {boss && Object.keys(boss.clip_notes).length > 0 && (
          <>
            <span style={label}>Clip notes</span>
            {Object.entries(boss.clip_notes).map(([k, v]) => (
              <div key={k} style={{ color: '#9ab', fontSize: 11, marginTop: 2 }}>
                <code style={{ color: '#cdf' }}>{k}</code> — {v}
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}

const btn: CSSProperties = {
  background: '#1a1a35',
  color: '#cdf',
  border: '1px solid #334',
  borderRadius: 4,
  padding: '3px 8px',
  fontSize: 11,
  cursor: 'pointer',
  marginTop: 4,
};
