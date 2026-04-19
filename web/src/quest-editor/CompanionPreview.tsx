/**
 * CompanionPreview — 3D preview of companion NPCs using THREE.js.
 * Shows selected companions with idle animation in a small viewport.
 */

import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

/** Model + texture paths per companion, mirrors COMPANION_MODELS in companion_npc.gd */
const COMPANION_ASSETS: Record<string, { glb: string; texture: string }> = {
  kai:      { glb: 'assets/npcs/kai/pc_a01_000.glb',         texture: 'assets/npcs/kai/pc_a01_000.png' },
  sarisa:   { glb: 'assets/npcs/sarisa/pc_a00_000.glb',      texture: 'assets/npcs/sarisa/pc_a00_000.png' },
  elio:     { glb: 'assets/npcs/elio/elio.glb',              texture: 'assets/npcs/elio/elio.png' },
  dorn:     { glb: 'assets/npcs/dorn/dorn.glb',              texture: 'assets/npcs/dorn/dorn.png' },
  ren:      { glb: 'assets/npcs/ren/ren.glb',                texture: 'assets/npcs/ren/ren.png' },
  fern:     { glb: 'assets/npcs/fern/fern.glb',              texture: 'assets/npcs/fern/fern.png' },
  dr_carlo: { glb: 'assets/npcs/dr_carlo/dr_carlo.glb',      texture: 'assets/npcs/dr_carlo/dr_carlo.png' },
  mira:     { glb: 'assets/npcs/mira/mira.glb',              texture: 'assets/npcs/mira/mira.png' },
  vash:     { glb: 'assets/npcs/vash/vash.glb',              texture: 'assets/npcs/vash/vash.png' },
};

/** Companion class → gender, mirrors COMPANION_CLASSES + FEMALE_CLASSES in companion_npc.gd */
const COMPANION_GENDER: Record<string, 'm' | 'f'> = {
  kai: 'm', sarisa: 'f', elio: 'f', dorn: 'm',
  ren: 'm', fern: 'f', dr_carlo: 'm', mira: 'f', vash: 'm',
};

interface Props {
  companionId: string;
}

export default function CompanionPreview({ companionId }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<{
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    renderer: THREE.WebGLRenderer;
    controls: OrbitControls;
    mixer: THREE.AnimationMixer | null;
    model: THREE.Object3D | null;
    animFrameId: number;
  } | null>(null);
  const loadedRef = useRef<string | null>(null);

  // Initialize THREE scene once
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 100);
    camera.position.set(0, 1.2, 2.5);

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(width, height);
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setClearColor(0x000000, 0);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(5, 5, 5);
    scene.add(dirLight);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.8, 0);

    const clock = new THREE.Clock();
    const sceneData = {
      scene, camera, renderer, controls,
      mixer: null as THREE.AnimationMixer | null,
      model: null as THREE.Object3D | null,
      animFrameId: 0,
    };
    sceneRef.current = sceneData;

    const animate = () => {
      sceneData.animFrameId = requestAnimationFrame(animate);
      const delta = clock.getDelta();
      if (sceneData.mixer) sceneData.mixer.update(delta);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const handleResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      cancelAnimationFrame(sceneData.animFrameId);
      sceneRef.current = null;
      renderer.dispose();
      if (container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
    };
  }, []);

  // Load companion model when companionId changes
  useEffect(() => {
    if (!sceneRef.current || !companionId) return;
    const s = sceneRef.current;
    const assets = COMPANION_ASSETS[companionId];
    if (!assets) return;
    if (loadedRef.current === companionId) return;

    // Remove old model
    if (s.model) {
      s.scene.remove(s.model);
      s.model = null;
    }
    s.mixer = null;

    const loader = new GLTFLoader();
    const modelPath = assetUrl(assets.glb);
    const texturePath = assetUrl(assets.texture);
    const gender = COMPANION_GENDER[companionId] || 'm';
    const animPath = assetUrl(`assets/player/animations/saver_${gender === 'f' ? 'w' : 'm'}.glb`);

    loader.load(modelPath, (gltf) => {
      if (!sceneRef.current) return;
      const model = gltf.scene;
      s.scene.add(model);
      s.model = model;
      loadedRef.current = companionId;

      // Apply texture with nearest-neighbor filtering
      const textureLoader = new THREE.TextureLoader();
      textureLoader.load(texturePath, (texture) => {
        texture.magFilter = THREE.NearestFilter;
        texture.minFilter = THREE.NearestFilter;
        texture.flipY = false;
        texture.colorSpace = THREE.SRGBColorSpace;
        model.traverse((child: THREE.Object3D) => {
          if ((child as THREE.Mesh).isMesh && (child as THREE.Mesh).material) {
            ((child as THREE.Mesh).material as THREE.MeshStandardMaterial).map = texture;
            ((child as THREE.Mesh).material as THREE.MeshStandardMaterial).needsUpdate = true;
          }
        });
      });

      // Load idle animation
      loader.load(animPath, (animGltf) => {
        if (!sceneRef.current) return;
        const mixer = new THREE.AnimationMixer(model);
        s.mixer = mixer;
        const idleName = gender === 'f' ? 'pwsa_wait' : 'pmsa_wait';
        const clip = animGltf.animations.find((a) => a.name === idleName) || animGltf.animations[0];
        if (clip) {
          mixer.clipAction(clip).play();
        }
      });
    });
  }, [companionId]);

  return (
    <div
      ref={containerRef}
      style={{
        width: '100%',
        height: '100%',
        background: 'transparent',
        overflow: 'hidden',
      }}
    />
  );
}
