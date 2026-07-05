import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Tech room — the design mock for TECHNIQUE casting, playable against
 * training dummies. Sibling of #/combat-room (weapon hit cones); this room
 * owns the tech side: effect shapes, targeting, hold-to-charge, PP.
 *
 * Effect shapes mirror the shipped _spawn_* implementations in player.gd:
 *  - foie      straight bolt (speed 20, range 15, first hit)
 *  - barta     ground bolt, PIERCES the full line (speed 20, range 15)
 *  - zonde     instant strike on the primary target
 *  - gifoie    fireball spiralling outward (12 rad/s, +2 m/s, fizzle 4→5 m)
 *  - gibarta   3 waves × 3 fan bolts, pierce (18 m/s, range 10, 0.15 s apart)
 *  - gizonde   chain lightning — nearest unhit enemy within 8 m, ≤10 targets
 *  - rafoie    explosion at the primary target (r=5, splash ×0.6)
 *  - rabarta   10 pierce shards in a circle (12 m/s, range 8)
 *  - razonde   nova around the caster (r=12, no target needed)
 *
 * Targeting: zonde / gizonde / rafoie require a primary target. The runtime
 * widens the weapon's scan cone for equipped techs (_update_combat_targets:
 * extra distance = tech range, extra half-angle, zonde ≥25°); the mock owns
 * that geometry directly as a per-tech target cone (violet). Contract note:
 * the shipped cast order spends PP and plays the cast anim BEFORE the
 * no-target early-return — the mock reproduces that (a whiffed cast still
 * costs PP) so the cost is visible while we decide if it should stay.
 *
 * Charge (hold-to-charge, player.gd TECH_CHARGE_THRESHOLD 0.6 s): holding
 * the cast button charges; released past the threshold casts the CHARGE_MAP
 * variant (foie→rafoie, barta→rabarta, zonde→razonde; gi/ra techs charge to
 * themselves). Damage = power × (1 + level/10) + TEC, ±10% variance; PP cost
 * = max(1, pp − level/5) (CombatManager.calculate_technique_damage).
 *
 * Controls: Z cast (hold to charge) · WASD/arrows steer · R reset ·
 * drag dummies to reposition. Tunables persist per tech; export as GDScript.
 */

const STORAGE_KEY = 'psz-tech-room:v1';

type Gender = 'm' | 'w';
type TechKey =
  | 'foie' | 'gifoie' | 'rafoie'
  | 'barta' | 'gibarta' | 'rabarta'
  | 'zonde' | 'gizonde' | 'razonde';
type TechKind = 'bolt' | 'spiral' | 'fan' | 'radial' | 'strike' | 'chain' | 'explosion' | 'nova';
type TechElement = 'fire' | 'ice' | 'lightning';

interface TechTuning {
  power: number;             // TechniqueManager base power
  pp: number;                // base PP cost (level discounts it)
  // bolt / fan / radial
  speed: number;             // m/s
  range: number;             // max travel, m
  pierce: boolean;           // keep flying through hit enemies
  // spiral (gifoie)
  rotSpeed: number;          // rad/s orbit
  expandSpeed: number;       // m/s radius growth
  maxRadius: number;         // fizzle-out radius
  fizzleStart: number;       // start shrinking here
  // fan (gibarta)
  waves: number;
  waveInterval: number;      // s between waves
  fanCount: number;          // bolts per wave
  fanSpreadDeg: number;      // angle between adjacent bolts
  // radial (rabarta)
  shardCount: number;
  // chain (gizonde)
  chainDist: number;         // max hop distance
  maxChainTargets: number;   // total targets incl. primary
  // explosion (rafoie)
  aoeRadius: number;
  splashMult: number;        // damage fraction for non-primary
  // nova (razonde)
  novaRadius: number;
  // targeting cone (strike / chain / explosion)
  targetRange: number;
  targetHalfAngleDeg: number;
}

interface TechDef {
  id: TechKey;
  label: string;
  element: TechElement;
  kind: TechKind;
  needsTarget: boolean;
  defaults: TechTuning;
}

const BASE_TUNING: TechTuning = {
  power: 50, pp: 5,
  speed: 20, range: 15, pierce: false,
  rotSpeed: 12, expandSpeed: 2, maxRadius: 5, fizzleStart: 4,
  waves: 3, waveInterval: 0.15, fanCount: 3, fanSpreadDeg: 6.9,
  shardCount: 10,
  chainDist: 8, maxChainTargets: 10,
  aoeRadius: 5, splashMult: 0.6,
  novaRadius: 12,
  targetRange: 15, targetHalfAngleDeg: 25,
};

const tech = (
  id: TechKey, label: string, element: TechElement, kind: TechKind,
  power: number, pp: number, over: Partial<TechTuning> = {},
): TechDef => ({
  id, label, element, kind,
  needsTarget: kind === 'strike' || kind === 'chain' || kind === 'explosion',
  defaults: { ...BASE_TUNING, power, pp, ...over },
});

// Powers/PP from TechniqueManager.TECHNIQUES; shapes from player.gd _spawn_*.
const TECHS: TechDef[] = [
  tech('foie',    'Foie',    'fire',      'bolt',      50,  5,  { speed: 20, range: 15, pierce: false }),
  tech('barta',   'Barta',   'ice',       'bolt',      55,  6,  { speed: 20, range: 15, pierce: true }),
  tech('zonde',   'Zonde',   'lightning', 'strike',    45,  4),
  tech('gifoie',  'Gifoie',  'fire',      'spiral',    120, 20, { rotSpeed: 12, expandSpeed: 2, maxRadius: 5, fizzleStart: 4 }),
  tech('gibarta', 'Gibarta', 'ice',       'fan',       130, 22, { speed: 18, range: 10, pierce: true, waves: 3, waveInterval: 0.15, fanCount: 3, fanSpreadDeg: 6.9 }),
  tech('gizonde', 'Gizonde', 'lightning', 'chain',     110, 18, { chainDist: 8, maxChainTargets: 10 }),
  tech('rafoie',  'Rafoie',  'fire',      'explosion', 200, 30, { aoeRadius: 5, splashMult: 0.6 }),
  tech('rabarta', 'Rabarta', 'ice',       'radial',    220, 35, { speed: 12, range: 8, pierce: true, shardCount: 10 }),
  tech('razonde', 'Razonde', 'lightning', 'nova',      180, 28, { novaRadius: 12 }),
];

const TECH_BY_ID = new Map(TECHS.map((t) => [t.id, t]));

// Hold-to-charge variants (TechniqueManager.CHARGE_MAP).
const CHARGE_MAP: Record<TechKey, TechKey> = {
  foie: 'rafoie', barta: 'rabarta', zonde: 'razonde',
  gifoie: 'gifoie', gibarta: 'gibarta', gizonde: 'gizonde',
  rafoie: 'rafoie', rabarta: 'rabarta', razonde: 'razonde',
};

const ELEMENT_HEX: Record<TechElement, number> = {
  fire: 0xff4d0d, ice: 0x4db3ff, lightning: 0xffff4d,
};
const ELEMENT_CSS: Record<TechElement, string> = {
  fire: '#f73', ice: '#7cf', lightning: '#ff5',
};

interface ClassDef { id: string; label: string; desc: string; gender: Gender; pc: string }

// Non-CAST roster from #/combat-room — CASTs have no technique access
// (ClassData.technique_limits empty), so they are not in this room.
const CLASSES: ClassDef[] = [
  { id: 'humar',     label: 'HUmar',     desc: 'Human Hunter',  gender: 'm', pc: 'pc_000' },
  { id: 'humarl',    label: 'HUmarl',    desc: 'Human Hunter',  gender: 'w', pc: 'pc_010' },
  { id: 'ramar',     label: 'RAmar',     desc: 'Human Ranger',  gender: 'm', pc: 'pc_020' },
  { id: 'ramarl',    label: 'RAmarl',    desc: 'Human Ranger',  gender: 'w', pc: 'pc_030' },
  { id: 'fomar',     label: 'FOmar',     desc: 'Human Force',   gender: 'm', pc: 'pc_040' },
  { id: 'fomarl',    label: 'FOmarl',    desc: 'Human Force',   gender: 'w', pc: 'pc_050' },
  { id: 'hunewm',    label: 'HUnewm',    desc: 'Newman Hunter', gender: 'm', pc: 'pc_060' },
  { id: 'hunewearl', label: 'HUnewearl', desc: 'Newman Hunter', gender: 'w', pc: 'pc_070' },
  { id: 'fonewm',    label: 'FOnewm',    desc: 'Newman Force',  gender: 'm', pc: 'pc_080' },
  { id: 'fonewearl', label: 'FOnewearl', desc: 'Newman Force',  gender: 'w', pc: 'pc_090' },
];

type CastAnim = 'rod' | 'wand';

interface Config {
  classId: string;
  anim: CastAnim;            // animation pack the cast clips come from
  tech: TechKey;
  level: number;             // tech disk level 1–30
  tecStat: number;           // caster's TEC stat
  chargeThreshold: number;   // s held before the charged variant fires
  perTech: Partial<Record<TechKey, Partial<TechTuning>>>;
}

const DEFAULT_CONFIG: Config = {
  classId: 'fonewearl', anim: 'wand', tech: 'foie',
  level: 10, tecStat: 100, chargeThreshold: 0.6, perTech: {},
};

function loadConfig(): Config {
  if (typeof window === 'undefined') return DEFAULT_CONFIG;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CONFIG;
    const parsed = JSON.parse(raw) as Partial<Config>;
    const cfg: Config = { ...DEFAULT_CONFIG, ...parsed };
    if (typeof cfg.perTech !== 'object' || cfg.perTech === null) cfg.perTech = {};
    if (!CLASSES.some((c) => c.id === cfg.classId)) cfg.classId = DEFAULT_CONFIG.classId;
    if (!TECH_BY_ID.has(cfg.tech)) cfg.tech = DEFAULT_CONFIG.tech;
    if (cfg.anim !== 'rod' && cfg.anim !== 'wand') cfg.anim = DEFAULT_CONFIG.anim;
    cfg.level = Math.min(30, Math.max(1, Math.round(cfg.level || 10)));
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

function getTechTuning(cfg: Config, id: TechKey): TechTuning {
  const def = TECH_BY_ID.get(id)!;
  return { ...def.defaults, ...(cfg.perTech[id] || {}) };
}

const rad2deg = (r: number) => (r * 180) / Math.PI;
const deg2rad = (d: number) => (d * Math.PI) / 180;

/** Distance from point (px,pz) to the segment (ax,az)→(bx,bz), in XZ.
 *  Used for SWEPT projectile hits — a fast bolt on a slow frame must not
 *  tunnel through a dummy between two discrete positions. */
function pointSegDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number {
  const dx = bx - ax;
  const dz = bz - az;
  const lenSq = dx * dx + dz * dz;
  const t = lenSq > 1e-8 ? Math.max(0, Math.min(1, ((px - ax) * dx + (pz - az) * dz) / lenSq)) : 0;
  return Math.hypot(px - (ax + dx * t), pz - (az + dz * t));
}

function stripRootMotion(clip: THREE.AnimationClip): void {
  clip.tracks = clip.tracks.filter((t) =>
    t.name !== '000_Root.position' && !t.name.endsWith('/000_Root.position'));
}

// ---------------------------------------------------------------------------
// Dummies + target cone (same flat XZ arena as #/combat-room)
// ---------------------------------------------------------------------------

interface Dummy {
  name: string;
  x: number; z: number;
  radius: number;
  maxHp: number;
  hp: number;
  hitFlash: number;
  hitCount: number;
}

const DEFAULT_DUMMIES: Array<Pick<Dummy, 'name' | 'x' | 'z' | 'radius' | 'maxHp'>> = [
  { name: 'Dummy A',     x: 0,    z: -3.5, radius: 0.5,  maxHp: 400 },
  { name: 'Dummy B',     x: -2.2, z: -3.0, radius: 0.5,  maxHp: 400 },
  { name: 'Dummy C',     x: 2.2,  z: -3.0, radius: 0.5,  maxHp: 400 },
  { name: 'Far Dummy',   x: 0.8,  z: -9.0, radius: 0.5,  maxHp: 400 },
  { name: 'Heavy Dummy', x: -4.5, z: -6.0, radius: 0.8,  maxHp: 900 },
  { name: 'Small Dummy', x: 4.2,  z: -1.2, radius: 0.35, maxHp: 200 },
  { name: 'Dummy G',     x: -1.5, z: 3.2,  radius: 0.5,  maxHp: 400 },
];

/** Nearest-first alive dummies inside a flat cone from the player (origin). */
function targetsInCone(yaw: number, range: number, halfAngleDeg: number, dummies: Dummy[]): number[] {
  const fx = Math.sin(yaw);
  const fz = Math.cos(yaw);
  const cosLimit = Math.cos(deg2rad(halfAngleDeg));
  const out: Array<{ i: number; d: number }> = [];
  for (let i = 0; i < dummies.length; i++) {
    const d = dummies[i];
    if (d.hp <= 0) continue;
    const dist = Math.hypot(d.x, d.z);
    if (dist > range + d.radius) continue;
    if (dist > 1e-4) {
      const cosA = (d.x * fx + d.z * fz) / dist;
      if (cosA < cosLimit) continue;
    }
    out.push({ i, d: dist });
  }
  out.sort((a, b) => a.d - b.d);
  return out.map((o) => o.i);
}

// ---------------------------------------------------------------------------
// Live effects (projectiles, spirals, rings, bolts, chain lines)
// ---------------------------------------------------------------------------

interface ProjEffect {
  type: 'proj';
  mesh: THREE.Mesh;
  x: number; z: number; y: number;
  dx: number; dz: number;
  speed: number; range: number; traveled: number;
  pierce: boolean;
  damage: number;
  hit: Set<number>;
  dead: boolean;
}

interface SpiralEffect {
  type: 'spiral';
  mesh: THREE.Mesh;
  angle: number; radius: number;
  rotSpeed: number; expandSpeed: number;
  maxRadius: number; fizzleStart: number;
  damage: number;
  hit: Set<number>;
  dead: boolean;
}

interface RingEffect {
  type: 'ring';
  mesh: THREE.Mesh;
  mat: THREE.MeshBasicMaterial;
  ttl: number; maxTtl: number;
  targetRadius: number;
  dead: boolean;
}

interface BoltEffect {
  type: 'boltfx';
  mesh: THREE.Mesh;
  mat: THREE.MeshBasicMaterial;
  ttl: number;
  dead: boolean;
}

interface LineEffect {
  type: 'line';
  line: THREE.Line;
  mat: THREE.LineBasicMaterial;
  ttl: number;
  dead: boolean;
}

type Effect = ProjEffect | SpiralEffect | RingEffect | BoltEffect | LineEffect;

interface PendingWave { t: number; yaw: number; damage: number; tuning: TechTuning; element: TechElement }

// ---------------------------------------------------------------------------

type Phase = 'idle' | 'charging' | 'cast';

interface Sim {
  phase: Phase;
  elapsed: number;
  clipLen: number;
  chargeT: number;
  chargeReadyLogged: boolean;
  yaw: number;
  displayYaw: number;
  desiredYaw: number | null;
  keysDown: Set<string>;
  pp: number;
  casts: number;
  hitsLanded: number;
}

const PP_MAX = 100;
const PP_REGEN = 5; // per second — mock-only pacing aid, not a shipped number

function freshSim(): Sim {
  return {
    phase: 'idle', elapsed: 0, clipLen: 0,
    chargeT: 0, chargeReadyLogged: false,
    yaw: Math.PI, displayYaw: Math.PI, desiredYaw: null,
    keysDown: new Set(), pp: PP_MAX, casts: 0, hitsLanded: 0,
  };
}

interface LogEntry { id: number; color: string; text: string }

interface DummyHandle {
  mesh: THREE.Mesh;
  ring: THREE.Mesh;
  ringMat: THREE.MeshBasicMaterial;
  bodyMat: THREE.MeshStandardMaterial;
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
  targetCone: THREE.Mesh;
  targetConeMat: THREE.MeshBasicMaterial;
  targetConeKey: string;
  rangeRing: THREE.Mesh;
  rangeRingKey: string;
  facingArrow: THREE.ArrowHelper;
  dummies: DummyHandle[];
  raycaster: THREE.Raycaster;
  dragIdx: number;
}

/** Sector mesh: apex at local origin, aimed at +Z (shared with combat-room). */
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

export default function TechRoom() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const simRef = useRef<Sim>(freshSim());
  const dummiesRef = useRef<Dummy[]>(DEFAULT_DUMMIES.map((d) => ({ ...d, hp: d.maxHp, hitFlash: 0, hitCount: 0 })));
  const effectsRef = useRef<Effect[]>([]);
  const wavesRef = useRef<PendingWave[]>([]);
  const logIdRef = useRef(0);

  const [config, setConfig] = useState<Config>(loadConfig);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [hud, setHud] = useState({
    phase: 'idle' as Phase, chargeT: 0, chargeReady: false,
    pp: PP_MAX, casts: 0, hits: 0, yawDeg: 180,
    primary: null as null | { name: string; hp: number; maxHp: number },
    targetCount: 0,
  });

  const classDef = CLASSES.find((c) => c.id === config.classId)!;
  const gender = classDef.gender;
  const techDef = TECH_BY_ID.get(config.tech)!;
  const tuning = getTechTuning(config, config.tech);
  const chargedId = CHARGE_MAP[config.tech];

  const configRef = useRef(config);
  configRef.current = config;

  useEffect(() => {
    try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); } catch { /* ignore */ }
  }, [config]);

  const pushLog = useCallback((text: string, color = '#aaa') => {
    logIdRef.current += 1;
    const id = logIdRef.current;
    setLog((prev) => [{ id, color, text }, ...prev].slice(0, 12));
  }, []);

  const setTuning = (patch: Partial<TechTuning>) => {
    setConfig((cfg) => ({
      ...cfg,
      perTech: { ...cfg.perTech, [cfg.tech]: { ...getTechTuning(cfg, cfg.tech), ...patch } },
    }));
  };

  // -------------------------------------------------------------------------
  // Animation helpers
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

  // -------------------------------------------------------------------------
  // Damage + effect spawning
  // -------------------------------------------------------------------------

  const hitDummy = useCallback((i: number, dmg: number) => {
    const d = dummiesRef.current[i];
    if (d.hp <= 0) return;
    d.hitFlash = 0.3;
    d.hitCount += 1;
    d.hp = Math.max(0, d.hp - dmg);
    simRef.current.hitsLanded += 1;
    if (d.hp <= 0) pushLog(`${d.name} defeated`, '#fa6');
  }, [pushLog]);

  const addEffect = useCallback((e: Effect) => {
    effectsRef.current.push(e);
  }, []);

  const makeOrb = useCallback((hex: number, radius: number): THREE.Mesh => {
    const s = sceneRef.current!;
    const mat = new THREE.MeshBasicMaterial({ color: hex });
    const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 10, 8), mat);
    s.scene.add(mesh);
    return mesh;
  }, []);

  const spawnProj = useCallback((yaw: number, damage: number, t: TechTuning, element: TechElement, ground: boolean, angleOffset = 0) => {
    const a = yaw + angleOffset;
    const dx = Math.sin(a);
    const dz = Math.cos(a);
    const y = ground ? 0.3 : 1.0;
    const mesh = makeOrb(ELEMENT_HEX[element], 0.22);
    mesh.position.set(dx * 0.5, y, dz * 0.5);
    addEffect({
      type: 'proj', mesh,
      x: dx * 0.5, z: dz * 0.5, y, dx, dz,
      speed: t.speed, range: t.range, traveled: 0,
      pierce: t.pierce, damage, hit: new Set(), dead: false,
    });
  }, [addEffect, makeOrb]);

  const spawnRing = useCallback((x: number, z: number, radius: number, hex: number, ttl = 0.5) => {
    const s = sceneRef.current!;
    const mat = new THREE.MeshBasicMaterial({
      color: hex, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false,
    });
    const mesh = new THREE.Mesh(new THREE.RingGeometry(0.85, 1, 48), mat);
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set(x, 0.05, z);
    mesh.scale.setScalar(0.05);
    s.scene.add(mesh);
    addEffect({ type: 'ring', mesh, mat, ttl, maxTtl: ttl, targetRadius: radius, dead: false });
  }, [addEffect]);

  const spawnBoltVisual = useCallback((x: number, z: number) => {
    const s = sceneRef.current!;
    const mat = new THREE.MeshBasicMaterial({
      color: ELEMENT_HEX.lightning, transparent: true, opacity: 0.9,
    });
    const mesh = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 10, 6), mat);
    mesh.position.set(x, 5, z);
    s.scene.add(mesh);
    addEffect({ type: 'boltfx', mesh, mat, ttl: 0.4, dead: false });
  }, [addEffect]);

  const spawnChainLine = useCallback((points: Array<{ x: number; z: number }>) => {
    const s = sceneRef.current!;
    const geo = new THREE.BufferGeometry().setFromPoints(
      points.map((p) => new THREE.Vector3(p.x, 1.0, p.z)));
    const mat = new THREE.LineBasicMaterial({ color: ELEMENT_HEX.lightning, transparent: true, opacity: 1 });
    const line = new THREE.Line(geo, mat);
    s.scene.add(line);
    addEffect({ type: 'line', line, mat, ttl: 0.4, dead: false });
  }, [addEffect]);

  /** Fire one gibarta wave (fanCount bolts around yaw). */
  const fireWave = useCallback((yaw: number, damage: number, t: TechTuning, element: TechElement) => {
    const mid = (t.fanCount - 1) / 2;
    for (let i = 0; i < t.fanCount; i++) {
      spawnProj(yaw, damage, t, element, true, deg2rad((i - mid) * t.fanSpreadDeg));
    }
  }, [spawnProj]);

  /** Spawn the selected tech's effect. Returns false when the cast whiffed
   *  for lack of a target (shipped: PP is already spent by then). */
  const spawnTechEffect = useCallback((id: TechKey, damage: number): boolean => {
    const def = TECH_BY_ID.get(id)!;
    const t = getTechTuning(configRef.current, id);
    const sim = simRef.current;
    const dummies = dummiesRef.current;
    const primaryList = def.needsTarget
      ? targetsInCone(sim.yaw, t.targetRange, t.targetHalfAngleDeg, dummies)
      : [];

    switch (def.kind) {
      case 'bolt':
        spawnProj(sim.yaw, damage, t, def.element, id === 'barta');
        return true;
      case 'fan': {
        fireWave(sim.yaw, damage, t, def.element);
        for (let w = 1; w < t.waves; w++) {
          wavesRef.current.push({ t: w * t.waveInterval, yaw: sim.yaw, damage, tuning: t, element: def.element });
        }
        return true;
      }
      case 'radial': {
        for (let i = 0; i < t.shardCount; i++) {
          spawnProj((i * Math.PI * 2) / t.shardCount, damage, t, def.element, true);
        }
        return true;
      }
      case 'spiral': {
        const mesh = makeOrb(ELEMENT_HEX[def.element], 0.25);
        addEffect({
          type: 'spiral', mesh,
          angle: sim.yaw, radius: 0.3,
          rotSpeed: t.rotSpeed, expandSpeed: t.expandSpeed,
          maxRadius: t.maxRadius, fizzleStart: t.fizzleStart,
          damage, hit: new Set(), dead: false,
        });
        return true;
      }
      case 'nova': {
        for (let i = 0; i < dummies.length; i++) {
          const d = dummies[i];
          if (d.hp <= 0) continue;
          if (Math.hypot(d.x, d.z) <= t.novaRadius) {
            hitDummy(i, damage);
            spawnBoltVisual(d.x, d.z);
          }
        }
        spawnRing(0, 0, t.novaRadius, ELEMENT_HEX[def.element]);
        return true;
      }
      case 'strike': {
        if (primaryList.length === 0) return false;
        const d = dummies[primaryList[0]];
        hitDummy(primaryList[0], damage);
        spawnBoltVisual(d.x, d.z);
        return true;
      }
      case 'explosion': {
        if (primaryList.length === 0) return false;
        const prim = dummies[primaryList[0]];
        const cx = prim.x;
        const cz = prim.z;
        hitDummy(primaryList[0], damage);
        for (let i = 0; i < dummies.length; i++) {
          if (i === primaryList[0]) continue;
          const d = dummies[i];
          if (d.hp <= 0) continue;
          if (Math.hypot(d.x - cx, d.z - cz) <= t.aoeRadius) {
            hitDummy(i, Math.round(damage * t.splashMult));
          }
        }
        spawnRing(cx, cz, t.aoeRadius, ELEMENT_HEX[def.element]);
        return true;
      }
      case 'chain': {
        if (primaryList.length === 0) return false;
        const hitIdx: number[] = [primaryList[0]];
        hitDummy(primaryList[0], damage);
        spawnBoltVisual(dummies[primaryList[0]].x, dummies[primaryList[0]].z);
        let last = dummies[primaryList[0]];
        for (let hop = 1; hop < t.maxChainTargets; hop++) {
          let best = -1;
          let bestDist = t.chainDist;
          for (let i = 0; i < dummies.length; i++) {
            const d = dummies[i];
            if (d.hp <= 0 || hitIdx.includes(i)) continue;
            const dist = Math.hypot(d.x - last.x, d.z - last.z);
            if (dist < bestDist) { bestDist = dist; best = i; }
          }
          if (best < 0) break;
          hitDummy(best, damage);
          spawnBoltVisual(dummies[best].x, dummies[best].z);
          hitIdx.push(best);
          last = dummies[best];
        }
        spawnChainLine([{ x: 0, z: 0 }, ...hitIdx.map((i) => ({ x: dummies[i].x, z: dummies[i].z }))]);
        return true;
      }
    }
  }, [spawnProj, fireWave, makeOrb, addEffect, hitDummy, spawnRing, spawnBoltVisual, spawnChainLine]);

  /** Cast: PP gate → spend → cast anim → spawn (shipped _cast_technique order:
   *  a target-less zonde/rafoie/gizonde still costs PP and swings the anim). */
  const castTech = useCallback((id: TechKey, viaCharge: boolean) => {
    const sim = simRef.current;
    const cfg = configRef.current;
    const def = TECH_BY_ID.get(id)!;
    const t = getTechTuning(cfg, id);
    const ppCost = Math.max(1, Math.round(t.pp - cfg.level / 5));
    if (sim.pp < ppCost) {
      pushLog(`not enough PP for ${def.label} (need ${ppCost}, have ${Math.floor(sim.pp)})`, '#f96');
      sim.phase = 'idle';
      playClip('wait', true);
      return;
    }
    sim.pp -= ppCost;
    sim.casts += 1;

    const scaled = Math.round(t.power * (1 + cfg.level / 10));
    const variance = 0.9 + Math.random() * 0.2; // CombatManager DAMAGE_VARIANCE 0.1
    const damage = Math.max(1, Math.round((scaled + cfg.tecStat) * variance));

    sim.phase = 'cast';
    sim.elapsed = 0;
    const len = playClip('tec', false);
    sim.clipLen = len > 0 ? len : 0.6;

    const landed = spawnTechEffect(id, damage);
    const chargeTag = viaCharge ? ' (charged)' : '';
    if (landed) {
      pushLog(`cast ${def.label}${chargeTag} — ${damage} dmg base, ${ppCost} PP`, ELEMENT_CSS[def.element]);
    } else {
      pushLog(`cast ${def.label}${chargeTag} — NO TARGET (${ppCost} PP still spent)`, '#f96');
    }
  }, [playClip, pushLog, spawnTechEffect]);

  const resetRoom = useCallback(() => {
    dummiesRef.current.forEach((d, i) => {
      const def = DEFAULT_DUMMIES[i];
      d.x = def.x; d.z = def.z; d.hp = def.maxHp; d.hitFlash = 0; d.hitCount = 0;
    });
    const sim = simRef.current;
    sim.pp = PP_MAX;
    sim.casts = 0;
    sim.hitsLanded = 0;
    for (const e of effectsRef.current) e.dead = true;
    wavesRef.current = [];
  }, []);

  const castRef = useRef(castTech);
  castRef.current = castTech;
  const resetRef = useRef(resetRoom);
  resetRef.current = resetRoom;
  const playClipRef = useRef(playClip);
  playClipRef.current = playClip;
  const pushLogRef = useRef(pushLog);
  pushLogRef.current = pushLog;

  // -------------------------------------------------------------------------
  // Keyboard — Z hold-to-charge, WASD steer, R reset
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
      const sim = simRef.current;
      if (e.code === 'KeyZ' || e.code === 'KeyJ') {
        if (sim.phase === 'idle') {
          sim.phase = 'charging';
          sim.chargeT = 0;
          sim.chargeReadyLogged = false;
          playClipRef.current('chg', true);
        }
      } else if (e.code === 'KeyR') {
        resetRef.current();
      }
    };
    const onUp = (e: KeyboardEvent) => {
      simRef.current.keysDown.delete(e.code);
      if (e.code === 'KeyZ' || e.code === 'KeyJ') {
        const sim = simRef.current;
        if (sim.phase === 'charging') {
          const cfg = configRef.current;
          const charged = sim.chargeT >= cfg.chargeThreshold;
          castRef.current(charged ? CHARGE_MAP[cfg.tech] : cfg.tech, charged);
        }
      }
    };
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
    camera.position.set(0, 14, 10);
    camera.lookAt(0, 0, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.75));
    const dir = new THREE.DirectionalLight(0xffffff, 0.7);
    dir.position.set(4, 8, 5);
    scene.add(dir);

    scene.add(new THREE.GridHelper(30, 60, 0x444466, 0x222238));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.5, 0);
    controls.mouseButtons = { LEFT: null as unknown as THREE.MOUSE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };

    const playerGroup = new THREE.Group();
    scene.add(playerGroup);

    // Targeting cone (violet) — only shown for target-required techs
    const targetConeMat = new THREE.MeshBasicMaterial({
      color: 0xaa66ff, transparent: true, opacity: 0.12, side: THREE.DoubleSide, depthWrite: false,
    });
    const targetCone = new THREE.Mesh(buildSectorGeometry(deg2rad(25), 15), targetConeMat);
    targetCone.visible = false;
    scene.add(targetCone);

    // Faint reach ring for the selected tech (range / nova radius / spiral max)
    const rangeRingMat = new THREE.MeshBasicMaterial({
      color: 0x8888cc, transparent: true, opacity: 0.18, side: THREE.DoubleSide, depthWrite: false,
    });
    const rangeRing = new THREE.Mesh(new THREE.RingGeometry(14.9, 15, 64), rangeRingMat);
    rangeRing.rotation.x = -Math.PI / 2;
    rangeRing.position.y = 0.01;
    scene.add(rangeRing);

    const facingArrow = new THREE.ArrowHelper(
      new THREE.Vector3(0, 0, -1), new THREE.Vector3(0, 0.05, 0), 2.0, 0x44ccff, 0.32, 0.18);
    scene.add(facingArrow);

    const dummyHandles: DummyHandle[] = dummiesRef.current.map((d, i) => {
      const bodyMat = new THREE.MeshStandardMaterial({ color: 0x8888aa, roughness: 0.8 });
      const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(d.radius * 0.55, 1.0, 4, 12), bodyMat);
      mesh.position.set(d.x, 0.85, d.z);
      mesh.userData.dummyIdx = i;
      scene.add(mesh);
      const ringMat = new THREE.MeshBasicMaterial({
        color: 0x555577, transparent: true, opacity: 0.7, side: THREE.DoubleSide,
      });
      const ring = new THREE.Mesh(new THREE.RingGeometry(d.radius - 0.05, d.radius, 32), ringMat);
      ring.rotation.x = -Math.PI / 2;
      ring.position.set(d.x, 0.02, d.z);
      scene.add(ring);
      return { mesh, ring, ringMat, bodyMat };
    });

    sceneRef.current = {
      scene, camera, renderer, controls, playerGroup,
      mixer: null, actions: {}, currentAction: null, clips: {},
      targetCone, targetConeMat, targetConeKey: '',
      rangeRing, rangeRingKey: '',
      facingArrow,
      dummies: dummyHandles,
      raycaster: new THREE.Raycaster(),
      dragIdx: -1,
    };

    // Dummy dragging (left button; orbit on right/middle)
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
        d.x = THREE.MathUtils.clamp(hitPoint.x, -14, 14);
        d.z = THREE.MathUtils.clamp(hitPoint.z, -14, 14);
      }
    };
    const onPointerUp = () => { if (sceneRef.current) sceneRef.current.dragIdx = -1; };
    renderer.domElement.addEventListener('pointerdown', onPointerDown);
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);

    const wrapAngle = (a: number) => {
      while (a > Math.PI) a -= Math.PI * 2;
      while (a < -Math.PI) a += Math.PI * 2;
      return a;
    };

    const disposeEffect = (e: Effect) => {
      if (e.type === 'line') {
        scene.remove(e.line);
        e.line.geometry.dispose();
        e.mat.dispose();
      } else {
        scene.remove(e.mesh);
        e.mesh.geometry.dispose();
        (e.mesh.material as THREE.Material).dispose();
      }
    };

    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const delta = Math.min(clock.getDelta(), 0.1);
      const s = sceneRef.current;
      const sim = simRef.current;
      if (!s) return;
      const cfg = configRef.current;
      const def = TECH_BY_ID.get(cfg.tech)!;
      const t = getTechTuning(cfg, cfg.tech);
      const dummies = dummiesRef.current;

      // steering input — free while idle or charging, locked during the cast
      let kx = 0; let kz = 0;
      const kd = sim.keysDown;
      if (kd.has('KeyW') || kd.has('ArrowUp')) kz -= 1;
      if (kd.has('KeyS') || kd.has('ArrowDown')) kz += 1;
      if (kd.has('KeyA') || kd.has('ArrowLeft')) kx -= 1;
      if (kd.has('KeyD') || kd.has('ArrowRight')) kx += 1;
      sim.desiredYaw = (kx !== 0 || kz !== 0) ? Math.atan2(kx, kz) : null;
      if (sim.phase !== 'cast' && sim.desiredYaw !== null) sim.yaw = sim.desiredYaw;

      // phase machine
      if (sim.phase === 'charging') {
        sim.chargeT += delta;
        if (!sim.chargeReadyLogged && sim.chargeT >= cfg.chargeThreshold) {
          sim.chargeReadyLogged = true;
          const charged = TECH_BY_ID.get(CHARGE_MAP[cfg.tech])!;
          pushLogRef.current(`charge ready — release casts ${charged.label}`, ELEMENT_CSS[charged.element]);
        }
      } else if (sim.phase === 'cast') {
        sim.elapsed += delta;
        if (sim.elapsed >= sim.clipLen) {
          sim.phase = 'idle';
          playClipRef.current('wait', true);
        }
      }

      // PP regen (mock pacing aid)
      sim.pp = Math.min(PP_MAX, sim.pp + PP_REGEN * delta);

      // pending gibarta waves
      const waves = wavesRef.current;
      for (let i = waves.length - 1; i >= 0; i--) {
        waves[i].t -= delta;
        if (waves[i].t <= 0) {
          const w = waves[i];
          const mid = (w.tuning.fanCount - 1) / 2;
          for (let b = 0; b < w.tuning.fanCount; b++) {
            const a = w.yaw + deg2rad((b - mid) * w.tuning.fanSpreadDeg);
            const mat = new THREE.MeshBasicMaterial({ color: ELEMENT_HEX[w.element] });
            const mesh = new THREE.Mesh(new THREE.SphereGeometry(0.22, 10, 8), mat);
            mesh.position.set(Math.sin(a) * 0.5, 0.3, Math.cos(a) * 0.5);
            scene.add(mesh);
            effectsRef.current.push({
              type: 'proj', mesh,
              x: Math.sin(a) * 0.5, z: Math.cos(a) * 0.5, y: 0.3,
              dx: Math.sin(a), dz: Math.cos(a),
              speed: w.tuning.speed, range: w.tuning.range, traveled: 0,
              pierce: w.tuning.pierce, damage: w.damage, hit: new Set(), dead: false,
            });
          }
          waves.splice(i, 1);
        }
      }

      // live effects
      for (const e of effectsRef.current) {
        if (e.dead) continue;
        if (e.type === 'proj') {
          const step = Math.min(e.speed * delta, e.range - e.traveled);
          const px = e.x;
          const pz = e.z;
          e.x += e.dx * step;
          e.z += e.dz * step;
          e.traveled += step;
          e.mesh.position.set(e.x, e.y, e.z);
          for (let i = 0; i < dummies.length; i++) {
            const d = dummies[i];
            if (d.hp <= 0 || e.hit.has(i)) continue;
            if (pointSegDist(d.x, d.z, px, pz, e.x, e.z) <= d.radius + 0.25) {
              e.hit.add(i);
              hitDummy(i, e.damage);
              if (!e.pierce) { e.dead = true; break; }
            }
          }
          if (e.traveled >= e.range) e.dead = true;
        } else if (e.type === 'spiral') {
          const px = Math.sin(e.angle) * e.radius;
          const pz = Math.cos(e.angle) * e.radius;
          e.angle += e.rotSpeed * delta;
          e.radius += e.expandSpeed * delta;
          const ex = Math.sin(e.angle) * e.radius;
          const ez = Math.cos(e.angle) * e.radius;
          e.mesh.position.set(ex, 1.0, ez);
          if (e.radius > e.fizzleStart) {
            const f = (e.radius - e.fizzleStart) / Math.max(0.01, e.maxRadius - e.fizzleStart);
            e.mesh.scale.setScalar(Math.max(1 - f, 0.05));
          }
          for (let i = 0; i < dummies.length; i++) {
            const d = dummies[i];
            if (d.hp <= 0 || e.hit.has(i)) continue;
            if (pointSegDist(d.x, d.z, px, pz, ex, ez) <= d.radius + 0.3) {
              e.hit.add(i);
              hitDummy(i, e.damage);
            }
          }
          if (e.radius >= e.maxRadius) e.dead = true;
        } else if (e.type === 'ring') {
          e.ttl -= delta;
          const p = 1 - Math.max(0, e.ttl) / e.maxTtl;
          e.mesh.scale.setScalar(Math.max(0.05, e.targetRadius * Math.min(1, p * 2)));
          e.mat.opacity = 0.55 * Math.max(0, e.ttl) / e.maxTtl;
          if (e.ttl <= 0) e.dead = true;
        } else if (e.type === 'boltfx') {
          e.ttl -= delta;
          e.mat.opacity = Math.max(0, e.ttl / 0.4) * 0.9;
          if (e.ttl <= 0) e.dead = true;
        } else if (e.type === 'line') {
          e.ttl -= delta;
          e.mat.opacity = Math.max(0, e.ttl / 0.4);
          if (e.ttl <= 0) e.dead = true;
        }
      }
      for (let i = effectsRef.current.length - 1; i >= 0; i--) {
        if (effectsRef.current[i].dead) {
          disposeEffect(effectsRef.current[i]);
          effectsRef.current.splice(i, 1);
        }
      }

      // targeting scan (HUD + reticle tint) — target techs use their cone;
      // non-target techs still show what the strike would grab for reference
      const targetable = def.needsTarget
        ? targetsInCone(sim.yaw, t.targetRange, t.targetHalfAngleDeg, dummies)
        : [];
      const primIdx = targetable.length > 0 ? targetable[0] : -1;

      // visuals
      sim.displayYaw += wrapAngle(sim.yaw - sim.displayYaw) * Math.min(1, delta * 14);
      s.playerGroup.rotation.y = sim.displayYaw;
      s.facingArrow.setDirection(new THREE.Vector3(Math.sin(sim.displayYaw), 0, Math.cos(sim.displayYaw)));

      // charge glow: pulse the facing arrow color when ready
      const chargeReady = sim.phase === 'charging' && sim.chargeT >= cfg.chargeThreshold;
      s.facingArrow.setColor(chargeReady ? ELEMENT_HEX[TECH_BY_ID.get(CHARGE_MAP[cfg.tech])!.element] : 0x44ccff);

      // target cone
      s.targetCone.visible = def.needsTarget;
      if (def.needsTarget) {
        const key = `${t.targetHalfAngleDeg}:${t.targetRange}`;
        if (key !== s.targetConeKey) {
          s.targetCone.geometry.dispose();
          s.targetCone.geometry = buildSectorGeometry(deg2rad(t.targetHalfAngleDeg), t.targetRange);
          s.targetConeKey = key;
        }
        s.targetCone.rotation.y = sim.displayYaw;
      }

      // reach ring for the selected tech
      const reach = def.kind === 'nova' ? t.novaRadius
        : def.kind === 'spiral' ? t.maxRadius
        : def.kind === 'explosion' || def.kind === 'strike' || def.kind === 'chain' ? 0
        : t.range;
      s.rangeRing.visible = reach > 0;
      if (reach > 0) {
        const key = `${reach}`;
        if (key !== s.rangeRingKey) {
          s.rangeRing.geometry.dispose();
          s.rangeRing.geometry = new THREE.RingGeometry(reach - 0.08, reach, 64);
          s.rangeRingKey = key;
        }
      }

      // dummies: primary bright, targetable green, hit flash red, dead slump
      for (let i = 0; i < s.dummies.length; i++) {
        const dh = s.dummies[i];
        const d = dummies[i];
        dh.mesh.position.x = d.x;
        dh.mesh.position.z = d.z;
        dh.ring.position.set(d.x, 0.02, d.z);
        const isPrimary = primIdx === i;
        const inSet = targetable.includes(i);
        const dead = d.hp <= 0;
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
            dh.bodyMat.color.setHex(isPrimary ? 0xffee66 : inSet ? 0x66dd88 : 0x8888aa);
            dh.ringMat.color.setHex(isPrimary ? 0xffee66 : inSet ? 0x33aa55 : 0x555577);
          }
        }
        dh.ringMat.opacity = inSet ? 0.95 : 0.5;
      }

      if (s.mixer) s.mixer.update(delta);
      controls.update();
      renderer.render(scene, camera);

      const prim = primIdx >= 0 ? dummies[primIdx] : null;
      setHud({
        phase: sim.phase, chargeT: sim.chargeT, chargeReady,
        pp: sim.pp, casts: sim.casts, hits: sim.hitsLanded,
        yawDeg: rad2deg(sim.yaw),
        primary: prim ? { name: prim.name, hp: prim.hp, maxHp: prim.maxHp } : null,
        targetCount: targetable.length,
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
      for (const e of effectsRef.current) disposeEffect(e);
      effectsRef.current = [];
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
      sceneRef.current = null;
    };
  }, [hitDummy]);

  // -------------------------------------------------------------------------
  // Model + animation loading (class model + rod/wand pack: wait, tec, chg)
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setIsLoading(true);
    setLoadError(null);
    const prev = simRef.current;
    simRef.current = { ...freshSim(), pp: prev.pp, casts: prev.casts, hitsLanded: prev.hitsLanded };

    s.playerGroup.clear();
    s.mixer = null;
    s.actions = {};
    s.currentAction = null;
    s.clips = {};

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const pc = classDef.pc;
    const animGlb = `${config.anim}_${gender}`;
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
          ['wait', '_wait'], ['tec', '_tec'], ['chg', '_chg'],
        ];
        const mixer = new THREE.AnimationMixer(gltf.scene);
        for (const [key, suffix] of wanted) {
          const clip = animGltf.animations.find((a) => a.name.endsWith(suffix));
          if (!clip) continue;
          stripRootMotion(clip);
          s.clips[key] = clip;
          s.actions[key] = mixer.clipAction(clip);
        }
        if (!s.clips.wait || !s.clips.tec) {
          setLoadError(`Missing clips in ${animGlb}.glb`);
          setIsLoading(false);
          return;
        }
        s.mixer = mixer;
        setIsLoading(false);
        playClip('wait', true);
      }, undefined, (err) => { setLoadError(`Animation load failed: ${err}`); setIsLoading(false); });
    }, undefined, (err) => { setLoadError(`Model load failed: ${err}`); setIsLoading(false); });

    return () => { cancelled = true; };
  }, [config.classId, config.anim, classDef.pc, gender, playClip]);

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  const copyGdscript = useCallback(() => {
    const t = tuning;
    const d = techDef;
    const lines: string[] = [
      `# Technique effect tuning — ${d.label} (${d.element}, ${d.kind})`,
      `# From web #/tech-room (shipped _spawn_* shapes in player.gd).`,
      `\t"${d.id}": {`,
      `\t\t"power": ${t.power},`,
      `\t\t"pp": ${t.pp},`,
    ];
    if (d.kind === 'bolt' || d.kind === 'fan' || d.kind === 'radial') {
      lines.push(`\t\t"speed": ${t.speed.toFixed(1)},`);
      lines.push(`\t\t"max_range": ${t.range.toFixed(1)},`);
      lines.push(`\t\t"pierce": ${t.pierce},`);
    }
    if (d.kind === 'fan') {
      lines.push(`\t\t"waves": ${t.waves},`);
      lines.push(`\t\t"wave_interval": ${t.waveInterval.toFixed(2)},`);
      lines.push(`\t\t"fan_count": ${t.fanCount},`);
      lines.push(`\t\t"fan_spread_deg": ${t.fanSpreadDeg.toFixed(1)},`);
    }
    if (d.kind === 'radial') lines.push(`\t\t"shard_count": ${t.shardCount},`);
    if (d.kind === 'spiral') {
      lines.push(`\t\t"rot_speed": ${t.rotSpeed.toFixed(1)},  # rad/s`);
      lines.push(`\t\t"expand_speed": ${t.expandSpeed.toFixed(2)},`);
      lines.push(`\t\t"max_radius": ${t.maxRadius.toFixed(1)},`);
      lines.push(`\t\t"fizzle_start": ${t.fizzleStart.toFixed(1)},`);
    }
    if (d.kind === 'chain') {
      lines.push(`\t\t"chain_dist": ${t.chainDist.toFixed(1)},`);
      lines.push(`\t\t"max_chain_targets": ${t.maxChainTargets},`);
    }
    if (d.kind === 'explosion') {
      lines.push(`\t\t"aoe_radius": ${t.aoeRadius.toFixed(1)},`);
      lines.push(`\t\t"splash_mult": ${t.splashMult.toFixed(2)},`);
    }
    if (d.kind === 'nova') lines.push(`\t\t"nova_radius": ${t.novaRadius.toFixed(1)},`);
    if (d.needsTarget) {
      lines.push(`\t\t"target_range": ${t.targetRange.toFixed(1)},`);
      lines.push(`\t\t"target_half_angle_deg": ${t.targetHalfAngleDeg.toFixed(1)},`);
    }
    lines.push(`\t},`);
    navigator.clipboard.writeText(lines.join('\n'));
    pushLog(`copied GDScript for ${d.label}`, '#6b8afd');
  }, [tuning, techDef, pushLog]);

  const resetTech = () => {
    if (!confirm(`Reset ${techDef.label} tuning to defaults?`)) return;
    setConfig((cfg) => {
      const next = { ...cfg.perTech };
      delete next[cfg.tech];
      return { ...cfg, perTech: next };
    });
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

  const scaledPower = Math.round(tuning.power * (1 + config.level / 10));
  const ppCost = Math.max(1, Math.round(tuning.pp - config.level / 5));

  const phaseLabel = hud.phase === 'idle' ? 'IDLE'
    : hud.phase === 'charging'
      ? (hud.chargeReady ? `CHARGED — release: ${TECH_BY_ID.get(chargedId)!.label}` : `charging ${(hud.chargeT * 1000).toFixed(0)} ms`)
      : 'CASTING';

  const kind = techDef.kind;

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: 16, boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: 16, height: '100%' }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
          <div style={{
            background: '#2d2d44', borderRadius: 8, padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16,
          }}>
            <span style={{ fontSize: 14, fontWeight: 'bold', color: '#6bf' }}>
              Tech Room — {classDef.label} · {techDef.label} Lv.{config.level}
            </span>
            <span style={{ fontSize: 12, color: hud.chargeReady ? ELEMENT_CSS[TECH_BY_ID.get(chargedId)!.element] : '#888' }}>
              {phaseLabel}
            </span>
            <span style={{ fontSize: 12, color: '#888', display: 'flex', alignItems: 'center', gap: 8 }}>
              <span>PP</span>
              <span style={{ width: 90, height: 8, background: '#1a1a2e', borderRadius: 3, overflow: 'hidden', display: 'inline-block' }}>
                <span style={{
                  display: 'block', height: '100%', width: `${(hud.pp / PP_MAX) * 100}%`,
                  background: hud.pp >= ppCost ? '#4d9de0' : '#d8663a',
                }} />
              </span>
              <span style={{ fontVariantNumeric: 'tabular-nums' }}>{Math.floor(hud.pp)}/{PP_MAX}</span>
              · <span style={{ color: '#4f4' }}>{hud.hits} hits</span> · {hud.casts} casts
            </span>
            {isLoading && <span style={{ color: '#888', fontSize: 12 }}>(loading…)</span>}
            {loadError && <span style={{ color: '#f88', fontSize: 12 }}>{loadError}</span>}
          </div>

          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: 8, overflow: 'hidden', position: 'relative' }} ref={containerRef}>
            <div style={{
              position: 'absolute', left: 10, top: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              <span style={{ color: ELEMENT_CSS[techDef.element] }}>Z</span> cast (hold ≥{config.chargeThreshold.toFixed(1)} s → {TECH_BY_ID.get(chargedId)!.label}) ·{' '}
              WASD steer · R reset · drag dummies · right-drag orbit
            </div>
            <div style={{
              position: 'absolute', right: 10, bottom: 10, fontSize: 11, color: '#99a',
              background: 'rgba(10,10,26,0.75)', padding: '6px 10px', borderRadius: 6, pointerEvents: 'none',
            }}>
              <span style={{ color: '#a7f' }}>violet</span> = target cone ·{' '}
              <span style={{ color: '#99c' }}>ring</span> = reach ·{' '}
              <span style={{ color: '#fe6' }}>yellow</span> = primary ·{' '}
              <span style={{ color: '#f54' }}>red</span> = hit
            </div>

            {hud.primary && (
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
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Caster</h3>
            <select value={config.classId} onChange={(e) => setConfig((c) => ({ ...c, classId: e.target.value }))}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12, marginBottom: 8 }}>
              {CLASSES.map((c) => (
                <option key={c.id} value={c.id}>{c.label} — {c.desc} ({c.gender === 'w' ? 'F' : 'M'})</option>
              ))}
            </select>
            <select value={config.anim} onChange={(e) => setConfig((c) => ({ ...c, anim: e.target.value as CastAnim }))}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12 }}>
              <option value="rod">Rod cast animation (rod_{gender})</option>
              <option value="wand">Wand cast animation (wand_{gender})</option>
            </select>
            <div style={{ fontSize: 10, color: '#666', marginTop: 6 }}>
              CASTs are not in the roster — technique_limits is empty for them
              (TechniqueManager.can_learn). Any weapon pack carries a _tec clip;
              rod/wand are the Force pair.
            </div>
          </div>

          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Technique</h3>
            <select value={config.tech} onChange={(e) => setConfig((c) => ({ ...c, tech: e.target.value as TechKey }))}
              style={{ width: '100%', padding: 8, background: '#1a1a2e', color: '#fff', border: '1px solid #444', borderRadius: 4, fontSize: 12, marginBottom: 10 }}>
              {TECHS.map((t) => (
                <option key={t.id} value={t.id}>{t.label} — {t.element} · {t.kind}</option>
              ))}
            </select>
            {sliderRow('Tech level', config.level, 1, 30, 1,
              (v) => setConfig((c) => ({ ...c, level: Math.round(v) })), (v) => `Lv.${v.toFixed(0)}`)}
            {sliderRow('Caster TEC stat', config.tecStat, 0, 300, 5,
              (v) => setConfig((c) => ({ ...c, tecStat: Math.round(v) })), (v) => `${v.toFixed(0)}`)}
            {sliderRow('Base power', tuning.power, 0, 400, 5,
              (v) => setTuning({ power: Math.round(v) }), (v) => `${v.toFixed(0)}`)}
            {sliderRow('Base PP cost', tuning.pp, 1, 60, 1,
              (v) => setTuning({ pp: Math.round(v) }), (v) => `${v.toFixed(0)} PP`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Damage = power × (1 + level/10) + TEC, ±10% variance
              (CombatManager.calculate_technique_damage) →{' '}
              <span style={{ color: '#ccc' }}>{scaledPower + config.tecStat} ±10%</span>.
              PP cost = max(1, pp − level/5) → <span style={{ color: '#ccc' }}>{ppCost} PP</span>.
            </div>
          </div>

          {/* Effect shape */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Effect shape — {techDef.label}
            </h3>
            {(kind === 'bolt' || kind === 'fan' || kind === 'radial') && (
              <>
                {sliderRow('Projectile speed', tuning.speed, 4, 40, 0.5,
                  (v) => setTuning({ speed: v }), (v) => `${v.toFixed(1)} m/s`)}
                {sliderRow('Max range', tuning.range, 2, 30, 0.5,
                  (v) => setTuning({ range: v }), (v) => `${v.toFixed(1)} m`)}
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#aaa', marginBottom: 8 }}>
                  <input type="checkbox" checked={tuning.pierce}
                    onChange={(e) => setTuning({ pierce: e.target.checked })} />
                  Pierce — keep flying through hit enemies
                </label>
              </>
            )}
            {kind === 'fan' && (
              <>
                {sliderRow('Waves', tuning.waves, 1, 5, 1,
                  (v) => setTuning({ waves: Math.round(v) }), (v) => `${v.toFixed(0)}`)}
                {sliderRow('Wave interval', tuning.waveInterval, 0.05, 0.5, 0.01,
                  (v) => setTuning({ waveInterval: v }), (v) => `${(v * 1000).toFixed(0)} ms`)}
                {sliderRow('Bolts per wave', tuning.fanCount, 1, 7, 1,
                  (v) => setTuning({ fanCount: Math.round(v) }), (v) => `${v.toFixed(0)}`)}
                {sliderRow('Fan spread', tuning.fanSpreadDeg, 0, 30, 0.5,
                  (v) => setTuning({ fanSpreadDeg: v }), (v) => `${v.toFixed(1)}° apart`)}
              </>
            )}
            {kind === 'radial' && sliderRow('Shard count', tuning.shardCount, 4, 24, 1,
              (v) => setTuning({ shardCount: Math.round(v) }), (v) => `${v.toFixed(0)}`)}
            {kind === 'spiral' && (
              <>
                {sliderRow('Orbit speed', tuning.rotSpeed, 2, 24, 0.5,
                  (v) => setTuning({ rotSpeed: v }), (v) => `${v.toFixed(1)} rad/s`)}
                {sliderRow('Expand speed', tuning.expandSpeed, 0.5, 6, 0.1,
                  (v) => setTuning({ expandSpeed: v }), (v) => `${v.toFixed(1)} m/s`)}
                {sliderRow('Max radius', tuning.maxRadius, 2, 12, 0.5,
                  (v) => setTuning({ maxRadius: v, fizzleStart: Math.min(tuning.fizzleStart, v - 0.5) }), (v) => `${v.toFixed(1)} m`)}
                {sliderRow('Fizzle starts', tuning.fizzleStart, 1, 11, 0.5,
                  (v) => setTuning({ fizzleStart: Math.min(v, tuning.maxRadius - 0.5) }), (v) => `${v.toFixed(1)} m`)}
              </>
            )}
            {kind === 'chain' && (
              <>
                {sliderRow('Chain hop distance', tuning.chainDist, 2, 15, 0.5,
                  (v) => setTuning({ chainDist: v }), (v) => `${v.toFixed(1)} m`)}
                {sliderRow('Max chain targets', tuning.maxChainTargets, 2, 15, 1,
                  (v) => setTuning({ maxChainTargets: Math.round(v) }), (v) => `${v.toFixed(0)}`)}
              </>
            )}
            {kind === 'explosion' && (
              <>
                {sliderRow('Explosion radius', tuning.aoeRadius, 1, 10, 0.5,
                  (v) => setTuning({ aoeRadius: v }), (v) => `${v.toFixed(1)} m`)}
                {sliderRow('Splash damage', tuning.splashMult, 0, 1, 0.05,
                  (v) => setTuning({ splashMult: v }), (v) => `×${v.toFixed(2)}`)}
              </>
            )}
            {kind === 'nova' && sliderRow('Nova radius', tuning.novaRadius, 3, 20, 0.5,
              (v) => setTuning({ novaRadius: v }), (v) => `${v.toFixed(1)} m`)}
            {kind === 'strike' && (
              <div style={{ fontSize: 10, color: '#666', marginBottom: 6 }}>
                Zonde is an instant strike on the primary target — its shape IS
                the targeting cone below.
              </div>
            )}
            <div style={{ fontSize: 10, color: '#666' }}>
              Defaults mirror the shipped _spawn_{techDef.id}() in player.gd.
              Pierce bolts (Barta / Gibarta / Rabarta) hit every enemy along the
              path; non-pierce stops at the first.
            </div>
          </div>

          {/* Targeting */}
          {techDef.needsTarget && (
            <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
              <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
                Targeting cone
              </h3>
              {sliderRow('Target range', tuning.targetRange, 5, 25, 0.5,
                (v) => setTuning({ targetRange: v }), (v) => `${v.toFixed(1)} m`)}
              {sliderRow('Half-angle', tuning.targetHalfAngleDeg, 5, 60, 1,
                (v) => setTuning({ targetHalfAngleDeg: v }), (v) => `${v.toFixed(0)}°`)}
              <div style={{ fontSize: 10, color: '#666' }}>
                {techDef.label} needs a primary target. The runtime widens the
                weapon scan cone for equipped techs (_update_combat_targets;
                zonde forces ≥25° half-angle) — the mock owns the geometry
                directly. Open question (shipped behavior kept here): a cast
                with no target still spends PP and plays the cast animation.
              </div>
            </div>
          )}

          {/* Charge */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              Hold-to-charge
            </h3>
            {sliderRow('Charge threshold', config.chargeThreshold, 0.2, 2.0, 0.05,
              (v) => setConfig((c) => ({ ...c, chargeThreshold: v })), (v) => `${(v * 1000).toFixed(0)} ms`)}
            <div style={{ fontSize: 10, color: '#666' }}>
              Hold Z past the threshold, release to cast the CHARGE_MAP
              variant: {techDef.label} →{' '}
              <span style={{ color: ELEMENT_CSS[TECH_BY_ID.get(chargedId)!.element] }}>
                {TECH_BY_ID.get(chargedId)!.label}
              </span>
              {chargedId === config.tech ? ' (charges to itself)' : ''}.
              Shipped threshold: 0.6 s (player.gd TECH_CHARGE_THRESHOLD).
              The charged cast uses the charged tech's own tuning and PP cost.
            </div>
          </div>

          {/* Log */}
          <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: 10 }}>
            <h3 style={{ fontSize: 12, color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>Log</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minHeight: 60 }}>
              {log.length === 0 && <span style={{ fontSize: 11, color: '#555' }}>Z to cast…</span>}
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
              Copy GDScript — {techDef.label}
            </button>
            <button onClick={resetRoom} style={{
              padding: 8, background: '#1a1a2e', border: '1px solid #444',
              borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 12,
            }}>
              Reset dummies + PP + stats
            </button>
            <button onClick={resetTech} style={{
              padding: 8, background: '#1a1a2e', border: '1px solid #444',
              borderRadius: 4, color: '#aaa', cursor: 'pointer', fontSize: 12,
            }}>
              Reset {techDef.label} to defaults
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
