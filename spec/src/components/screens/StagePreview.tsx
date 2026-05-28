import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../../utils/assets';

const W = 960, H = 540;

interface Props {
  glb: string;
  spawn: [number, number, number];
  cameraOffset?: [number, number, number];
  lookAt?: [number, number, number];
}

export default function StagePreview({ glb, spawn, cameraOffset = [0, 12, 18], lookAt }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2a);

    const target = lookAt ?? spawn;
    const camPos: [number, number, number] = [
      target[0] + cameraOffset[0],
      target[1] + cameraOffset[1],
      target[2] + cameraOffset[2],
    ];

    const camera = new THREE.PerspectiveCamera(50, W / H, 0.1, 500);
    camera.position.set(...camPos);
    camera.lookAt(...target);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(W, H);
    renderer.setPixelRatio(1);
    el.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.target.set(...target);
    controls.enableDamping = true;
    controls.update();

    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dir = new THREE.DirectionalLight(0xffffff, 0.8);
    dir.position.set(10, 20, 15);
    scene.add(dir);

    // Player pill — capsule at spawn position
    const pillGeo = new THREE.CapsuleGeometry(0.3, 1.0, 8, 16);
    const pillMat = new THREE.MeshStandardMaterial({ color: 0x44cc44, emissive: 0x228822, roughness: 0.4 });
    const pill = new THREE.Mesh(pillGeo, pillMat);
    pill.position.set(spawn[0], spawn[1] + 0.8, spawn[2]);
    scene.add(pill);

    // Spawn ring on ground
    const ringGeo = new THREE.RingGeometry(0.5, 0.7, 32);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0x44cc44, side: THREE.DoubleSide, transparent: true, opacity: 0.5 });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.position.set(spawn[0], spawn[1] + 0.05, spawn[2]);
    ring.rotation.x = -Math.PI / 2;
    scene.add(ring);

    // Load stage GLB
    const url = assetUrl(glb);
    new GLTFLoader().load(url, (gltf) => {
      const model = gltf.scene;
      model.traverse((obj) => {
        const m = obj as THREE.Mesh;
        if (m.isMesh) {
          if (!m.material || (m.material as THREE.MeshStandardMaterial).map === null) {
            m.material = new THREE.MeshStandardMaterial({
              color: 0x8899aa,
              roughness: 0.7,
              metalness: 0.1,
              side: THREE.DoubleSide,
            });
          }
        }
      });
      scene.add(model);
    });

    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      // Pill bob
      pill.position.y = spawn[1] + 0.8 + Math.sin(Date.now() * 0.003) * 0.15;
      controls.update();
      renderer.render(scene, camera);
    };
    raf = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(raf);
      controls.dispose();
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
  }, [glb, spawn[0], spawn[1], spawn[2]]);

  return <div ref={ref} style={{ width: W, height: H, background: '#000' }} />;
}
