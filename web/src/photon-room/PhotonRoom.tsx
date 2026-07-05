import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/**
 * Viewer/mock for the two photon systems the game doesn't implement yet:
 *
 * Photon Arts — every weapon animation pack carries `<prefix>_pa1/2/3`
 * (level 1-3 photon art) clips alongside the atk1-3 combo. In PSZ the PA
 * fires as the finisher input at the end of a full combo, so the tool's
 * "combo → PA" playback chains atk1 → atk2 → atk3 → PA the way the game
 * sequences them. NOTE: the shipped packs currently only contain `_pa3` —
 * the psz-asset-viewer extractor collapsed the three pa NARCs into one GLB
 * (fixed there; packs regain pa1/pa2 on the next re-extract + reimport).
 * The level buttons light up per what the loaded pack actually has.
 *
 * Photon Blasts — the four mag blasts (fb_bird/kenta/hebi/rabbit from
 * raw/player/pb_*.narc, extracted via psz-asset-viewer). Every weapon pack
 * also carries the player-side summon pose `<prefix>_pb` + `_pb_lp` hold
 * loop, so "Summon" plays the full exchange: player pb → pb_lp hold while
 * the creature runs its clips → creature departs, player back to wait.
 *
 * Data still untranslated (raw/ in psz-asset-viewer): paeff00-16.rel
 * (per-category PA effect tables), pb_param_data.rel + mag_param.narc
 * (PB damage/params), and the per-set mot_rel*.rel motion metadata.
 *
 * Controls: Z/J photon art · X/K combo → PA · C/L summon blast · R reset.
 */

const STORAGE_KEY = 'psz-photon-room:v1';

type Gender = 'm' | 'w';
type Mode = 'arts' | 'blasts';

interface WeaponDef {
  id: string;
  label: string;
  glbBase: string; // assets/player/animations/<base>_<m|w>.glb
}

// Every imported animation pack (all carry _pa3 + _pb/_pb_lp). `common` is
// the unarmed/bare pack — its pa clips are the fist photon art.
const WEAPONS: WeaponDef[] = [
  { id: 'fists',   label: 'Fists',        glbBase: 'common' },
  { id: 'saber',   label: 'Saber',        glbBase: 'saver' },
  { id: 'sword',   label: 'Sword',        glbBase: 'sword' },
  { id: 'daggers', label: 'Daggers',      glbBase: 'dagger' },
  { id: 'claw',    label: 'Claw',         glbBase: 'claw' },
  { id: 'dsaber',  label: 'Double Saber', glbBase: 'dsaver' },
  { id: 'spear',   label: 'Spear',        glbBase: 'spear' },
  { id: 'slicer',  label: 'Slicer',       glbBase: 'slicer' },
  { id: 'handgun', label: 'Handgun',      glbBase: 'handgun' },
  { id: 'mechgun', label: 'Mechgun',      glbBase: 'machinegun' },
  { id: 'rifle',   label: 'Rifle',        glbBase: 'rifle' },
  { id: 'shotgun', label: 'Shotgun',      glbBase: 'shotgun' },
  { id: 'cannon',  label: 'Laser Cannon', glbBase: 'cannon' },
  { id: 'rod',     label: 'Rod',          glbBase: 'rod' },
  { id: 'wand',    label: 'Wand',         glbBase: 'wand' },
];

interface ClassDef {
  id: string;
  label: string;
  gender: Gender; // picks the _m/_w animation pack, like player.gd
  pc: string;     // model folder (variation 0 of PlayerConfig.CLASS_PREFIX)
}

// Model/gender picker only — PA clips exist for every pack, so this tool
// doesn't apply ClassData weapon legality the way combo-debug does.
const CLASSES: ClassDef[] = [
  { id: 'humar',     label: 'HUmar',     gender: 'm', pc: 'pc_000' },
  { id: 'humarl',    label: 'HUmarl',    gender: 'w', pc: 'pc_010' },
  { id: 'ramar',     label: 'RAmar',     gender: 'm', pc: 'pc_020' },
  { id: 'ramarl',    label: 'RAmarl',    gender: 'w', pc: 'pc_030' },
  { id: 'fomar',     label: 'FOmar',     gender: 'm', pc: 'pc_040' },
  { id: 'fomarl',    label: 'FOmarl',    gender: 'w', pc: 'pc_050' },
  { id: 'hunewm',    label: 'HUnewm',    gender: 'm', pc: 'pc_060' },
  { id: 'hunewearl', label: 'HUnewearl', gender: 'w', pc: 'pc_070' },
  { id: 'fonewm',    label: 'FOnewm',    gender: 'm', pc: 'pc_080' },
  { id: 'fonewearl', label: 'FOnewearl', gender: 'w', pc: 'pc_090' },
  { id: 'hucast',    label: 'HUcast',    gender: 'm', pc: 'pc_100' },
  { id: 'hucaseal',  label: 'HUcaseal',  gender: 'w', pc: 'pc_110' },
  { id: 'racast',    label: 'RAcast',    gender: 'm', pc: 'pc_120' },
  { id: 'racaseal',  label: 'RAcaseal',  gender: 'w', pc: 'pc_130' },
];

interface BlastDef {
  id: string;          // NARC id in raw/player
  key: string;         // asset base name under assets/player/photon_blasts/
  label: string;
  clips: string[];     // clip suffixes in playback order
  clipLabels: string[];
}

const BLASTS: BlastDef[] = [
  { id: 'pb_bird',    key: 'fb_bird',   label: 'Mylla & Youlla', clips: ['_st', '_atk'], clipLabels: ['Entrance', 'Attack'] },
  { id: 'pb_centaur', key: 'fb_kenta',  label: 'Konda Konda',    clips: ['_st', '_atk'], clipLabels: ['Entrance', 'Attack'] },
  { id: 'pb_dragon',  key: 'fb_hebi',   label: 'Leogini',        clips: ['_st', '_atk'], clipLabels: ['Entrance', 'Attack'] },
  { id: 'pb_rabbit',  key: 'fb_rabbit', label: 'Bunny',          clips: ['_rnd', '_hit'], clipLabels: ['Round', 'Hit'] },
];

// Player-pack clips resolved by suffix (per-pack prefixes are irregular —
// same reasoning as combo-debug). `required` gates the load error.
const PACK_CLIPS: { key: string; suffix: string; required: boolean }[] = [
  { key: 'wait', suffix: '_wait', required: true },
  { key: 'atk1', suffix: '_atk1', required: true },
  { key: 'atk2', suffix: '_atk2', required: false },
  { key: 'atk3', suffix: '_atk3', required: false },
  { key: 'pa1', suffix: '_pa1', required: false },
  { key: 'pa2', suffix: '_pa2', required: false },
  { key: 'pa3', suffix: '_pa3', required: false },
  { key: 'pb', suffix: '_pb', required: false },
  { key: 'pb_lp', suffix: '_pb_lp', required: false },
];

interface Config {
  mode: Mode;
  classId: string;
  weapon: string;
  blast: string;
  paLevel: number;        // preferred PA level (1-3); falls back to best available
  rootMotion: boolean;    // keep baked root translation on player clips
  creatureScale: number;
}

const DEFAULT_CONFIG: Config = {
  mode: 'arts', classId: 'humar', weapon: 'saber', blast: 'pb_bird',
  paLevel: 3, rootMotion: true, creatureScale: 1,
};

function loadConfig(): Config {
  if (typeof window === 'undefined') return DEFAULT_CONFIG;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CONFIG;
    const cfg = { ...DEFAULT_CONFIG, ...(JSON.parse(raw) as Partial<Config>) };
    if (!WEAPONS.some((w) => w.id === cfg.weapon)) cfg.weapon = DEFAULT_CONFIG.weapon;
    if (!CLASSES.some((c) => c.id === cfg.classId)) cfg.classId = DEFAULT_CONFIG.classId;
    if (!BLASTS.some((b) => b.id === cfg.blast)) cfg.blast = DEFAULT_CONFIG.blast;
    return cfg;
  } catch {
    return DEFAULT_CONFIG;
  }
}

/** Strip the 000_Root position track (same as combo/dodge-debug). */
function stripRootMotion(clip: THREE.AnimationClip): THREE.AnimationClip {
  const out = clip.clone();
  out.tracks = out.tracks.filter((t) => {
    if (t.name === '000_Root.position') return false;
    if (t.name.endsWith('/000_Root.position')) return false;
    return true;
  });
  return out;
}

function loadNearestTexture(loader: THREE.TextureLoader, path: string): THREE.Texture {
  return loader.load(path, (tx) => {
    tx.magFilter = THREE.NearestFilter;
    tx.minFilter = THREE.NearestFilter;
    tx.flipY = false;
    tx.colorSpace = THREE.SRGBColorSpace;
  });
}

function applyTexture(root: THREE.Object3D, tex: THREE.Texture): void {
  root.traverse((child) => {
    const m = child as THREE.Mesh;
    if (m.isMesh && m.material) {
      const mat = m.material as THREE.MeshBasicMaterial;
      mat.map = tex;
      mat.needsUpdate = true;
      // NDS skinned meshes keep their bind-pose bounds; animated poses swing
      // outside them and get frustum-culled mid-clip.
      m.frustumCulled = false;
    }
  });
}

interface LogEntry { id: number; color: string; text: string }

interface SceneRefs {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  playerGroup: THREE.Group;
  creatureGroup: THREE.Group;
  // player animation state
  mixer: THREE.AnimationMixer | null;
  actions: Record<string, THREE.AnimationAction>;       // root motion stripped
  actionsRM: Record<string, THREE.AnimationAction>;     // raw (with root motion)
  clips: Record<string, THREE.AnimationClip>;
  currentAction: THREE.AnimationAction | null;
  // creature animation state
  creatureMixer: THREE.AnimationMixer | null;
  creatureActions: Record<string, THREE.AnimationAction>;
  creatureClips: Record<string, THREE.AnimationClip>;
  creatureCurrent: THREE.AnimationAction | null;
}

/** One step of a playback sequence. */
interface SeqStep {
  actor: 'player' | 'creature';
  key: string;
  loop?: boolean;      // loop step: holds until the sequence is cancelled or advanced externally
  label?: string;
}

export default function PhotonRoom() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneRefs | null>(null);
  const logIdRef = useRef(0);

  const [config, setConfig] = useState<Config>(loadConfig);
  const [speed, setSpeed] = useState(1.0);
  const [isLoading, setIsLoading] = useState(true);
  const [creatureLoading, setCreatureLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);
  const [packInfo, setPackInfo] = useState<{ prefix: string; clips: Record<string, number> }>({ prefix: '', clips: {} });
  const [creatureClipNames, setCreatureClipNames] = useState<string[]>([]);
  const [playing, setPlaying] = useState<{ label: string; progress: number } | null>(null);

  const classDef = CLASSES.find((c) => c.id === config.classId)!;
  const gender = classDef.gender;
  const weaponDef = WEAPONS.find((w) => w.id === config.weapon)!;
  const blastDef = BLASTS.find((b) => b.id === config.blast)!;

  const speedRef = useRef(speed);
  speedRef.current = speed;
  const rootMotionRef = useRef(config.rootMotion);
  rootMotionRef.current = config.rootMotion;

  useEffect(() => {
    try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); } catch { /* ignore quota */ }
  }, [config]);

  const pushLog = useCallback((text: string, color = '#aaa') => {
    logIdRef.current += 1;
    const id = logIdRef.current;
    setLog((prev) => [{ id, color, text }, ...prev].slice(0, 10));
  }, []);

  // -------------------------------------------------------------------------
  // Sequence playback: a queue of steps advanced by mixer 'finished' events.
  // -------------------------------------------------------------------------

  const seqRef = useRef<{ steps: SeqStep[]; index: number; label: string; keepCreature?: boolean } | null>(null);

  const playerAction = useCallback((key: string): THREE.AnimationAction | null => {
    const s = sceneRef.current;
    if (!s) return null;
    const pool = rootMotionRef.current ? s.actionsRM : s.actions;
    return pool[key] ?? null;
  }, []);

  const fadeToPlayer = useCallback((key: string, loop: boolean): number => {
    const s = sceneRef.current;
    const action = playerAction(key);
    if (!s || !action) return 0;
    if (s.currentAction && s.currentAction !== action) s.currentAction.fadeOut(0.08);
    action.reset();
    action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    action.clampWhenFinished = !loop;
    action.fadeIn(0.08);
    action.play();
    s.currentAction = action;
    return s.clips[key]?.duration ?? 0;
  }, [playerAction]);

  const fadeToCreature = useCallback((key: string, loop: boolean): number => {
    const s = sceneRef.current;
    if (!s || !s.creatureActions[key]) return 0;
    const action = s.creatureActions[key];
    if (s.creatureCurrent && s.creatureCurrent !== action) s.creatureCurrent.fadeOut(0.08);
    action.reset();
    action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    action.clampWhenFinished = !loop;
    action.fadeIn(0.08);
    action.play();
    s.creatureCurrent = action;
    return s.creatureClips[key]?.duration ?? 0;
  }, []);

  const playIdle = useCallback(() => {
    seqRef.current = null;
    setPlaying(null);
    const s = sceneRef.current;
    if (s) {
      s.creatureGroup.visible = false;
      if (s.creatureCurrent) { s.creatureCurrent.stop(); s.creatureCurrent = null; }
    }
    fadeToPlayer('wait', true);
  }, [fadeToPlayer]);

  const runStep = useCallback((step: SeqStep) => {
    const s = sceneRef.current;
    if (!s) return;
    if (step.actor === 'player') {
      fadeToPlayer(step.key, !!step.loop);
    } else {
      s.creatureGroup.visible = true;
      fadeToCreature(step.key, !!step.loop);
    }
    if (step.label) pushLog(step.label, step.actor === 'player' ? '#8cf' : '#fc8');
  }, [fadeToPlayer, fadeToCreature, pushLog]);

  const startSequence = useCallback((label: string, steps: SeqStep[], keepCreature = false) => {
    const available = steps.filter((st) => {
      const s = sceneRef.current;
      if (!s) return false;
      return st.actor === 'player' ? !!s.clips[st.key] : !!s.creatureClips[st.key];
    });
    if (available.length === 0) return;
    seqRef.current = { steps: available, index: 0, label, keepCreature };
    setPlaying({ label, progress: 0 });
    runStep(available[0]);
  }, [runStep]);

  /** Advance the active sequence when a LoopOnce action finishes. */
  const onActionFinished = useCallback((actor: 'player' | 'creature') => {
    const seq = seqRef.current;
    if (!seq) {
      if (actor === 'player') playIdle();
      return;
    }
    const current = seq.steps[seq.index];
    if (!current || current.actor !== actor) return; // a stale finish from the other mixer
    // A loop step never emits 'finished'; anything else advances the queue.
    let next = seq.index + 1;
    // Skip past loop steps that were only meant to hold WHILE the other actor
    // plays: if the finished step was the other actor's last clip, cancel the
    // player hold too.
    if (next >= seq.steps.length) {
      if (seq.keepCreature) {
        // Creature-only playback: hold the final pose on screen for
        // inspection; only Reset / the next sequence clears it.
        seqRef.current = null;
        setPlaying(null);
        fadeToPlayer('wait', true);
      } else {
        playIdle();
      }
      pushLog(`${seq.label} — done`, '#6f6');
      return;
    }
    seq.index = next;
    runStep(seq.steps[next]);
  }, [playIdle, pushLog, runStep, fadeToPlayer]);

  const onActionFinishedRef = useRef(onActionFinished);
  onActionFinishedRef.current = onActionFinished;

  // -------------------------------------------------------------------------
  // Play helpers wired to UI
  // -------------------------------------------------------------------------

  /** Best available PA level: the preferred one, else highest present. */
  const resolvePaKey = useCallback((): string | null => {
    const s = sceneRef.current;
    if (!s) return null;
    const preferred = `pa${config.paLevel}`;
    if (s.clips[preferred]) return preferred;
    for (const lvl of [3, 2, 1]) if (s.clips[`pa${lvl}`]) return `pa${lvl}`;
    return null;
  }, [config.paLevel]);

  const playPa = useCallback(() => {
    const key = resolvePaKey();
    if (!key) { pushLog('no PA clip in this pack', '#f88'); return; }
    startSequence(`${weaponDef.label} ${key}`, [
      { actor: 'player', key, label: `photon art ${key} (${sceneRef.current?.clips[key]?.name})` },
    ]);
  }, [resolvePaKey, startSequence, weaponDef.label, pushLog]);

  const playComboPa = useCallback(() => {
    const key = resolvePaKey();
    if (!key) { pushLog('no PA clip in this pack', '#f88'); return; }
    const steps: SeqStep[] = [
      { actor: 'player', key: 'atk1', label: 'combo atk1' },
      { actor: 'player', key: 'atk2', label: 'combo atk2' },
      { actor: 'player', key: 'atk3', label: 'combo atk3' },
      { actor: 'player', key, label: `→ photon art ${key}` },
    ];
    startSequence(`${weaponDef.label} combo → ${key}`, steps);
  }, [resolvePaKey, startSequence, weaponDef.label, pushLog]);

  const playCreatureClip = useCallback((suffix: string, label: string) => {
    startSequence(`${blastDef.label} ${label}`, [
      { actor: 'creature', key: suffix, label: `${blastDef.label} — ${label}` },
    ], true);
  }, [startSequence, blastDef.label]);

  const playSummon = useCallback(() => {
    // Player raises the mag (pb), holds the loop while the blast plays out.
    const steps: SeqStep[] = [
      { actor: 'player', key: 'pb', label: 'summon — player pb pose' },
    ];
    for (let i = 0; i < blastDef.clips.length; i++) {
      steps.push({ actor: 'creature', key: blastDef.clips[i], label: `${blastDef.label} — ${blastDef.clipLabels[i]}` });
    }
    startSequence(`Summon ${blastDef.label}`, steps);
    // The pb_lp hold runs on the player in parallel once pb finishes — handled
    // below in the finished listener shim (see loadPack effect).
  }, [blastDef, startSequence]);

  const playPaRef = useRef(playPa); playPaRef.current = playPa;
  const playComboPaRef = useRef(playComboPa); playComboPaRef.current = playComboPa;
  const playSummonRef = useRef(playSummon); playSummonRef.current = playSummon;
  const playIdleRef = useRef(playIdle); playIdleRef.current = playIdle;

  // During a summon, when the player's one-shot pb finishes we switch the
  // player onto the pb_lp hold loop and let the creature advance the queue.
  const handlePlayerFinished = useCallback(() => {
    const seq = seqRef.current;
    if (seq && seq.steps[seq.index]?.actor === 'player' && seq.steps[seq.index].key === 'pb') {
      // advance to the creature steps while the player holds pb_lp
      fadeToPlayer('pb_lp', true);
      const next = seq.index + 1;
      if (next < seq.steps.length) {
        seq.index = next;
        runStep(seq.steps[next]);
      } else {
        playIdleRef.current();
      }
      return;
    }
    onActionFinishedRef.current('player');
  }, [fadeToPlayer, runStep]);
  const handlePlayerFinishedRef = useRef(handlePlayerFinished);
  handlePlayerFinishedRef.current = handlePlayerFinished;

  // -------------------------------------------------------------------------
  // Keyboard
  // -------------------------------------------------------------------------

  useEffect(() => {
    const onDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      if (e.repeat) return;
      if (e.code === 'KeyZ' || e.code === 'KeyJ') playPaRef.current();
      else if (e.code === 'KeyX' || e.code === 'KeyK') playComboPaRef.current();
      else if (e.code === 'KeyC' || e.code === 'KeyL') playSummonRef.current();
      else if (e.code === 'KeyR') playIdleRef.current();
    };
    window.addEventListener('keydown', onDown);
    return () => window.removeEventListener('keydown', onDown);
  }, []);

  // -------------------------------------------------------------------------
  // Scene setup
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a1a);

    const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 100);
    camera.position.set(0, 4.6, 6.4);
    camera.lookAt(0, 1, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(3, 6, 4);
    scene.add(dir);

    scene.add(new THREE.GridHelper(14, 28, 0x444466, 0x222238));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 1, 0);

    const playerGroup = new THREE.Group();
    scene.add(playerGroup); // models natively face +Z, toward the camera

    const creatureGroup = new THREE.Group();
    creatureGroup.position.set(0, 0, -2.4); // behind/above the player, like a summon
    creatureGroup.visible = false;
    scene.add(creatureGroup);

    sceneRef.current = {
      scene, camera, renderer, controls, playerGroup, creatureGroup,
      mixer: null, actions: {}, actionsRM: {}, clips: {}, currentAction: null,
      creatureMixer: null, creatureActions: {}, creatureClips: {}, creatureCurrent: null,
    };

    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const delta = Math.min(clock.getDelta(), 0.1) * speedRef.current;
      const s = sceneRef.current;
      if (!s) return;
      if (s.mixer) s.mixer.update(delta);
      if (s.creatureMixer && s.creatureGroup.visible) s.creatureMixer.update(delta);
      controls.update();
      renderer.render(scene, camera);

      // progress readout for the HUD bar
      const seq = seqRef.current;
      if (seq) {
        const step = seq.steps[seq.index];
        const action = step?.actor === 'creature' ? s.creatureCurrent : s.currentAction;
        const clipLen = action?.getClip().duration ?? 0;
        setPlaying({ label: `${seq.label} — ${step?.key ?? ''}`, progress: clipLen > 0 ? Math.min(1, (action?.time ?? 0) / clipLen) : 0 });
      }
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

  // -------------------------------------------------------------------------
  // Player model + animation pack loading
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setIsLoading(true);
    setLoadError(null);
    setPackInfo({ prefix: '', clips: {} });
    seqRef.current = null;
    setPlaying(null);

    s.playerGroup.clear();
    s.mixer = null;
    s.actions = {};
    s.actionsRM = {};
    s.clips = {};
    s.currentAction = null;

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    const pc = classDef.pc;
    const animGlb = `${weaponDef.glbBase}_${gender}`;
    let cancelled = false;

    loader.load(assetUrl(`assets/player/${pc}/${pc}_000.glb`), (gltf) => {
      if (cancelled || !sceneRef.current) return;
      applyTexture(gltf.scene, loadNearestTexture(texLoader, assetUrl(`assets/player/${pc}/textures/${pc}_000.png`)));
      s.playerGroup.add(gltf.scene);

      loader.load(assetUrl(`assets/player/animations/${animGlb}.glb`), (animGltf) => {
        if (cancelled || !sceneRef.current) return;
        const mixer = new THREE.AnimationMixer(gltf.scene);
        mixer.addEventListener('finished', () => handlePlayerFinishedRef.current());
        const missing: string[] = [];
        const lens: Record<string, number> = {};
        for (const { key, suffix, required } of PACK_CLIPS) {
          const clip = animGltf.animations.find((a) => a.name.endsWith(suffix));
          if (!clip) { if (required) missing.push(`*${suffix}`); continue; }
          s.clips[key] = clip;
          s.actions[key] = mixer.clipAction(stripRootMotion(clip));
          s.actionsRM[key] = mixer.clipAction(clip);
          lens[key] = clip.duration;
        }
        if (missing.length > 0) {
          setLoadError(`Missing clips: ${missing.join(', ')} in ${animGlb}.glb`);
          setIsLoading(false);
          return;
        }
        s.mixer = mixer;
        setPackInfo({ prefix: s.clips.wait.name.replace(/_wait$/, ''), clips: lens });
        setIsLoading(false);
        playIdleRef.current();
      }, undefined, (err) => {
        setLoadError(`Failed to load animation pack ${animGlb}.glb: ${err}`);
        setIsLoading(false);
      });
    }, undefined, (err) => {
      setLoadError(`Failed to load model: ${err}`);
      setIsLoading(false);
    });

    return () => { cancelled = true; };
  }, [config.weapon, config.classId, classDef.pc, weaponDef.glbBase, gender]);

  // -------------------------------------------------------------------------
  // Photon blast creature loading
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!sceneRef.current) return;
    const s = sceneRef.current;
    setCreatureLoading(true);
    setCreatureClipNames([]);

    s.creatureGroup.clear();
    s.creatureMixer = null;
    s.creatureActions = {};
    s.creatureClips = {};
    s.creatureCurrent = null;
    s.creatureGroup.visible = false;

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    let cancelled = false;

    loader.load(assetUrl(`assets/player/photon_blasts/${blastDef.key}.glb`), (gltf) => {
      if (cancelled || !sceneRef.current) return;
      applyTexture(gltf.scene, loadNearestTexture(texLoader, assetUrl(`assets/player/photon_blasts/${blastDef.key}.png`)));
      s.creatureGroup.add(gltf.scene);
      const mixer = new THREE.AnimationMixer(gltf.scene);
      mixer.addEventListener('finished', () => onActionFinishedRef.current('creature'));
      for (const suffix of blastDef.clips) {
        const clip = gltf.animations.find((a) => a.name.endsWith(suffix));
        if (!clip) continue;
        s.creatureClips[suffix] = clip;
        s.creatureActions[suffix] = mixer.clipAction(clip);
      }
      s.creatureMixer = mixer;
      setCreatureClipNames(gltf.animations.map((a) => a.name));
      setCreatureLoading(false);
    }, undefined, (err) => {
      pushLog(`failed to load ${blastDef.key}.glb: ${err}`, '#f88');
      setCreatureLoading(false);
    });

    return () => { cancelled = true; };
  }, [config.blast, blastDef.key, blastDef.clips, pushLog]);

  // creature scale is a live transform, not a reload
  useEffect(() => {
    const s = sceneRef.current;
    if (s) s.creatureGroup.scale.setScalar(config.creatureScale);
  }, [config.creatureScale, creatureLoading]);

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  const paLevels = [1, 2, 3].map((lvl) => ({ lvl, available: !!packInfo.clips[`pa${lvl}`] }));
  const selStyle: React.CSSProperties = {
    background: '#1a1a2e', color: '#dde', border: '1px solid #33334f', borderRadius: 4,
    padding: '4px 8px', fontSize: 12,
  };
  const btnStyle = (active = false, disabled = false): React.CSSProperties => ({
    background: disabled ? '#16162a' : active ? '#31437a' : '#22223a',
    color: disabled ? '#556' : '#dde',
    border: `1px solid ${active ? '#6b8afd' : '#33334f'}`,
    borderRadius: 4, padding: '5px 10px', fontSize: 12,
    cursor: disabled ? 'default' : 'pointer',
  });

  return (
    <div style={{ display: 'flex', height: 'calc(100vh - 42px)', background: '#0d0d1c', color: '#dde', fontFamily: 'ui-monospace, monospace' }}>
      {/* 3D viewport */}
      <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
        <div ref={containerRef} style={{ position: 'absolute', inset: 0 }} />
        {(isLoading || loadError) && (
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(10,10,26,0.7)', color: loadError ? '#f88' : '#889', fontSize: 13 }}>
            {loadError ?? 'Loading…'}
          </div>
        )}
        {/* playback HUD */}
        <div style={{ position: 'absolute', left: 12, bottom: 12, right: 12, pointerEvents: 'none' }}>
          {playing && (
            <div style={{ marginBottom: 8, maxWidth: 460 }}>
              <div style={{ fontSize: 11, color: '#8cf', marginBottom: 3 }}>{playing.label}</div>
              <div style={{ height: 6, background: '#1a1a2e', borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${(playing.progress * 100).toFixed(1)}%`, background: '#6b8afd' }} />
              </div>
            </div>
          )}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {log.map((l) => (
              <div key={l.id} style={{ fontSize: 11, color: l.color }}>{l.text}</div>
            ))}
          </div>
        </div>
        <div style={{ position: 'absolute', top: 10, left: 12, fontSize: 11, color: '#667' }}>
          Z/J photon art · X/K combo → PA · C/L summon blast · R reset · drag to orbit
        </div>
      </div>

      {/* side panel */}
      <div style={{ width: 320, borderLeft: '1px solid #22223a', padding: 14, overflowY: 'auto', flexShrink: 0 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16 }}>Photon Room</h2>
        <div style={{ fontSize: 11, color: '#778', marginBottom: 12 }}>
          Photon arts (per-weapon pa1-3) and mag photon blasts, straight from the
          extracted animation packs.
        </div>

        {/* mode tabs */}
        <div style={{ display: 'flex', gap: 6, marginBottom: 12 }}>
          <button style={btnStyle(config.mode === 'arts')} onClick={() => setConfig((c) => ({ ...c, mode: 'arts' }))}>Photon Arts</button>
          <button style={btnStyle(config.mode === 'blasts')} onClick={() => setConfig((c) => ({ ...c, mode: 'blasts' }))}>Photon Blasts</button>
        </div>

        {/* shared: class + weapon */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
          <label style={{ flex: 1, fontSize: 11, color: '#99a' }}>
            Class
            <select
              style={{ ...selStyle, width: '100%', marginTop: 3 }}
              value={config.classId}
              onChange={(e) => setConfig((c) => ({ ...c, classId: e.target.value }))}
            >
              {CLASSES.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
            </select>
          </label>
          <label style={{ flex: 1, fontSize: 11, color: '#99a' }}>
            Weapon pack
            <select
              style={{ ...selStyle, width: '100%', marginTop: 3 }}
              value={config.weapon}
              onChange={(e) => setConfig((c) => ({ ...c, weapon: e.target.value }))}
            >
              {WEAPONS.map((w) => <option key={w.id} value={w.id}>{w.label}</option>)}
            </select>
          </label>
        </div>
        <div style={{ fontSize: 10, color: '#667', marginBottom: 14 }}>
          pack {weaponDef.glbBase}_{gender}.glb{packInfo.prefix ? ` · prefix ${packInfo.prefix}` : ''}
        </div>

        {config.mode === 'arts' && (
          <>
            <div style={{ fontSize: 12, color: '#aab', marginBottom: 6 }}>Photon art level</div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 10 }}>
              {paLevels.map(({ lvl, available }) => (
                <button
                  key={lvl}
                  style={btnStyle(config.paLevel === lvl && available, !available)}
                  disabled={!available}
                  title={available ? `${packInfo.clips[`pa${lvl}`]?.toFixed(2)}s` : 'not in the pack yet — pa1/pa2 return after the psz-asset-viewer re-extract'}
                  onClick={() => setConfig((c) => ({ ...c, paLevel: lvl }))}
                >
                  PA {lvl}{available ? '' : ' ✕'}
                </button>
              ))}
            </div>
            {!packInfo.clips.pa1 && !isLoading && (
              <div style={{ fontSize: 10, color: '#a86', marginBottom: 10 }}>
                Only pa3 is in the shipped packs — the extractor was overwriting the
                pa00/pa01 NARCs (fixed in psz-asset-viewer; levels 1-2 arrive with
                the next re-extract + reimport).
              </div>
            )}
            <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
              <button style={btnStyle()} onClick={playPa} disabled={isLoading}>▶ Photon Art</button>
              <button style={btnStyle()} onClick={playComboPa} disabled={isLoading}>▶ Combo → PA</button>
              <button style={btnStyle()} onClick={playIdle}>Reset</button>
            </div>
            <div style={{ fontSize: 11, color: '#778', marginBottom: 14 }}>
              Clip lengths:{' '}
              {['atk1', 'atk2', 'atk3', 'pa1', 'pa2', 'pa3'].filter((k) => packInfo.clips[k]).map((k) => `${k} ${packInfo.clips[k].toFixed(2)}s`).join(' · ') || '—'}
            </div>
          </>
        )}

        {config.mode === 'blasts' && (
          <>
            <div style={{ fontSize: 12, color: '#aab', marginBottom: 6 }}>Photon blast</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginBottom: 10 }}>
              {BLASTS.map((b) => (
                <button key={b.id} style={btnStyle(config.blast === b.id)} onClick={() => setConfig((c) => ({ ...c, blast: b.id }))}>
                  {b.label}
                </button>
              ))}
            </div>
            <div style={{ fontSize: 10, color: '#667', marginBottom: 10 }}>
              {blastDef.key}.glb ({blastDef.id}.narc) · clips: {creatureClipNames.join(', ') || (creatureLoading ? 'loading…' : '—')}
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 10, flexWrap: 'wrap' }}>
              <button style={btnStyle()} onClick={playSummon} disabled={isLoading || creatureLoading}>▶ Summon (full)</button>
              {blastDef.clips.map((suffix, i) => (
                <button key={suffix} style={btnStyle()} disabled={creatureLoading} onClick={() => playCreatureClip(suffix, blastDef.clipLabels[i])}>
                  ▶ {blastDef.clipLabels[i]}
                </button>
              ))}
              <button style={btnStyle()} onClick={playIdle}>Reset</button>
            </div>
            <label style={{ fontSize: 11, color: '#99a', display: 'block', marginBottom: 14 }}>
              Creature scale {config.creatureScale.toFixed(2)}×
              <input
                type="range" min={0.25} max={4} step={0.05} value={config.creatureScale}
                style={{ width: '100%' }}
                onChange={(e) => setConfig((c) => ({ ...c, creatureScale: Number(e.target.value) }))}
              />
            </label>
          </>
        )}

        {/* shared playback options */}
        <div style={{ borderTop: '1px solid #22223a', paddingTop: 10, marginTop: 4 }}>
          <label style={{ fontSize: 11, color: '#99a', display: 'block', marginBottom: 8 }}>
            Speed {speed.toFixed(2)}×
            <input type="range" min={0.1} max={2} step={0.05} value={speed} style={{ width: '100%' }} onChange={(e) => setSpeed(Number(e.target.value))} />
          </label>
          <label style={{ fontSize: 11, color: '#99a', display: 'flex', gap: 6, alignItems: 'center' }}>
            <input
              type="checkbox"
              checked={config.rootMotion}
              onChange={(e) => setConfig((c) => ({ ...c, rootMotion: e.target.checked }))}
            />
            Root motion (PA lunges move the character)
          </label>
        </div>

        <div style={{ borderTop: '1px solid #22223a', paddingTop: 10, marginTop: 12, fontSize: 10, color: '#667', lineHeight: 1.5 }}>
          Sources: player packs assets/player/animations/*.glb (clips *_pa1-3,
          *_pb, *_pb_lp) · blasts raw/player/pb_*.narc via psz-asset-viewer.
          Untranslated params: paeff00-16.rel (PA effects), pb_param_data.rel +
          mag_param.narc (PB stats).
        </div>
      </div>
    </div>
  );
}
