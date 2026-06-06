import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../../utils/assets';

const MAX_W = 720;
const ASPECT = 720 / 440;

interface Props {
  glb: string;
  scale?: number;
  cameraOffset?: [number, number, number];
}

/**
 * Reusable single-object turntable viewer. Loads one GLB, centers it on a
 * grid, auto-frames the camera to its bounding box, and slowly autorotates.
 * Mirrors the raw-three pattern in screens/StagePreview.tsx (the spec site
 * does not use @react-three/fiber).
 *
 * The wrapper is fluid (width:100%, capped at MAX_W, fixed aspect ratio); the
 * renderer + camera are sized from the container's real dimensions and kept in
 * sync with a ResizeObserver, so the canvas never overflows on narrow layouts.
 * On unmount it disposes geometries/materials/textures to avoid leaking GPU
 * memory across page navigations. Pages with no model render a static
 * placeholder instead of mounting this island (see [object].astro).
 */
export default function ObjectViewer({ glb, scale = 1, cameraOffset }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!glb) return;
    const el = ref.current;
    if (!el) return;

    const w0 = el.clientWidth || MAX_W;
    const h0 = el.clientHeight || Math.round(MAX_W / ASPECT);

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a2a);

    const camera = new THREE.PerspectiveCamera(45, w0 / h0, 0.01, 1000);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w0, h0);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    renderer.domElement.style.display = 'block';
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

    // Keep renderer + camera matched to the container's actual size.
    const resize = () => {
      const w = el.clientWidth || MAX_W;
      const h = el.clientHeight || Math.round(MAX_W / ASPECT);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    const ro = new ResizeObserver(resize);
    ro.observe(el);

    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    };
    raf = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      controls.dispose();
      // Dispose GPU resources so navigating between viewers doesn't leak.
      scene.traverse((obj) => {
        const m = obj as THREE.Mesh;
        if (!m.isMesh) return;
        m.geometry?.dispose?.();
        const mats = Array.isArray(m.material) ? m.material : [m.material];
        for (const mat of mats) {
          if (!mat) continue;
          for (const key of Object.keys(mat) as (keyof THREE.Material)[]) {
            const val = (mat as Record<string, unknown>)[key as string];
            if (val && (val as THREE.Texture).isTexture) (val as THREE.Texture).dispose();
          }
          mat.dispose();
        }
      });
      grid.geometry.dispose();
      (grid.material as THREE.Material).dispose();
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
  }, [glb, scale, cameraOffset?.[0], cameraOffset?.[1], cameraOffset?.[2]]);

  return (
    <div
      ref={ref}
      style={{
        width: '100%',
        maxWidth: MAX_W,
        aspectRatio: `${ASPECT}`,
        background: '#000',
        borderRadius: 8,
        overflow: 'hidden',
      }}
    />
  );
}
