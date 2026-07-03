import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Combat room — the design mock for weapon HIT DETECTION and INTER-SWING
 * TURNING, playable against training dummies. Godot implementation follows
 * this contract (same flow as #/combo-debug → #474).
 *
 * Hit model (PSO:BB RE, check_enemy_is_targetable + ItemPMT; see
 * wiki.pioneer2.net/w/Weapons):
 *  - each weapon has a targeting cone: apex pulled BACK behind the player by
 *    vDist along -facing, reach hDist + vDist, half-angle hAngle. The
 *    target's own hitbox radius extends the reach (dist ≤ reach + radius).
 *  - all dummies passing the cone are "targetable"; the nearest is the
 *    primary (bright reticle). A swing hits up to maxTargets of the nearest
 *    targetables — resolved once, at the swing's damaging frame.
 *  - vertical cone params exist in PSO but the room is a flat arena; they
 *    ride along in the export untouched.
 *
 * Turning (PSZ design, PSO-informed):
 *  - facing locks during a swing. On chain, if target-snap is ON and a
 *    primary target exists, facing snaps to it (PSO behavior — unclamped);
 *    otherwise held stick steers the facing clamped to the weapon's
 *    per-transition turn limit (green fan). First swing from idle aims free.
 *
 * Combos use the SHIPPED queue model (#474 + #475): tiers are fractions of
 *  the swing ([just_start, just_end) = just, then normal), a press QUEUES
 *  the chain which fires at swing end, miss-early FUMBLES the swing.
 *
 * Target-info HUD (bottom-left, PSZ panel style): shows the primary target —
 *  enemy name + HP bar, or a ground item's name. Contract: no primary target
 *  → the panel does not render at all; the Quick Menu (Q) owns that corner —
 *  while it is open the target panel MUST NOT render (menu takes priority).
 *  Ground items join the cone scan as targetable entities (PSO's reticle
 *  system handles item pickup through the same targeting-info slots), but
 *  swings only ever hit enemies.
 *
 * Controls: Z normal · X strong · C special · WASD/arrows steer · R reset ·
 * drag dummies to reposition. Tunables persist per weapon type; export as
 * GDScript.
 */

const STORAGE_KEY = 'psz-combat-room:v1';

type Gender = 'm' | 'w';
type WeaponKey =
  | 'saber' | 'sword' | 'daggers' | 'claw' | 'dsaber' | 'spear' | 'slicer'
  | 'handgun' | 'mechgun' | 'rifle' | 'rod' | 'wand';

interface Tuning {
  comboSteps: number;
  justStart: number;         // fraction of swing — just tier opens (chain accept opens)
  justEnd: number;           // fraction — just tier ends, normal tier begins
  justMult: number;
  strongWindup: number;
  specialWindup: number;
  turnLimitDeg: number[];    // max |facing change| entering steps 2, 3 (free aim)
  targetSnap: boolean;       // chain re-aims at the primary target (PSO behavior)
  // Hit detection (PSO cone model; meters/degrees)
  hDist: number;             // horizontal reach from the apex
  vDist: number;             // apex pull-back behind the player (also extends reach)
  hAngleDeg: number;         // half-angle of the cone
  maxTargets: number;        // targets a single swing can hit
  damagingFrac: number[];    // fraction of each step's clip where the hit lands
  hitsPerStep: number[];     // hits per target per step (daggers multi-hit etc)
}

interface WeaponDef {
  id: WeaponKey;
  label: string;
  glbBase: string;
  weaponType: number;
  defaults: Tuning;
}

const tune = (
  hit: { h: number; v: number; a: number; mt: number },
  turnLimitDeg: [number, number],
  justStart = 0.55, justEnd = 0.70,
  damagingFrac: [number, number, number] = [0.4, 0.4, 0.45],
  hitsPerStep: [number, number, number] = [1, 1, 1],
): Tuning => ({
  comboSteps: 3, justStart, justEnd, justMult: 1.3,
  strongWindup: 0.4, specialWindup: 0.4,
  turnLimitDeg, targetSnap: true,
  hDist: hit.h, vDist: hit.v, hAngleDeg: hit.a, maxTargets: hit.mt,
  damagingFrac: [...damagingFrac], hitsPerStep: [...hitsPerStep],
});

// Hit defaults loosely scaled from the ItemPMT numbers the wiki tabulates
// (PSO units ÷ 10 ≈ meters; e.g. Handgun 170 → 17 m, Mechgun 85 → 8.5 m
// with the wide "auto-aim" angle; Partisan 40° / Sword 45° half-angles).
// Melee reach lines up with the current WEAPON_TYPE_CONFIGS hitboxes
// (offset 1.5–1.8 + depth 2.0–2.5). All of it is what this room exists to
// tune. Combo tiers: saber [0.45,0.60) per data/combo_configs, rest default.
const WEAPONS: WeaponDef[] = [
  { id: 'saber',   label: 'Saber',        glbBase: 'saver',      weaponType: 0,  defaults: tune({ h: 2.4, v: 0.5, a: 30, mt: 1 }, [90, 90], 0.45, 0.60) },
  { id: 'sword',   label: 'Sword',        glbBase: 'sword',      weaponType: 1,  defaults: tune({ h: 3.0, v: 1.0, a: 45, mt: 3 }, [60, 60]) },
  { id: 'daggers', label: 'Daggers',      glbBase: 'dagger',     weaponType: 2,  defaults: tune({ h: 2.0, v: 0.4, a: 22, mt: 1 }, [120, 120], 0.55, 0.70, [0.35, 0.35, 0.4], [2, 2, 3]) },
  { id: 'claw',    label: 'Claw',         glbBase: 'claw',       weaponType: 3,  defaults: tune({ h: 1.8, v: 0.3, a: 20, mt: 1 }, [120, 120], 0.55, 0.70, [0.35, 0.35, 0.4], [2, 2, 2]) },
  { id: 'dsaber',  label: 'Double Saber', glbBase: 'dsaver',     weaponType: 4,  defaults: tune({ h: 2.6, v: 0.8, a: 60, mt: 2 }, [180, 180], 0.55, 0.70, [0.4, 0.4, 0.45], [1, 2, 1]) },
  { id: 'spear',   label: 'Spear',        glbBase: 'spear',      weaponType: 5,  defaults: tune({ h: 3.6, v: 0.6, a: 40, mt: 2 }, [75, 75]) },
  { id: 'slicer',  label: 'Slicer',       glbBase: 'slicer',     weaponType: 6,  defaults: tune({ h: 8.0, v: 0.5, a: 15, mt: 4 }, [90, 90]) },
  { id: 'handgun', label: 'Handgun',      glbBase: 'handgun',    weaponType: 9,  defaults: tune({ h: 17.0, v: 0.0, a: 10, mt: 1 }, [180, 180]) },
  { id: 'mechgun', label: 'Mechgun',      glbBase: 'machinegun', weaponType: 10, defaults: tune({ h: 8.5, v: 0.0, a: 35, mt: 1 }, [180, 180], 0.55, 0.70, [0.3, 0.3, 0.35], [3, 3, 4]) },
  { id: 'rifle',   label: 'Rifle',        glbBase: 'rifle',      weaponType: 11, defaults: tune({ h: 25.0, v: 0.0, a: 6, mt: 1 }, [45, 45]) },
  { id: 'rod',     label: 'Rod',          glbBase: 'rod',        weaponType: 14, defaults: tune({ h: 2.2, v: 0.4, a: 30, mt: 1 }, [90, 90]) },
  { id: 'wand',    label: 'Wand',         glbBase: 'wand',       weaponType: 15, defaults: tune({ h: 2.2, v: 0.4, a: 30, mt: 1 }, [90, 90]) },
];

const WEAPON_BY_TYPE = new Map(WEAPONS.map((w) => [w.weaponType, w]));

interface ClassDef {
  id: string; label: string; desc: string; gender: Gender; pc: string;
  allowed: number[]; innate: number;
}

// Same roster as #/combo-debug (data/classes/*.tres + PlayerConfig).
const CLASSES: ClassDef[] = [
  { id: 'humar',     label: 'HUmar',     desc: 'Human Hunter',  gender: 'm', pc: 'pc_000', allowed: [0, 1, 2, 5, 9],       innate: 0 },
  { id: 'humarl',    label: 'HUmarl',    desc: 'Human Hunter',  gender: 'w', pc: 'pc_010', allowed: [0, 1, 2, 3, 9, 15],   innate: 2 },
  { id: 'ramar',     label: 'RAmar',     desc: 'Human Ranger',  gender: 'm', pc: 'pc_020', allowed: [0, 5, 9, 10, 11, 12], innate: 11 },
  { id: 'ramarl',    label: 'RAmarl',    desc: 'Human Ranger',  gender: 'w', pc: 'pc_030', allowed: [0, 2, 9, 10, 11, 12], innate: 9 },
  { id: 'fomar',     label: 'FOmar',     desc: 'Human Force',   gender: 'm', pc: 'pc_040', allowed: [0, 5, 9, 14, 15],     innate: 14 },
  { id: 'fomarl',    label: 'FOmarl',    desc: 'Human Force',   gender: 'w', pc: 'pc_050', allowed: [0, 6, 9, 14, 15],     innate: 15 },
  { id: 'hunewm',    label: 'HUnewm',    desc: 'Newman Hunter', gender: 'm', pc: 'pc_060', allowed: [0, 1, 2, 4, 5, 9],    innate: 4 },
  { id: 'hunewearl', label: 'HUnewearl', desc: 'Newman Hunter', gender: 'w', pc: 'pc_070', allowed: [0, 1, 2, 3, 6, 9],    innate: 6 },
  { id: 'fonewm',    label: 'FOnewm',    desc: 'Newman Force',  gender: 'm', pc: 'pc_080', allowed: [0, 9, 14, 15],        innate: 14 },
  { id: 'fonewearl', label: 'FOnewearl', desc: 'Newman Force',  gender: 'w', pc: 'pc_090', allowed: [0, 9, 14, 15],        innate: 15 },
  { id: 'hucast',    label: 'HUcast',    desc: 'Cast Hunter',   gender: 'm', pc: 'pc_100', allowed: [0, 1, 2, 5, 9],       innate: 1 },
  { id: 'hucaseal',  label: 'HUcaseal',  desc: 'Cast Hunter',   gender: 'w', pc: 'pc_110', allowed: [0, 1, 2, 3, 9, 10],   innate: 3 },
  { id: 'racast',    label: 'RAcast',    desc: 'Cast Ranger',   gender: 'm', pc: 'pc_120', allowed: [0, 1, 9, 10, 11, 12], innate: 12 },
  { id: 'racaseal',  label: 'RAcaseal',  desc: 'Cast Ranger',   gender: 'w', pc: 'pc_130', allowed: [0, 4, 9, 10, 11, 12], innate: 10 },
];

function availableWeapons(cls: ClassDef): WeaponDef[] {
  return cls.allowed.map((t) => WEAPON_BY_TYPE.get(t)).filter((w): w is WeaponDef => !!w);
}

function defaultWeaponFor(cls: ClassDef): WeaponKey {
  const avail = availableWeapons(cls);
  const innate = WEAPON_BY_TYPE.get(cls.innate);
  return innate && avail.includes(innate) ? innate.id : avail[0].id;
}

type AttackType = 'normal' | 'strong' | 'special';
const ATTACK_COLORS: Record<AttackType, string> = { normal: '#4f4', strong: '#fc4', special: '#c8f' };

interface Config {
  classId: string;
  weapon: WeaponKey;
  perWeapon: Partial<Record<WeaponKey, Tuning>>;  // hit/turn tuning is per TYPE (matches Godot data)
}

const DEFAULT_CONFIG: Config = { classId: 'humar', weapon: 'saber', perWeapon: {} };

function loadConfig(): Config {
  if (typeof window === 'undefined') return DEFAULT_CONFIG;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CONFIG;
    const parsed = JSON.parse(raw) as Partial<Config>;
    const cfg: Config = { ...DEFAULT_CONFIG, ...parsed };
    if (typeof cfg.perWeapon !== 'object' || cfg.perWeapon === null) cfg.perWeapon = {};
    const cls = CLASSES.find((c) => c.id === cfg.classId) || CLASSES[0];
    cfg.classId = cls.id;
    if (!availableWeapons(cls).some((w) => w.id === cfg.weapon)) cfg.weapon = defaultWeaponFor(cls);
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

function getTuning(cfg: Config, weapon: WeaponKey): Tuning {
  const def = WEAPONS.find((w) => w.id === weapon)!;
  const t: Tuning = { ...def.defaults, ...(cfg.perWeapon[weapon] || {}) };
  for (const k of ['turnLimitDeg', 'damagingFrac', 'hitsPerStep'] as const) {
    if (!Array.isArray(t[k])) t[k] = def.defaults[k].slice();
  }
  t.justEnd = Math.max(t.justEnd, t.justStart);
  return t;
}

function wrapAngle(a: number): number {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}
const rad2deg = (r: number) => (r * 180) / Math.PI;
const deg2rad = (d: number) => (d * Math.PI) / 180;

function stripRootMotion(clip: THREE.AnimationClip): void {
  clip.tracks = clip.tracks.filter((t) =>
    t.name !== '000_Root.position' && !t.name.endsWith('/000_Root.position'));
}

// ---------------------------------------------------------------------------
// Dummies + hit test (the PSO cone, in the XZ plane)
// ---------------------------------------------------------------------------

type EntityKind = 'enemy' | 'item';

interface Dummy {
  kind: EntityKind;
  name: string;
  x: number; z: number;
  radius: number;        // hitbox radius — extends the weapon's reach (PSO)
  maxHp: number;         // 0 for items
  hp: number;
  hitFlash: number;      // seconds left on hit tint
  hitCount: number;
}

const DEFAULT_DUMMIES: Array<Pick<Dummy, 'kind' | 'name' | 'x' | 'z' | 'radius' | 'maxHp'>> = [
  { kind: 'enemy', name: 'Dummy A',     x: 0,    z: -2.6, radius: 0.5,  maxHp: 120 },
  { kind: 'enemy', name: 'Dummy B',     x: -1.8, z: -2.2, radius: 0.5,  maxHp: 120 },
  { kind: 'enemy', name: 'Dummy C',     x: 1.8,  z: -2.2, radius: 0.5,  maxHp: 120 },
  { kind: 'enemy', name: 'Heavy Dummy', x: -3.2, z: 0.5,  radius: 0.8,  maxHp: 300 },
  { kind: 'enemy', name: 'Small Dummy', x: 3.4,  z: -0.6, radius: 0.35, maxHp: 60 },
  { kind: 'enemy', name: 'Dummy F',     x: 0.5,  z: 3.0,  radius: 0.5,  maxHp: 120 },
  { kind: 'item',  name: 'Monomate',    x: 1.2,  z: -1.3, radius: 0.3,  maxHp: 0 },
  { kind: 'item',  name: 'Saber',       x: -1.1, z: 1.6,  radius: 0.3,  maxHp: 0 },
];

/**
 * PSO cone test (check_enemy_is_targetable, flattened to XZ):
 * apex = playerPos - facing * vDist; reach = hDist + vDist + dummy.radius;
 * pass if dist(apex→dummy) ≤ reach AND angle(facing, apex→dummy) ≤ hAngle.
 * Returns indices sorted nearest-first (nearest = primary target).
 */
function targetableDummies(
  px: number, pz: number, yaw: number, t: Tuning, dummies: Dummy[],
): number[] {
  const fx = Math.sin(yaw);
  const fz = Math.cos(yaw);
  const ax = px - fx * t.vDist;
  const az = pz - fz * t.vDist;
  const cosLimit = Math.cos(deg2rad(t.hAngleDeg));
  const out: Array<{ i: number; d2: number }> = [];
  for (let i = 0; i < dummies.length; i++) {
    const d = dummies[i];
    if (d.kind === 'enemy' && d.hp <= 0) continue;  // defeated — not targetable
    const dx = d.x - ax;
    const dz = d.z - az;
    const dist = Math.hypot(dx, dz);
    const reach = t.hDist + t.vDist + d.radius;
    if (dist > reach) continue;
    if (dist > 1e-4) {
      const cosA = (dx * fx + dz * fz) / dist;
      if (cosA < cosLimit) continue;
    }
    out.push({ i, d2: dist });
  }
  out.sort((a, b) => a.d2 - b.d2);
  return out.map((o) => o.i);
}

// ---------------------------------------------------------------------------
// Sim (shipped Godot combo model: queue + fumble, #474/#475)
// ---------------------------------------------------------------------------

type Phase = 'idle' | 'windup' | 'swing';
type QueueTier = 'none' | 'just' | 'normal';

interface Sim {
  phase: Phase;
  step: number;
  attackType: AttackType;
  elapsed: number;
  clipLen: number;
  queued: QueueTier;
  queuedSpecial: boolean;
  fumbled: boolean;
  isJust: boolean;             // current swing chained via the just tier
  hitResolved: boolean;        // damaging frame consumed for this swing
  yaw: number;
  displayYaw: number;
  desiredYaw: number | null;
  ghostYaw: number | null;
  ghostFade: number;
  ringFlash: { color: THREE.Color; ttl: number } | null;
  keysDown: Set<string>;
  hitsLanded: number;
  swingsMissed: number;        // swings whose damaging frame hit nothing
}

function freshSim(): Sim {
  return {
    phase: 'idle', step: 0, attackType: 'normal',
    elapsed: 0, clipLen: 0,
    queued: 'none', queuedSpecial: false, fumbled: false, isJust: false,
    hitResolved: false,
    yaw: Math.PI, displayYaw: Math.PI, desiredYaw: null,
    ghostYaw: null, ghostFade: 0, ringFlash: null,
    keysDown: new Set(), hitsLanded: 0, swingsMissed: 0,
  };
}

interface LogEntry { id: number; color: string; text: string }

interface DummyHandle {
  mesh: THREE.Mesh;
  ring: THREE.Mesh;
  ringMat: THREE.MeshBasicMaterial;
  bodyMat: THREE.MeshStandardMaterial;
  label: number;
}

interface SceneRefs {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  playerGroup: THREE.Group;
  mixer: THREE.AnimationMixer | null;
  actions: Record<string, THREE.AnimationAction>;
  currentAction: THREE.AnimationAction | null;
  clips: Record<string, THREE.AnimationClip>;
  cone: THREE.Mesh;
  coneMat: THREE.MeshBasicMaterial;
  coneKey: string;
  fan: THREE.Mesh;
  fanMat: THREE.MeshBasicMaterial;
  fanLimitRad: number;
  facingArrow: THREE.ArrowHelper;
  desiredArrow: THREE.ArrowHelper;
  ghostArrow: THREE.ArrowHelper;
  dummies: DummyHandle[];
  raycaster: THREE.Raycaster;
  dragIdx: number;
}

/** Sector mesh for the hit cone: apex at local origin, aimed at +Z. */
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

function buildFanGeometry(limitRad: number, radius = 1.9, segments = 32): THREE.BufferGeometry {
  return buildSectorGeometry(limitRad, radius, segments);
}

export default function CombatRoom() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const simRef = useRef<Sim>(freshSim());
  const dummiesRef = useRef<Dummy[]>(DEFAULT_DUMMIES.map((d) => ({ ...d, hp: d.maxHp, hitFlash: 0, hitCount: 0 })));
  const logIdRef = useRef(0);

  const [config, setConfig] = useState<Config>(loadConfig);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [hud, setHud] = useState({
    phase: 'idle' as Phase, step: 0, frac: 0, queued: 'none' as QueueTier,
    fumbled: false, yawDeg: 180, targetable: [] as number[],
    hits: 0, whiffs: 0,
    primary: null as null | { kind: EntityKind; name: string; hp: number; maxHp: number },
  });
  const [quickMenuOpen, setQuickMenuOpen] = useState(false);

  const classDef = CLASSES.find((c) => c.id === config.classId)!;
  const gender = classDef.gender;
  const weaponDef = WEAPONS.find((w) => w.id === config.weapon)!;
  const tuning = getTuning(config, config.weapon);
  const classWeapons = availableWeapons(classDef);

  const tuningRef = useRef(tuning);
  tuningRef.current = tuning;

  useEffect(() => {
    try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); } catch { /* ignore */ }
  }, [config]);

  const pushLog = useCallback((text: string, color = '#aaa') => {
    logIdRef.current += 1;
    const id = logIdRef.current;
    setLog((prev) => [{ id, color, text }, ...prev].slice(0, 12));
  }, []);

  const setTuning = (patch: Partial<Tuning>) => {
    setConfig((cfg) => ({
      ...cfg,
      perWeapon: { ...cfg.perWeapon, [cfg.weapon]: { ...getTuning(cfg, cfg.weapon), ...patch } },
    }));
  };

  const setClass = (id: string) => {
    setConfig((cfg) => {
      const cls = CLASSES.find((c) => c.id === id);
      if (!cls) return cfg;
      const avail = availableWeapons(cls);
      const weapon = avail.some((w) => w.id === cfg.weapon) ? cfg.weapon : defaultWeaponFor(cls);
      return { ...cfg, classId: id, weapon };
    });
  };

  // -------------------------------------------------------------------------
  // Animation + sim helpers
  // -------------------------------------------------------------------------

  const playClip = useCallback((name: string, loop: boolean) => {
    const s = sceneRef.current;
    if (!s || !s.actions[name]) return 0;
    if (s.currentAction && s.currentAction !== s.actions[name]) s.currentAction.fadeOut(0.06);
    const action = s.actions[name];
    action.reset();
    action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    action.clampWhenFinished = !loop;
    action.fadeIn(0.06);
    action.play();
    s.currentAction = action;
    return s.clips[name]?.duration ?? 0;
  }, []);

  const ringFlash = useCallback((hex: number) => {
    simRef.current.ringFlash = { color: new THREE.Color(hex), ttl: 0.35 };
  }, []);

  const resetToIdle = useCallback(() => {
    const sim = simRef.current;
    sim.phase = 'idle';
    sim.step = 0;
    sim.queued = 'none';
    sim.fumbled = false;
    sim.isJust = false;
    playClip('wait', true);
  }, [playClip]);

  const startSwing = useCallback((step: number) => {
    const sim = simRef.current;
    const len = playClip(`atk${step}`, false);
    sim.phase = 'swing';
    sim.elapsed = 0;
    sim.clipLen = len > 0 ? len : 0.5;
    sim.fumbled = false;
    sim.hitResolved = false;
  }, [playClip]);

  /** Apply the inter-swing turn: target snap (PSO) or clamped free steer. */
  const applyChainTurn = useCallback((enteringStep: number) => {
    const sim = simRef.current;
    const t = tuningRef.current;
    // Target snap: re-aim at the nearest ENEMY in the cone like PSO does per
    // step — unclamped, because the target was already inside the cone.
    // Items are never snap targets (PSO's weapon reticle only targets
    // attackables; item pickup is a separate reticle slot).
    if (t.targetSnap) {
      const enemies = targetableDummies(0, 0, sim.yaw, t, dummiesRef.current)
        .filter((i) => dummiesRef.current[i].kind === 'enemy');
      if (enemies.length > 0) {
        const d = dummiesRef.current[enemies[0]];
        sim.yaw = Math.atan2(d.x, d.z);
        return;
      }
    }
    if (sim.desiredYaw === null) return;
    if (enteringStep <= 1) {
      sim.yaw = sim.desiredYaw;  // fresh combo aims free
      return;
    }
    const limitIdx = Math.min(enteringStep - 2, t.turnLimitDeg.length - 1);
    const limit = deg2rad(t.turnLimitDeg[limitIdx] ?? 90);
    const delta = wrapAngle(sim.desiredYaw - sim.yaw);
    const clamped = Math.max(-limit, Math.min(limit, delta));
    if (Math.abs(delta) > limit + 1e-4) {
      sim.ghostYaw = sim.desiredYaw;
      sim.ghostFade = 0.8;
      pushLog(`turn ${rad2deg(delta).toFixed(0)}° requested → clamped ${rad2deg(clamped).toFixed(0)}° (±${t.turnLimitDeg[limitIdx]}°)`, '#f88');
    }
    sim.yaw = wrapAngle(sim.yaw + clamped);
  }, [pushLog]);

  const beginStep = useCallback((step: number, type: AttackType) => {
    const sim = simRef.current;
    const t = tuningRef.current;
    sim.step = step;
    sim.attackType = type;
    sim.isJust = sim.queued === 'just';
    const windup = type === 'strong' ? t.strongWindup : type === 'special' ? t.specialWindup : 0;
    if (windup > 0.001) {
      sim.phase = 'windup';
      sim.elapsed = 0;
      sim.clipLen = windup;
      sim.fumbled = false;
      playClip('wait', true);
    } else {
      startSwing(step);
    }
  }, [playClip, startSwing]);

  /** Attack press → shipped queue model: fumble / just / normal. */
  const pressAttack = useCallback((type: AttackType) => {
    const sim = simRef.current;
    const t = tuningRef.current;
    if (isLoading) return;
    if (sim.phase === 'idle') {
      applyChainTurn(1);
      sim.queued = 'none';
      sim.isJust = false;
      beginStep(1, type);
      ringFlash(type === 'normal' ? 0x33ff66 : type === 'strong' ? 0xffcc33 : 0xcc88ff);
      pushLog(`combo start — ${type} atk1`, ATTACK_COLORS[type]);
      return;
    }
    if (sim.phase === 'windup') return;
    if (sim.step >= t.comboSteps) { pushLog('finisher — nothing to chain', '#888'); return; }
    if (sim.queued !== 'none') return;      // one slot, no re-roll
    if (sim.fumbled) { pushLog('fumbled — presses locked out this swing', '#f96'); return; }
    const frac = sim.clipLen > 0 ? sim.elapsed / sim.clipLen : 0;
    if (frac >= t.justStart && frac < t.justEnd) {
      sim.queued = 'just';
      sim.queuedSpecial = type !== 'normal';
      ringFlash(0x88ffaa);
      pushLog(`JUST ×${t.justMult.toFixed(2)} queued at ${(frac * 100).toFixed(0)}%`, '#6f9');
    } else if (frac >= t.justEnd) {
      sim.queued = 'normal';
      sim.queuedSpecial = type !== 'normal';
      ringFlash(type === 'normal' ? 0x33ff66 : 0xffcc33);
      pushLog(`chain queued at ${(frac * 100).toFixed(0)}%`, ATTACK_COLORS[type]);
    } else {
      sim.fumbled = true;
      ringFlash(0xbf4d4d);
      pushLog(`too early at ${(frac * 100).toFixed(0)}% — FUMBLED (swing locked out)`, '#f96');
    }
  }, [isLoading, applyChainTurn, beginStep, ringFlash, pushLog]);

  /** Swing end: fire the queue or break (shipped _attack_step_finished). */
  const stepFinished = useCallback(() => {
    const sim = simRef.current;
    const t = tuningRef.current;
    if (sim.queued !== 'none' && sim.step < t.comboSteps) {
      const type: AttackType = sim.queuedSpecial ? 'strong' : 'normal';
      const next = sim.step + 1;
      applyChainTurn(next);
      const wasJust = sim.queued === 'just';
      sim.queued = 'none';
      beginStep(next, type);
      sim.isJust = wasJust;
      return;
    }
    if (sim.step < t.comboSteps) ringFlash(0xff3333);
    resetToIdle();
  }, [applyChainTurn, beginStep, ringFlash, resetToIdle]);

  /** Damaging frame: resolve hits against the cone — nearest maxTargets
   *  ENEMIES (items are targetable for the reticle/HUD but never hit). */
  const resolveHits = useCallback(() => {
    const sim = simRef.current;
    const t = tuningRef.current;
    const stepIdx = Math.min(Math.max(sim.step - 1, 0), 2);
    const targetable = targetableDummies(0, 0, sim.yaw, t, dummiesRef.current);
    const enemies = targetable.filter((i) => dummiesRef.current[i].kind === 'enemy');
    const hit = enemies.slice(0, t.maxTargets);
    const hits = t.hitsPerStep[stepIdx] ?? 1;
    const dmg = Math.round(25 * hits * (sim.isJust ? t.justMult : 1));
    for (const i of hit) {
      const d = dummiesRef.current[i];
      d.hitFlash = 0.3;
      d.hitCount += hits;
      d.hp = Math.max(0, d.hp - dmg);
    }
    if (hit.length > 0) {
      sim.hitsLanded += hit.length;
      pushLog(
        `atk${sim.step} hit ${hit.length}/${enemies.length} enemies (${dmg} dmg${sim.isJust ? `, JUST ×${t.justMult.toFixed(2)}` : ''})`,
        sim.isJust ? '#6f9' : '#4f4',
      );
      for (const i of hit) {
        const d = dummiesRef.current[i];
        if (d.hp <= 0) pushLog(`${d.name} defeated`, '#fa6');
      }
    } else {
      sim.swingsMissed += 1;
      pushLog(`atk${sim.step} whiffed — no enemy in the cone`, '#888');
    }
  }, [pushLog]);

  const pressAttackRef = useRef(pressAttack);
  pressAttackRef.current = pressAttack;
  const stepFinishedRef = useRef(stepFinished);
  stepFinishedRef.current = stepFinished;
  const resolveHitsRef = useRef(resolveHits);
  resolveHitsRef.current = resolveHits;
  const startSwingRef = useRef(startSwing);
  startSwingRef.current = startSwing;
  const resetRef = useRef(resetToIdle);
  resetRef.current = resetToIdle;

  // -------------------------------------------------------------------------
  // Keyboard
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
      else if (e.code === 'KeyQ') setQuickMenuOpen((p) => !p);
      else if (e.code === 'KeyR') resetRef.current();
    };
    const onUp = (e: KeyboardEvent) => simRef.current.keysDown.delete(e.code);
    window.addEventListener('keydown', onDown);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onDown);
      window.removeEventListener('keyup', onUp);
    };
  }, []);

  // -------------------------------------------------------------------------
  // Scene + loop
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 200);
    camera.position.set(0, 11, 8);
    camera.lookAt(0, 0, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.75));
    const dir = new THREE.DirectionalLight(0xffffff, 0.7);
    dir.position.set(4, 8, 5);
    scene.add(dir);

    scene.add(new THREE.GridHelper(24, 48, 0x444466, 0x222238));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.5, 0);
    controls.mouseButtons = { LEFT: null as unknown as THREE.MOUSE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };

    const playerGroup = new THREE.Group();
    scene.add(playerGroup);

    // Hit cone (rebuilt when angle/reach change)
    const coneMat = new THREE.MeshBasicMaterial({
      color: 0xffaa44, transparent: true, opacity: 0.14, side: THREE.DoubleSide, depthWrite: false,
    });
    const cone = new THREE.Mesh(buildSectorGeometry(deg2rad(30), 3), coneMat);
    scene.add(cone);

    // Turn-limit fan
    const fanMat = new THREE.MeshBasicMaterial({
      color: 0x33ff88, transparent: true, opacity: 0.16, side: THREE.DoubleSide, depthWrite: false,
    });
    const fan = new THREE.Mesh(buildFanGeometry(deg2rad(90)), fanMat);
    fan.visible = false;
    scene.add(fan);

    const facingArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.05, 0), 2.0, 0x44ccff, 0.32, 0.18);
    const desiredArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.08, 0), 1.6, 0xffee44, 0.28, 0.16);
    desiredArrow.visible = false;
    const ghostArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.08, 0), 1.6, 0xff4444, 0.28, 0.16);
    ghostArrow.visible = false;
    scene.add(facingArrow, desiredArrow, ghostArrow);

    // Entities: enemies are capsules, ground items small octahedra
    const dummyHandles: DummyHandle[] = dummiesRef.current.map((d, i) => {
      const bodyMat = new THREE.MeshStandardMaterial({
        color: d.kind === 'item' ? 0xddbb44 : 0x8888aa, roughness: 0.8,
      });
      const mesh = d.kind === 'item'
        ? new THREE.Mesh(new THREE.OctahedronGeometry(0.22), bodyMat)
        : new THREE.Mesh(new THREE.CapsuleGeometry(d.radius * 0.55, 1.0, 4, 12), bodyMat);
      mesh.position.set(d.x, d.kind === 'item' ? 0.3 : 0.85, d.z);
      mesh.userData.dummyIdx = i;
      scene.add(mesh);
      const ringMat = new THREE.MeshBasicMaterial({
        color: 0x555577, transparent: true, opacity: 0.7, side: THREE.DoubleSide,
      });
      const ring = new THREE.Mesh(new THREE.RingGeometry(d.radius - 0.05, d.radius, 32), ringMat);
      ring.rotation.x = -Math.PI / 2;
      ring.position.set(d.x, 0.02, d.z);
      scene.add(ring);
      return { mesh, ring, ringMat, bodyMat, label: i };
    });

    sceneRef.current = {
      scene, camera, renderer, controls, playerGroup,
      mixer: null, actions: {}, currentAction: null, clips: {},
      cone, coneMat, coneKey: '',
      fan, fanMat, fanLimitRad: deg2rad(90),
      facingArrow, desiredArrow, ghostArrow,
      dummies: dummyHandles,
      raycaster: new THREE.Raycaster(),
      dragIdx: -1,
    };

    // Dummy dragging (left button; orbit is on right/middle)
    const groundPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const ndc = new THREE.Vector2();
    const hitPoint = new THREE.Vector3();
    const toNdc = (e: PointerEvent) => {
      const r = renderer.domElement.getBoundingClientRect();
      ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    };
    const onPointerDown = (e: PointerEvent) => {
      if (e.button !== 0 || !sceneRef.current) return;
      toNdc(e);
      const s = sceneRef.current;
      s.raycaster.setFromCamera(ndc, camera);
      const hits = s.raycaster.intersectObjects(s.dummies.map((d) => d.mesh), false);
      if (hits.length > 0) s.dragIdx = hits[0].object.userData.dummyIdx as number;
    };
    const onPointerMove = (e: PointerEvent) => {
      const s = sceneRef.current;
      if (!s || s.dragIdx < 0) return;
      toNdc(e);
      s.raycaster.setFromCamera(ndc, camera);
      if (s.raycaster.ray.intersectPlane(groundPlane, hitPoint)) {
        const d = dummiesRef.current[s.dragIdx];
        d.x = THREE.MathUtils.clamp(hitPoint.x, -11, 11);
        d.z = THREE.MathUtils.clamp(hitPoint.z, -11, 11);
      }
    };
    const onPointerUp = () => { if (sceneRef.current) sceneRef.current.dragIdx = -1; };
    renderer.domElement.addEventListener('pointerdown', onPointerDown);
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);

    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const delta = Math.min(clock.getDelta(), 0.1);
      const s = sceneRef.current;
      const sim = simRef.current;
      if (!s) return;
      const t = tuningRef.current;

      // steering input
      let kx = 0; let kz = 0;
      const kd = sim.keysDown;
      if (kd.has('KeyW') || kd.has('ArrowUp')) kz -= 1;
      if (kd.has('KeyS') || kd.has('ArrowDown')) kz += 1;
      if (kd.has('KeyA') || kd.has('ArrowLeft')) kx -= 1;
      if (kd.has('KeyD') || kd.has('ArrowRight')) kx += 1;
      sim.desiredYaw = (kx !== 0 || kz !== 0) ? Math.atan2(kx, kz) : null;

      // state machine (queue model)
      if (sim.phase === 'idle') {
        if (sim.desiredYaw !== null) sim.yaw = sim.desiredYaw;
      } else if (sim.phase === 'windup') {
        sim.elapsed += delta;
        if (sim.elapsed >= sim.clipLen) startSwingRef.current(sim.step);
      } else if (sim.phase === 'swing') {
        sim.elapsed += delta;
        const stepIdx = Math.min(Math.max(sim.step - 1, 0), 2);
        const dmgAt = sim.clipLen * (t.damagingFrac[stepIdx] ?? 0.4);
        if (!sim.hitResolved && sim.elapsed >= dmgAt) {
          sim.hitResolved = true;
          resolveHitsRef.current();
        }
        if (sim.elapsed >= sim.clipLen) stepFinishedRef.current();
      }

      // targetable set (live, like PSO's per-frame reticle scan). HUD-primary
      // precedence mirrors PSO's split reticles: the nearest ENEMY in the
      // weapon cone wins; an item is primary only when no enemy is targetable
      // and the item sits within pickup range.
      const ITEM_INFO_RANGE = 2.0;
      const targetable = targetableDummies(0, 0, sim.yaw, t, dummiesRef.current);
      let primIdx = targetable.find((i) => dummiesRef.current[i].kind === 'enemy') ?? -1;
      if (primIdx < 0) {
        primIdx = targetable.find((i) => {
          const d = dummiesRef.current[i];
          return d.kind === 'item' && Math.hypot(d.x, d.z) <= ITEM_INFO_RANGE;
        }) ?? -1;
      }

      // visuals
      sim.displayYaw += wrapAngle(sim.yaw - sim.displayYaw) * Math.min(1, delta * 14);
      s.playerGroup.rotation.y = sim.displayYaw;
      s.facingArrow.setDirection(new THREE.Vector3(Math.sin(sim.displayYaw), 0, Math.cos(sim.displayYaw)));
      if (sim.desiredYaw !== null) {
        s.desiredArrow.visible = true;
        s.desiredArrow.setDirection(new THREE.Vector3(Math.sin(sim.desiredYaw), 0, Math.cos(sim.desiredYaw)));
      } else s.desiredArrow.visible = false;
      if (sim.ghostFade > 0 && sim.ghostYaw !== null) {
        sim.ghostFade -= delta;
        s.ghostArrow.visible = sim.ghostFade > 0;
        s.ghostArrow.setDirection(new THREE.Vector3(Math.sin(sim.ghostYaw), 0, Math.cos(sim.ghostYaw)));
      } else s.ghostArrow.visible = false;

      // hit cone: apex pulled back by vDist, aimed at yaw
      const coneKey = `${t.hAngleDeg}:${t.hDist}:${t.vDist}`;
      if (coneKey !== s.coneKey) {
        s.cone.geometry.dispose();
        s.cone.geometry = buildSectorGeometry(deg2rad(t.hAngleDeg), t.hDist + t.vDist);
        s.coneKey = coneKey;
      }
      s.cone.position.set(-Math.sin(sim.displayYaw) * t.vDist, 0, -Math.cos(sim.displayYaw) * t.vDist);
      s.cone.rotation.y = sim.displayYaw;
      s.coneMat.opacity = sim.phase === 'swing' && !sim.hitResolved ? 0.3 : 0.14;

      // turn fan while a chain remains
      const showFan = sim.phase !== 'idle' && sim.step < t.comboSteps && !t.targetSnap;
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
      }

      // entities: primary bright, targetable green, hit flash red,
      // defeated enemies slumped dark, items idle-spin
      for (let i = 0; i < s.dummies.length; i++) {
        const dh = s.dummies[i];
        const d = dummiesRef.current[i];
        dh.mesh.position.x = d.x;
        dh.mesh.position.z = d.z;
        dh.ring.position.set(d.x, 0.02, d.z);
        if (d.kind === 'item') dh.mesh.rotation.y += delta * 1.5;
        const isPrimary = primIdx === i;
        const inSet = targetable.includes(i);
        const isItem = d.kind === 'item';
        const dead = !isItem && d.hp <= 0;
        if (dead) {
          dh.mesh.scale.y = Math.max(0.25, dh.mesh.scale.y - delta * 3);
          dh.bodyMat.color.setHex(0x44445a);
          dh.ringMat.color.setHex(0x333344);
        } else {
          dh.mesh.scale.y = 1;
          if (d.hitFlash > 0) {
            d.hitFlash -= delta;
            dh.bodyMat.color.setHex(0xff5544);
            dh.ringMat.color.setHex(0xff5544);
          } else {
            const base = isItem ? 0xddbb44 : 0x8888aa;
            dh.bodyMat.color.setHex(isPrimary ? 0xffee66 : inSet ? (isItem ? 0xeedd88 : 0x66dd88) : base);
            dh.ringMat.color.setHex(isPrimary ? 0xffee66 : inSet ? 0x33aa55 : 0x555577);
          }
        }
        dh.ringMat.opacity = inSet ? 0.95 : 0.5;
      }

      // ring flash decay lives on the cone material tint via dummies; combo
      // feedback is the log + HUD here (no separate ring — the cone is the
      // room's focal visual).
      if (sim.ringFlash) {
        sim.ringFlash.ttl -= delta;
        s.coneMat.color.copy(sim.ringFlash.color);
        if (sim.ringFlash.ttl <= 0) {
          sim.ringFlash = null;
          s.coneMat.color.setHex(0xffaa44);
        }
      }

      if (s.mixer) s.mixer.update(delta);
      controls.update();
      renderer.render(scene, camera);

      const prim = primIdx >= 0 ? dummiesRef.current[primIdx] : null;
      setHud({
        phase: sim.phase, step: sim.step,
        frac: sim.clipLen > 0 ? Math.min(1, sim.elapsed / sim.clipLen) : 0,
        queued: sim.queued, fumbled: sim.fumbled,
        yawDeg: rad2deg(sim.yaw), targetable: targetable.slice(),
        hits: sim.hitsLanded, whiffs: sim.swingsMissed,
        primary: prim ? { kind: prim.kind, name: prim.name, hp: prim.hp, maxHp: prim.maxHp } : null,
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
      renderer.domElement.removeEventListener('pointerdown', onPointerDown);
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerup', onPointerUp);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
      sceneRef.current = null;
    };
  }, []);

  // -------------------------------------------------------------------------
  // Model + animation loading (class model, gendered pack, suffix clips)
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setIsLoading(true);
    setLoadError(null);
    simRef.current = {
      ...freshSim(),
      hitsLanded: simRef.current.hitsLanded,
      swingsMissed: simRef.current.swingsMissed,
    };

    s.playerGroup.clear();
    s.mixer = null;
    s.actions = {};
    s.currentAction = null;
    s.clips = {};

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const pc = classDef.pc;
    const animGlb = `${weaponDef.glbBase}_${gender}`;
    let cancelled = false;

    loader.load(assetUrl(`assets/player/${pc}/${pc}_000.glb`), (gltf) => {
      if (cancelled || !sceneRef.current) return;
      const tex = texLoader.load(assetUrl(`assets/player/${pc}/textures/${pc}_000.png`), (tx) => {
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

      loader.load(assetUrl(`assets/player/animations/${animGlb}.glb`), (animGltf) => {
        if (cancelled || !sceneRef.current) return;
        const wanted: [string, string][] = [
          ['wait', '_wait'], ['atk1', '_atk1'], ['atk2', '_atk2'], ['atk3', '_atk3'],
        ];
        const mixer = new THREE.AnimationMixer(gltf.scene);
        for (const [key, suffix] of wanted) {
          const clip = animGltf.animations.find((a) => a.name.endsWith(suffix));
          if (!clip) continue;
          stripRootMotion(clip);
          s.clips[key] = clip;
          s.actions[key] = mixer.clipAction(clip);
        }
        if (!s.clips.wait || !s.clips.atk1) {
          setLoadError(`Missing clips in ${animGlb}.glb`);
          setIsLoading(false);
          return;
        }
        s.mixer = mixer;
        setIsLoading(false);
        resetRef.current();
      }, undefined, (err) => { setLoadError(`Animation load failed: ${err}`); setIsLoading(false); });
    }, undefined, (err) => { setLoadError(`Model load failed: ${err}`); setIsLoading(false); });

    return () => { cancelled = true; };
  }, [config.weapon, config.classId, classDef.pc, weaponDef.glbBase, gender]);

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  const copyGdscript = useCallback(() => {
    const t = tuning;
    const w = weaponDef;
    const lines = [
      `# Hit detection + inter-swing turn tuning — ${w.label} (WeaponType ${w.weaponType})`,
      `# From web #/combat-room (PSO cone model: apex pulled back by hit_v_dist,`,
      `# reach hit_h_dist + hit_v_dist + target hitbox radius, half-angle hit_h_angle_deg).`,
      `\t${w.weaponType}: {`,
      `\t\t"hit_h_dist": ${t.hDist.toFixed(2)},`,
      `\t\t"hit_v_dist": ${t.vDist.toFixed(2)},  # cone apex pull-back; also extends reach`,
      `\t\t"hit_h_angle_deg": ${t.hAngleDeg.toFixed(1)},  # half-angle`,
      `\t\t"max_targets": ${t.maxTargets},`,
      `\t\t"damaging_frac": [${t.damagingFrac.map((v) => v.toFixed(2)).join(', ')}],  # hit lands at this fraction of each swing`,
      `\t\t"hits_per_step": [${t.hitsPerStep.join(', ')}],`,
      `\t\t"turn_limit_deg": [${t.turnLimitDeg.map((v) => v.toFixed(1)).join(', ')}],  # free-aim clamp entering steps 2, 3`,
      `\t\t"target_snap": ${t.targetSnap},  # chain re-aims at the primary target (PSO)`,
      `\t},`,
    ];
    navigator.clipboard.writeText(lines.join('\n'));
    pushLog(`copied GDScript for ${w.label}`, '#6b8afd');
  }, [tuning, weaponDef, pushLog]);

  const resetWeapon = () => {
    if (!confirm(`Reset ${weaponDef.label} tuning to defaults?`)) return;
    setConfig((cfg) => {
      const next = { ...cfg.perWeapon };
      delete next[cfg.weapon];
      return { ...cfg, perWeapon: next };
    });
  };

  const resetDummies = () => {
    dummiesRef.current.forEach((d, i) => {
      const def = DEFAULT_DUMMIES[i];
      d.x = def.x; d.z = def.z; d.hitFlash = 0; d.hitCount = 0; d.hp = def.maxHp;
    });
    simRef.current.hitsLanded = 0;
    simRef.current.swingsMissed = 0;
  };

  // -------------------------------------------------------------------------

  const sliderRow = (
    label: string, value: number, min: number, max: number, step: number,
    onChange: (v: number) => void, fmt: (v: number) => string,
  ) => (
    <div style={{ marginBottom: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: '#aaa', marginBottom: 2 }}>
        <span>{label}</span>
        <span style={{ color: '#fff', fontVariantNumeric: 'tabular-nums' }}>{fmt(value)}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))} style={{ width: '100%' }} />
    </div>
  );

  const phaseLabel = hud.phase === 'idle' ? 'IDLE'
    : hud.phase === 'windup' ? 'WIND-UP'
    : `SWING ${hud.step}/${tuning.comboSteps} · ${(hud.frac * 100).toFixed(0)}%`;

  const tierLabel = hud.phase === 'swing'
    ? (hud.fumbled ? 'FUMBLED' : hud.queued !== 'none' ? `QUEUED (${hud.queued})`
      : hud.frac < tuning.justStart ? 'miss-early' : hud.frac < tuning.justEnd ? 'JUST tier' : 'normal tier')
    : '';

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: 16, boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: 16, height: '100%' }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
          <div style={{
            background: '#2d2d44', borderRadius: 8, padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16,
          }}>
            <span style={{ fontSize: 14, fontWeight: 'bold', color: '#6bf' }}>
              Combat Room — {classDef.label} · {weaponDef.label}
            </span>
            <span style={{ fontSize: 12, color: hud.queued !== 'none' ? '#6f9' : hud.fumbled ? '#f96' : '#888' }}>
              {phaseLabel}{tierLabel && ` · ${tierLabel}`}
            </span>
            <span style={{ fontSize: 12, color: '#888' }}>
              {hud.targetable.length} in cone · <span style={{ color: '#4f4' }}>{hud.hits} hits</span> · {hud.whiffs} whiffs
            </span>
            {isLoading && <span style={{ color: '#888', fontSize: 12 }}>(loading…)</span>}
            {loadError && <span style={{ color: '#f88', fontSize: 12 }}>{loadError}</span>}
          </div>

          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: 8, overflow: 'hidden', position: 'relative' }} ref={containerRef}>
            <div style={{
              position: 'absolute', left: 10, top: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              <span style={{ color: ATTACK_COLORS.normal }}>Z</span> normal ·{' '}
              <span style={{ color: ATTACK_COLORS.strong }}>X</span> strong ·{' '}
              <span style={{ color: ATTACK_COLORS.special }}>C</span> special ·{' '}
              Q quick menu · WASD steer · R reset · drag dummies · right-drag orbit
            </div>
            <div style={{
              position: 'absolute', right: 10, bottom: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              <span style={{ color: '#fa4' }}>orange</span> = hit cone ·{' '}
              <span style={{ color: '#fe6' }}>yellow</span> = primary ·{' '}
              <span style={{ color: '#6d8' }}>green</span> = in cone ·{' '}
              <span style={{ color: '#f54' }}>red</span> = hit
            </div>

            {/* Bottom-left HUD corner. Priority contract: quick menu owns the
                corner while open; otherwise the primary target's info panel;
                nothing to show → nothing rendered. */}
            {quickMenuOpen ? (
              <div style={{
                position: 'absolute', left: 14, bottom: 14, width: 220,
                background: '#1a2a4a', padding: 2, pointerEvents: 'none',
                clipPath: 'polygon(8px 0, calc(100% - 8px) 0, 100% 10px, 100% calc(100% - 16px), calc(100% - 24px) 100%, 8px 100%, 0 calc(100% - 10px), 0 10px)',
              }}>
                <div style={{
                  background: 'repeating-linear-gradient(180deg, #2a3d63 0px, #2a3d63 3px, #24365a 3px, #24365a 6px)',
                  clipPath: 'polygon(7px 0, calc(100% - 7px) 0, 100% 9px, 100% calc(100% - 15px), calc(100% - 23px) 100%, 7px 100%, 0 calc(100% - 9px), 0 9px)',
                  padding: '8px 14px 12px',
                }}>
                  <div style={{ fontSize: 10, color: '#8fb4e8', letterSpacing: 1, marginBottom: 6 }}>QUICK MENU</div>
                  {[['Monomate', '×5'], ['Dimate', '×2'], ['Telepipe', '×1']].map(([n, q], i) => (
                    <div key={n} style={{
                      display: 'flex', justifyContent: 'space-between', fontSize: 12,
                      color: i === 0 ? '#fff' : '#a9c4e4', background: i === 0 ? 'rgba(90,130,190,0.45)' : 'transparent',
                      padding: '2px 6px', borderRadius: 2,
                    }}>
                      <span>{n}</span><span>{q}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : hud.primary && (
              <div style={{
                position: 'absolute', left: 14, bottom: 14, width: 210,
                background: '#1a2a4a', padding: 2, pointerEvents: 'none',
                clipPath: 'polygon(8px 0, calc(100% - 8px) 0, 100% 10px, 100% calc(100% - 16px), calc(100% - 24px) 100%, 8px 100%, 0 calc(100% - 10px), 0 10px)',
              }}>
                <div style={{
                  background: 'repeating-linear-gradient(180deg, #b8d4ea 0px, #b8d4ea 3px, #a8c6e0 3px, #a8c6e0 6px)',
                  clipPath: 'polygon(7px 0, calc(100% - 7px) 0, 100% 9px, 100% calc(100% - 15px), calc(100% - 23px) 100%, 7px 100%, 0 calc(100% - 9px), 0 9px)',
                  padding: '7px 14px 11px', color: '#16264a',
                }}>
                  {hud.primary.kind === 'enemy' ? (
                    <>
                      <div style={{ fontSize: 13, fontWeight: 'bold', marginBottom: 4 }}>{hud.primary.name}</div>
                      <div style={{ height: 8, background: '#31507c', borderRadius: 2, overflow: 'hidden' }}>
                        <div style={{
                          height: '100%', width: `${hud.primary.maxHp > 0 ? (hud.primary.hp / hud.primary.maxHp) * 100 : 0}%`,
                          background: hud.primary.hp / Math.max(1, hud.primary.maxHp) > 0.35 ? '#4dc45f' : '#d8a03a',
                        }} />
                      </div>
                      <div style={{ fontSize: 10, marginTop: 3, fontVariantNumeric: 'tabular-nums' }}>
                        HP {hud.primary.hp}/{hud.primary.maxHp}
                      </div>
                    </>
                  ) : (
                    <>
                      <div style={{ fontSize: 9, letterSpacing: 1, color: '#3a5a8a', marginBottom: 2 }}>ITEM</div>
                      <div style={{ fontSize: 13, fontWeight: 'bold' }}>{hud.primary.name}</div>
                    </>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>

        <div style={{
          width: 330, background: '#2d2d44', borderRadius: 8, padding: 12,
          overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 14,
        }}>
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Class</h3>
            <select value={config.classId} onChange={(e) => setClass(e.target.value)}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12, marginBottom: 10 }}>
              {CLASSES.map((c) => (
                <option key={c.id} value={c.id}>{c.label} — {c.desc} ({c.gender === 'w' ? 'F' : 'M'})</option>
              ))}
            </select>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Weapon</h3>
            <select value={config.weapon}
              onChange={(e) => setConfig((c) => ({ ...c, weapon: e.target.value as WeaponKey }))}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12 }}>
              {classWeapons.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.weaponType === classDef.innate ? '★ ' : ''}{w.label} ({w.glbBase}_{gender})
                </option>
              ))}
            </select>
          </div>

          {/* Hit detection */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Hit cone — {weaponDef.label}
            </h3>
            {sliderRow('Reach (h_dist)', tuning.hDist, 0.5, 30, 0.1,
              (v) => setTuning({ hDist: v }), (v) => `${v.toFixed(1)} m`)}
            {sliderRow('Apex pull-back (v_dist)', tuning.vDist, 0, 3, 0.05,
              (v) => setTuning({ vDist: v }), (v) => `${v.toFixed(2)} m`)}
            {sliderRow('Half-angle', tuning.hAngleDeg, 3, 90, 1,
              (v) => setTuning({ hAngleDeg: v }), (v) => `${v.toFixed(0)}°`)}
            {sliderRow('Max targets per swing', tuning.maxTargets, 1, 6, 1,
              (v) => setTuning({ maxTargets: v }), (v) => `${v}`)}
            {sliderRow('Damaging frame (step 1)', tuning.damagingFrac[0], 0.1, 0.9, 0.01,
              (v) => setTuning({ damagingFrac: [v, tuning.damagingFrac[1], tuning.damagingFrac[2]] }), (v) => `${(v * 100).toFixed(0)}%`)}
            {sliderRow('Damaging frame (step 2)', tuning.damagingFrac[1], 0.1, 0.9, 0.01,
              (v) => setTuning({ damagingFrac: [tuning.damagingFrac[0], v, tuning.damagingFrac[2]] }), (v) => `${(v * 100).toFixed(0)}%`)}
            {sliderRow('Damaging frame (step 3)', tuning.damagingFrac[2], 0.1, 0.9, 0.01,
              (v) => setTuning({ damagingFrac: [tuning.damagingFrac[0], tuning.damagingFrac[1], v] }), (v) => `${(v * 100).toFixed(0)}%`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              PSO model (check_enemy_is_targetable + ItemPMT): the cone's apex
              sits v_dist behind the player, reach = h_dist + v_dist + the
              target's hitbox radius. Hits resolve once per swing, at the
              damaging frame — nearest {tuning.maxTargets} in the cone.
            </div>
          </div>

          {/* Turning */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Turning between swings
            </h3>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#aaa', marginBottom: 8 }}>
              <input type="checkbox" checked={tuning.targetSnap}
                onChange={(e) => setTuning({ targetSnap: e.target.checked })} />
              Target snap (PSO): chain re-aims at the primary target
            </label>
            {sliderRow('Free-aim clamp entering swing 2', tuning.turnLimitDeg[0] ?? 90, 0, 180, 5,
              (v) => setTuning({ turnLimitDeg: [v, tuning.turnLimitDeg[1] ?? 90] }), (v) => `±${v.toFixed(0)}°`)}
            {sliderRow('Free-aim clamp entering swing 3', tuning.turnLimitDeg[1] ?? 90, 0, 180, 5,
              (v) => setTuning({ turnLimitDeg: [tuning.turnLimitDeg[0] ?? 90, v] }), (v) => `±${v.toFixed(0)}°`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Facing locks during a swing. With snap ON and a target in the
              cone, the chain re-aims at it (unclamped — PSO:BB behavior).
              Otherwise a held direction steers the facing, clamped to the
              limit (green fan; red ghost arrow when clamped).
            </div>
          </div>

          {/* Combo timing (shipped model, read-mostly) */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Combo tiers (shipped #474/#475 model)
            </h3>
            {sliderRow('Just tier opens (fraction)', tuning.justStart, 0.2, 0.9, 0.01,
              (v) => setTuning({ justStart: v, justEnd: Math.max(tuning.justEnd, v) }), (v) => `${(v * 100).toFixed(0)}%`)}
            {sliderRow('Just tier ends / normal begins', tuning.justEnd, 0.2, 0.95, 0.01,
              (v) => setTuning({ justEnd: Math.max(v, tuning.justStart) }), (v) => `${(v * 100).toFixed(0)}%`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Fraction tiers + queue + fumble, matching data/combo_configs.
              Press early → fumble (swing locked out); [just_start, just_end)
              → JUST ×{tuning.justMult.toFixed(2)}; later → normal chain. The queued step fires
              at swing end.
            </div>
          </div>

          {/* Target-info HUD contract */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Target info HUD (bottom-left)
            </h3>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#aaa', marginBottom: 6 }}>
              <input type="checkbox" checked={quickMenuOpen}
                onChange={(e) => setQuickMenuOpen(e.target.checked)} />
              Quick menu open (Q) — takes priority over target info
            </label>
            <div style={{ fontSize: 10, color: '#666' }}>
              The panel shows the primary target: enemy → name + HP; ground
              item → item name. No primary target → the panel does not render
              at all. While the quick menu is open it owns the corner and the
              target panel never shows. Defeated dummies stop being targetable.
              Precedence (design point, PSO's split-reticle model): an enemy in
              the cone always wins; an item is primary only when no enemy is
              targetable and it's within ~2 m pickup range.
            </div>
          </div>

          {/* Log */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Log</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minHeight: 60 }}>
              {log.length === 0 && <span style={{ fontSize: 11, color: '#555' }}>Z / X / C to attack…</span>}
              {log.map((e) => (
                <span key={e.id} style={{ fontSize: 11, color: e.color, fontVariantNumeric: 'tabular-nums' }}>{e.text}</span>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <button onClick={copyGdscript} style={{
              padding: 10, background: '#2a4a6a', border: '1px solid #6b8afd',
              borderRadius: 4, color: '#fff', cursor: 'pointer', fontSize: 12, fontWeight: 'bold',
            }}>
              Copy GDScript — {weaponDef.label}
            </button>
            <button onClick={resetDummies} style={{
              padding: 8, background: '#1a1a2e', border: '1px solid #444',
              borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 12,
            }}>
              Reset dummies + stats
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
