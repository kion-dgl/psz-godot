import { useState, useEffect, useRef, useCallback, useMemo, type CSSProperties } from 'react';
import { useParams, Link } from 'react-router-dom';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { getEnemyGlbPath, getBaseEnemyId, getEnemyDisplayName } from '../storybook/enemyData';
import {
  loadConfig,
  loadRoster,
  resolveEntry,
  defaultAttackFor,
  type EnemyAttackConfig,
  type EnemyAttackEntry,
  type AttackDef,
  type ResolvedEntry,
  type RosterEntry,
} from './types';
import { makeSim, stepEnemy, applyHurt, type EnemySim, type SimEvent } from './fsm';
import { clipToken, resolveClip } from './anim';
import { ARCHETYPE_BY_ID } from './archetypes';

/**
 * Enemy room — the design mock for per-enemy ATTACK BEHAVIOR (spec
 * /mechanics/enemy-attacks), the enemy-side sibling of #/combat-room.
 *
 * The full enemy_base.gd FSM (fsm.ts port) runs against a WASD player
 * dummy: wander → chase (walk/charge) → attack → loaf → hurt. Each attack
 * is frame-tied: windup telegraph → damaging window (fractions of the
 * resolved clip) → arc hit shape, dodgeable through the 0.2s dodge
 * i-frames (player.gd:247). Tunables edit data/enemy_attacks.json entries;
 * export replaces that file wholesale (seeded by
 * scripts/tools/gen_enemy_attacks.py).
 *
 * Controls: WASD/arrows move · Space dodge · H hit the enemy (HURT path) ·
 * P pause (scrub the attack clip while paused) · R reset positions.
 */

const STORAGE_KEY = 'psz-enemy-room:v1';

const PLAYER_SPEED = 5.0;
const PLAYER_RADIUS = 0.4;
const DODGE_DURATION = 0.4;
const DODGE_SPEED = 8.0;
/** player.gd:247 DODGE_IFRAME_DURATION — first 0.2s of the dodge is invincible. */
const DODGE_IFRAME_DURATION = 0.2;
const PLAYER_MAX_HP = 100;
const ARENA_HALF = 11;

interface StoredState {
  /** Last-selected enemy per archetype room. */
  enemyByArchetype: Record<string, string>;
  overrides: Record<string, EnemyAttackEntry>;
}

function loadStored(): StoredState {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed && parsed.overrides) {
        return {
          enemyByArchetype: parsed.enemyByArchetype ?? {},
          overrides: parsed.overrides,
        };
      }
    }
  } catch {
    /* ignore */
  }
  return { enemyByArchetype: {}, overrides: {} };
}


/** Sector mesh: apex at local origin, aimed at +Z (combat-room pattern). */
function buildSectorGeometry(halfAngleRad: number, radius: number, segments = 40): THREE.BufferGeometry {
  const verts: number[] = [];
  const y = 0.015;
  for (let i = 0; i < segments; i++) {
    const a0 = -halfAngleRad + (2 * halfAngleRad * i) / segments;
    const a1 = -halfAngleRad + (2 * halfAngleRad * (i + 1)) / segments;
    verts.push(0, y, 0);
    verts.push(Math.sin(a0) * radius, y, Math.cos(a0) * radius);
    verts.push(Math.sin(a1) * radius, y, Math.cos(a1) * radius);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
  return geo;
}

function buildRing(radius: number, color: number, opacity: number): THREE.Mesh {
  const mesh = new THREE.Mesh(
    new THREE.RingGeometry(Math.max(radius - 0.05, 0.01), radius, 64),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity, side: THREE.DoubleSide, depthWrite: false }),
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.01;
  return mesh;
}

interface PlayerSim {
  pos: { x: number; z: number };
  moveDir: { x: number; z: number };
  dodgeTimer: number; // >0 while dodging
  dodgeDir: { x: number; z: number };
  hp: number;
}

interface SceneRefs {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  enemyGroup: THREE.Group;
  playerGroup: THREE.Group;
  playerBodyMat: THREE.MeshStandardMaterial;
  detectionRing: THREE.Mesh;
  attackRing: THREE.Mesh;
  chargeRing: THREE.Mesh;
  arc: THREE.Mesh;
  arcMat: THREE.MeshBasicMaterial;
  arcKey: string;
  mixer: THREE.AnimationMixer | null;
  clips: THREE.AnimationClip[];
  currentAction: THREE.AnimationAction | null;
  currentClipName: string;
  /** Pooled visuals for ranged deliveries (quad_machine projectiles/lobs). */
  projPool: THREE.Mesh[];
  lobBallPool: THREE.Mesh[];
  lobRingPool: THREE.Mesh[];
}

interface LogEntry {
  id: number;
  color: string;
  text: string;
}

export default function EnemyRoom() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const simRef = useRef<EnemySim>(makeSim({ x: 0, z: -4 }));
  const playerRef = useRef<PlayerSim>({
    pos: { x: 0, z: 4 },
    moveDir: { x: 0, z: 0 },
    dodgeTimer: 0,
    dodgeDir: { x: 0, z: 0 },
    hp: PLAYER_MAX_HP,
  });
  const keysRef = useRef<Record<string, boolean>>({});
  const pausedRef = useRef(false);
  const logIdRef = useRef(0);

  const [baseConfig, setBaseConfig] = useState<EnemyAttackConfig | null>(null);
  const [roster, setRoster] = useState<Map<string, RosterEntry>>(new Map());
  const [loadError, setLoadError] = useState<string | null>(null);
  const [stored, setStored] = useState<StoredState>(loadStored);
  const [clipNames, setClipNames] = useState<string[]>([]);
  const [modelError, setModelError] = useState<string | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [paused, setPaused] = useState(false);
  const [hud, setHud] = useState({ state: 'idle', anim: '', t: 0, duration: 0, cooldown: 0, hp: PLAYER_MAX_HP, dodging: false, dist: 0 });
  const [scrub, setScrub] = useState(0);

  // Dev-only debug handle (used by preview verification + handy in devtools).
  useEffect(() => {
    if (!import.meta.env.DEV) return;
    (window as unknown as Record<string, unknown>).__enemyRoom = { simRef, playerRef, sceneRef };
    return () => {
      delete (window as unknown as Record<string, unknown>).__enemyRoom;
    };
  }, []);

  const { archetype: archetypeParam } = useParams();
  const archetypeId = archetypeParam ?? 'simple_melee';
  const archetype = ARCHETYPE_BY_ID.get(archetypeId);

  // This room's roster: enemies stamped with this archetype.
  const enemyIds = useMemo(
    () =>
      baseConfig
        ? Object.keys(baseConfig.enemies)
            .filter((id) => (baseConfig.enemies[id].archetype ?? 'unclassified') === archetypeId)
            .sort()
        : [],
    [baseConfig, archetypeId],
  );
  const storedPick = stored.enemyByArchetype[archetypeId];
  const enemyId = storedPick && enemyIds.includes(storedPick) ? storedPick : (enemyIds[0] ?? '');
  const setEnemyId = useCallback(
    (id: string) =>
      setStored((prev) => ({ ...prev, enemyByArchetype: { ...prev.enemyByArchetype, [archetypeId]: id } })),
    [archetypeId],
  );

  // Effective entry: file config with the local override applied, defaults resolved.
  const entry: ResolvedEntry = useMemo(() => {
    if (!baseConfig) {
      return resolveEntry(null, enemyId);
    }
    const merged: EnemyAttackConfig = {
      ...baseConfig,
      enemies: { ...baseConfig.enemies, ...(stored.overrides[enemyId] ? { [enemyId]: stored.overrides[enemyId] } : {}) },
    };
    return resolveEntry(merged, enemyId);
  }, [baseConfig, stored.overrides, enemyId]);
  const entryRef = useRef(entry);
  entryRef.current = entry;

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
    } catch {
      /* ignore */
    }
  }, [stored]);

  useEffect(() => {
    loadConfig().then(setBaseConfig, (e) => setLoadError(String(e)));
    loadRoster().then(setRoster, (e) => setLoadError(String(e)));
  }, []);

  // Roster ids (enemy_attacks.json) are game enemies; their GLB lives under
  // the MODEL id (e.g. hildegigas → gorilla_rare) from data/enemies.json.
  const modelId = roster.get(enemyId)?.model_id || enemyId;
  const displayName = roster.get(enemyId)?.name || getEnemyDisplayName(enemyId);

  const pushLog = useCallback((text: string, color = '#aaa') => {
    logIdRef.current += 1;
    const id = logIdRef.current;
    setLog((prev) => [{ id, color, text }, ...prev].slice(0, 12));
  }, []);

  /** Update the current enemy's entry (writes the local override). */
  const setEntry = useCallback(
    (patch: (prev: EnemyAttackEntry) => EnemyAttackEntry) => {
      setStored((prev) => {
        const current: EnemyAttackEntry = prev.overrides[enemyId] ??
          baseConfig?.enemies[enemyId] ?? {
            stats: entryRef.current.stats,
            fsm: {},
            attacks: entryRef.current.attacks,
          };
        return { ...prev, overrides: { ...prev.overrides, [enemyId]: patch(structuredClone(current)) } };
      });
    },
    [enemyId, baseConfig],
  );

  // ── Scene setup (once) ────────────────────────────────────────────────
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const camera = new THREE.PerspectiveCamera(50, container.clientWidth / container.clientHeight, 0.1, 200);
    camera.position.set(0, 12, 10);
    camera.lookAt(0, 0, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.75));
    const dir = new THREE.DirectionalLight(0xffffff, 0.7);
    dir.position.set(4, 8, 5);
    scene.add(dir);
    scene.add(new THREE.GridHelper(ARENA_HALF * 2, ARENA_HALF * 4, 0x444466, 0x222238));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.5, 0);

    const enemyGroup = new THREE.Group();
    scene.add(enemyGroup);

    // Player dummy: capsule + facing wedge
    const playerGroup = new THREE.Group();
    const playerBodyMat = new THREE.MeshStandardMaterial({ color: 0x44ccff, roughness: 0.7 });
    const body = new THREE.Mesh(new THREE.CapsuleGeometry(PLAYER_RADIUS * 0.9, 1.0, 4, 12), playerBodyMat);
    body.position.y = 0.9;
    playerGroup.add(body);
    const wedge = new THREE.Mesh(new THREE.ConeGeometry(0.18, 0.5, 4), new THREE.MeshBasicMaterial({ color: 0xffffff }));
    wedge.rotation.x = Math.PI / 2;
    wedge.position.set(0, 0.9, 0.65);
    playerGroup.add(wedge);
    scene.add(playerGroup);

    // Rings follow the enemy; radii rebuilt when tuning changes.
    const detectionRing = buildRing(15, 0x8888ff, 0.35);
    const attackRing = buildRing(2, 0xff6666, 0.5);
    const chargeRing = buildRing(4, 0xffaa44, 0.4);
    scene.add(detectionRing, attackRing, chargeRing);

    // Attack arc (telegraph → hot), positioned at the enemy with locked facing.
    const arcMat = new THREE.MeshBasicMaterial({
      color: 0xffee44,
      transparent: true,
      opacity: 0,
      side: THREE.DoubleSide,
      depthWrite: false,
    });
    const arc = new THREE.Mesh(buildSectorGeometry(THREE.MathUtils.degToRad(45), 2), arcMat);
    scene.add(arc);

    // Pooled ranged-delivery visuals (hidden until used).
    const projPool: THREE.Mesh[] = [];
    for (let i = 0; i < 8; i++) {
      const m = new THREE.Mesh(
        new THREE.SphereGeometry(0.18, 10, 8),
        new THREE.MeshBasicMaterial({ color: 0xffcc33 }),
      );
      m.visible = false;
      m.position.y = 0.9;
      scene.add(m);
      projPool.push(m);
    }
    const lobBallPool: THREE.Mesh[] = [];
    const lobRingPool: THREE.Mesh[] = [];
    for (let i = 0; i < 4; i++) {
      const ball = new THREE.Mesh(
        new THREE.SphereGeometry(0.22, 10, 8),
        new THREE.MeshBasicMaterial({ color: 0xff6633 }),
      );
      ball.visible = false;
      scene.add(ball);
      lobBallPool.push(ball);
      const ring = buildRing(1.6, 0xff6633, 0.4);
      ring.visible = false;
      scene.add(ring);
      lobRingPool.push(ring);
    }

    sceneRef.current = {
      scene, camera, renderer, controls, enemyGroup, playerGroup, playerBodyMat,
      detectionRing, attackRing, chargeRing, arc, arcMat, arcKey: '',
      mixer: null, clips: [], currentAction: null, currentClipName: '',
      projPool, lobBallPool, lobRingPool,
    };

    const onResize = () => {
      camera.aspect = container.clientWidth / container.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(container.clientWidth, container.clientHeight);
    };
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      renderer.dispose();
      container.removeChild(renderer.domElement);
      sceneRef.current = null;
    };
  }, []);

  // ── Enemy model load (per enemy) ──────────────────────────────────────
  useEffect(() => {
    const s = sceneRef.current;
    if (!s || !enemyId) return;
    let cancelled = false;
    setClipNames([]);
    setModelError(null);
    s.enemyGroup.clear();
    s.mixer = null;
    s.clips = [];
    s.currentAction = null;
    s.currentClipName = '';

    const loader = new GLTFLoader();
    const baseId = getBaseEnemyId(modelId);
    const loadOne = (url: string) =>
      new Promise<{ scene: THREE.Group; animations: THREE.AnimationClip[] }>((res, rej) =>
        loader.load(url, (g) => res({ scene: g.scene as unknown as THREE.Group, animations: g.animations }), undefined, rej),
      );

    (async () => {
      try {
        const model = await loadOne(getEnemyGlbPath(modelId));
        let animations = model.animations;
        if (animations.length === 0 && baseId) {
          const animSource = await loadOne(getEnemyGlbPath(baseId));
          animations = animSource.animations;
        }
        if (cancelled || !sceneRef.current) return;
        const sc = sceneRef.current;
        sc.enemyGroup.add(model.scene);
        sc.mixer = new THREE.AnimationMixer(model.scene);
        sc.clips = animations;
        setClipNames(animations.map((a) => a.name));
        // Reset sims on enemy swap
        simRef.current = makeSim({ x: 0, z: -4 });
        playerRef.current.pos = { x: 0, z: 4 };
        playerRef.current.hp = PLAYER_MAX_HP;
      } catch (e) {
        if (!cancelled) setModelError(`GLB load failed for ${enemyId} (model ${modelId}): ${e}`);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [enemyId, modelId]);

  // ── Input ─────────────────────────────────────────────────────────────
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      keysRef.current[e.code] = true;
      if (e.code.startsWith('Arrow')) e.preventDefault();
      if (e.code === 'Space') {
        e.preventDefault();
        const p = playerRef.current;
        if (p.dodgeTimer <= 0) {
          const dir = p.moveDir.x || p.moveDir.z ? p.moveDir : { x: 0, z: 1 };
          p.dodgeTimer = DODGE_DURATION;
          p.dodgeDir = { ...dir };
          pushLog('dodge', '#6bf');
        }
      } else if (e.code === 'KeyH') {
        const events = applyHurt(simRef.current, entryRef.current);
        handleEvents(events);
        pushLog('hit enemy → HURT', '#fa6');
      } else if (e.code === 'KeyP') {
        pausedRef.current = !pausedRef.current;
        setPaused(pausedRef.current);
      } else if (e.code === 'KeyR') {
        simRef.current = makeSim({ x: 0, z: -4 });
        playerRef.current.pos = { x: 0, z: 4 };
        playerRef.current.hp = PLAYER_MAX_HP;
        setLog([]);
      }
    };
    const up = (e: KeyboardEvent) => {
      keysRef.current[e.code] = false;
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleEvents = useCallback(
    (events: SimEvent[]) => {
      for (const e of events) {
        switch (e.type) {
          case 'state_change':
            pushLog(`${e.from} → ${e.to}`, '#889');
            break;
          case 'attack_start':
            pushLog(
              `attack '${e.attack.id}' (${e.resolvedClip || `no clip — fallback ${e.duration.toFixed(2)}s`})`,
              '#fd7',
            );
            break;
          case 'window_open':
            pushLog(`window open [${e.attack.windup_frac}–${e.attack.damage_end_frac}]`, '#f66');
            break;
          case 'hit': {
            const p = playerRef.current;
            p.hp = Math.max(0, p.hp - e.damage);
            pushLog(`HIT for ${e.damage} (hp ${p.hp})${e.attack.knockdown ? ' — KNOCKED DOWN' : ''}`, '#f44');
            if (p.hp <= 0) {
              pushLog('player down — R to reset', '#f44');
            }
            break;
          }
          case 'vulnerable_open':
            pushLog(`VULNERABLE ×${e.mult} while recovery plays — punish window`, '#4fd');
            break;
          case 'hit_dodged':
            pushLog('dodged through the window (i-frames)', '#4f8');
            break;
          case 'window_close':
            pushLog('window closed', '#666');
            break;
          case 'projectile_fired':
            pushLog(`projectile '${e.attack.id}' fired`, '#fc3');
            break;
          case 'lob_fired':
            pushLog(`grenade '${e.attack.id}' lobbed`, '#f63');
            break;
          case 'lob_landed':
            pushLog(`grenade landed (AoE r=${e.attack.hit_reach})`, '#f63');
            break;
          case 'leap_landed':
            pushLog(`belly flop landed (AoE r=${e.attack.hit_reach})`, '#f96');
            break;
          case 'attack_end':
            pushLog(`attack '${e.attack.id}' end → loaf`, '#889');
            break;
        }
      }
    },
    [pushLog],
  );

  // ── Main loop ─────────────────────────────────────────────────────────
  useEffect(() => {
    let raf = 0;
    let last = performance.now();
    let hudAccum = 0;
    const clock = { dt: 0 };

    const tick = (now: number) => {
      raf = requestAnimationFrame(tick);
      clock.dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      const s = sceneRef.current;
      if (!s) return;
      const sim = simRef.current;
      const p = playerRef.current;
      const e = entryRef.current;

      if (!pausedRef.current) {
        // Player
        const k = keysRef.current;
        const mx = (k['KeyD'] || k['ArrowRight'] ? 1 : 0) - (k['KeyA'] || k['ArrowLeft'] ? 1 : 0);
        const mz = (k['KeyS'] || k['ArrowDown'] ? 1 : 0) - (k['KeyW'] || k['ArrowUp'] ? 1 : 0);
        const ml = Math.hypot(mx, mz);
        p.moveDir = ml > 0 ? { x: mx / ml, z: mz / ml } : { x: 0, z: 0 };
        if (p.dodgeTimer > 0) {
          p.dodgeTimer -= clock.dt;
          p.pos.x += p.dodgeDir.x * DODGE_SPEED * clock.dt;
          p.pos.z += p.dodgeDir.z * DODGE_SPEED * clock.dt;
        } else if (ml > 0) {
          p.pos.x += p.moveDir.x * PLAYER_SPEED * clock.dt;
          p.pos.z += p.moveDir.z * PLAYER_SPEED * clock.dt;
        }
        p.pos.x = THREE.MathUtils.clamp(p.pos.x, -ARENA_HALF, ARENA_HALF);
        p.pos.z = THREE.MathUtils.clamp(p.pos.z, -ARENA_HALF, ARENA_HALF);

        const invincible = p.dodgeTimer > DODGE_DURATION - DODGE_IFRAME_DURATION;

        // Enemy
        const events = stepEnemy(sim, e, {
          dt: clock.dt,
          playerPos: p.pos,
          playerRadius: PLAYER_RADIUS,
          playerInvincible: invincible,
          rng: Math.random,
          clipDurationFor: (token) => resolveClip(s.clips, token)?.duration ?? null,
        });
        if (events.length) handleEvents(events);
        sim.pos.x = THREE.MathUtils.clamp(sim.pos.x, -ARENA_HALF, ARENA_HALF);
        sim.pos.z = THREE.MathUtils.clamp(sim.pos.z, -ARENA_HALF, ARENA_HALF);

        // Enemy animation: crossfade to sim.anim's resolved clip.
        if (s.mixer) {
          // run→wlk mirrors the runtime's "unresolved play keeps the previous
          // clip" behavior for rigs without a run clip (swordman/tank).
          const clip =
            resolveClip(s.clips, sim.anim) ??
            (sim.anim === 'run' ? resolveClip(s.clips, 'wlk') : null) ??
            resolveClip(s.clips, 'wat') ??
            resolveClip(s.clips, 'stt');
          if (clip && clip.name !== s.currentClipName) {
            const action = s.mixer.clipAction(clip);
            // Charge loop segments repeat while the charge travels (bigrig
            // _lp suffixes AND explicit segments like the roller's wat3).
            const looping =
              (sim.state !== 'attacking' && sim.state !== 'hurt') ||
              sim.currentAttack?.charge?.phase === 'lp';
            action.reset();
            action.setLoop(looping ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
            action.clampWhenFinished = true;
            if (s.currentAction) s.currentAction.fadeOut(0.1);
            action.fadeIn(0.1).play();
            s.currentAction = action;
            s.currentClipName = clip.name;
          }
          s.mixer.update(clock.dt);
        }
      } else if (s.mixer && sim.state === 'attacking' && sim.currentAttack && s.currentAction) {
        // Paused scrub: keep action time in sync with the sim's attack t.
        s.currentAction.time = Math.min(sim.currentAttack.t, s.currentAction.getClip().duration);
        s.mixer.update(0);
      }

      // ── Visual sync ──
      s.playerGroup.position.set(p.pos.x, 0, p.pos.z);
      if (p.moveDir.x || p.moveDir.z) s.playerGroup.rotation.y = Math.atan2(p.moveDir.x, p.moveDir.z);
      const invNow = p.dodgeTimer > DODGE_DURATION - DODGE_IFRAME_DURATION;
      s.playerBodyMat.color.setHex(invNow ? 0x88ffcc : p.dodgeTimer > 0 ? 0x2288aa : 0x44ccff);

      // Leap gets a visual hop (parabola over the damaging window).
      let hopY = 0;
      const atkNow = sim.currentAttack;
      if (atkNow?.leap && atkNow.windowOpened && !atkNow.windowClosed) {
        const ws = atkNow.def.windup_frac * atkNow.duration;
        const we = atkNow.def.damage_end_frac * atkNow.duration;
        const f = Math.min(Math.max((atkNow.t - ws) / (we - ws), 0), 1);
        hopY = 3.0 * f * (1 - f);
      }
      s.enemyGroup.position.set(sim.pos.x, sim.altitude + hopY, sim.pos.z);
      s.enemyGroup.rotation.y = Math.atan2(sim.facing.x, sim.facing.z);
      // Roller ball travel: the curled clip has no motion of its own — the
      // engine rotates it (spec §roller). Forward tumble while lp plays.
      if (atkNow?.charge?.phase === 'lp' && atkNow.def.charge_segments) {
        s.enemyGroup.rotation.x += clock.dt * 8;
      } else {
        s.enemyGroup.rotation.x = 0;
      }
      for (const ring of [s.detectionRing, s.attackRing, s.chargeRing]) {
        ring.position.x = sim.pos.x;
        ring.position.z = sim.pos.z;
      }

      // Ranged deliveries: sync pools to the sim's in-flight lists.
      s.projPool.forEach((m, i) => {
        const p = sim.projectiles[i];
        m.visible = !!p;
        if (p) m.position.set(p.pos.x, 0.9, p.pos.z);
      });
      s.lobBallPool.forEach((m, i) => {
        const l = sim.lobs[i];
        m.visible = !!l;
        if (l) {
          const f = 1 - l.timer / l.flightTime;
          const x = l.from.x + (l.target.x - l.from.x) * f;
          const z = l.from.z + (l.target.z - l.from.z) * f;
          m.position.set(x, 0.9 + 4.5 * f * (1 - f), z); // parabola
        }
        const ring = s.lobRingPool[i];
        ring.visible = !!l;
        if (l) {
          ring.position.x = l.target.x;
          ring.position.z = l.target.z;
        }
      });

      // Attack arc overlay
      const atk = sim.currentAttack;
      if (sim.state === 'attacking' && atk) {
        const key = `${atk.def.hit_half_angle_deg}:${atk.def.hit_reach}`;
        if (key !== s.arcKey) {
          s.arc.geometry.dispose();
          s.arc.geometry = buildSectorGeometry(THREE.MathUtils.degToRad(atk.def.hit_half_angle_deg), atk.def.hit_reach);
          s.arcKey = key;
        }
        s.arc.position.set(sim.pos.x, 0, sim.pos.z);
        s.arc.rotation.y = Math.atan2(atk.facing.x, atk.facing.z);
        if (!atk.windowOpened) {
          s.arcMat.color.setHex(0xffee44); // telegraph
          s.arcMat.opacity = 0.18;
        } else if (!atk.windowClosed) {
          s.arcMat.color.setHex(0xff3333); // damaging window
          s.arcMat.opacity = 0.35;
        } else {
          s.arcMat.color.setHex(0x666666); // recovery
          s.arcMat.opacity = 0.1;
        }
      } else {
        s.arcMat.opacity = 0;
      }

      // HUD at ~12Hz
      hudAccum += clock.dt;
      if (hudAccum > 0.08) {
        hudAccum = 0;
        setHud({
          state: sim.state,
          anim: s.currentClipName || sim.anim,
          t: atk?.t ?? 0,
          duration: atk?.duration ?? 0,
          cooldown: Math.max(sim.attackCooldown, 0),
          hp: p.hp,
          dodging: p.dodgeTimer > 0,
          dist: Math.hypot(p.pos.x - sim.pos.x, p.pos.z - sim.pos.z),
        });
        if (pausedRef.current && atk) setScrub(atk.t);
      }

      s.controls.update();
      s.renderer.render(s.scene, s.camera);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [handleEvents]);

  // Ring radii follow tuning.
  useEffect(() => {
    const s = sceneRef.current;
    if (!s) return;
    const rebuild = (mesh: THREE.Mesh, radius: number) => {
      mesh.geometry.dispose();
      mesh.geometry = new THREE.RingGeometry(Math.max(radius - 0.05, 0.01), radius, 64);
    };
    rebuild(s.detectionRing, entry.stats.detection_range);
    rebuild(s.attackRing, entry.stats.attack_range);
    rebuild(s.chargeRing, entry.stats.attack_range * entry.fsm.charge_range_mult);
  }, [entry]);

  // ── Editing helpers ───────────────────────────────────────────────────
  const setStat = (key: keyof EnemyAttackEntry['stats'], value: number) =>
    setEntry((prev) => ({ ...prev, stats: { ...prev.stats, [key]: value } }));
  const setFsm = (key: string, value: number) =>
    setEntry((prev) => ({ ...prev, fsm: { ...prev.fsm, [key]: value } }));
  const setAttack = (idx: number, patch: Partial<AttackDef>) =>
    setEntry((prev) => ({
      ...prev,
      attacks: prev.attacks.map((a, i) => (i === idx ? { ...a, ...patch } : a)),
    }));
  const addAttack = () =>
    setEntry((prev) => ({
      ...prev,
      attacks: [
        ...prev.attacks,
        { ...defaultAttackFor(entryRef.current.stats), id: `attack_${prev.attacks.length + 1}` },
      ],
    }));
  const removeAttack = (idx: number) =>
    setEntry((prev) => ({ ...prev, attacks: prev.attacks.filter((_, i) => i !== idx) }));
  const resetEnemy = () =>
    setStored((prev) => {
      const overrides = { ...prev.overrides };
      delete overrides[enemyId];
      return { ...prev, overrides };
    });

  /** Full merged config — what data/enemy_attacks.json should become. */
  const mergedConfig = useCallback((): EnemyAttackConfig | null => {
    if (!baseConfig) return null;
    return { ...baseConfig, enemies: { ...baseConfig.enemies, ...stored.overrides } };
  }, [baseConfig, stored.overrides]);

  const copyJson = () => {
    const cfg = mergedConfig();
    if (!cfg) return;
    navigator.clipboard.writeText(JSON.stringify(cfg, null, 2) + '\n');
    pushLog('copied enemy_attacks.json to clipboard', '#6bf');
  };
  const downloadJson = () => {
    const cfg = mergedConfig();
    if (!cfg) return;
    const blob = new Blob([JSON.stringify(cfg, null, 2) + '\n'], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'enemy_attacks.json';
    a.click();
    URL.revokeObjectURL(a.href);
  };

  // Clip tokens available on the loaded rig (for the attack clip dropdown).
  const clipTokens = useMemo(() => {
    const tokens = new Set<string>();
    for (const name of clipNames) tokens.add(clipToken(name));
    return [...tokens].sort();
  }, [clipNames]);

  const grouped = useMemo(() => {
    const groups = new Map<string, string[]>();
    for (const id of enemyIds) {
      const r = roster.get(id);
      const label = r?.is_boss ? 'Bosses' : (r?.locations?.[0] ?? 'other');
      if (!groups.has(label)) groups.set(label, []);
      groups.get(label)!.push(id);
    }
    return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
  }, [enemyIds, roster]);

  const hasOverride = !!stored.overrides[enemyId];

  // ── Render ────────────────────────────────────────────────────────────
  const sliderRow = (
    label: string,
    value: number,
    min: number,
    max: number,
    step: number,
    onChange: (v: number) => void,
  ) => (
    <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
      <span style={{ width: 130, fontSize: 11, color: '#aab' }}>{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(ev) => onChange(parseFloat(ev.target.value))}
        style={{ flex: 1 }}
      />
      <span style={{ width: 44, fontSize: 11, textAlign: 'right' }}>{value.toFixed(step < 0.1 ? 2 : 1)}</span>
    </div>
  );

  return (
    <div style={{ display: 'flex', height: 'calc(100vh - 60px)', background: '#0a0a1a', color: '#fff' }}>
      <div ref={containerRef} style={{ flex: 1, position: 'relative' }}>
        {/* HUD */}
        <div style={{ position: 'absolute', top: 10, left: 10, fontFamily: 'monospace', fontSize: 12, background: 'rgba(10,10,26,0.75)', padding: '8px 10px', borderRadius: 6, pointerEvents: 'none' }}>
          <div style={{ fontWeight: 'bold', marginBottom: 4 }}>{displayName} <span style={{ color: '#889' }}>({enemyId} · {modelId})</span></div>
          <div>state: <span style={{ color: '#fd7' }}>{hud.state}</span> · clip: {hud.anim || '—'}</div>
          {hud.duration > 0 && <div>attack t: {hud.t.toFixed(2)} / {hud.duration.toFixed(2)}s</div>}
          <div>cooldown: {hud.cooldown.toFixed(2)}s · dist: {hud.dist.toFixed(2)}</div>
          <div style={{ marginTop: 4 }}>
            player HP:{' '}
            <span style={{ display: 'inline-block', width: 100, height: 8, background: '#333', verticalAlign: 'middle', borderRadius: 3 }}>
              <span style={{ display: 'block', width: `${hud.hp}%`, height: '100%', background: hud.hp > 30 ? '#4f8' : '#f44', borderRadius: 3 }} />
            </span>{' '}
            {hud.hp} {hud.dodging && <span style={{ color: '#4f8' }}>· dodging</span>}
          </div>
          <div style={{ color: '#667', marginTop: 4 }}>WASD move · Space dodge · H hit enemy · P pause · R reset</div>
        </div>
        {/* Log */}
        <div style={{ position: 'absolute', bottom: 10, left: 10, fontFamily: 'monospace', fontSize: 11, pointerEvents: 'none' }}>
          {log.map((l) => (
            <div key={l.id} style={{ color: l.color }}>{l.text}</div>
          ))}
        </div>
        {/* Pause / scrubber */}
        {paused && (
          <div style={{ position: 'absolute', bottom: 10, left: '50%', transform: 'translateX(-50%)', width: '50%', background: 'rgba(10,10,26,0.85)', padding: '8px 12px', borderRadius: 6, fontSize: 11 }}>
            <div style={{ marginBottom: 4, color: '#fd7' }}>PAUSED{simRef.current.currentAttack ? ' — scrub attack clip' : ' (attack scrub available during ATTACKING)'}</div>
            {simRef.current.currentAttack && (
              <div style={{ position: 'relative' }}>
                <input
                  type="range"
                  min={0}
                  max={simRef.current.currentAttack.duration}
                  step={0.01}
                  value={scrub}
                  onChange={(ev) => {
                    const t = parseFloat(ev.target.value);
                    setScrub(t);
                    if (simRef.current.currentAttack) simRef.current.currentAttack.t = t;
                  }}
                  style={{ width: '100%' }}
                />
                {/* windup / window markers */}
                {(() => {
                  const atk = simRef.current.currentAttack!;
                  const w = atk.def.windup_frac * 100;
                  const d = atk.def.damage_end_frac * 100;
                  return (
                    <div style={{ position: 'relative', height: 6, background: '#223', borderRadius: 2 }}>
                      <div style={{ position: 'absolute', left: 0, width: `${w}%`, height: '100%', background: '#aa4', borderRadius: 2 }} title="windup" />
                      <div style={{ position: 'absolute', left: `${w}%`, width: `${d - w}%`, height: '100%', background: '#f33' }} title="damaging window" />
                    </div>
                  );
                })()}
              </div>
            )}
          </div>
        )}
        {(loadError || modelError) && (
          <div style={{ position: 'absolute', top: '40%', width: '100%', textAlign: 'center', color: '#f66' }}>{loadError || modelError}</div>
        )}
        {!archetype && (
          <div style={{ position: 'absolute', top: '40%', width: '100%', textAlign: 'center', color: '#f66' }}>
            unknown archetype '{archetypeId}' — <Link to="/enemy-room" style={{ color: '#6bf' }}>pick one</Link>
          </div>
        )}
      </div>

      {/* Sidebar */}
      <div style={{ width: 340, overflowY: 'auto', padding: 12, background: '#12122a', fontSize: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <h3 style={{ margin: '0 0 4px' }}>{archetype?.label ?? archetypeId} Room</h3>
          <Link to="/enemy-room" style={{ color: '#6bf', fontSize: 11 }}>all archetypes</Link>
        </div>
        {archetype && (
          <>
            <div style={{ color: '#9ab', fontSize: 11, marginBottom: 4 }}>{archetype.blurb}</div>
            <div style={{ color: '#786', fontSize: 10, marginBottom: 8, fontStyle: 'italic' }}>{archetype.simNote}</div>
          </>
        )}
        <select
          value={enemyId}
          onChange={(ev) => setEnemyId(ev.target.value)}
          style={{ width: '100%', padding: 6, marginBottom: 8, background: '#1a1a3a', color: '#fff', border: '1px solid #334' }}
        >
          {grouped.map(([label, ids]) => (
            <optgroup key={label} label={label}>
              {ids.map((id) => (
                <option key={id} value={id}>
                  {roster.get(id)?.name || getEnemyDisplayName(id)} ({id})
                </option>
              ))}
            </optgroup>
          ))}
        </select>
        {hasOverride && (
          <div style={{ marginBottom: 8, color: '#fd7' }}>
            local tuning differs from data/enemy_attacks.json{' '}
            <button onClick={resetEnemy} style={btnStyle}>reset to file</button>
          </div>
        )}

        <h4 style={h4Style}>Stats <span style={{ color: '#667', fontWeight: 'normal' }}>(.tres is authoritative)</span></h4>
        {sliderRow('move_speed', entry.stats.move_speed, 0.5, 10, 0.1, (v) => setStat('move_speed', v))}
        {sliderRow('attack_range', entry.stats.attack_range, 0.5, 12, 0.1, (v) => setStat('attack_range', v))}
        {sliderRow('attack_cooldown', entry.stats.attack_cooldown, 0.1, 6, 0.1, (v) => setStat('attack_cooldown', v))}
        {sliderRow('detection_range', entry.stats.detection_range, 2, 30, 0.5, (v) => setStat('detection_range', v))}
        {sliderRow('attack_base', entry.stats.attack_base, 1, 60, 1, (v) => setStat('attack_base', v))}

        <h4 style={h4Style}>FSM</h4>
        {sliderRow('walk_speed_mult', entry.fsm.walk_speed_mult, 0.1, 2, 0.05, (v) => setFsm('walk_speed_mult', v))}
        {sliderRow('charge_range_mult', entry.fsm.charge_range_mult, 1, 5, 0.1, (v) => setFsm('charge_range_mult', v))}
        {sliderRow('charge_speed_mult', entry.fsm.charge_speed_mult, 0.5, 4, 0.05, (v) => setFsm('charge_speed_mult', v))}
        {sliderRow('loaf_duration_min', entry.fsm.loaf_duration_min, 0.5, 6, 0.1, (v) => setFsm('loaf_duration_min', v))}
        {sliderRow('loaf_duration_max', entry.fsm.loaf_duration_max, 0.5, 8, 0.1, (v) => setFsm('loaf_duration_max', v))}
        {sliderRow('attack_fallback_dur', entry.fsm.attack_fallback_duration, 0.2, 3, 0.05, (v) => setFsm('attack_fallback_duration', v))}
        {entry.archetype === 'quad_machine' &&
          sliderRow('standoff_range', entry.fsm.standoff_range, 1, 14, 0.5, (v) => setFsm('standoff_range', v))}
        {entry.archetype === 'flyer_combo' && (
          <>
            {sliderRow('orbit (standoff)', entry.fsm.standoff_range, 1, 8, 0.25, (v) => setFsm('standoff_range', v))}
            {sliderRow('hover_height', entry.fsm.hover_height, 0, 3, 0.1, (v) => setFsm('hover_height', v))}
          </>
        )}

        <h4 style={h4Style}>Attacks ({entry.attacks.length})</h4>
        {entry.attacks.map((a, i) => {
          const clips = sceneRef.current?.clips ?? [];
          const isCharge = a.kind === 'charge';
          // Charge kind resolves its st/lp/ed segments (suffix-derived or
          // explicit charge_segments), not the base token.
          const segTokens = a.charge_segments ?? { st: `${a.clip}_st`, lp: `${a.clip}_lp`, ed: `${a.clip}_ed` };
          const resolved = isCharge ? resolveClip(clips, segTokens.lp) : resolveClip(clips, a.clip);
          const chargeSegs = isCharge
            ? (['st', 'lp', 'ed'] as const).map((k) => resolveClip(clips, segTokens[k])?.name ?? `${segTokens[k]}?`)
            : null;
          return (
            <div key={i} style={{ border: '1px solid #334', borderRadius: 6, padding: 8, marginBottom: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                <input
                  value={a.id}
                  onChange={(ev) => setAttack(i, { id: ev.target.value })}
                  style={{ width: 110, background: '#1a1a3a', color: '#fff', border: '1px solid #334', padding: 2 }}
                />
                <button onClick={() => removeAttack(i)} style={btnStyle} disabled={entry.attacks.length <= 1}>
                  remove
                </button>
              </div>
              <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 4 }}>
                <span style={{ width: 60, fontSize: 11, color: '#aab' }}>clip</span>
                <select
                  value={a.clip}
                  onChange={(ev) => setAttack(i, { clip: ev.target.value })}
                  style={{ flex: 1, background: '#1a1a3a', color: resolved ? '#fff' : '#f66', border: '1px solid #334', padding: 2 }}
                >
                  {!clipTokens.includes(a.clip) && <option value={a.clip}>{a.clip} (unresolved)</option>}
                  {clipTokens.map((t) => (
                    <option key={t} value={t}>
                      {t}
                    </option>
                  ))}
                </select>
              </div>
              <div style={{ fontSize: 10, color: resolved ? '#667' : '#f66', marginBottom: 4 }}>
                {chargeSegs
                  ? `→ segments: ${chargeSegs.join(' · ')}`
                  : resolved
                    ? `→ ${resolved.name} (${resolved.duration.toFixed(2)}s)`
                    : `no clip resolves — timeline uses fallback ${entry.fsm.attack_fallback_duration}s (#477 path)`}
              </div>
              {entry.clip_notes[a.clip] && (
                <div style={{ fontSize: 10, color: '#9ab', marginBottom: 4, fontStyle: 'italic' }}>
                  {entry.clip_notes[a.clip]}
                </div>
              )}
              <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 4 }}>
                <span style={{ width: 60, fontSize: 11, color: '#aab' }}>tech</span>
                <input
                  value={a.tech ?? ''}
                  placeholder="— (not a tech cast)"
                  onChange={(ev) => setAttack(i, { tech: ev.target.value || undefined })}
                  style={{ flex: 1, background: '#1a1a3a', color: '#9cf', border: '1px solid #334', padding: 2, fontSize: 11 }}
                />
              </div>
              <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 4 }}>
                <span style={{ width: 60, fontSize: 11, color: '#aab' }}>kind</span>
                <select
                  value={a.kind ?? 'melee_arc'}
                  onChange={(ev) => setAttack(i, { kind: ev.target.value as AttackDef['kind'] })}
                  style={{ flex: 1, background: '#1a1a3a', color: '#fff', border: '1px solid #334', padding: 2 }}
                >
                  <option value="melee_arc">melee_arc</option>
                  <option value="projectile">projectile</option>
                  <option value="lob">lob (grenade AoE)</option>
                  <option value="charge">charge (st/lp/ed, moves)</option>
                  <option value="leap">leap (AoE on landing)</option>
                </select>
              </div>
              {sliderRow('weight', a.weight, 0.1, 10, 0.1, (v) => setAttack(i, { weight: v }))}
              {sliderRow('min_range', a.min_range, 0, 12, 0.1, (v) => setAttack(i, { min_range: v }))}
              {sliderRow('max_range', Math.min(a.max_range, 20), 0.5, 20, 0.1, (v) => setAttack(i, { max_range: v }))}
              {sliderRow('windup_frac', a.windup_frac, 0, 0.95, 0.01, (v) =>
                setAttack(i, { windup_frac: Math.min(v, a.damage_end_frac - 0.01) }),
              )}
              {sliderRow('damage_end_frac', a.damage_end_frac, 0.05, 1, 0.01, (v) =>
                setAttack(i, { damage_end_frac: Math.max(v, a.windup_frac + 0.01) }),
              )}
              {sliderRow('hit_half_angle', a.hit_half_angle_deg, 5, 180, 1, (v) => setAttack(i, { hit_half_angle_deg: v }))}
              {sliderRow('hit_reach', a.hit_reach, 0.5, 12, 0.1, (v) => setAttack(i, { hit_reach: v }))}
              {sliderRow('damage_mult', a.damage_mult, 0.1, 5, 0.1, (v) => setAttack(i, { damage_mult: v }))}
            </div>
          );
        })}
        <button onClick={addAttack} style={{ ...btnStyle, width: '100%', marginBottom: 12 }}>
          + add attack
        </button>

        <h4 style={h4Style}>Export</h4>
        <div style={{ display: 'flex', gap: 6, marginBottom: 6 }}>
          <button onClick={copyJson} style={{ ...btnStyle, flex: 1 }}>Copy JSON</button>
          <button onClick={downloadJson} style={{ ...btnStyle, flex: 1 }}>Download</button>
        </div>
        <div style={{ color: '#667', fontSize: 10 }}>
          Replaces the data file wholesale: <code>cp ~/Downloads/enemy_attacks.json data/enemy_attacks.json</code>.
          Seeded by scripts/tools/gen_enemy_attacks.py; contract in spec /mechanics/enemy-attacks.
        </div>
      </div>
    </div>
  );
}

const btnStyle: CSSProperties = {
  background: '#223',
  color: '#cde',
  border: '1px solid #445',
  borderRadius: 4,
  padding: '3px 8px',
  cursor: 'pointer',
  fontSize: 11,
};

const h4Style: CSSProperties = { margin: '12px 0 6px', borderBottom: '1px solid #334', paddingBottom: 3 };
