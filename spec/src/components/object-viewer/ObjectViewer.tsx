import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../../utils/assets';

const W = 720, H = 440;

interface Props {
  glb: string;
  scale?: number;
  cameraOffset?: [number, number, number];
}

/**
 * Reusable single-object turntable viewer. Loads one GLB, centers it on a
 * grid, auto-frames the camera to its bounding box, and slowly autorotates.
 * Mirrors the raw-three pattern in screens/StagePreview.tsx (the spec site
 * does not use @react-three/fiber). Renders a placeholder panel when no GLB
 * is supplied (objects whose model varies at runtime).
 */
export default function ObjectViewer({ glb, scale = 1, cameraOffset }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!glb) return; // placeholder rendered in JSX below
    const el = ref.current;
    if (!el) return;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2a);

    const camera = new THREE.PerspectiveCamera(45, W / H, 0.01, 1000);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(W, H);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    el.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 1.4;

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const dir = new THREE.DirectionalLight(0xffffff, 0.85);
    dir.position.set(8, 16, 12);
    scene.add(dir);
    const dir2 = new THREE.DirectionalLight(0x8899ff, 0.25);
    dir2.position.set(-10, 6, -8);
    scene.add(dir2);

    // Subtle ground grid
    const grid = new THREE.GridHelper(40, 40, 0x3a3a5a, 0x262640);
    (grid.material as THREE.Material).transparent = true;
    (grid.material as THREE.Material).opacity = 0.5;
    scene.add(grid);

    const url = assetUrl(glb);
    new GLTFLoader().load(
      url,
      (gltf) => {
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
        model.scale.setScalar(scale);

        // Auto-frame: center the model over the grid origin, then fit camera.
        const box = new THREE.Box3().setFromObject(model);
        const size = new THREE.Vector3();
        const center = new THREE.Vector3();
        box.getSize(size);
        box.getCenter(center);

        // Drop the model so its base rests on the grid, centered in X/Z.
        model.position.x -= center.x;
        model.position.z -= center.z;
        model.position.y -= box.min.y;
        scene.add(model);

        const maxDim = Math.max(size.x, size.y, size.z) || 1;
        const fitDist = maxDim / (2 * Math.tan((Math.PI * 45) / 360));
        const dist = fitDist * 1.8;
        const focus = new THREE.Vector3(0, size.y / 2, 0);

        if (cameraOffset) {
          camera.position.set(
            focus.x + cameraOffset[0],
            focus.y + cameraOffset[1],
            focus.z + cameraOffset[2],
          );
        } else {
          camera.position.set(focus.x + dist * 0.7, focus.y + dist * 0.6, focus.z + dist * 0.9);
        }
        camera.near = maxDim / 100;
        camera.far = maxDim * 100;
        camera.updateProjectionMatrix();
        controls.target.copy(focus);
        controls.update();
      },
      undefined,
      (err) => {
        console.error('[ObjectViewer] failed to load', url, err);
      },
    );

    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
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
  }, [glb, scale, cameraOffset?.[0], cameraOffset?.[1], cameraOffset?.[2]]);

  if (!glb) {
    return (
      <div
        style={{
          width: W,
          maxWidth: '100%',
          height: H,
          background: '#1a1a2a',
          border: '1px solid #30363d',
          borderRadius: 8,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#8b949e',
          fontSize: 14,
          fontStyle: 'italic',
          boxSizing: 'border-box',
        }}
      >
        No single model — varies at runtime
      </div>
    );
  }

  return (
    <div
      ref={ref}
      style={{
        width: W,
        maxWidth: '100%',
        height: H,
        background: '#000',
        borderRadius: 8,
        overflow: 'hidden',
      }}
    />
  );
}
