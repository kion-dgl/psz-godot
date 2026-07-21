// ShopScene — the reusable 3D "shopkeeper stage" behind every 3D-menu variation.
//
// It loads a PSZ city NPC (the low-poly np_0XX rig, same models the Godot city
// spawns) with its sibling PNG texture kept on an UNLIT MeshBasicMaterial — so
// the shopkeeper reads exactly like it does in-game — plays an idle clip out of
// the shared npc_idles.glb, and frames a cinematic camera on the figure using a
// declarative FramePreset. The variation overlays (SideStage / LowerThird /
// HoloCounter / Dossier) draw PSZ UI on top of this canvas; the camera preset is
// what makes each variation feel like a different "shot" of the same NPC.
//
// Lighting note: the NPC material is unlit by design, so scene lights don't
// touch it. All the mood (accent glow, gradient sky, ground disc, optional
// counter slab) lives in the ENVIRONMENT meshes, tinted per-shop by `accent`.
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { assetUrl } from '../utils/assets';

const IDLE_ANIM_GLB = assetUrl('assets/player/animations/npc_idles.glb');

export interface FramePreset {
  azimuthDeg: number;    // yaw around the figure; 0 = dead front, + = camera to figure's left
  elevationDeg: number;  // + looks down at the NPC, - looks up
  distanceMul: number;   // camera distance as a multiple of figure height
  targetYFrac: number;   // look-at height as fraction of figure height (0 feet, 1 head)
  lateralShift: number;  // push the NPC off-centre: + = NPC to the RIGHT (overlay space on left)
  counter?: boolean;     // draw a shop-counter slab in front of the NPC
  fov?: number;
}

export interface ShopSceneProps {
  modelUrl: string;
  texUrl: string;
  idleClip?: string;
  accent: number;        // hex, e.g. 0x8844cc — tints glow/ground/sky
  preset: FramePreset;
  className?: string;
}

// Vertical gradient sky as a CanvasTexture — cheap, and gives the PSZ "cool
// interior" backdrop without shipping an image.
function makeSky(accent: number): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 8; c.height = 256;
  const ctx = c.getContext('2d')!;
  const a = new THREE.Color(accent);
  const top = a.clone().lerp(new THREE.Color(0x0a0e1a), 0.55);
  const mid = a.clone().lerp(new THREE.Color(0x0a0e1a), 0.78);
  const bot = new THREE.Color(0x05070d);
  const g = ctx.createLinearGradient(0, 0, 0, 256);
  g.addColorStop(0, `#${top.getHexString()}`);
  g.addColorStop(0.55, `#${mid.getHexString()}`);
  g.addColorStop(1, `#${bot.getHexString()}`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 8, 256);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

// Soft radial glow sprite parked behind the NPC — the "spotlight from behind".
function makeGlow(accent: number): THREE.Sprite {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const ctx = c.getContext('2d')!;
  const col = new THREE.Color(accent);
  const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
  g.addColorStop(0, `rgba(${col.r * 255 | 0},${col.g * 255 | 0},${col.b * 255 | 0},0.9)`);
  g.addColorStop(0.4, `rgba(${col.r * 255 | 0},${col.g * 255 | 0},${col.b * 255 | 0},0.35)`);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 256, 256);
  const tex = new THREE.CanvasTexture(c);
  const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  return spr;
}

export default function ShopScene({ modelUrl, texUrl, idleClip, accent, preset, className }: ShopSceneProps) {
  const mountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;
    let w = el.clientWidth || 960, h = el.clientHeight || 540;

    const scene = new THREE.Scene();
    scene.background = makeSky(accent);
    scene.fog = new THREE.Fog(new THREE.Color(accent).lerp(new THREE.Color(0x05070d), 0.8), 6, 26);

    const camera = new THREE.PerspectiveCamera(preset.fov ?? 34, w / h, 0.1, 200);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    el.appendChild(renderer.domElement);

    // ---- environment ----
    const accentColor = new THREE.Color(accent);
    // Ground disc: dark, accent-rimmed radial — reads as a lit shop floor.
    const groundCanvas = document.createElement('canvas');
    groundCanvas.width = groundCanvas.height = 256;
    {
      const g = groundCanvas.getContext('2d')!;
      const rad = g.createRadialGradient(128, 128, 10, 128, 128, 128);
      const c0 = accentColor.clone().lerp(new THREE.Color(0x0a0e1a), 0.45);
      rad.addColorStop(0, `#${c0.getHexString()}`);
      rad.addColorStop(0.7, '#0a0e18');
      rad.addColorStop(1, 'rgba(6,8,14,0)');
      g.fillStyle = rad; g.fillRect(0, 0, 256, 256);
    }
    const groundTex = new THREE.CanvasTexture(groundCanvas);
    const ground = new THREE.Mesh(
      new THREE.CircleGeometry(6, 48),
      new THREE.MeshBasicMaterial({ map: groundTex, transparent: true, depthWrite: false }),
    );
    ground.rotation.x = -Math.PI / 2;
    scene.add(ground);
    // Faint concentric ring for a "teleporter pad" vibe under the NPC.
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(1.15, 1.25, 64),
      new THREE.MeshBasicMaterial({ color: accentColor, transparent: true, opacity: 0.5, side: THREE.DoubleSide, depthWrite: false }),
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.01;
    scene.add(ring);

    const glow = makeGlow(accent);
    glow.scale.set(6, 6, 1);
    scene.add(glow);

    const modelGroup = new THREE.Group();
    scene.add(modelGroup);

    let mixer: THREE.AnimationMixer | null = null;
    let figureHeight = 1.7;
    let counter: THREE.Group | null = null;

    const stripRoot = (clip: THREE.AnimationClip) => {
      clip.tracks = clip.tracks.filter((t) => !(t.name.endsWith('.position') && /Hips|_root|Root|00_|Pelvis/i.test(t.name)));
    };

    const loader = new GLTFLoader();
    const texLoader = new THREE.TextureLoader();

    loader.load(modelUrl, (gltf) => {
      const tex = texLoader.load(texUrl, (tx) => {
        tx.magFilter = THREE.NearestFilter; tx.minFilter = THREE.NearestFilter;
        tx.flipY = false; tx.colorSpace = THREE.SRGBColorSpace;
      });
      gltf.scene.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && m.material) {
          (m.material as THREE.MeshBasicMaterial).map = tex;
          (m.material as THREE.Material).needsUpdate = true;
        }
      });
      modelGroup.add(gltf.scene);

      // Recentre: feet to y=0, centred on x/z, facing +Z (toward camera-ish).
      const box = new THREE.Box3().setFromObject(gltf.scene);
      const size = box.getSize(new THREE.Vector3());
      const center = box.getCenter(new THREE.Vector3());
      figureHeight = Math.max(size.y, 0.5);
      gltf.scene.position.x -= center.x;
      gltf.scene.position.z -= center.z;
      gltf.scene.position.y -= box.min.y;

      placeCamera();
      // The counter slab is authored at ~1.7u-tall scale; scale + place it
      // relative to THIS figure so short NPCs aren't swallowed by it and the
      // top sits around the NPC's waist regardless of height.
      if (counter) {
        const s = figureHeight / 1.7;
        counter.scale.setScalar(s);
        counter.position.set(0, 0, figureHeight * 0.5);
      }

      // idle clip
      if (idleClip) {
        // Node names present on THIS NPC's skeleton — used to drop clip tracks
        // that target bones this model lacks (idle clips are authored against a
        // shared PSO rig; some NPCs are missing e.g. the leg bones). Prevents
        // "No target node found" spam and pointless bindings.
        const nodeNames = new Set<string>();
        gltf.scene.traverse((o) => { if (o.name) nodeNames.add(o.name); });
        loader.load(IDLE_ANIM_GLB, (ag) => {
          const clip = ag.animations.find((a) => a.name === idleClip) || ag.animations.find((a) => a.name.endsWith(idleClip));
          if (!clip) return;
          stripRoot(clip);
          clip.tracks = clip.tracks.filter((t) => nodeNames.has(t.name.split('.')[0]));
          if (!clip.tracks.length) return;
          mixer = new THREE.AnimationMixer(gltf.scene);
          const action = mixer.clipAction(clip);
          action.setLoop(THREE.LoopRepeat, Infinity);
          action.play();
        }, undefined, () => { /* static pose fallback */ });
      }
    }, undefined, (e) => { console.warn('[ShopScene] model load failed', modelUrl, e); });

    // optional counter slab
    if (preset.counter) {
      counter = new THREE.Group();
      const top = new THREE.Mesh(
        new THREE.BoxGeometry(3.4, 0.12, 0.7),
        new THREE.MeshBasicMaterial({ color: accentColor.clone().lerp(new THREE.Color(0xffffff), 0.15) }),
      );
      top.position.y = 0.92;
      const body = new THREE.Mesh(
        new THREE.BoxGeometry(3.4, 0.92, 0.6),
        new THREE.MeshBasicMaterial({ color: new THREE.Color(0x0c1220) }),
      );
      body.position.y = 0.46;
      const trim = new THREE.Mesh(
        new THREE.BoxGeometry(3.42, 0.05, 0.62),
        new THREE.MeshBasicMaterial({ color: accentColor, transparent: true, opacity: 0.8 }),
      );
      trim.position.y = 0.86;
      counter.add(body, top, trim);
      counter.position.z = 0.9;
      scene.add(counter);
    }

    // ---- camera placement from the preset ----
    const target = new THREE.Vector3();
    function placeCamera() {
      const az = THREE.MathUtils.degToRad(preset.azimuthDeg);
      const el2 = THREE.MathUtils.degToRad(preset.elevationDeg);
      const dist = figureHeight * preset.distanceMul;
      target.set(0, figureHeight * preset.targetYFrac, 0);
      camera.position.set(
        target.x + dist * Math.sin(az) * Math.cos(el2),
        target.y + dist * Math.sin(el2),
        target.z + dist * Math.cos(az) * Math.cos(el2),
      );
      camera.lookAt(target);
      glow.position.set(0, figureHeight * 0.6, -0.8);
      applyViewOffset();
    }

    // lateralShift pushes the framed subject sideways so the overlay has room.
    function applyViewOffset() {
      if (!preset.lateralShift) { camera.clearViewOffset(); return; }
      // +shift => NPC to the right => render window offset to the left.
      const dx = -preset.lateralShift * w;
      camera.setViewOffset(w, h, dx, 0, w, h);
    }

    // ---- loop ----
    const clock = new THREE.Clock();
    let raf = 0;
    const baseAz = preset.azimuthDeg;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.05);
      if (mixer) mixer.update(dt);
      // gentle breathing drift on the camera for life
      const t = clock.elapsedTime;
      preset.azimuthDeg = baseAz + Math.sin(t * 0.25) * 1.4;
      placeCamera();
      renderer.render(scene, camera);
    };
    animate();

    const ro = new ResizeObserver(() => {
      if (!mountRef.current) return;
      w = mountRef.current.clientWidth; h = mountRef.current.clientHeight;
      if (!w || !h) return;
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      applyViewOffset();
    });
    ro.observe(el);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      renderer.dispose();
      scene.background = null;
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
      preset.azimuthDeg = baseAz;
    };
  }, [modelUrl, texUrl, idleClip, accent, preset]);

  return <div ref={mountRef} className={className} style={{ position: 'absolute', inset: 0 }} />;
}
