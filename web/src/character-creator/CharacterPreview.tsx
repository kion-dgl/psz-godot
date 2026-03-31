import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { getModelPath, getTexturePath, getIdleAnimationPath, GENDER_MAP } from './data/constants';

interface Props {
  classId: string | null;
  variationIndex: number;
  hairColorIndex: number;
  skinToneIndex: number;
  bodyColorIndex: number;
}

export default function CharacterPreview({ classId, variationIndex, hairColorIndex, skinToneIndex, bodyColorIndex }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<{
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    renderer: THREE.WebGLRenderer;
    controls: OrbitControls;
    mixer: THREE.AnimationMixer | null;
    model: THREE.Object3D | null;
    currentAction: THREE.AnimationAction | null;
    animFrameId: number;
  } | null>(null);

  // Track what's currently loaded so we can avoid redundant reloads
  const loadedRef = useRef<{ classId: string | null; variation: number }>({ classId: null, variation: -1 });

  // Initialize Three.js scene once
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 1000);
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

    // Force canvas to be transparent
    renderer.domElement.style.background = 'transparent';

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.autoRotate = false;
    controls.target.set(0, 0.8, 0);

    const clock = new THREE.Clock();
    let animFrameId = 0;
    const sceneData = {
      scene, camera, renderer, controls,
      mixer: null as THREE.AnimationMixer | null,
      model: null as THREE.Object3D | null,
      currentAction: null as THREE.AnimationAction | null,
      animFrameId: 0,
    };
    sceneRef.current = sceneData;

    const animate = () => {
      animFrameId = requestAnimationFrame(animate);
      sceneData.animFrameId = animFrameId;
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
      cancelAnimationFrame(animFrameId);
      renderer.dispose();
      if (container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
    };
  }, []);

  // Load model + idle animation when classId or variation changes
  useEffect(() => {
    if (!sceneRef.current || !classId) return;
    const s = sceneRef.current;

    // Skip if already loaded
    if (loadedRef.current.classId === classId && loadedRef.current.variation === variationIndex) {
      return;
    }

    // Remove old model
    if (s.model) {
      s.scene.remove(s.model);
      s.model = null;
    }
    s.mixer = null;
    s.currentAction = null;

    const loader = new GLTFLoader();
    const modelPath = getModelPath(classId, variationIndex);
    const texturePath = getTexturePath(classId, variationIndex, hairColorIndex, skinToneIndex, bodyColorIndex);
    const animPath = getIdleAnimationPath(classId);

    loader.load(modelPath, (gltf) => {
      // Guard: scene may have been cleaned up
      if (!sceneRef.current) return;

      const model = gltf.scene;
      s.scene.add(model);
      s.model = model;
      loadedRef.current = { classId, variation: variationIndex };

      // Apply texture
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

        const gender = GENDER_MAP[classId] || 'm';
        const idleName = gender === 'm' ? 'pmsa_wait' : 'pwsa_wait';
        const clip = animGltf.animations.find((a) => a.name === idleName) || animGltf.animations[0];
        if (clip) {
          const action = mixer.clipAction(clip);
          action.play();
          s.currentAction = action;
        }
      });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [classId, variationIndex]);

  // Reload texture only when color indices change (model stays)
  useEffect(() => {
    if (!sceneRef.current || !classId || !sceneRef.current.model) return;
    // If model is still loading (classId/variation mismatch), the model load above will handle texture
    if (loadedRef.current.classId !== classId || loadedRef.current.variation !== variationIndex) return;

    const model = sceneRef.current.model;
    const texturePath = getTexturePath(classId, variationIndex, hairColorIndex, skinToneIndex, bodyColorIndex);
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
  }, [classId, variationIndex, hairColorIndex, skinToneIndex, bodyColorIndex]);

  return (
    <div
      ref={containerRef}
      style={{
        width: '100%',
        height: '100%',
        minHeight: 400,
        background: '#0a0a1a',
        borderRadius: 8,
        overflow: 'hidden',
      }}
    />
  );
}
