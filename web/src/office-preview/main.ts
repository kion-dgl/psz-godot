import './style.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

const element = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const container = element('canvas');
const status = element('status');
let activeMode = 'model';
const views = ['model', 'compare', 'angle'];
for (const button of document.querySelectorAll<HTMLButtonElement>('[data-mode]')) {
  button.addEventListener('click', () => {
    activeMode = button.dataset.mode!;
    for (const view of views) element(`${view}-view`).hidden = view !== activeMode;
    for (const tab of document.querySelectorAll('[data-mode]')) {
      tab.setAttribute('aria-pressed', String((tab as HTMLButtonElement).dataset.mode === activeMode));
    }
    status.hidden = activeMode !== 'model' || status.dataset.loaded === 'true';
    element('help').textContent = activeMode === 'model'
      ? 'Drag to orbit · Scroll to zoom · Right-drag to pan'
      : activeMode === 'compare' ? 'Move the slider to compare the same camera angle' : 'Angled view of the updated office';
    element('source').textContent = activeMode === 'model'
      ? 'Current Godot geometry · Browser lighting approximation' : 'Actual Godot render';
  });
}
element<HTMLInputElement>('compare-slider').addEventListener('input', (event) => {
  const value = (event.target as HTMLInputElement).value;
  element('after-layer').style.clipPath = `inset(0 0 0 ${value}%)`;
  element('divider').style.left = `${value}%`;
});

try {
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  container.appendChild(renderer.domElement);
  renderer.domElement.setAttribute('aria-label', 'Interactive 3D model of the principal’s office');
  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#25383d');
  const camera = new THREE.PerspectiveCamera(55, 1, 0.05, 100);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.minDistance = 1;
  controls.maxDistance = 30;
  controls.maxPolarAngle = Math.PI * 0.49;
  const presets: Record<string, { position: [number, number, number]; target: [number, number, number] }> = {
    entrance: { position: [0, 3.4, 8.2], target: [0, 3.6, -4.5] },
    desk: { position: [4.2, 4.3, 1.7], target: [0, 3.8, -5.6] },
    overview: { position: [11, 13, 16], target: [0, 2.2, -1] },
  };
  function setCamera(name: string) {
    const preset = presets[name];
    camera.position.fromArray(preset.position);
    controls.target.fromArray(preset.target);
    controls.update();
    for (const button of document.querySelectorAll<HTMLButtonElement>('[data-camera]')) {
      button.setAttribute('aria-pressed', String(button.dataset.camera === name));
    }
  }
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-camera]')) {
    button.addEventListener('click', () => setCamera(button.dataset.camera!));
  }
  setCamera('entrance');
  scene.add(new THREE.AmbientLight('#cdb088', 1.1));
  scene.add(new THREE.HemisphereLight('#e1edf2', '#514433', 1.1));
  const key = new THREE.DirectionalLight('#fff2dd', 1.8);
  key.position.set(3, 8, 6);
  scene.add(key);
  const cool = new THREE.PointLight('#9fe8ff', 22, 16);
  cool.position.set(0, 4, -7);
  scene.add(cool);
  const materials = new Set<THREE.MeshStandardMaterial | THREE.MeshBasicMaterial>();
  const wireframe = element<HTMLInputElement>('wireframe');
  wireframe.addEventListener('change', () => {
    materials.forEach(material => { material.wireframe = wireframe.checked; });
  });
  new GLTFLoader().load('./office-preview/room.glb', gltf => {
    gltf.scene.traverse(node => {
      // Godot and Three use different point-light intensity conventions.
      if (node instanceof THREE.Light) node.visible = false;
      if (node instanceof THREE.Mesh) {
        const list = Array.isArray(node.material) ? node.material : [node.material];
        for (const material of list) {
          if (material instanceof THREE.MeshStandardMaterial || material instanceof THREE.MeshBasicMaterial) {
            material.wireframe = wireframe.checked;
            materials.add(material);
            if (material.map) material.map.anisotropy = renderer.capabilities.getMaxAnisotropy();
          }
        }
      }
    });
    scene.add(gltf.scene);
    status.dataset.loaded = 'true';
    status.hidden = true;
  }, undefined, error => {
    console.error(error);
    status.textContent = 'The 3D room could not load. You can still review the Before & after and In-game detail tabs.';
  });
  const resize = new ResizeObserver(() => {
    if (!container.clientWidth || !container.clientHeight) return;
    renderer.setSize(container.clientWidth, container.clientHeight);
    camera.aspect = container.clientWidth / container.clientHeight;
    camera.updateProjectionMatrix();
  });
  resize.observe(container);
  renderer.setAnimationLoop(() => {
    if (activeMode !== 'model' || document.hidden) return;
    controls.update();
    renderer.render(scene, camera);
  });
} catch (error) {
  console.error(error);
  status.textContent = '3D rendering is unavailable in this browser. Use Before & after or In-game detail to review the Godot captures.';
}
