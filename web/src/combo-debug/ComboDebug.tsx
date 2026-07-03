import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Interactive debug view for weapon combo timing + inter-swing turning.
 *
 * Mirrors the in-game combo state machine (scripts/3d/player/player.gd +
 * CombatManager.WEAPON_TYPE_CONFIGS):
 *  - press attack → combo step 1 plays `<prefix>_atkN`
 *  - the chain window opens at COMBO_WINDOW_OPEN_PCT of the clip and stays
 *    open for the weapon's combo_window seconds; press inside it to chain,
 *    miss it and the combo resets
 *  - strong/special attacks insert a `_wait` wind-up pause before the swing
 *    (SPECIAL_ATTACK_DELAY in player.gd)
 *
 * On top of that it prototypes a mechanic the game does NOT have yet:
 * per-weapon turn limits between swings. Once a swing starts the facing is
 * locked; holding a direction only records the *requested* heading, and when
 * the next swing begins the yaw snaps toward it clamped to that weapon's
 * turn_limit_deg for the transition (e.g. double saber ±180°, saber ±90°).
 * The ground fan shows the allowed range; the yellow arrow is the requested
 * heading; a red flash + ghost arrow mark a clamped turn.
 *
 * Controls: Z/J normal · X/K strong · C/L special · WASD/arrows steer ·
 * R reset. Tunables persist to localStorage per weapon; "Copy GDScript"
 * exports a WEAPON_TYPE_CONFIGS-style snippet.
 */

const STORAGE_KEY = 'psz-combo-debug:v1';

type WeaponKey =
  | 'saber' | 'sword' | 'daggers' | 'claw' | 'dsaber' | 'spear' | 'slicer'
  | 'handgun' | 'mechgun' | 'rifle' | 'rod' | 'wand';

interface WeaponDef {
  id: WeaponKey;
  label: string;
  glb: string;         // file under assets/player/animations/
  prefix: string;      // animation clip prefix (male set)
  weaponType: number;  // WeaponData.WeaponType enum value
  defaults: Tuning;
}

interface Tuning {
  comboSteps: number;        // steps in the chain (1-3)
  windowOpenPct: number;     // chain window opens at this fraction of the swing clip
  windowDuration: number;    // seconds the window stays open (combo_window)
  strongWindup: number;      // wait-pose pause before a strong swing
  specialWindup: number;     // wait-pose pause before a special swing
  turnLimitDeg: number[];    // max |facing change| entering step 2, step 3
}

const tune = (
  windowDuration: number, turnLimitDeg: [number, number],
  comboSteps = 3, windowOpenPct = 0.55, strongWindup = 0.4, specialWindup = 0.4,
): Tuning => ({ comboSteps, windowOpenPct, windowDuration, strongWindup, specialWindup, turnLimitDeg });

// combo_window defaults come from CombatManager.WEAPON_TYPE_CONFIGS; the
// turn limits are proposals (the game has no turn clamp yet).
const WEAPONS: WeaponDef[] = [
  { id: 'saber',   label: 'Saber',        glb: 'saver_m',      prefix: 'pmsa', weaponType: 0,  defaults: tune(0.5,  [90, 90]) },
  { id: 'sword',   label: 'Sword',        glb: 'sword_m',      prefix: 'pmsw', weaponType: 1,  defaults: tune(0.6,  [60, 60]) },
  { id: 'daggers', label: 'Daggers',      glb: 'dagger_m',     prefix: 'pmda', weaponType: 2,  defaults: tune(0.4,  [120, 120]) },
  { id: 'claw',    label: 'Claw',         glb: 'claw_m',       prefix: 'pmcl', weaponType: 3,  defaults: tune(0.35, [120, 120]) },
  { id: 'dsaber',  label: 'Double Saber', glb: 'dsaver_m',     prefix: 'pmds', weaponType: 4,  defaults: tune(0.45, [180, 180]) },
  { id: 'spear',   label: 'Spear',        glb: 'spear_m',      prefix: 'pmsp', weaponType: 5,  defaults: tune(0.5,  [75, 75]) },
  { id: 'slicer',  label: 'Slicer',       glb: 'slicer_m',     prefix: 'pmsl', weaponType: 6,  defaults: tune(0.5,  [90, 90]) },
  { id: 'handgun', label: 'Handgun',      glb: 'handgun_m',    prefix: 'pmhg', weaponType: 9,  defaults: tune(0.4,  [180, 180]) },
  { id: 'mechgun', label: 'Mechgun',      glb: 'machinegun_m', prefix: 'pmmg', weaponType: 10, defaults: tune(0.3,  [180, 180]) },
  { id: 'rifle',   label: 'Rifle',        glb: 'rifle_m',      prefix: 'pmar', weaponType: 11, defaults: tune(0.6,  [45, 45]) },
  { id: 'rod',     label: 'Rod',          glb: 'rod_m',        prefix: 'pmro', weaponType: 14, defaults: tune(0.5,  [90, 90]) },
  { id: 'wand',    label: 'Wand',         glb: 'wand_m',       prefix: 'pmwa', weaponType: 15, defaults: tune(0.5,  [90, 90]) },
];

type AttackType = 'normal' | 'strong' | 'special';

const ATTACK_COLORS: Record<AttackType, string> = {
  normal: '#4f4', strong: '#fc4', special: '#c8f',
};

interface Config {
  weapon: WeaponKey;
  perWeapon: Partial<Record<WeaponKey, Tuning>>;
}

const DEFAULT_CONFIG: Config = { weapon: 'saber', perWeapon: {} };

function loadConfig(): Config {
  if (typeof window === 'undefined') return DEFAULT_CONFIG;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CONFIG;
    const parsed = JSON.parse(raw) as Partial<Config>;
    const cfg: Config = { ...DEFAULT_CONFIG, ...parsed };
    if (!WEAPONS.some((w) => w.id === cfg.weapon)) cfg.weapon = 'saber';
    if (typeof cfg.perWeapon !== 'object' || cfg.perWeapon === null) cfg.perWeapon = {};
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

function getTuning(cfg: Config, weapon: WeaponKey): Tuning {
  const def = WEAPONS.find((w) => w.id === weapon)!;
  const stored = cfg.perWeapon[weapon];
  const t: Tuning = { ...def.defaults, ...(stored || {}) };
  if (!Array.isArray(t.turnLimitDeg) || t.turnLimitDeg.length !== 2) {
    t.turnLimitDeg = def.defaults.turnLimitDeg.slice();
  }
  return t;
}

/** Wrap an angle difference into [-PI, PI]. */
function wrapAngle(a: number): number {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

const rad2deg = (r: number) => (r * 180) / Math.PI;
const deg2rad = (d: number) => (d * Math.PI) / 180;

/**
 * Strip the 000_Root position track. Same reasoning as dodge-debug: the PSO
 * clips bake root translation that fights the group transform we drive, and
 * for this tool the character must stay parked at the origin so the turning
 * is the only spatial change.
 */
function stripRootMotion(clip: THREE.AnimationClip): void {
  clip.tracks = clip.tracks.filter((t) => {
    if (t.name === '000_Root.position') return false;
    if (t.name.endsWith('/000_Root.position')) return false;
    return true;
  });
}

// ---------------------------------------------------------------------------
// Simulation state (mutable, lives in a ref — the rAF loop drives it)
// ---------------------------------------------------------------------------

type Phase = 'idle' | 'windup' | 'swing';

interface PressMarker {
  step: number;        // which swing bar the press landed on
  t: number;           // seconds into that swing clip
  ok: boolean;         // accepted (chained)?
}

interface Sim {
  phase: Phase;
  step: number;                 // current combo step (1-based) while attacking
  attackType: AttackType;       // type of the CURRENT swing
  elapsed: number;              // seconds into current phase (windup or swing)
  clipLen: number;              // current swing clip length
  windowOpen: boolean;
  windowOpened: boolean;        // opened already this step
  windowTimer: number;          // seconds since window opened
  yaw: number;                  // committed facing (radians)
  displayYaw: number;           // lerped visual yaw
  desiredYaw: number | null;    // steering input heading (null = no input)
  ghostYaw: number | null;      // requested-but-clamped heading (red arrow)
  ghostFade: number;            // seconds left on the ghost arrow
  ringFlash: { color: THREE.Color; ttl: number } | null;
  markers: PressMarker[];       // presses this combo (for the timeline)
  keysDown: Set<string>;
  comboCount: number;           // completed full combos (session stat)
  missCount: number;
}

function freshSim(): Sim {
  return {
    phase: 'idle', step: 0, attackType: 'normal',
    elapsed: 0, clipLen: 0,
    windowOpen: false, windowOpened: false, windowTimer: 0,
    yaw: Math.PI, displayYaw: Math.PI, desiredYaw: null,
    ghostYaw: null, ghostFade: 0, ringFlash: null,
    markers: [], keysDown: new Set(),
    comboCount: 0, missCount: 0,
  };
}

interface LogEntry {
  id: number;
  color: string;
  text: string;
}

// ---------------------------------------------------------------------------

interface SceneRefs {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  playerGroup: THREE.Group;      // yaw applied here
  mixer: THREE.AnimationMixer | null;
  actions: Record<string, THREE.AnimationAction>;
  currentAction: THREE.AnimationAction | null;
  clips: Record<string, THREE.AnimationClip>;
  ring: THREE.Mesh;
  ringMat: THREE.MeshBasicMaterial;
  fan: THREE.Mesh;
  fanMat: THREE.MeshBasicMaterial;
  fanLimitRad: number;           // limit the fan geometry was built for
  facingArrow: THREE.ArrowHelper;
  desiredArrow: THREE.ArrowHelper;
  ghostArrow: THREE.ArrowHelper;
}

function buildFanGeometry(limitRad: number, radius = 1.9, segments = 32): THREE.BufferGeometry {
  // Triangle fan spanning [-limit, +limit] around local +Z, flat on the
  // ground. Rotating the mesh by yaw aims it at the current facing.
  const verts: number[] = [];
  const y = 0.02;
  for (let i = 0; i < segments; i++) {
    const a0 = -limitRad + (2 * limitRad * i) / segments;
    const a1 = -limitRad + (2 * limitRad * (i + 1)) / segments;
    verts.push(0, y, 0);
    verts.push(Math.sin(a0) * radius, y, Math.cos(a0) * radius);
    verts.push(Math.sin(a1) * radius, y, Math.cos(a1) * radius);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
  return geo;
}

export default function ComboDebug() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const simRef = useRef<Sim>(freshSim());
  const logIdRef = useRef(0);

  const [config, setConfig] = useState<Config>(loadConfig);
  const [speed, setSpeed] = useState(1.0);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  // HUD snapshot pushed from the rAF loop
  const [hud, setHud] = useState({
    phase: 'idle' as Phase, step: 0, elapsed: 0, clipLen: 0,
    windowOpen: false, windowT: 0, yawDeg: 180, desiredDeg: null as number | null,
    markers: [] as PressMarker[], attackType: 'normal' as AttackType,
    combos: 0, misses: 0,
  });
  const [clipLens, setClipLens] = useState<number[]>([]);

  const weaponDef = WEAPONS.find((w) => w.id === config.weapon)!;
  const tuning = getTuning(config, config.weapon);

  // Refs so the sim loop / input handlers always see current values
  const tuningRef = useRef(tuning);
  tuningRef.current = tuning;
  const weaponRef = useRef(weaponDef);
  weaponRef.current = weaponDef;
  const speedRef = useRef(speed);
  speedRef.current = speed;

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
    } catch { /* ignore quota */ }
  }, [config]);

  const pushLog = useCallback((text: string, color = '#aaa') => {
    logIdRef.current += 1;
    const id = logIdRef.current;
    setLog((prev) => [{ id, color, text }, ...prev].slice(0, 12));
  }, []);

  const setTuning = (patch: Partial<Tuning>) => {
    setConfig((cfg) => ({
      ...cfg,
      perWeapon: {
        ...cfg.perWeapon,
        [cfg.weapon]: { ...getTuning(cfg, cfg.weapon), ...patch },
      },
    }));
  };

  const setTurnLimit = (idx: number, deg: number) => {
    const next = tuning.turnLimitDeg.slice();
    next[idx] = deg;
    setTuning({ turnLimitDeg: next });
  };

  // -------------------------------------------------------------------------
  // Animation helpers (operate on sceneRef)
  // -------------------------------------------------------------------------

  const playClip = useCallback((name: string, loop: boolean) => {
    const s = sceneRef.current;
    if (!s || !s.actions[name]) return 0;
    if (s.currentAction && s.currentAction !== s.actions[name]) {
      s.currentAction.fadeOut(0.06);
    }
    const action = s.actions[name];
    action.reset();
    action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    action.clampWhenFinished = !loop;
    action.fadeIn(0.06);
    action.play();
    s.currentAction = action;
    return s.clips[name]?.duration ?? 0;
  }, []);

  const playIdle = useCallback(() => {
    playClip(`${weaponRef.current.prefix}_wait`, true);
  }, [playClip]);

  const startSwing = useCallback((step: number) => {
    const sim = simRef.current;
    const len = playClip(`${weaponRef.current.prefix}_atk${step}`, false);
    sim.phase = 'swing';
    sim.elapsed = 0;
    sim.clipLen = len > 0 ? len : 0.5;
    sim.windowOpen = false;
    sim.windowOpened = false;
    sim.windowTimer = 0;
  }, [playClip]);

  const ringFlash = useCallback((hex: number) => {
    simRef.current.ringFlash = { color: new THREE.Color(hex), ttl: 0.35 };
  }, []);

  const resetToIdle = useCallback(() => {
    const sim = simRef.current;
    sim.phase = 'idle';
    sim.step = 0;
    sim.windowOpen = false;
    sim.windowOpened = false;
    playIdle();
  }, [playIdle]);

  /** Apply the inter-swing turn: clamp requested heading change to ±limit. */
  const applyTurn = useCallback((enteringStep: number) => {
    const sim = simRef.current;
    if (sim.desiredYaw === null) return;
    const t = tuningRef.current;
    if (enteringStep <= 1) {
      // Starting a combo from idle — free aim, no clamp.
      sim.yaw = sim.desiredYaw;
      return;
    }
    const limitIdx = Math.min(enteringStep - 2, t.turnLimitDeg.length - 1);
    const limit = deg2rad(t.turnLimitDeg[limitIdx] ?? 90);
    const delta = wrapAngle(sim.desiredYaw - sim.yaw);
    const clamped = Math.max(-limit, Math.min(limit, delta));
    if (Math.abs(delta) > limit + 1e-4) {
      sim.ghostYaw = sim.desiredYaw;
      sim.ghostFade = 0.8;
      pushLog(
        `step ${enteringStep}: turn ${rad2deg(delta).toFixed(0)}° requested → clamped to ${rad2deg(clamped).toFixed(0)}° (limit ±${t.turnLimitDeg[limitIdx]}°)`,
        '#f88',
      );
    }
    sim.yaw = wrapAngle(sim.yaw + clamped);
  }, [pushLog]);

  /** Begin step N as the given type: wind-up first for strong/special. */
  const beginStep = useCallback((step: number, type: AttackType) => {
    const sim = simRef.current;
    const t = tuningRef.current;
    sim.step = step;
    sim.attackType = type;
    const windup = type === 'strong' ? t.strongWindup : type === 'special' ? t.specialWindup : 0;
    if (windup > 0.001) {
      sim.phase = 'windup';
      sim.elapsed = 0;
      sim.clipLen = windup;
      sim.windowOpen = false;
      sim.windowOpened = false;
      playClip(`${weaponRef.current.prefix}_wait`, true);
    } else {
      startSwing(step);
    }
  }, [playClip, startSwing]);

  const pressAttack = useCallback((type: AttackType) => {
    const sim = simRef.current;
    const t = tuningRef.current;
    if (isLoading) return;

    if (sim.phase === 'idle') {
      sim.markers = [];
      applyTurn(1);
      beginStep(1, type);
      ringFlash(type === 'normal' ? 0x33ff66 : type === 'strong' ? 0xffcc33 : 0xcc88ff);
      pushLog(`combo start — ${type} atk1`, ATTACK_COLORS[type]);
      return;
    }

    if (sim.phase === 'windup') return; // committed: wind-up eats inputs

    // phase === 'swing'
    if (sim.windowOpen && sim.step < t.comboSteps) {
      const intoWindow = sim.windowTimer;
      sim.markers.push({ step: sim.step, t: sim.elapsed, ok: true });
      sim.windowOpen = false;
      applyTurn(sim.step + 1);
      const next = sim.step + 1;
      beginStep(next, type);
      ringFlash(type === 'normal' ? 0x33ff66 : type === 'strong' ? 0xffcc33 : 0xcc88ff);
      pushLog(
        `chained → ${type} atk${next} (${(intoWindow * 1000).toFixed(0)}ms into ${(t.windowDuration * 1000).toFixed(0)}ms window)`,
        ATTACK_COLORS[type],
      );
      return;
    }

    // Ignored press — diagnose why so timing is learnable.
    sim.markers.push({ step: sim.step, t: sim.elapsed, ok: false });
    if (sim.step >= t.comboSteps) {
      pushLog(`ignored — final step, nothing to chain`, '#888');
    } else if (!sim.windowOpened) {
      const openAt = sim.clipLen * t.windowOpenPct;
      pushLog(`too early — window opens in ${((openAt - sim.elapsed) * 1000).toFixed(0)}ms`, '#f96');
    } else {
      pushLog(`too late — window already closed`, '#f96');
    }
  }, [isLoading, applyTurn, beginStep, ringFlash, pushLog]);

  const pressAttackRef = useRef(pressAttack);
  pressAttackRef.current = pressAttack;
  const resetRef = useRef(resetToIdle);
  resetRef.current = resetToIdle;

  // -------------------------------------------------------------------------
  // Keyboard input
  // -------------------------------------------------------------------------

  useEffect(() => {
    const DIR_KEYS = ['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'];
    const onDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      if (DIR_KEYS.includes(e.code)) {
        e.preventDefault();
        simRef.current.keysDown.add(e.code);
        return;
      }
      if (e.repeat) return;
      if (e.code === 'KeyZ' || e.code === 'KeyJ') pressAttackRef.current('normal');
      else if (e.code === 'KeyX' || e.code === 'KeyK') pressAttackRef.current('strong');
      else if (e.code === 'KeyC' || e.code === 'KeyL') pressAttackRef.current('special');
      else if (e.code === 'KeyR') resetRef.current();
    };
    const onUp = (e: KeyboardEvent) => {
      simRef.current.keysDown.delete(e.code);
    };
    window.addEventListener('keydown', onDown);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onDown);
      window.removeEventListener('keyup', onUp);
    };
  }, []);

  // -------------------------------------------------------------------------
  // Three.js scene + sim loop
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 100);
    // 3/4 view from +Z: screen-up ≈ world -Z, screen-right = +X.
    camera.position.set(0, 5.2, 5.2);
    camera.lookAt(0, 0.8, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(3, 6, 4);
    scene.add(dir);

    const grid = new THREE.GridHelper(12, 24, 0x444466, 0x222238);
    scene.add(grid);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.8, 0);

    const playerGroup = new THREE.Group();
    scene.add(playerGroup);

    // Combo ring (mirrors the in-game _combo_ring): flat ring around the feet.
    const ringMat = new THREE.MeshBasicMaterial({
      color: 0x555577, transparent: true, opacity: 0.55, side: THREE.DoubleSide,
    });
    const ring = new THREE.Mesh(new THREE.RingGeometry(1.35, 1.5, 48), ringMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.015;
    scene.add(ring);

    // Turn-limit fan (geometry rebuilt when the limit changes).
    const fanMat = new THREE.MeshBasicMaterial({
      color: 0x33ff88, transparent: true, opacity: 0.14, side: THREE.DoubleSide, depthWrite: false,
    });
    const fan = new THREE.Mesh(buildFanGeometry(deg2rad(90)), fanMat);
    fan.visible = false;
    scene.add(fan);

    const facingArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.05, 0), 2.1, 0x44ccff, 0.35, 0.2);
    const desiredArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.08, 0), 1.7, 0xffee44, 0.3, 0.17);
    desiredArrow.visible = false;
    const ghostArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.08, 0), 1.7, 0xff4444, 0.3, 0.17);
    ghostArrow.visible = false;
    scene.add(facingArrow, desiredArrow, ghostArrow);

    sceneRef.current = {
      scene, camera, renderer, controls, playerGroup,
      mixer: null, actions: {}, currentAction: null, clips: {},
      ring, ringMat, fan, fanMat, fanLimitRad: deg2rad(90),
      facingArrow, desiredArrow, ghostArrow,
    };

    const clock = new THREE.Clock();
    let raf = 0;
    const RING_BASE = new THREE.Color(0x555577);
    const RING_WINDOW = new THREE.Color(0x33ff66);
    const RING_SWING = new THREE.Color(0xccccdd);

    const animate = () => {
      raf = requestAnimationFrame(animate);
      const rawDelta = Math.min(clock.getDelta(), 0.1);
      const delta = rawDelta * speedRef.current;
      const s = sceneRef.current;
      const sim = simRef.current;
      if (!s) return;
      const t = tuningRef.current;

      // ---- steering input → desiredYaw
      let kx = 0; let kz = 0;
      const kd = sim.keysDown;
      if (kd.has('KeyW') || kd.has('ArrowUp')) kz -= 1;
      if (kd.has('KeyS') || kd.has('ArrowDown')) kz += 1;
      if (kd.has('KeyA') || kd.has('ArrowLeft')) kx -= 1;
      if (kd.has('KeyD') || kd.has('ArrowRight')) kx += 1;
      sim.desiredYaw = (kx !== 0 || kz !== 0) ? Math.atan2(kx, kz) : null;

      // ---- state machine
      if (sim.phase === 'idle') {
        // Free rotation toward the stick, like walking.
        if (sim.desiredYaw !== null) sim.yaw = sim.desiredYaw;
      } else if (sim.phase === 'windup') {
        sim.elapsed += delta;
        if (sim.elapsed >= sim.clipLen) startSwingRef.current(sim.step);
      } else if (sim.phase === 'swing') {
        sim.elapsed += delta;
        const openAt = sim.clipLen * t.windowOpenPct;
        if (!sim.windowOpened && sim.step > 0 && sim.step < t.comboSteps && sim.elapsed >= openAt) {
          sim.windowOpen = true;
          sim.windowOpened = true;
          sim.windowTimer = 0;
        }
        if (sim.windowOpen) {
          sim.windowTimer += delta;
          if (sim.windowTimer >= t.windowDuration) {
            // Missed the rhythm — combo resets (matches player.gd timeout).
            sim.windowOpen = false;
            sim.missCount += 1;
            sim.ringFlash = { color: new THREE.Color(0xff3333), ttl: 0.35 };
            resetRef.current();
          }
        } else if (sim.step >= t.comboSteps && sim.elapsed >= sim.clipLen) {
          // Final step ran its full length — combo complete.
          sim.comboCount += 1;
          resetRef.current();
        }
      }

      // ---- visuals
      sim.displayYaw = sim.displayYaw + wrapAngle(sim.yaw - sim.displayYaw) * Math.min(1, delta * 14);
      s.playerGroup.rotation.y = sim.displayYaw;

      s.facingArrow.setDirection(new THREE.Vector3(Math.sin(sim.displayYaw), 0, Math.cos(sim.displayYaw)));
      if (sim.desiredYaw !== null) {
        s.desiredArrow.visible = true;
        s.desiredArrow.setDirection(new THREE.Vector3(Math.sin(sim.desiredYaw), 0, Math.cos(sim.desiredYaw)));
      } else {
        s.desiredArrow.visible = false;
      }
      if (sim.ghostFade > 0 && sim.ghostYaw !== null) {
        sim.ghostFade -= rawDelta;
        s.ghostArrow.visible = sim.ghostFade > 0;
        s.ghostArrow.setDirection(new THREE.Vector3(Math.sin(sim.ghostYaw), 0, Math.cos(sim.ghostYaw)));
      } else {
        s.ghostArrow.visible = false;
      }

      // Turn fan: while attacking (and another step remains), show the
      // allowed range for the NEXT chain around the committed facing.
      const showFan = sim.phase !== 'idle' && sim.step < t.comboSteps;
      s.fan.visible = showFan;
      if (showFan) {
        const limitIdx = Math.min(Math.max(sim.step - 1, 0), t.turnLimitDeg.length - 1);
        const limitRad = deg2rad(t.turnLimitDeg[limitIdx] ?? 90);
        if (Math.abs(limitRad - s.fanLimitRad) > 1e-3) {
          s.fan.geometry.dispose();
          s.fan.geometry = buildFanGeometry(limitRad);
          s.fanLimitRad = limitRad;
        }
        s.fan.rotation.y = sim.yaw;
        s.fanMat.opacity = sim.windowOpen ? 0.28 : 0.14;
      }

      // Ring color: window state + flash overrides.
      if (sim.ringFlash) {
        sim.ringFlash.ttl -= rawDelta;
        s.ringMat.color.copy(sim.ringFlash.color);
        s.ringMat.opacity = 0.8;
        if (sim.ringFlash.ttl <= 0) sim.ringFlash = null;
      } else {
        s.ringMat.opacity = 0.55;
        s.ringMat.color.copy(
          sim.phase === 'idle' ? RING_BASE : sim.windowOpen ? RING_WINDOW : RING_SWING,
        );
      }

      if (s.mixer) s.mixer.update(delta);
      controls.update();
      renderer.render(scene, camera);

      setHud({
        phase: sim.phase, step: sim.step, elapsed: sim.elapsed, clipLen: sim.clipLen,
        windowOpen: sim.windowOpen, windowT: sim.windowTimer,
        yawDeg: rad2deg(sim.yaw), desiredDeg: sim.desiredYaw === null ? null : rad2deg(sim.desiredYaw),
        markers: sim.markers.slice(), attackType: sim.attackType,
        combos: sim.comboCount, misses: sim.missCount,
      });
    };
    animate();

    const onResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', onResize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
      sceneRef.current = null;
    };
  }, []);

  // startSwing is defined after the effect body runs on mount; use a ref so
  // the loop (created once) always calls the current closure.
  const startSwingRef = useRef(startSwing);
  startSwingRef.current = startSwing;

  // -------------------------------------------------------------------------
  // Model + animation pack loading (per weapon)
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setIsLoading(true);
    setLoadError(null);
    setClipLens([]);
    simRef.current = { ...freshSim(), comboCount: simRef.current.comboCount, missCount: simRef.current.missCount };

    // Tear down previous model
    s.playerGroup.clear();
    s.mixer = null;
    s.actions = {};
    s.currentAction = null;
    s.clips = {};

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const modelPath = assetUrl('assets/player/pc_000/pc_000_000.glb');
    const animPath = assetUrl(`assets/player/animations/${weaponDef.glb}.glb`);
    const texPath = assetUrl('assets/player/pc_000/textures/pc_000_000.png');
    const prefix = weaponDef.prefix;
    let cancelled = false;

    loader.load(modelPath, (gltf) => {
      if (cancelled || !sceneRef.current) return;
      const tex = texLoader.load(texPath, (tx) => {
        tx.magFilter = THREE.NearestFilter;
        tx.minFilter = THREE.NearestFilter;
        tx.flipY = false;
        tx.colorSpace = THREE.SRGBColorSpace;
      });
      gltf.scene.traverse((child) => {
        const m = child as THREE.Mesh;
        if (m.isMesh && m.material) {
          const mat = m.material as THREE.MeshBasicMaterial;
          mat.map = tex;
          mat.needsUpdate = true;
        }
      });
      s.playerGroup.add(gltf.scene);

      loader.load(animPath, (animGltf) => {
        if (cancelled || !sceneRef.current) return;
        const wanted = [
          `${prefix}_wait`,
          `${prefix}_atk1`, `${prefix}_atk2`, `${prefix}_atk3`,
        ];
        const missing: string[] = [];
        const mixer = new THREE.AnimationMixer(gltf.scene);
        for (const name of wanted) {
          const clip = animGltf.animations.find((a) => a.name === name);
          if (!clip) { missing.push(name); continue; }
          stripRootMotion(clip);
          s.clips[name] = clip;
          s.actions[name] = mixer.clipAction(clip);
        }
        if (!s.clips[`${prefix}_wait`] || !s.clips[`${prefix}_atk1`]) {
          setLoadError(`Missing clips: ${missing.join(', ')} in ${weaponDef.glb}.glb`);
          setIsLoading(false);
          return;
        }
        s.mixer = mixer;
        setClipLens([1, 2, 3].map((n) => s.clips[`${prefix}_atk${n}`]?.duration ?? 0));
        setIsLoading(false);
        resetRef.current();
      }, undefined, (err) => {
        setLoadError(`Failed to load animation pack: ${err}`);
        setIsLoading(false);
      });
    }, undefined, (err) => {
      setLoadError(`Failed to load model: ${err}`);
      setIsLoading(false);
    });

    return () => { cancelled = true; };
  }, [config.weapon, weaponDef.glb, weaponDef.prefix]);

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  const gdscriptFor = useCallback((w: WeaponDef, t: Tuning): string => {
    const lines: string[] = [];
    lines.push(`\t${w.weaponType}: {  # ${w.label.toUpperCase()} — combo timing/turn tuning (web #/combo-debug)`);
    lines.push(`\t\t"combo_steps": ${t.comboSteps},`);
    lines.push(`\t\t"combo_window_open_pct": ${t.windowOpenPct.toFixed(2)},  # window opens at ${(t.windowOpenPct * 100).toFixed(0)}% of the swing clip`);
    lines.push(`\t\t"combo_window": ${t.windowDuration.toFixed(2)},  # seconds the chain window stays open`);
    lines.push(`\t\t"strong_windup": ${t.strongWindup.toFixed(2)},  # wait-pose pause before a strong swing`);
    lines.push(`\t\t"special_windup": ${t.specialWindup.toFixed(2)},`);
    lines.push(`\t\t"turn_limit_deg": [${t.turnLimitDeg.map((d) => d.toFixed(1)).join(', ')}],  # max facing change entering steps 2, 3`);
    lines.push(`\t},`);
    return lines.join('\n');
  }, []);

  const copyGdscript = useCallback(() => {
    const out = [
      `# Combo tuning — merge into CombatManager.WEAPON_TYPE_CONFIGS`,
      gdscriptFor(weaponDef, tuning),
    ].join('\n');
    navigator.clipboard.writeText(out);
    pushLog(`copied GDScript for ${weaponDef.label}`, '#6b8afd');
  }, [weaponDef, tuning, gdscriptFor, pushLog]);

  const copyAllGdscript = useCallback(() => {
    const out = [
      `# Combo tuning (all weapons) — merge into CombatManager.WEAPON_TYPE_CONFIGS`,
      ...WEAPONS.map((w) => gdscriptFor(w, getTuning(config, w.id))),
    ].join('\n');
    navigator.clipboard.writeText(out);
    pushLog('copied GDScript for all weapons', '#6b8afd');
  }, [config, gdscriptFor, pushLog]);

  const resetWeapon = () => {
    if (!confirm(`Reset ${weaponDef.label} tuning to defaults?`)) return;
    setConfig((cfg) => {
      const next = { ...cfg.perWeapon };
      delete next[cfg.weapon];
      return { ...cfg, perWeapon: next };
    });
  };

  // -------------------------------------------------------------------------
  // Timeline rendering helpers
  // -------------------------------------------------------------------------

  const PX_PER_SEC = 130;
  const windup = hud.attackType === 'strong' ? tuning.strongWindup
    : hud.attackType === 'special' ? tuning.specialWindup : 0;

  const renderStepBar = (stepNum: number) => {
    const len = clipLens[stepNum - 1] ?? 0;
    if (len <= 0) return null;
    const openAt = len * tuning.windowOpenPct;
    const isLast = stepNum >= tuning.comboSteps;
    const winStart = openAt;
    const winEnd = openAt + tuning.windowDuration; // may overflow the clip
    const totalW = Math.max(len, isLast ? len : winEnd) * PX_PER_SEC;
    const active = hud.step === stepNum && hud.phase === 'swing';
    const markers = hud.markers.filter((m) => m.step === stepNum);
    return (
      <div key={stepNum} style={{ display: 'flex', alignItems: 'center', gap: 8, opacity: stepNum > tuning.comboSteps ? 0.25 : 1 }}>
        <span style={{ width: 66, fontSize: 11, color: active ? '#fff' : '#888', fontWeight: active ? 'bold' : 'normal' }}>
          atk{stepNum} <span style={{ color: '#666' }}>{len.toFixed(2)}s</span>
        </span>
        <div style={{ position: 'relative', height: 22, width: totalW, background: '#1a1a2e', borderRadius: 3, overflow: 'hidden', border: active ? '1px solid #6b8afd' : '1px solid #26263e' }}>
          {/* clip body */}
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: len * PX_PER_SEC, background: '#33334f' }} />
          {/* chain window (green) — absent on the last step */}
          {!isLast && (
            <div style={{
              position: 'absolute', left: winStart * PX_PER_SEC, top: 0, bottom: 0,
              width: (winEnd - winStart) * PX_PER_SEC,
              background: 'rgba(60,220,110,0.45)', borderLeft: '1px solid #3c6',
            }} />
          )}
          {/* clip end line */}
          <div style={{ position: 'absolute', left: len * PX_PER_SEC - 1, top: 0, bottom: 0, width: 1, background: '#667' }} />
          {/* live cursor */}
          {active && (
            <div style={{ position: 'absolute', left: Math.min(hud.elapsed, Math.max(len, winEnd)) * PX_PER_SEC - 1, top: 0, bottom: 0, width: 2, background: '#fff' }} />
          )}
          {/* press markers */}
          {markers.map((m, i) => (
            <div key={i} style={{
              position: 'absolute', left: m.t * PX_PER_SEC - 1, top: 2, bottom: 2, width: 2,
              background: m.ok ? '#4f4' : '#f66',
            }} />
          ))}
        </div>
        {!isLast && (
          <span style={{ fontSize: 10, color: '#4a8', whiteSpace: 'nowrap' }}>
            window {winStart.toFixed(2)}–{winEnd.toFixed(2)}s
          </span>
        )}
      </div>
    );
  };

  const phaseLabel = hud.phase === 'idle' ? 'IDLE'
    : hud.phase === 'windup' ? `WIND-UP (${hud.attackType})`
    : `SWING ${hud.step}/${tuning.comboSteps} (${hud.attackType})`;

  const sliderRow = (
    label: string, value: number, min: number, max: number, step: number,
    onChange: (v: number) => void, fmt: (v: number) => string,
  ) => (
    <div style={{ marginBottom: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: '#aaa', marginBottom: 2 }}>
        <span>{label}</span>
        <span style={{ color: '#fff', fontVariantNumeric: 'tabular-nums' }}>{fmt(value)}</span>
      </div>
      <input
        type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ width: '100%' }}
      />
    </div>
  );

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: '16px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: '16px', height: '100%' }}>
        {/* Center — viewport + timeline */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
          <div style={{
            background: '#2d2d44', borderRadius: 8, padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16,
          }}>
            <span style={{ fontSize: 14, fontWeight: 'bold', color: '#6bf' }}>
              Combo Debug — {weaponDef.label} ({weaponDef.prefix}_atk1..{tuning.comboSteps})
            </span>
            <span style={{ fontSize: 12, color: hud.windowOpen ? '#4f4' : '#888', fontWeight: hud.windowOpen ? 'bold' : 'normal' }}>
              {phaseLabel}{hud.windowOpen && ` · WINDOW OPEN ${((tuning.windowDuration - hud.windowT) * 1000).toFixed(0)}ms left`}
            </span>
            <span style={{ fontSize: 12, color: '#888' }}>
              facing {hud.yawDeg.toFixed(0)}°{hud.desiredDeg !== null && ` · stick ${hud.desiredDeg.toFixed(0)}°`}
              {' · '}{hud.combos} combos · {hud.misses} misses
            </span>
            {isLoading && <span style={{ color: '#888', fontSize: 12 }}>(loading…)</span>}
            {loadError && <span style={{ color: '#f88', fontSize: 12 }}>{loadError}</span>}
          </div>

          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: 8, overflow: 'hidden', position: 'relative' }} ref={containerRef}>
            <div style={{
              position: 'absolute', left: 10, bottom: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              <span style={{ color: ATTACK_COLORS.normal }}>Z</span> normal ·{' '}
              <span style={{ color: ATTACK_COLORS.strong }}>X</span> strong ·{' '}
              <span style={{ color: ATTACK_COLORS.special }}>C</span> special ·{' '}
              WASD/arrows steer · R reset
            </div>
          </div>

          {/* Timeline */}
          <div style={{ background: '#2d2d44', borderRadius: 8, padding: 10, overflowX: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
              <span style={{ fontSize: 12, color: '#6b8afd', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                Swing timeline — green = chain window, white = cursor, ticks = your presses
              </span>
              {windup > 0 && hud.phase === 'windup' && (
                <span style={{ fontSize: 11, color: '#fc4' }}>
                  wind-up {hud.elapsed.toFixed(2)} / {windup.toFixed(2)}s
                </span>
              )}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[1, 2, 3].map((n) => (n <= tuning.comboSteps ? renderStepBar(n) : null))}
            </div>
          </div>
        </div>

        {/* Right — controls */}
        <div style={{
          width: 330, background: '#2d2d44', borderRadius: 8, padding: 12,
          overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 14,
        }}>
          {/* Weapon */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Weapon</h3>
            <select
              value={config.weapon}
              onChange={(e) => setConfig((c) => ({ ...c, weapon: e.target.value as WeaponKey }))}
              style={{
                width: '100%', padding: 8, background: '#1a1a2e', color: '#fff',
                border: '1px solid #444', borderRadius: 4, fontSize: 12,
              }}
            >
              {WEAPONS.map((w) => (
                <option key={w.id} value={w.id}>{w.label} ({w.prefix})</option>
              ))}
            </select>
          </div>

          {/* Attack buttons (mouse alternative to Z/X/C) */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Attack</h3>
            <div style={{ display: 'flex', gap: 6 }}>
              {(['normal', 'strong', 'special'] as AttackType[]).map((tp) => (
                <button key={tp} onClick={() => pressAttack(tp)} style={{
                  flex: 1, padding: '10px 4px', background: '#1a1a2e',
                  border: `1px solid ${ATTACK_COLORS[tp]}`, borderRadius: 4,
                  color: ATTACK_COLORS[tp], cursor: 'pointer', fontSize: 12, fontWeight: 'bold',
                }}>
                  {tp}
                </button>
              ))}
            </div>
            <button onClick={resetToIdle} style={{
              marginTop: 6, width: '100%', padding: 6, background: '#1a1a2e',
              border: '1px solid #444', borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 11,
            }}>
              Reset combo (R)
            </button>
          </div>

          {/* Timing */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Timing — {weaponDef.label}
            </h3>
            {sliderRow('Window opens at (% of swing)', tuning.windowOpenPct, 0.2, 0.95, 0.01,
              (v) => setTuning({ windowOpenPct: v }), (v) => `${(v * 100).toFixed(0)}%`)}
            {sliderRow('Window duration', tuning.windowDuration, 0.1, 1.0, 0.01,
              (v) => setTuning({ windowDuration: v }), (v) => `${v.toFixed(2)}s`)}
            {sliderRow('Strong wind-up', tuning.strongWindup, 0, 1.0, 0.05,
              (v) => setTuning({ strongWindup: v }), (v) => `${v.toFixed(2)}s`)}
            {sliderRow('Special wind-up', tuning.specialWindup, 0, 1.0, 0.05,
              (v) => setTuning({ specialWindup: v }), (v) => `${v.toFixed(2)}s`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              In-game today: opens at 55% (COMBO_WINDOW_OPEN_PCT), 0.35s duration
              (COMBO_WINDOW_DURATION), 0.4s special delay — player.gd.
            </div>
          </div>

          {/* Turn limits */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Turn limit between swings
            </h3>
            {sliderRow('Entering swing 2 (±deg)', tuning.turnLimitDeg[0] ?? 90, 0, 180, 5,
              (v) => setTurnLimit(0, v), (v) => `±${v.toFixed(0)}°`)}
            {tuning.comboSteps >= 3 && sliderRow('Entering swing 3 (±deg)', tuning.turnLimitDeg[1] ?? 90, 0, 180, 5,
              (v) => setTurnLimit(1, v), (v) => `±${v.toFixed(0)}°`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Facing locks when a swing starts. Hold a direction during the swing —
              on chain, the yaw snaps toward it, clamped to this limit (green fan).
              Clamped turns flash a red ghost arrow. First attack from idle aims freely.
            </div>
          </div>

          {/* Playback */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Playback</h3>
            {sliderRow('Speed', speed, 0.25, 1.5, 0.05, setSpeed, (v) => `${v.toFixed(2)}×`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Slows the whole sim (animation + windows) to inspect the rhythm. Not exported.
            </div>
          </div>

          {/* Event log */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Log</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minHeight: 60 }}>
              {log.length === 0 && <span style={{ fontSize: 11, color: '#555' }}>Press Z / X / C to attack…</span>}
              {log.map((e) => (
                <span key={e.id} style={{ fontSize: 11, color: e.color, fontVariantNumeric: 'tabular-nums' }}>{e.text}</span>
              ))}
            </div>
          </div>

          {/* Export / reset */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <button onClick={copyGdscript} style={{
              padding: 10, background: '#2a4a6a', border: '1px solid #6b8afd',
              borderRadius: 4, color: '#fff', cursor: 'pointer', fontSize: 12, fontWeight: 'bold',
            }}>
              Copy GDScript — {weaponDef.label}
            </button>
            <button onClick={copyAllGdscript} style={{
              padding: 8, background: '#1a1a2e', border: '1px solid #6b8afd',
              borderRadius: 4, color: '#9bf', cursor: 'pointer', fontSize: 12,
            }}>
              Copy GDScript — all weapons
            </button>
            <button onClick={resetWeapon} style={{
              padding: 8, background: '#1a1a2e', border: '1px solid #444',
              borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 12,
            }}>
              Reset {weaponDef.label} to defaults
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
