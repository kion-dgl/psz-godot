// ShopStage — the real in-game shop location rendered in three.js.
//
// Unlike a floating-portrait mock, this loads the ACTUAL Godot city stage the
// shop lives in (market / counter / underground GLBs), drops the shopkeeper NPC
// at its real world coordinates + rotation, and stands the player character in
// front of it. Two camera modes model the intended flow:
//
//   • follow — the gameplay chase-cam behind the player (walking up to the shop)
//   • talk   — a fixed cinematic shop angle framing the NPC; this is where the
//              PSZ menu overlay appears
//
// Switching mode lerps the camera between the two (approach / close). The player
// can be ghosted or hidden when it would obstruct the shopkeeper. The canvas
// renders at the game's native 1280×720; the parent scales that frame to fit.
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { PLAYER, STAGES } from './shopData';
import type { AreaId } from './shopData';
import { assetUrl } from '../utils/assets';

const NPC_IDLE_GLB = assetUrl('assets/player/animations/npc_idles.glb');

export interface TalkCam {
  azimuthDeg: number;   // swing around the NPC→player axis for a 3/4 angle (+ = camera toward player's right)
  distance: number;     // camera distance from the NPC (metres)
  height: number;       // camera height above the floor
  lookHeight: number;   // look-at height above the floor at the NPC
  lateralShift: number; // push the NPC off-centre for the overlay (+ = NPC to the RIGHT)
  fov?: number;
}

export type CamMode = 'follow' | 'talk';

export interface ShopStageProps {
  area: AreaId;
  npc: { model: string; tex: string; idle?: string; pos: [number, number, number]; rot: number };
  accent: number;
  talkCam: TalkCam;
  mode: CamMode;
  playerOpacity: number;  // 1 solid · ~0.25 ghost · 0 hidden
}

const VIEW_W = 1280, VIEW_H = 720;
const APPROACH = new THREE.Vector3(0, 0, 1);  // player stands on the +Z side of the NPC (matches every area's spawn)
const STAND_DIST = 2.4;
const FOLLOW_DIST = 4.5, FOLLOW_HEIGHT = 1.9, FOLLOW_LOOK = 1.0;  // orbit_camera.gd defaults

function skyTexture(accent: number): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 8; c.height = 256;
  const ctx = c.getContext('2d')!;
  const a = new THREE.Color(accent);
  const top = a.clone().lerp(new THREE.Color(0x11121c), 0.7);
  const bot = new THREE.Color(0x05060b);
  const g = ctx.createLinearGradient(0, 0, 0, 256);
  g.addColorStop(0, `#${top.getHexString()}`);
  g.addColorStop(1, `#${bot.getHexString()}`);
  ctx.fillStyle = g; ctx.fillRect(0, 0, 8, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

// Load a textured PSZ character (NPC or player): unlit MeshBasic + sibling PNG,
// plus one idle clip filtered to bones this skeleton actually has.
function loadCharacter(
  loader: GLTFLoader, texLoader: THREE.TextureLoader,
  modelUrl: string, texUrl: string, animGlb: string | undefined, clipName: string | undefined,
  onReady: (group: THREE.Object3D, mixer: THREE.AnimationMixer | null, mats: THREE.MeshBasicMaterial[]) => void,
) {
  loader.load(modelUrl, (gltf) => {
    const mats: THREE.MeshBasicMaterial[] = [];
    const tex = texLoader.load(texUrl, (tx) => {
      tx.magFilter = THREE.NearestFilter; tx.minFilter = THREE.NearestFilter;
      tx.flipY = false; tx.colorSpace = THREE.SRGBColorSpace;
    });
    gltf.scene.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh && m.material) {
        const mat = m.material as THREE.MeshBasicMaterial;
        mat.map = tex; mat.needsUpdate = true; mats.push(mat);
      }
    });
    let mixer: THREE.AnimationMixer | null = null;
    const finish = () => onReady(gltf.scene, mixer, mats);
    if (animGlb && clipName) {
      const nodeNames = new Set<string>();
      gltf.scene.traverse((o) => { if (o.name) nodeNames.add(o.name); });
      loader.load(animGlb, (ag) => {
        const clip = ag.animations.find((a) => a.name === clipName) || ag.animations.find((a) => a.name.endsWith(clipName));
        if (clip) {
          clip.tracks = clip.tracks.filter((t) => !(t.name.endsWith('.position') && /Hips|_root|Root|00_|Pelvis/i.test(t.name)));
          clip.tracks = clip.tracks.filter((t) => nodeNames.has(t.name.split('.')[0]));
          if (clip.tracks.length) {
            mixer = new THREE.AnimationMixer(gltf.scene);
            mixer.clipAction(clip).setLoop(THREE.LoopRepeat, Infinity).play();
          }
        }
        finish();
      }, undefined, finish);
    } else finish();
  }, undefined, (e) => console.warn('[ShopStage] character load failed', modelUrl, e));
}

export default function ShopStage({ area, npc, accent, talkCam, mode, playerOpacity }: ShopStageProps) {
  const mountRef = useRef<HTMLDivElement>(null);
  // Live-updated refs so the render loop always reads the latest without
  // rebuilding the scene (switching style / mode / opacity stays smooth).
  const talkCamRef = useRef(talkCam); talkCamRef.current = talkCam;
  const modeRef = useRef(mode); modeRef.current = mode;
  const opacityRef = useRef(playerOpacity); opacityRef.current = playerOpacity;

  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    const scene = new THREE.Scene();
    scene.background = skyTexture(accent);

    const camera = new THREE.PerspectiveCamera(talkCamRef.current.fov ?? 50, VIEW_W / VIEW_H, 0.1, 1000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(VIEW_W, VIEW_H);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    el.appendChild(renderer.domElement);

    // Lights for the stage's (lit) materials. Character models are unlit.
    scene.add(new THREE.AmbientLight(0xffffff, 1.5));
    scene.add(new THREE.HemisphereLight(0xbfd4ff, 0x20242e, 0.6));
    const dir = new THREE.DirectionalLight(0xffffff, 1.0);
    dir.position.set(10, 20, 10);
    scene.add(dir);

    const stageDef = STAGES[area];
    const floorY = npc.pos[1];
    const npcPos = new THREE.Vector3(npc.pos[0], npc.pos[1], npc.pos[2]);
    const playerPos = npcPos.clone().addScaledVector(APPROACH, STAND_DIST);

    // ---- stage ----
    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();
    for (const url of stageDef.models) {
      loader.load(url, (g) => scene.add(g.scene), undefined, (e) => console.warn('[ShopStage] stage load failed', url, e));
    }

    const mixers: THREE.AnimationMixer[] = [];
    let playerMats: THREE.MeshBasicMaterial[] = [];
    let playerGroup: THREE.Object3D | null = null;

    // ---- NPC at its real world pose ----
    loadCharacter(loader, texLoader, npc.model, npc.tex, npc.idle ? NPC_IDLE_GLB : undefined, npc.idle, (group, mixer) => {
      group.position.copy(npcPos);
      group.rotation.y = npc.rot;  // model.rotation.y from Godot
      scene.add(group);
      if (mixer) mixers.push(mixer);
    });

    // ---- player standing in front, facing the NPC ----
    loadCharacter(loader, texLoader, PLAYER.model, PLAYER.tex, PLAYER.animGlb, PLAYER.idleClip, (group, mixer, mats) => {
      group.position.copy(playerPos);
      // face the NPC (dir = npc - player = -APPROACH)
      const dir = npcPos.clone().sub(playerPos);
      group.rotation.y = Math.atan2(dir.x, dir.z);
      scene.add(group);
      playerGroup = group;
      playerMats = mats;
      if (mixer) mixers.push(mixer);
    });

    // ---- camera state (lerped) ----
    const curPos = new THREE.Vector3();
    const curLook = new THREE.Vector3();
    let curShift = 0;
    let initialised = false;

    function targetsFor(m: CamMode): { pos: THREE.Vector3; look: THREE.Vector3; shift: number; fov: number } {
      const tc = talkCamRef.current;
      if (m === 'talk') {
        const az = THREE.MathUtils.degToRad(tc.azimuthDeg);
        const d = APPROACH.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), az);
        const pos = npcPos.clone().addScaledVector(d, tc.distance).setY(floorY + tc.height);
        const look = new THREE.Vector3(npcPos.x, floorY + tc.lookHeight, npcPos.z);
        return { pos, look, shift: tc.lateralShift, fov: tc.fov ?? 50 };
      }
      // follow: behind the player (player faces the NPC, so behind = +Z)
      const pos = playerPos.clone().addScaledVector(APPROACH, FOLLOW_DIST).setY(floorY + FOLLOW_HEIGHT);
      const look = new THREE.Vector3(playerPos.x, floorY + FOLLOW_LOOK, playerPos.z);
      return { pos, look, shift: 0, fov: 50 };
    }

    function applyShift(shift: number) {
      if (Math.abs(shift) < 0.001) { camera.clearViewOffset(); return; }
      camera.setViewOffset(VIEW_W, VIEW_H, -shift * VIEW_W, 0, VIEW_W, VIEW_H);
    }

    // ---- loop ----
    const clock = new THREE.Clock();
    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      for (const mx of mixers) mx.update(dt);

      const tgt = targetsFor(modeRef.current);
      if (!initialised) { curPos.copy(tgt.pos); curLook.copy(tgt.look); curShift = tgt.shift; initialised = true; }
      const k = 1 - Math.exp(-dt * 4.5);  // smooth approach/close + style changes
      curPos.lerp(tgt.pos, k);
      curLook.lerp(tgt.look, k);
      curShift += (tgt.shift - curShift) * k;
      if (Math.abs(camera.fov - tgt.fov) > 0.01) { camera.fov += (tgt.fov - camera.fov) * k; camera.updateProjectionMatrix(); }
      camera.position.copy(curPos);
      applyShift(curShift);
      camera.lookAt(curLook);

      // player opacity
      if (playerGroup) {
        const op = opacityRef.current;
        playerGroup.visible = op > 0.02;
        for (const m of playerMats) {
          const wantTransparent = op < 0.99;
          if (m.transparent !== wantTransparent) { m.transparent = wantTransparent; m.needsUpdate = true; }
          m.opacity = op;
          m.depthWrite = op > 0.5;
        }
      }
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(raf);
      renderer.dispose();
      scene.background = null;
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
    // rebuild only when the shop (area/NPC) changes; style/mode/opacity ride refs
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [area, npc.model, npc.tex, npc.idle, npc.pos, npc.rot, accent]);

  return <div ref={mountRef} style={{ width: VIEW_W, height: VIEW_H }} />;
}
