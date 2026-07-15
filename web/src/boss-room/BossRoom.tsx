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
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import { assetUrl } from '../utils/assets';
import {
  GEM_HEX,
  arenaFloorUrl,
  arenaModelUrl,
  arenaSkyboxUrl,
  bossPartUrl,
  loadBossConfig,
  loadRoster,
  partAnimated,
  partInstances,
  partName,
  resolveBoss,
  resolveClipToken,
  segmentFamilies,
  type BossArenaConfig,
  type BossAttackDef,
  type BossPartInstance,
  type RosterEntry,
  type SegmentFamily,
} from './types';
import { damageBoss, lobImpacts, makeBossSim, stepBoss, type BossEvent, type BossSim, type BossStateName } from './sim';
import {
  DEFAULT_DIP,
  DEFAULT_LIFT,
  DEFAULT_REACH,
  curveDip,
  curveLift,
  defaultArch,
  makeSampler,
  poseBonesAlongCurve,
  retargetTip,
  setDip,
  setLift,
  translateCurve,
  type BonePose,
  type CurveSampler,
  type RestBone,
  type Vec3Tuple,
} from './curvePose';

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
  /** Composite boss: index into boss.forms (which rig is loaded). */
  form?: number;
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
  /** Re-apply the session curves (curvesRef) to every part rig + rebuild the gizmos. */
  refreshCurves(): void;
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
  const [clickMode, setClickMode] = useState<'anchor' | 'boss' | 'curve' | 'curve-base' | 'curve-tip' | null>(null);
  const clickModeRef = useRef(clickMode);
  const [markers, setMarkers] = useState<Marker[]>([]);
  // Tentacle poser (#508): session curves keyed `${part}:${instanceIndex}`,
  // control points in the boss's local frame (spec /states/bosses parts).
  const [curveTarget, setCurveTarget] = useState<string | null>(null);
  const curveTargetRef = useRef<string | null>(null);
  const [curves, setCurves] = useState<Record<string, Vec3Tuple[]>>({});
  const curvesRef = useRef<Record<string, Vec3Tuple[]>>({});
  // Roll about the tube axis per instance (suckers down) — curve pose only.
  const [rolls, setRolls] = useState<Record<string, number>>({});
  const rollsRef = useRef<Record<string, number>>({});
  const [curveOverlay, setCurveOverlay] = useState(true);
  const curveOverlayRef = useRef(true);
  // Start depth used when PLACING a fresh arch (the emergence sits this far
  // below the clicked water surface); once a curve exists the slider edits
  // the curve itself.
  const [dip, setDipDefault] = useState(DEFAULT_DIP);
  const dipRef = useRef(DEFAULT_DIP);
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
  // Composite boss (forms): the picked form's rig is what loads. A form with
  // `part_of` is a part rig (the robot's split halves), loaded from the
  // parent enemy's parts/ dir instead of a top-level model.
  const formIdx = ov.form ?? 0;
  const activeForm = boss?.forms?.[formIdx] ?? boss?.forms?.[0];
  const effectiveModelId = activeForm?.model_id ?? boss?.model_id ?? '';
  const effectiveGlbUrl = activeForm?.part_of
    ? bossPartUrl(activeForm.part_of, effectiveModelId)
    : assetUrl(`assets/enemies/${effectiveModelId}/${effectiveModelId}.glb`);
  const families = useMemo(() => segmentFamilies(clips), [clips]);

  const setOverride = (patch: Overrides) => {
    const next = { ...overrides, [bossId]: { ...overrides[bossId], ...patch } };
    setOverrides(next);
    saveStore(next);
  };

  // Seed the session curves from the authored data whenever the boss changes.
  useEffect(() => {
    const b = config?.bosses[bossId];
    if (!b) return;
    const seeded: Record<string, Vec3Tuple[]> = {};
    const seededRolls: Record<string, number> = {};
    for (const p of b.parts ?? []) {
      partInstances(p).forEach((inst, i) => {
        if (inst.curve && inst.curve.length >= 2) {
          seeded[`${partName(p)}:${i}`] = inst.curve.map((pt) => [...pt] as Vec3Tuple);
        }
        if (inst.roll_deg !== undefined) seededRolls[`${partName(p)}:${i}`] = inst.roll_deg;
      });
    }
    setCurves(seeded);
    setRolls(seededRolls);
    setCurveTarget(null);
  }, [config, bossId]);

  // Poser curves merge into parts[].instances[].curve. They live in the
  // BOSS's local frame (not the arena frame), so — unlike anchors — they
  // merge regardless of which arena is loaded. An empty session curve
  // strips a previously authored one (revert to pos/yaw placement).
  const mergeSessionCurves = () => {
    const round = (pts: Vec3Tuple[]) => pts.map((pt) => pt.map((n) => +n.toFixed(2)) as Vec3Tuple);
    return boss?.parts?.map((p) => {
      const name = partName(p);
      let touched = false;
      const instances = partInstances(p).map((inst, i) => {
        const key = `${name}:${i}`;
        const c = curves[key];
        const roll = rolls[key] ?? 0;
        const { curve: _c, roll_deg: _r, ...rest } = inst;
        const next = {
          ...rest,
          ...(roll !== 0 ? { roll_deg: +roll.toFixed(1) } : {}),
          ...(c && c.length >= 2 ? { curve: round(c) } : {}),
        } as BossPartInstance;
        if (JSON.stringify(next) === JSON.stringify(inst)) return inst;
        touched = true;
        return next;
      });
      // Spread the object form so part-level fields (animated) survive the merge.
      return touched ? { ...(typeof p === 'string' ? {} : p), part: name, instances } : p;
    });
  };

  // Just the tentacles: this boss's parts with the session curves merged —
  // paste over the boss's "parts": field in data/boss_arenas.json.
  const copyParts = () => {
    const parts = mergeSessionCurves();
    if (parts) navigator.clipboard?.writeText(JSON.stringify(parts, null, 2) + '\n');
  };

  // Round-trip export: the whole config with this boss's clicked markers
  // merged into its authored anchors — paste over data/boss_arenas.json.
  // Markers only merge in the default arena (anchors ride that frame).
  const copyConfig = () => {
    if (!config || !boss) return;
    const inHomeArena = arenaId === boss.arena;
    const merged = inHomeArena
      ? [...(boss.anchors ?? []), ...markers.map((m) => ({ name: m.name, pos: m.pos }))]
      : (boss.anchors ?? []);
    // The CURRENT boss position (wherever "move boss" put it) is authored
    // as spawn_pos — this is how staging like humilias's broken-ledge spot
    // gets captured without reading numbers off the HUD.
    const spawnPos: [number, number, number] | undefined = inHomeArena
      ? [+readout.boss[0].toFixed(2), +readout.boss[1].toFixed(2), +readout.boss[2].toFixed(2)]
      : boss.spawn_pos;
    const mergedParts = mergeSessionCurves();
    const cfg: BossArenaConfig = {
      ...config,
      bosses: {
        ...config.bosses,
        [bossId]: {
          ...boss,
          anchors: merged,
          ...(spawnPos ? { spawn_pos: spawnPos } : {}),
          ...(mergedParts ? { parts: mergedParts } : {}),
        },
      },
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
    let floorMaxY = 0; // top of the collider — settle fallback where it has holes (the octopus pool)
    let arenaMesh: THREE.Object3D | null = null;
    let skyMesh: THREE.Object3D | null = null; // carries the pool water plane (o0s_zsky 1_water2)
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
        floorMaxY = box.max.y;
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
        if (authoredPos) {
          placeBossAuthored(authoredPos);
        } else {
          bossPos.set(c.x, box.max.y + 5, c.z);
          settleBoss();
        }
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
        skyMesh = g.scene;
        oneLoaded();
      }, undefined, oneLoaded); // skybox is decorative — missing is fine
    }

    // Boss rig — clips come from the loaded GLB, never assumed.
    loader.load(
      effectiveGlbUrl,
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
      () => setStatus(`boss model failed: ${effectiveModelId}`),
    );

    // Multi-part pieces (tentacles, faces, horn) — ride the boss group and
    // mirror the body's clips by name. Decorative: loading doesn't gate the
    // room, a missing part just logs to the status line.
    //
    // Tube rigs (the tentacles) can additionally be POSED along an authored
    // curve (#508, spec /states/bosses parts contract): flat sibling bones
    // under a root, rest-spaced along local +X, so a Catmull-Rom through the
    // control points arc-length-sampled at the rest offsets IS the pose.
    interface PartBoneInfo {
      root: THREE.Bone;
      children: THREE.Bone[]; // direct bone children of root, sorted by rest x
      rest: RestBone[]; // [root, ...children] order
      restLocal: Array<{ pos: THREE.Vector3; quat: THREE.Quaternion }>;
    }
    interface PartRig {
      key: string; // `${part}:${instanceIndex}` — matches the curves store
      wrapper: THREE.Group;
      authored: BossPartInstance;
      /** false = never mirrors the body's clips (octopus tentacles) — holds its wrapper/curve pose. */
      animated: boolean;
      mixer: THREE.AnimationMixer;
      animations: THREE.AnimationClip[];
      action: THREE.AnimationAction | null;
      boneInfo: PartBoneInfo | null;
      /** Non-null while an authored curve poses this rig. */
      sampler: CurveSampler | null;
    }
    const partRigs: PartRig[] = [];

    function extractBoneInfo(rig: THREE.Object3D): PartBoneInfo | null {
      let root: THREE.Bone | null = null;
      rig.traverse((o) => {
        const b = o as THREE.Bone;
        if (b.isBone && !(b.parent as THREE.Bone | null)?.isBone && !root) root = b;
      });
      if (!root) return null;
      const children = (root as THREE.Bone).children
        .filter((c): c is THREE.Bone => (c as THREE.Bone).isBone)
        .sort((a, b) => a.position.x - b.position.x);
      const bones = [root as THREE.Bone, ...children];
      return {
        root,
        children,
        rest: bones.map((b, i) =>
          i === 0
            ? { arc: 0, lateral: [0, 0] as [number, number] }
            : { arc: b.position.x, lateral: [b.position.y, b.position.z] as [number, number] },
        ),
        restLocal: bones.map((b) => ({ pos: b.position.clone(), quat: b.quaternion.clone() })),
      };
    }

    /** Write boss-local {pos, quat} poses ([root, ...children] order) into the bones. */
    function poseBonesWorld(rig: PartRig, poses: BonePose[]) {
      const info = rig.boneInfo!;
      bossGroup.updateWorldMatrix(true, false);
      rig.wrapper.updateWorldMatrix(true, true);
      const bossQuat = bossGroup.getWorldQuaternion(new THREE.Quaternion());
      const setBone = (bone: THREE.Bone, parent: THREE.Object3D, pose: BonePose) => {
        const posW = bossGroup.localToWorld(pose.pos.clone());
        bone.position.copy(parent.worldToLocal(posW));
        const parentQuatW = parent.getWorldQuaternion(new THREE.Quaternion());
        bone.quaternion.copy(parentQuatW.invert().multiply(bossQuat.clone().multiply(pose.quat)));
      };
      const rootParent = info.root.parent as THREE.Object3D;
      setBone(info.root, rootParent, poses[0]);
      info.root.updateWorldMatrix(true, false);
      info.children.forEach((b, i) => setBone(b, info.root, poses[i + 1]));
    }

    /** Apply (or revert) the session curve for one rig. */
    function applyCurvePose(rig: PartRig) {
      const info = rig.boneInfo;
      if (!info) return;
      const pts = curvesRef.current[rig.key];
      if (!pts || pts.length < 2) {
        // Revert: authored wrapper placement + rest bone pose.
        rig.sampler = null;
        const a = rig.authored;
        rig.wrapper.position.set(a.pos[0], a.pos[1], a.pos[2]);
        rig.wrapper.rotation.set(((a.pitch_deg ?? 0) * Math.PI) / 180, ((a.yaw_deg ?? 0) * Math.PI) / 180, 0);
        [info.root, ...info.children].forEach((b, i) => {
          b.position.copy(info.restLocal[i].pos);
          b.quaternion.copy(info.restLocal[i].quat);
        });
        return;
      }
      // The curve — not the wrapper — places the piece (spec parts contract).
      const roll = rollsRef.current[rig.key] ?? 0;
      rig.sampler = makeSampler(pts, roll);
      rig.wrapper.position.set(0, 0, 0);
      rig.wrapper.rotation.set(0, 0, 0);
      poseBonesWorld(rig, poseBonesAlongCurve(info.rest, pts, roll));
    }

    // Control-point gizmos + fitted-spline line for the instance being edited.
    // A child of bossGroup: curve points are boss-local, so the viz rides the
    // boss's transform exactly like the tentacles do.
    const curveViz = new THREE.Group();
    bossGroup.add(curveViz);
    function rebuildCurveViz() {
      curveViz.clear();
      const key = curveTargetRef.current;
      const pts = key ? curvesRef.current[key] : undefined;
      if (!pts?.length) return;
      pts.forEach((p, i) => {
        const dot = new THREE.Mesh(
          new THREE.SphereGeometry(i === 0 ? 0.4 : 0.3, 12, 8),
          new THREE.MeshBasicMaterial({ color: i === 0 ? 0x4ade80 : 0xfacc15 }),
        );
        dot.position.set(p[0], p[1], p[2]);
        curveViz.add(dot);
      });
      if (pts.length >= 2) {
        const curve = new THREE.CatmullRomCurve3(pts.map((p) => new THREE.Vector3(...p)), false, 'centripetal');
        const line = new THREE.Line(
          new THREE.BufferGeometry().setFromPoints(curve.getPoints(60)),
          new THREE.LineBasicMaterial({ color: 0xfacc15 }),
        );
        curveViz.add(line);
      }
    }

    function refreshCurves() {
      for (const rig of partRigs) applyCurvePose(rig);
      rebuildCurveViz();
    }

    for (const partDef of boss.parts ?? []) {
      const name = partName(partDef);
      loader.load(
        bossPartUrl(effectiveModelId, name),
        (g) => {
          if (disposed) return;
          // One wrapper per instance (position/yaw/pitch in the boss's local
          // frame, +z = facing); skinned rigs are cloned via SkeletonUtils so
          // every instance animates independently of its siblings.
          partInstances(partDef).forEach((inst, i) => {
            const rig = cloneSkinned(g.scene);
            const wrapper = new THREE.Group();
            wrapper.position.set(inst.pos[0], inst.pos[1], inst.pos[2]);
            wrapper.rotation.order = 'YXZ';
            wrapper.rotation.y = ((inst.yaw_deg ?? 0) * Math.PI) / 180;
            wrapper.rotation.x = ((inst.pitch_deg ?? 0) * Math.PI) / 180;
            wrapper.add(rig);
            bossGroup.add(wrapper);
            const partRig: PartRig = {
              key: `${name}:${i}`,
              wrapper,
              authored: inst,
              animated: partAnimated(partDef),
              mixer: new THREE.AnimationMixer(rig),
              animations: g.animations,
              action: null,
              boneInfo: extractBoneInfo(rig),
              sampler: null,
            };
            partRigs.push(partRig);
            if (name.startsWith('z_002_tt')) {
              wrapper.visible = false; // strike arm starts hidden until an attack presentation
            }
            applyCurvePose(partRig); // authored/session curve, if any
          });
        },
        undefined,
        () => setStatus(`part failed: ${name}`),
      );
    }

    // Clip-overlay support: which nodes a clip actually animates. An
    // untracked bone keeps its rest curvilinear coords in the remap —
    // reading its live transform would feed back our own written pose.
    const trackedCache = new WeakMap<THREE.AnimationClip, { pos: Set<string>; quat: Set<string> }>();
    function clipTrackSets(clip: THREE.AnimationClip) {
      let sets = trackedCache.get(clip);
      if (!sets) {
        sets = { pos: new Set(), quat: new Set() };
        for (const t of clip.tracks) {
          const dot = t.name.lastIndexOf('.');
          const node = t.name.slice(0, dot);
          const prop = t.name.slice(dot + 1);
          if (prop === 'position') sets.pos.add(node);
          else if (prop === 'quaternion') sets.quat.add(node);
        }
        trackedCache.set(clip, sets);
      }
      return sets;
    }

    /**
     * Wave-along-curve overlay (#508 blend mode): the clip's bone positions
     * are curvilinear coords in the root's rest frame (arc = x, lateral =
     * y/z) — re-map them onto the authored curve each frame.
     */
    function overlayCurvePoses() {
      for (const rig of partRigs) {
        if (!rig.sampler || !rig.boneInfo || !rig.action?.isRunning()) continue;
        const info = rig.boneInfo;
        const sets = clipTrackSets(rig.action.getClip());
        const poses: BonePose[] = [rig.sampler.poseAt(0)];
        info.children.forEach((b, i) => {
          const rest = info.restLocal[i + 1];
          const clipPos = sets.pos.has(b.name) ? b.position : rest.pos;
          const pose = rig.sampler!.poseAt(clipPos.x, [clipPos.y, clipPos.z]);
          pose.quat.multiply(sets.quat.has(b.name) ? b.quaternion : rest.quat);
          poses.push(pose);
        });
        poseBonesWorld(rig, poses);
      }
    }

    /** Play the same-named clip on every ANIMATED part rig (parts share the body's clip names). */
    function syncParts(clipName: string, loopMode: THREE.AnimationActionLoopStyles, reps: number) {
      for (const rig of partRigs) {
        if (!rig.animated) continue; // only the boss moves — the tentacles hold their pose
        rig.mixer.stopAllAction();
        rig.action = null;
        const clip = rig.animations.find((a) => a.name === clipName);
        if (!clip) continue; // static part (dragon horn) just rides the group
        const action = rig.mixer.clipAction(clip);
        action.reset();
        action.setLoop(loopMode, reps);
        action.clampWhenFinished = true;
        action.play();
        rig.action = action;
        if (rig.key.startsWith('z_002_tt')) {
          const isAttackClip = !['wat', 'wattir', 'float', 'wttr2wt'].includes(clipName);
          rig.wrapper.visible = isAttackClip;
        }
      }
    }

    function dropToFloor(p: THREE.Vector3): number | null {
      if (!floorMesh) return null;
      raycaster.set(new THREE.Vector3(p.x, p.y + STEP_UP + 100, p.z), DOWN);
      const hits = raycaster.intersectObject(floorMesh, true);
      return hits.length ? hits[0].point.y : null;
    }

    // Visual waterline offset — the octopus body sits IN the pool, not on
    // the walkable collider. Logical bossPos (readouts, sim) stays on the
    // floor; only the rendered group sinks.
    const modelOffsetY = boss.model_offset_y ?? 0;
    // Authored staging (humilias at the broken stage edge): spawn_pos is
    // trusted verbatim — including y, since the spot may be OFF the walkable
    // collider — and only applies in the boss's default arena.
    const authoredPos = arenaId === boss.arena ? boss.spawn_pos : undefined;
    function settleBoss() {
      // Colliders can have holes where only the boss lives (the octopus
      // pool) — settle to the collider's top there instead of dangling at
      // the spawn height, so model_offset_y has a stable reference.
      const y = dropToFloor(bossPos) ?? (floorMesh ? floorMaxY : null);
      if (y !== null) bossPos.y = y;
      bossGroup.position.set(bossPos.x, bossPos.y + modelOffsetY, bossPos.z);
    }
    function placeBossAuthored(pos: [number, number, number]) {
      bossPos.set(pos[0], pos[1], pos[2]);
      bossGroup.position.set(bossPos.x, bossPos.y + modelOffsetY, bossPos.z);
    }

    // ——— clip playback ———
    function stopClips() {
      mixer?.stopAllAction();
      for (const rig of partRigs) {
        rig.mixer.stopAllAction();
        rig.action = null;
      }
      currentAction = null;
      chain = null;
      setActiveClip(null);
      setClipDuration(0);
      refreshCurves(); // curve-posed rigs snap back to the static authored pose
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
      syncParts(clip.name, loopMode, reps);
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

    // Enrage tint: "turns red on the edges" — approximated with a red
    // emissive on the rig's materials; cleared when the sim resets.
    function tintBoss(on: boolean) {
      bossGroup.traverse((o) => {
        const mat = (o as THREE.Mesh).material as THREE.MeshStandardMaterial | undefined;
        if (mat?.emissive) mat.emissive.setHex(on ? 0x881111 : 0x000000);
      });
    }

    // Sim events → the existing playback machinery + player HP.
    function handleSimEvents(events: BossEvent[]) {
      for (const ev of events) {
        if (ev.type === 'anim') {
          if (ev.loop && ev.tokens.length === 1) {
            const name = resolveClipToken(animations.map((a) => a.name), ev.tokens[0]);
            if (name) playClip(name, true);
          } else {
            playTokens(ev.tokens, ev.lpLoops ?? 2);
          }
        } else if (ev.type === 'player-hit') {
          playerHp = Math.max(0, playerHp - ev.damage);
          if (ev.knockback) {
            // wing flap: shove the player along the boss's facing
            feet.x += ev.knockback.x;
            feet.z += ev.knockback.z;
            const ky = dropToFloor(feet);
            if (ky !== null) feet.y = Math.max(feet.y, ky);
          }
          if (playerHp <= 0) {
            feet.copy(spawn); // downed → respawn with full HP, sim keeps running
            velY = 0;
            playerHp = PLAYER_MAX_HP;
          }
        } else if (ev.type === 'player-pull') {
          feet.x += ev.dx;
          feet.z += ev.dz;
          const ky = dropToFloor(feet);
          if (ky !== null) feet.y = Math.max(feet.y, ky);
        } else if (ev.type === 'enrage') {
          tintBoss(true);
        }
      }
    }

    // Sim ordnance visuals: pooled fireball spheres + lob impact rings.
    const ordnanceGroup = new THREE.Group();
    scene.add(ordnanceGroup);
    const projPool: THREE.Mesh[] = [];
    const ringPool: THREE.Mesh[] = [];

    // Gem caster visuals (Chaos Sorcerer): two gems flanking the boss, tinted
    // by the held colors. Children of bossGroup so they ride the hover/teleport.
    const gemMeshes: THREE.Mesh[] = [0, 1].map((slot) => {
      const m = new THREE.Mesh(
        new THREE.OctahedronGeometry(0.35),
        new THREE.MeshBasicMaterial({ color: 0xffffff }),
      );
      m.position.set(slot === 0 ? -2.2 : 2.2, 1.6, 0.3);
      m.visible = false;
      bossGroup.add(m);
      return m;
    });
    // The casting gem: sits in front of the sorcerer and spins rapidly while a
    // spell is being cast, then vanishes at release.
    const castGemMesh = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.45),
      new THREE.MeshBasicMaterial({ color: 0xffffff }),
    );
    castGemMesh.position.set(0, 1.7, 2.6);
    castGemMesh.visible = false;
    bossGroup.add(castGemMesh);
    function syncGems() {
      if (!sim || !sim.gems) {
        for (const m of gemMeshes) m.visible = false;
        castGemMesh.visible = false;
        return;
      }
      sim.gems.forEach((color, i) => {
        const m = gemMeshes[i];
        if (!color) { m.visible = false; return; }
        m.visible = true;
        (m.material as THREE.MeshBasicMaterial).color.setHex(GEM_HEX[color]);
        m.rotation.y += 0.03; // slow idle spin
      });
      if (sim.castingGem) {
        castGemMesh.visible = true;
        (castGemMesh.material as THREE.MeshBasicMaterial).color.setHex(GEM_HEX[sim.castingGem]);
        castGemMesh.rotation.y += 0.5; // rapid spin while casting
      } else {
        castGemMesh.visible = false;
      }
    }
    function poolGet(pool: THREE.Mesh[], i: number, make: () => THREE.Mesh): THREE.Mesh {
      while (pool.length <= i) {
        const m = make();
        pool.push(m);
        ordnanceGroup.add(m);
      }
      pool[i].visible = true;
      return pool[i];
    }
    function syncOrdnance() {
      for (const m of [...projPool, ...ringPool]) m.visible = false;
      if (!sim) return;
      sim.projectiles.forEach((p, i) => {
        const m = poolGet(projPool, i, () => new THREE.Mesh(
          new THREE.SphereGeometry(0.5, 10, 8),
          new THREE.MeshBasicMaterial({ color: 0xff7722 }),
        ));
        const gy = dropToFloor(new THREE.Vector3(p.pos.x, bossPos.y + 2, p.pos.z));
        m.position.set(p.pos.x, (gy ?? bossPos.y) + 1.5, p.pos.z);
      });
      let ringIdx = 0;
      for (const l of sim.lobs) {
        for (const impact of lobImpacts(l)) {
          const m = poolGet(ringPool, ringIdx++, () => new THREE.Mesh(
            new THREE.RingGeometry(0.4, 2.5, 24),
            new THREE.MeshBasicMaterial({ color: 0xff3311, side: THREE.DoubleSide, transparent: true, opacity: 0.5 }),
          ));
          const gy = dropToFloor(new THREE.Vector3(impact.x, bossPos.y + 2, impact.z));
          m.position.set(impact.x, (gy ?? 0) + 0.06, impact.z);
          m.rotation.x = -Math.PI / 2;
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
        tintBoss(false);
        syncOrdnance();
        syncGems();
        settleBoss();
        refreshCurves();
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
        for (const rig of partRigs) rig.mixer.timeScale = v;
      },
      setPaused: (p) => {
        animPaused = p;
      },
      scrub: (t) => {
        if (!currentAction || !mixer) return;
        currentAction.time = t;
        mixer.update(0);
        for (const rig of partRigs) {
          if (rig.action) {
            rig.action.time = t;
            rig.mixer.update(0);
          }
        }
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
      refreshCurves,
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
      // Curve points also live on the pool water, which is a HOLE in the
      // walkable collider AND lives in the skybox GLB (o0s_zsky 1_water2) —
      // so curve modes raycast the arena visual and skybox too, nearest hit
      // wins (the water plane beats the sky dome anywhere that matters).
      const curveMode = mode === 'curve' || mode === 'curve-base' || mode === 'curve-tip';
      const targets = (curveMode ? [floorMesh, arenaMesh, skyMesh] : [floorMesh ?? arenaMesh]).filter(
        (t): t is THREE.Object3D => !!t,
      );
      if (!mode || !targets.length) return;
      if (Math.abs(ev.clientX - downX) > 4 || Math.abs(ev.clientY - downY) > 4) return; // drag
      const rect = renderer.domElement.getBoundingClientRect();
      const m = new THREE.Vector2(
        ((ev.clientX - rect.left) / rect.width) * 2 - 1,
        -((ev.clientY - rect.top) / rect.height) * 2 + 1,
      );
      raycaster.setFromCamera(m, camera);
      const wasVisible = targets.map((t) => t.visible);
      for (const t of targets) t.visible = true; // raycast needs the floor even when hidden
      const hits = raycaster.intersectObjects(targets, true);
      targets.forEach((t, i) => (t.visible = wasVisible[i]));
      if (!hits.length) return;
      const p = hits[0].point;
      if (curveMode) {
        const key = curveTargetRef.current;
        if (!key) {
          setClickMode(null);
          return;
        }
        const local = bossGroup.worldToLocal(p.clone());
        const pt: Vec3Tuple = [+local.x.toFixed(2), +local.y.toFixed(2), +local.z.toFixed(2)];
        setCurves((cur) => {
          const prev = cur[key] ?? [];
          let next: Vec3Tuple[];
          if (mode === 'curve-base') {
            // PLACE: a fresh default arch at the click (emergence dipped
            // below the clicked water surface), or move the whole authored
            // curve there with its bend AND start depth preserved.
            next = prev.length >= 2
              ? translateCurve(prev, [pt[0], pt[1] - curveDip(prev), pt[2]])
              : defaultArch(pt, undefined, DEFAULT_REACH, DEFAULT_LIFT, dipRef.current);
          } else if (mode === 'curve-tip') {
            // BEND: keep the base, re-aim the tip (needs a placed curve).
            next = prev.length >= 2
              ? retargetTip(prev, pt)
              : defaultArch(pt, undefined, DEFAULT_REACH, DEFAULT_LIFT, dipRef.current);
          } else {
            next = [...prev, pt]; // free-form append
          }
          return { ...cur, [key]: next };
        });
        // place/bend are one-shot; free-form point adding stays sticky.
        if (mode !== 'curve') setClickMode(null);
        return;
      }
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
        const gy2 = dropToFloor(new THREE.Vector3(sim.pos.x, bossPos.y + 2, sim.pos.z)) ?? (floorMesh ? floorMaxY : null);
        bossPos.set(sim.pos.x, (gy2 ?? bossPos.y) + sim.alt, sim.pos.z);
        bossGroup.position.set(bossPos.x, bossPos.y + modelOffsetY, bossPos.z);
        bossGroup.rotation.y = sim.yaw;
        syncOrdnance();
        syncGems();
      } else if (facePlayerLocal) {
        const dx = feet.x - bossPos.x;
        const dz = feet.z - bossPos.z;
        if (dx * dx + dz * dz > 1e-6) bossGroup.rotation.y = Math.atan2(dx, dz);
      }

      if (mixer && !animPaused) {
        mixer.update(dt);
        for (const rig of partRigs) {
          // Pure-curve mode freezes the rig on the authored pose; with the
          // overlay on, the clip plays and is re-mapped onto the curve below.
          if (rig.sampler && !curveOverlayRef.current) continue;
          rig.mixer.update(dt);
        }
        overlayCurvePoses();
      }

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
      (window as any).__bossRoom = {
        scene, feet, bossPos, playClip, playChain,
        get mixer() { return mixer; },
        refs: { curvesRef, curveTargetRef, clickModeRef, dipRef },
        get partRigs() { return partRigs; },
      };
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
  }, [config, bossId, arenaId, effectiveModelId, effectiveGlbUrl]);

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
  useEffect(() => {
    curvesRef.current = curves;
    apiRef.current?.refreshCurves();
  }, [curves]);
  useEffect(() => {
    curveTargetRef.current = curveTarget;
    apiRef.current?.refreshCurves();
  }, [curveTarget]);
  useEffect(() => {
    curveOverlayRef.current = curveOverlay;
    apiRef.current?.refreshCurves();
  }, [curveOverlay]);
  useEffect(() => {
    dipRef.current = dip;
  }, [dip]);
  useEffect(() => {
    rollsRef.current = rolls;
    apiRef.current?.refreshCurves();
  }, [rolls]);

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
            {rosterName}
            {activeForm ? ` — ${activeForm.label}` : ''}{' '}
            <span style={{ color: '#667', fontWeight: 400 }}>({effectiveModelId})</span>
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

        {boss?.forms && boss.forms.length > 0 && (
          <>
            <span style={label}>Form (composite boss — the fight cycles these)</span>
            <select
              value={formIdx}
              onChange={(e) => setOverride({ form: +e.target.value })}
              style={{ width: '100%', background: '#1a1a35', color: '#fff', border: '1px solid #334' }}
            >
              {boss.forms.map((f, i) => (
                <option key={f.roster_id} value={i}>
                  {f.label} — {f.roster_id} ({f.model_id})
                </option>
              ))}
            </select>
          </>
        )}

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
        {boss && (boss.parts?.length ?? 0) > 0 && (
          <>
            <span style={label}>Tentacle poser (#508) — points are boss-local, +z = facing</span>
            <select
              value={curveTarget ?? ''}
              onChange={(e) => {
                setCurveTarget(e.target.value || null);
                if (!e.target.value) setClickMode((m) => (m === 'curve' ? null : m));
              }}
              style={{ width: '100%', background: '#1a1a35', color: '#fff', border: '1px solid #334' }}
            >
              <option value="">— pick a part instance —</option>
              {(boss.parts ?? []).flatMap((p) =>
                partInstances(p).map((_, i) => {
                  const k = `${partName(p)}:${i}`;
                  const n = curves[k]?.length ?? 0;
                  return (
                    <option key={k} value={k}>
                      {partName(p)} #{i + 1}
                      {n ? ` · ${n} pt${n === 1 ? '' : 's'}` : ''}
                    </option>
                  );
                }),
              )}
            </select>
            {curveTarget && (
              <>
                <div style={{ display: 'flex', gap: 6 }}>
                  <button
                    onClick={() => setClickMode(clickMode === 'curve-base' ? null : 'curve-base')}
                    title="Click the ground/water to place the tentacle there — a fresh default arch, or the authored curve moved with its bend preserved."
                    style={{
                      ...btn,
                      flex: 1,
                      background: clickMode === 'curve-base' ? '#4ade80' : btn.background,
                      color: clickMode === 'curve-base' ? '#000' : btn.color,
                    }}
                  >
                    {clickMode === 'curve-base' ? 'click ground to place…' : 'place (click ground)'}
                  </button>
                  <button
                    onClick={() => setClickMode(clickMode === 'curve-tip' ? null : 'curve-tip')}
                    title="Click where the tip should reach — keeps the base, re-aims the arch at the current lift."
                    style={{
                      ...btn,
                      flex: 1,
                      background: clickMode === 'curve-tip' ? '#facc15' : btn.background,
                      color: clickMode === 'curve-tip' ? '#000' : btn.color,
                    }}
                  >
                    {clickMode === 'curve-tip' ? 'click tip target…' : 'bend (click tip)'}
                  </button>
                </div>
                {(curves[curveTarget]?.length ?? 0) >= 3 && (
                  <>
                    <span style={label}>Lift: {curveLift(curves[curveTarget]!).toFixed(2)}</span>
                    <input
                      type="range"
                      min={-2}
                      max={12}
                      step={0.25}
                      value={curveLift(curves[curveTarget]!)}
                      onChange={(e) =>
                        setCurves((cur) => ({ ...cur, [curveTarget]: setLift(cur[curveTarget]!, +e.target.value) }))
                      }
                      style={{ width: '100%' }}
                    />
                  </>
                )}
                {(curves[curveTarget]?.length ?? 0) >= 2 && (
                  <>
                    <span style={label}>Roll (turn the suckers): {(rolls[curveTarget] ?? 0).toFixed(0)}°</span>
                    <input
                      type="range"
                      min={-180}
                      max={180}
                      step={5}
                      value={rolls[curveTarget] ?? 0}
                      onChange={(e) => setRolls((cur) => ({ ...cur, [curveTarget]: +e.target.value }))}
                      style={{ width: '100%' }}
                    />
                  </>
                )}
                <span style={label}>
                  Start depth: {((curves[curveTarget]?.length ?? 0) >= 2 ? curveDip(curves[curveTarget]!) : dip).toFixed(2)}{' '}
                  (emergence below the click — in the water)
                </span>
                <input
                  type="range"
                  min={0}
                  max={8}
                  step={0.25}
                  value={(curves[curveTarget]?.length ?? 0) >= 2 ? curveDip(curves[curveTarget]!) : dip}
                  onChange={(e) => {
                    const v = +e.target.value;
                    setDipDefault(v);
                    if ((curves[curveTarget]?.length ?? 0) >= 2) {
                      setCurves((cur) => ({ ...cur, [curveTarget]: setDip(cur[curveTarget]!, v) }));
                    }
                  }}
                  style={{ width: '100%' }}
                />
                <button
                  onClick={() => setClickMode(clickMode === 'curve' ? null : 'curve')}
                  style={{
                    ...btn,
                    background: clickMode === 'curve' ? '#4ade80' : btn.background,
                    color: clickMode === 'curve' ? '#000' : btn.color,
                  }}
                >
                  {clickMode === 'curve' ? 'adding points — click floor/water (click again to stop)' : 'add points (click)'}
                </button>
                {(curves[curveTarget] ?? []).map((pt, i) => (
                  <div key={i} style={{ display: 'flex', gap: 4, marginTop: 2, alignItems: 'center' }}>
                    <span style={{ color: i === 0 ? '#4ade80' : '#889', fontSize: 10, width: 12 }}>{i === 0 ? '●' : i}</span>
                    {([0, 1, 2] as const).map((axis) => (
                      <input
                        key={axis}
                        type="number"
                        step={0.25}
                        value={+pt[axis].toFixed(2)}
                        onChange={(e) => {
                          const v = +e.target.value;
                          if (!Number.isFinite(v)) return;
                          setCurves((cur) => {
                            const arr = cur[curveTarget]!.map((q) => [...q] as Vec3Tuple);
                            arr[i][axis] = v;
                            return { ...cur, [curveTarget]: arr };
                          });
                        }}
                        style={{ width: 52, background: '#1a1a35', color: '#cdf', border: '1px solid #334', fontSize: 11 }}
                      />
                    ))}
                    <button
                      onClick={() => setCurves((cur) => ({ ...cur, [curveTarget]: cur[curveTarget]!.filter((_, j) => j !== i) }))}
                      style={btn}
                    >
                      ✕
                    </button>
                  </div>
                ))}
                {(curves[curveTarget]?.length ?? 0) === 1 && (
                  <div style={{ color: '#a86', fontSize: 11, marginTop: 2 }}>need ≥2 points to pose (emergence → apex → tip)</div>
                )}
                {(curves[curveTarget]?.length ?? 0) > 0 && (
                  <button onClick={() => setCurves((cur) => ({ ...cur, [curveTarget]: [] }))} style={btn}>
                    clear curve (revert to pos/yaw)
                  </button>
                )}
                <label style={{ ...label, cursor: 'pointer' }}>
                  <input type="checkbox" checked={curveOverlay} onChange={(e) => setCurveOverlay(e.target.checked)} /> clip
                  overlay — the wave rides the authored curve
                </label>
              </>
            )}
            <button
              onClick={copyParts}
              title='Copies this boss&apos;s "parts" array with the session curves merged in — paste over the parts field in data/boss_arenas.json.'
              style={{ ...btn, display: 'block', width: '100%' }}
            >
              copy tentacles (parts JSON, curves merged)
            </button>
          </>
        )}

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
            title="Copies data/boss_arenas.json with this boss's clicked markers merged into its anchors AND the current boss position as spawn_pos (use 'move boss' to stage it first) — paste over the file (rename anchors by hand)."
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
                // Keep the dark theme background when inactive — `undefined`
                // here reverted to the browser's light default button, leaving
                // the light-blue label unreadable.
                background: activeClip === c ? '#2a4a2a' : btn.background,
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
