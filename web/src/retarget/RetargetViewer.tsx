import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';
import { captureRestPose, getWorldRestQuat, type RestPoseData } from './retarget-utils';

const PSZ_MODEL_PATH = assetUrl('/player/pc_000/pc_000/pc_000_000.glb');
const PSZ_TEXTURE_PATH = assetUrl('/player/pc_000/textures/pc_000_000.png');
const PSO_MODEL_PATH = assetUrl('/data/retarget/Humar_body.glb');
const ANIMATION_MAP_PATH = assetUrl('/data/retarget/pso_animation_map.json');

// Animation name mapping: PSO animation index → PSZ animation name
interface AnimationMapData {
  _comment: string;
  mappings: Record<string, string>; // index as string → PSZ name
}

const BONE_MARKER_RADIUS = 0.012;

interface BoneInfo {
  name: string;
  depth: number;
  worldPos: THREE.Vector3;
  bone: THREE.Bone;
}

interface BoneTreeNode {
  info: BoneInfo;
  children: BoneTreeNode[];
}

interface BoneMarker {
  mesh: THREE.Mesh;
  boneName: string;
  side: 'psz' | 'pso';
}

// Build a tree from the flat depth-ordered bone list
function buildBoneTree(bones: BoneInfo[]): BoneTreeNode[] {
  const roots: BoneTreeNode[] = [];
  const stack: BoneTreeNode[] = [];
  for (const bone of bones) {
    const node: BoneTreeNode = { info: bone, children: [] };
    while (stack.length > 0 && stack[stack.length - 1].info.depth >= bone.depth) {
      stack.pop();
    }
    if (stack.length === 0) {
      roots.push(node);
    } else {
      stack[stack.length - 1].children.push(node);
    }
    stack.push(node);
  }
  return roots;
}

// Collect all descendant bone names (for hiding subtrees)
function collectDescendantNames(node: BoneTreeNode): string[] {
  const names: string[] = [];
  for (const child of node.children) {
    names.push(child.info.name);
    names.push(...collectDescendantNames(child));
  }
  return names;
}

function collectBones(root: THREE.Object3D): BoneInfo[] {
  const bones: BoneInfo[] = [];
  const traverse = (obj: THREE.Object3D, depth: number) => {
    if ((obj as THREE.Bone).isBone) {
      const worldPos = new THREE.Vector3();
      obj.getWorldPosition(worldPos);
      bones.push({ name: obj.name, depth, worldPos, bone: obj as THREE.Bone });
    }
    for (const child of obj.children) {
      traverse(child, depth + 1);
    }
  };
  traverse(root, 0);
  return bones;
}

function resetToBindPose(model: THREE.Object3D): void {
  model.traverse((child) => {
    if ((child as THREE.SkinnedMesh).isSkinnedMesh) {
      const skeleton = (child as THREE.SkinnedMesh).skeleton;
      if (skeleton) skeleton.pose();
    }
  });
  model.updateMatrixWorld(true);
}

function matchPsoScaleToPsz(pszModel: THREE.Object3D, psoModel: THREE.Object3D): void {
  const pszBox = new THREE.Box3().setFromObject(pszModel);
  const psoBox = new THREE.Box3().setFromObject(psoModel);
  const pszHeight = pszBox.max.y - pszBox.min.y;
  const psoHeight = psoBox.max.y - psoBox.min.y;
  if (psoHeight > 0 && pszHeight > 0) {
    psoModel.scale.multiplyScalar(pszHeight / psoHeight);
  }
}

function createSkeletonHelper(model: THREE.Object3D, color: number): THREE.SkeletonHelper | null {
  let skeleton: THREE.Skeleton | null = null;
  model.traverse((child) => {
    if ((child as THREE.SkinnedMesh).isSkinnedMesh) {
      skeleton = (child as THREE.SkinnedMesh).skeleton;
    }
  });
  if (!skeleton) return null;
  const helper = new THREE.SkeletonHelper(model);
  (helper.material as THREE.LineBasicMaterial).color.set(color);
  (helper.material as THREE.LineBasicMaterial).linewidth = 2;
  helper.renderOrder = 998;
  return helper;
}

function createBoneMarkers(
  bones: BoneInfo[],
  color: number,
  selectedBone: string | null,
  scene: THREE.Scene,
  side: 'psz' | 'pso',
  disabledBones?: Set<string>,
): BoneMarker[] {
  const markers: BoneMarker[] = [];
  const geo = new THREE.SphereGeometry(BONE_MARKER_RADIUS, 8, 6);
  for (const bone of bones) {
    if (disabledBones?.has(bone.name)) continue;
    const isSelected = bone.name === selectedBone;
    const mat = new THREE.MeshBasicMaterial({
      color: isSelected ? 0xffff00 : color,
      depthTest: false,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(bone.worldPos);
    mesh.renderOrder = 999;
    mesh.userData = { boneName: bone.name, side };
    scene.add(mesh);
    markers.push({ mesh, boneName: bone.name, side });
  }
  return markers;
}

function createSelectedLabel(bone: BoneInfo, color: string, scene: THREE.Scene): THREE.Sprite {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = 64;
  const ctx = canvas.getContext('2d')!;
  ctx.font = 'bold 24px monospace';
  ctx.fillStyle = color;
  ctx.fillText(bone.name, 4, 28);
  const texture = new THREE.CanvasTexture(canvas);
  const material = new THREE.SpriteMaterial({ map: texture, depthTest: false });
  const sprite = new THREE.Sprite(material);
  sprite.scale.set(1.6, 0.2, 1);
  sprite.position.copy(bone.worldPos);
  sprite.position.y += 0.06;
  sprite.renderOrder = 1000;
  scene.add(sprite);
  return sprite;
}

interface SceneState {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  pszModel: THREE.Object3D | null;
  psoModel: THREE.Object3D | null;
  pszHelper: THREE.SkeletonHelper | null;
  psoHelper: THREE.SkeletonHelper | null;
  psoMixer: THREE.AnimationMixer | null;
  pszMixer: THREE.AnimationMixer | null;
  psoAnimations: THREE.AnimationClip[];
  currentAction: THREE.AnimationAction | null;
  currentPszAction: THREE.AnimationAction | null;
  boneMarkers: BoneMarker[];
  selectedLabels: THREE.Sprite[];
  psoRest: RestPoseData;
  pszRest: RestPoseData;
}

// Collapsible bone tree row component
function BoneTreeRow({
  node,
  selectedBone,
  onSelect,
  collapsed,
  onToggleCollapse,
  color,
  selectedColor,
  mappings,
  disabledBones,
  onToggleDisable,
  side,
}: {
  node: BoneTreeNode;
  selectedBone: string | null;
  onSelect: (name: string) => void;
  collapsed: Set<string>;
  onToggleCollapse: (name: string) => void;
  color: string;
  selectedColor: string;
  mappings?: Record<string, string>;
  disabledBones?: Set<string>;
  onToggleDisable?: (name: string) => void;
  side: 'psz' | 'pso';
}) {
  const isSelected = selectedBone === node.info.name;
  const isCollapsed = collapsed.has(node.info.name);
  const hasChildren = node.children.length > 0;
  const isDisabled = disabledBones?.has(node.info.name);
  const isMapped = mappings && node.info.name in mappings;

  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', gap: '2px' }}>
        {/* Collapse toggle */}
        {hasChildren ? (
          <button
            onClick={(e) => { e.stopPropagation(); onToggleCollapse(node.info.name); }}
            style={{
              width: '14px', height: '14px', padding: 0,
              background: 'transparent', border: 'none',
              color: '#666', cursor: 'pointer', fontSize: '9px',
              flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >
            {isCollapsed ? '\u25b6' : '\u25bc'}
          </button>
        ) : (
          <span style={{ width: '14px', flexShrink: 0 }} />
        )}

        {/* Disable toggle (PSO only) */}
        {onToggleDisable && (
          <button
            onClick={(e) => { e.stopPropagation(); onToggleDisable(node.info.name); }}
            title={isDisabled ? 'Show bone' : 'Hide bone'}
            style={{
              width: '14px', height: '14px', padding: 0,
              background: 'transparent', border: 'none',
              color: isDisabled ? '#555' : '#888', cursor: 'pointer', fontSize: '10px',
              flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
              opacity: isDisabled ? 0.5 : 1,
            }}
          >
            {isDisabled ? '\u25cb' : '\u25cf'}
          </button>
        )}

        {/* Bone name button */}
        <button
          onClick={() => onSelect(node.info.name)}
          style={{
            flex: 1,
            padding: '3px 6px',
            paddingLeft: `${4 + node.info.depth * 10}px`,
            background: isSelected ? (side === 'psz' ? '#2a4a2a' : '#4a2a2a') : isMapped ? '#2a2a3a' : 'transparent',
            border: isSelected ? `1px solid ${selectedColor}` : '1px solid transparent',
            borderRadius: '3px',
            color: isDisabled ? '#444' : isSelected ? selectedColor : isMapped ? '#8888ff' : '#aaa',
            cursor: 'pointer',
            fontSize: '11px',
            textAlign: 'left',
            fontFamily: 'monospace',
            textDecoration: isDisabled ? 'line-through' : 'none',
            minWidth: 0,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {node.info.name}
          {isMapped && (
            <span style={{ color: '#44ff44', fontSize: '9px', marginLeft: '4px' }}>
              &rarr; {mappings![node.info.name]}
            </span>
          )}
        </button>
      </div>
      {/* Children */}
      {hasChildren && !isCollapsed && node.children.map((child) => (
        <BoneTreeRow
          key={child.info.name}
          node={child}
          selectedBone={selectedBone}
          onSelect={onSelect}
          collapsed={collapsed}
          onToggleCollapse={onToggleCollapse}
          color={color}
          selectedColor={selectedColor}
          mappings={mappings}
          disabledBones={disabledBones}
          onToggleDisable={onToggleDisable}
          side={side}
        />
      ))}
    </>
  );
}

export default function RetargetViewer() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneState | null>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);

  const [pszBones, setPszBones] = useState<BoneInfo[]>([]);
  const [psoBones, setPsoBones] = useState<BoneInfo[]>([]);
  const [selectedPszBone, setSelectedPszBone] = useState<string | null>(null);
  const [selectedPsoBone, setSelectedPsoBone] = useState<string | null>(null);
  const [psoAnimations, setPsoAnimations] = useState<string[]>([]);
  const [selectedAnimation, setSelectedAnimation] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showMeshes, setShowMeshes] = useState(true);
  const [showMarkers, setShowMarkers] = useState(false);
  const [showSkeleton, setShowSkeleton] = useState(false);
  const [mappings, setMappings] = useState<Record<string, string>>({
    bone_000: '000_Root',
    bone_002: '010_Hip',
    bone_024: '020_Spine',
    bone_028: '030_LArm01',
    bone_029: '040_LArm02',
    bone_041: '060_RArm01',
    bone_042: '070_RArm02',
    bone_056: '090_Head',
    bone_004: '100_LLeg01',
    bone_005: '110_LLeg02',
    bone_013: '120_RLeg01',
    bone_014: '130_RLeg02',
  });
  const [pszLoaded, setPszLoaded] = useState(false);
  const [psoLoaded, setPsoLoaded] = useState(false);
  const [psoLoadError, setPsoLoadError] = useState<string | null>(null);
  const [psoLoadProgress, setPsoLoadProgress] = useState(0);
  const [playOnBoth, setPlayOnBoth] = useState(true);
  const [hoveredBone, setHoveredBone] = useState<{ name: string; side: 'psz' | 'pso' } | null>(null);
  const [pszCollapsed, setPszCollapsed] = useState<Set<string>>(new Set());
  const [psoCollapsed, setPsoCollapsed] = useState<Set<string>>(new Set());
  const [disabledPsoBones, setDisabledPsoBones] = useState<Set<string>>(new Set());
  const [zeroedPsoRest, setZeroedPsoRest] = useState(false);
  const [animationNameMap, setAnimationNameMap] = useState<Record<string, string>>({});
  const [nameInput, setNameInput] = useState('');
  const [animFilter, setAnimFilter] = useState<'all' | 'mapped' | 'unmapped'>('all');
  const [pszBonesOpen, setPszBonesOpen] = useState(false);
  const [psoBonesOpen, setPsoBonesOpen] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState(1);

  // Load animation name mappings
  useEffect(() => {
    fetch(ANIMATION_MAP_PATH)
      .then((r) => r.json())
      .then((data: AnimationMapData) => setAnimationNameMap(data.mappings || {}))
      .catch(() => {});
  }, []);

  // When selected animation changes, populate input with existing mapping
  useEffect(() => {
    if (!selectedAnimation) return;
    const idx = selectedAnimation.replace('plymotiondata_', '');
    setNameInput(animationNameMap[idx] || '');
  }, [selectedAnimation, animationNameMap]);

  const assignAnimationName = useCallback(() => {
    if (!selectedAnimation) return;
    const idx = selectedAnimation.replace('plymotiondata_', '');
    const trimmed = nameInput.trim();
    setAnimationNameMap((prev) => {
      const next = { ...prev };
      if (trimmed) next[idx] = trimmed;
      else delete next[idx];
      return next;
    });
  }, [selectedAnimation, nameInput]);

  const exportAnimationMap = useCallback(() => {
    const data: AnimationMapData = {
      _comment: 'Maps PSO animation index (plymotiondata_NNN) to PSZ animation name. Set to null for unmapped.',
      mappings: animationNameMap,
    };
    navigator.clipboard.writeText(JSON.stringify(data, null, 2));
  }, [animationNameMap]);

  const downloadAnimationMap = useCallback(() => {
    const data: AnimationMapData = {
      _comment: 'Maps PSO animation index (plymotiondata_NNN) to PSZ animation name. Set to null for unmapped.',
      mappings: animationNameMap,
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'pso_animation_map.json';
    a.click();
    URL.revokeObjectURL(a.href);
  }, [animationNameMap]);

  const navigateAnimation = useCallback((direction: 1 | -1) => {
    if (psoAnimations.length === 0) return;
    const currentIdx = selectedAnimation ? psoAnimations.indexOf(selectedAnimation) : -1;
    let nextIdx = currentIdx + direction;
    if (nextIdx < 0) nextIdx = psoAnimations.length - 1;
    if (nextIdx >= psoAnimations.length) nextIdx = 0;
    setSelectedAnimation(psoAnimations[nextIdx]);
    setIsPlaying(true);
  }, [psoAnimations, selectedAnimation]);

  const mappedCount = Object.keys(animationNameMap).length;
  const totalAnims = psoAnimations.length;

  // Filter animation list
  const filteredAnimations = psoAnimations.filter((name) => {
    if (animFilter === 'all') return true;
    const idx = name.replace('plymotiondata_', '');
    const isMapped = idx in animationNameMap;
    return animFilter === 'mapped' ? isMapped : !isMapped;
  });

  const pszTree = buildBoneTree(pszBones);
  const psoTree = buildBoneTree(psoBones);

  const toggleCollapse = useCallback((setFn: React.Dispatch<React.SetStateAction<Set<string>>>) => (name: string) => {
    setFn((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }, []);

  const toggleDisablePsoBone = useCallback((name: string) => {
    setDisabledPsoBones((prev) => {
      const next = new Set(prev);
      // Find the node to also toggle descendants
      const findNode = (nodes: BoneTreeNode[]): BoneTreeNode | null => {
        for (const n of nodes) {
          if (n.info.name === name) return n;
          const found = findNode(n.children);
          if (found) return found;
        }
        return null;
      };
      const node = findNode(psoTree);
      const names = [name];
      if (node) names.push(...collectDescendantNames(node));

      const willDisable = !prev.has(name);
      for (const n of names) {
        if (willDisable) next.add(n);
        else next.delete(n);
      }
      return next;
    });
  }, [psoTree]);

  // Initialize Three.js scene
  useEffect(() => {
    if (!containerRef.current) return;
    const container = containerRef.current;
    const width = container.clientWidth;
    const height = container.clientHeight;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 100);
    camera.position.set(0, 1.5, 4);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.setClearColor(0x0a0a1a);
    container.appendChild(renderer.domElement);

    scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
    dirLight.position.set(5, 5, 5);
    scene.add(dirLight);
    scene.add(new THREE.GridHelper(10, 10, 0x333333, 0x222222));

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(0, 0.8, 0);

    sceneRef.current = {
      scene, camera, renderer, controls,
      pszModel: null, psoModel: null,
      pszHelper: null, psoHelper: null,
      psoMixer: null, pszMixer: null, psoAnimations: [],
      currentAction: null, currentPszAction: null, boneMarkers: [], selectedLabels: [],
      psoRest: { localQuats: {}, worldQuats: {}, parentMap: {} },
      pszRest: { localQuats: {}, worldQuats: {}, parentMap: {} },
    };

    const clock = new THREE.Clock();
    const animate = () => {
      requestAnimationFrame(animate);
      const delta = clock.getDelta();
      if (sceneRef.current?.psoMixer) sceneRef.current.psoMixer.update(delta);
      if (sceneRef.current?.pszMixer) sceneRef.current.pszMixer.update(delta);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();

    const onMouseMove = (e: MouseEvent) => {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
      if (!sceneRef.current) return;
      raycaster.setFromCamera(mouse, camera);
      const markerMeshes = sceneRef.current.boneMarkers.map((m) => m.mesh);
      const intersects = raycaster.intersectObjects(markerMeshes);
      if (tooltipRef.current) {
        if (intersects.length > 0) {
          const hit = intersects[0].object;
          const { boneName, side } = hit.userData;
          setHoveredBone({ name: boneName, side });
          tooltipRef.current.style.left = `${e.clientX - rect.left + 12}px`;
          tooltipRef.current.style.top = `${e.clientY - rect.top - 8}px`;
          tooltipRef.current.style.display = 'block';
          renderer.domElement.style.cursor = 'pointer';
        } else {
          setHoveredBone(null);
          tooltipRef.current.style.display = 'none';
          renderer.domElement.style.cursor = 'default';
        }
      }
    };

    const onClick = (e: MouseEvent) => {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
      if (!sceneRef.current) return;
      raycaster.setFromCamera(mouse, camera);
      const markerMeshes = sceneRef.current.boneMarkers.map((m) => m.mesh);
      const intersects = raycaster.intersectObjects(markerMeshes);
      if (intersects.length > 0) {
        const hit = intersects[0].object;
        const { boneName, side } = hit.userData;
        if (side === 'psz') setSelectedPszBone(boneName);
        else setSelectedPsoBone(boneName);
      }
    };

    renderer.domElement.addEventListener('mousemove', onMouseMove);
    renderer.domElement.addEventListener('click', onClick);

    const handleResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', handleResize);

    const loader = new GLTFLoader();
    const textureLoader = new THREE.TextureLoader();

    // PSZ model on the left
    loader.load(PSZ_MODEL_PATH, (gltf) => {
      const model = gltf.scene;
      model.position.x = -1.2;
      scene.add(model);
      sceneRef.current!.pszModel = model;
      textureLoader.load(PSZ_TEXTURE_PATH, (texture) => {
        texture.magFilter = THREE.NearestFilter;
        texture.minFilter = THREE.NearestFilter;
        texture.flipY = false;
        texture.colorSpace = THREE.SRGBColorSpace;
        model.traverse((child: THREE.Object3D) => {
          if ((child as THREE.Mesh).isMesh) {
            (child as THREE.Mesh).material = new THREE.MeshBasicMaterial({ map: texture });
          }
        });
      });
      const helper = createSkeletonHelper(model, 0x44ff44);
      if (helper) { helper.visible = false; scene.add(helper); sceneRef.current!.pszHelper = helper; }
      sceneRef.current!.pszMixer = new THREE.AnimationMixer(model);
      model.updateMatrixWorld(true);
      sceneRef.current!.pszRest = captureRestPose(model);
      setPszBones(collectBones(model));
      setPszLoaded(true);
      if (sceneRef.current!.psoModel) {
        matchPsoScaleToPsz(model, sceneRef.current!.psoModel);
        sceneRef.current!.psoModel.updateMatrixWorld(true);
        console.log('PSO scaled (from PSZ callback), scale:', sceneRef.current!.psoModel.scale.toArray());
      }
    });

    // PSO model on the right
    loader.load(
      PSO_MODEL_PATH,
      (gltf) => {
        const model = gltf.scene;
        model.position.x = 1.2;
        scene.add(model);
        sceneRef.current!.psoModel = model;

        // Scale BEFORE resetting to bind pose — animated pose gives reliable bounding box
        model.updateMatrixWorld(true);
        if (sceneRef.current!.pszModel) {
          matchPsoScaleToPsz(sceneRef.current!.pszModel, model);
          model.updateMatrixWorld(true);
        }

        // Now reset to T-pose and capture rest quaternions
        resetToBindPose(model);
        model.updateMatrixWorld(true);
        sceneRef.current!.psoRest = captureRestPose(model);

        const helper = createSkeletonHelper(model, 0xff4444);
        if (helper) { helper.visible = false; scene.add(helper); sceneRef.current!.psoHelper = helper; }
        const mixer = new THREE.AnimationMixer(model);
        sceneRef.current!.psoMixer = mixer;
        sceneRef.current!.psoAnimations = gltf.animations;
        setPsoAnimations(gltf.animations.map((a) => a.name));

        model.updateMatrixWorld(true);
        setPsoBones(collectBones(model));
        setPsoLoaded(true);
        console.log('PSO loaded, scale:', model.scale.toArray(), 'position:', model.position.toArray());
      },
      (progress) => {
        if (progress.total > 0) setPsoLoadProgress(Math.round((progress.loaded / progress.total) * 100));
      },
      (error) => {
        console.error('Failed to load PSO model:', error);
        setPsoLoadError(`Failed to load PSO model: ${error}`);
      },
    );

    return () => {
      window.removeEventListener('resize', handleResize);
      renderer.domElement.removeEventListener('mousemove', onMouseMove);
      renderer.domElement.removeEventListener('click', onClick);
      renderer.dispose();
      if (container.contains(renderer.domElement)) container.removeChild(renderer.domElement);
    };
  }, []);

  // Zero out or restore PSO bone rest rotations
  useEffect(() => {
    if (!sceneRef.current?.psoModel) return;
    const { psoModel, psoRest } = sceneRef.current;
    psoModel.traverse((child) => {
      if ((child as THREE.Bone).isBone) {
        if (zeroedPsoRest) {
          child.quaternion.identity();
        } else {
          const rest = psoRest.localQuats[child.name];
          if (rest) child.quaternion.copy(rest);
        }
      }
    });
    psoModel.updateMatrixWorld(true);
  }, [zeroedPsoRest]);

  // Update bone markers + selected labels
  useEffect(() => {
    if (!sceneRef.current) return;
    const { scene, boneMarkers, selectedLabels } = sceneRef.current;

    for (const marker of boneMarkers) scene.remove(marker.mesh);
    for (const label of selectedLabels) { scene.remove(label); label.material.map?.dispose(); (label.material as THREE.SpriteMaterial).dispose(); }

    if (!showMarkers) {
      sceneRef.current.boneMarkers = [];
      sceneRef.current.selectedLabels = [];
      return;
    }

    const pszMarkers = createBoneMarkers(pszBones, 0x44ff44, selectedPszBone, scene, 'psz');
    const psoMarkers = createBoneMarkers(psoBones, 0xff4444, selectedPsoBone, scene, 'pso', disabledPsoBones);
    sceneRef.current.boneMarkers = [...pszMarkers, ...psoMarkers];

    // Add 3D labels for selected bones
    const newLabels: THREE.Sprite[] = [];
    if (selectedPszBone) {
      const bone = pszBones.find((b) => b.name === selectedPszBone);
      if (bone) newLabels.push(createSelectedLabel(bone, '#44ff44', scene));
    }
    if (selectedPsoBone) {
      const bone = psoBones.find((b) => b.name === selectedPsoBone);
      if (bone && !disabledPsoBones.has(bone.name)) newLabels.push(createSelectedLabel(bone, '#ff4444', scene));
    }
    sceneRef.current.selectedLabels = newLabels;
  }, [pszBones, psoBones, selectedPszBone, selectedPsoBone, showMarkers, disabledPsoBones]);

  // Toggle meshes visibility
  useEffect(() => {
    if (!sceneRef.current) return;
    const toggle = (model: THREE.Object3D | null) => {
      if (!model) return;
      model.traverse((child) => {
        if ((child as THREE.Mesh).isMesh) (child as THREE.Mesh).visible = showMeshes;
      });
    };
    toggle(sceneRef.current.pszModel);
    toggle(sceneRef.current.psoModel);
  }, [showMeshes]);

  useEffect(() => {
    if (!sceneRef.current) return;
    if (sceneRef.current.pszHelper) sceneRef.current.pszHelper.visible = showSkeleton;
    if (sceneRef.current.psoHelper) sceneRef.current.psoHelper.visible = showSkeleton;
  }, [showSkeleton]);

  const buildRetargetedClip = useCallback((clip: THREE.AnimationClip, boneMap: Record<string, string>): THREE.AnimationClip | null => {
    if (!sceneRef.current || Object.keys(boneMap).length === 0) return null;
    const { psoRest, pszRest: pszRestOriginal } = sceneRef.current;

    // Create a modified copy of PSZ rest data with arm bones adjusted to match
    // PSO's rest orientation. PSO has arms at sides, PSZ has arms at 45° —
    // without this correction the conjugation overshoots arm animations.
    const pszRest: RestPoseData = {
      localQuats: { ...pszRestOriginal.localQuats },
      worldQuats: { ...pszRestOriginal.worldQuats },
      parentMap: pszRestOriginal.parentMap,
    };
    const armBones: [string, string][] = [
      ['bone_028', '030_LArm01'],
      ['bone_041', '060_RArm01'],
    ];
    for (const [psoBone, pszBone] of armBones) {
      if (!(psoBone in boneMap) || boneMap[psoBone] !== pszBone) continue;
      const pszParent = pszRest.parentMap[pszBone];
      const pszParentWorld = pszParent ? getWorldRestQuat(pszParent, pszRest) : new THREE.Quaternion();
      const psoArmWorld = getWorldRestQuat(psoBone, psoRest);
      // Set PSZ arm local rest so its world orientation matches PSO's
      pszRest.localQuats[pszBone] = pszParentWorld.clone().invert().multiply(psoArmWorld);
    }

    const tracks: THREE.KeyframeTrack[] = [];
    const identity = new THREE.Quaternion();

    // Scale ratio for position tracks: PSO model was scaled to match PSZ height
    const posScale = sceneRef.current.psoModel?.scale.x || 1;

    for (const track of clip.tracks) {
      const dotIdx = track.name.indexOf('.');
      if (dotIdx < 0) continue;
      const boneName = track.name.substring(0, dotIdx);
      const prop = track.name.substring(dotIdx);

      const pszBoneName = boneMap[boneName];
      if (!pszBoneName) continue;

      if (prop === '.quaternion') {
        // Conjugation approach: re-express the local animation delta in PSZ's bone frame
        // Precompute per-bone: prefix = pszLocalRest * F * inv(psoLocalRest), suffix = inv(F)
        // Per keyframe: pszLocal = prefix * psoLocalAnim * suffix
        const psoLocalRest = psoRest.localQuats[boneName] || identity;
        const pszLocalRest = pszRest.localQuats[pszBoneName] || identity;
        const psoWorldRest = getWorldRestQuat(boneName, psoRest);
        const pszWorldRest = getWorldRestQuat(pszBoneName, pszRest);

        const F = pszWorldRest.clone().invert().multiply(psoWorldRest);
        const Finv = F.clone().invert();
        const prefix = pszLocalRest.clone().multiply(F).multiply(psoLocalRest.clone().invert());
        const suffix = Finv;

        const srcValues = track.values;
        const dstValues = new Float32Array(srcValues.length);
        const psoLocalAnim = new THREE.Quaternion();

        for (let i = 0; i < srcValues.length; i += 4) {
          psoLocalAnim.set(srcValues[i], srcValues[i + 1], srcValues[i + 2], srcValues[i + 3]);
          const pszLocalResult = prefix.clone().multiply(psoLocalAnim).multiply(suffix);
          dstValues[i] = pszLocalResult.x;
          dstValues[i + 1] = pszLocalResult.y;
          dstValues[i + 2] = pszLocalResult.z;
          dstValues[i + 3] = pszLocalResult.w;
        }

        tracks.push(new THREE.QuaternionKeyframeTrack(
          pszBoneName + '.quaternion',
          Array.from(track.times),
          Array.from(dstValues),
        ));
      } else if (prop === '.position' && boneName === 'bone_000') {
        // Only transfer root bone position (walking/falling). Other bones have
        // different rest offsets and bone lengths that would distort the mesh.
        const srcValues = track.values;
        const dstValues = new Float32Array(srcValues.length);

        for (let i = 0; i < srcValues.length; i += 3) {
          dstValues[i] = srcValues[i] * posScale;
          dstValues[i + 1] = srcValues[i + 1] * posScale;
          dstValues[i + 2] = srcValues[i + 2] * posScale;
        }

        tracks.push(new THREE.VectorKeyframeTrack(
          pszBoneName + '.position',
          Array.from(track.times),
          Array.from(dstValues),
        ));
      }
    }
    if (tracks.length === 0) return null;
    return new THREE.AnimationClip(clip.name + '_retargeted', clip.duration, tracks);
  }, []);

  useEffect(() => {
    if (!sceneRef.current?.psoMixer || !selectedAnimation) return;
    const { psoMixer, pszMixer, psoAnimations, currentAction, currentPszAction } = sceneRef.current;
    if (currentAction) { currentAction.stop(); psoMixer.uncacheAction(currentAction.getClip()); }
    if (currentPszAction && pszMixer) { currentPszAction.stop(); pszMixer.uncacheAction(currentPszAction.getClip()); }
    sceneRef.current.currentPszAction = null;
    const clip = psoAnimations.find((a) => a.name === selectedAnimation);
    if (clip) {
      const action = psoMixer.clipAction(clip);
      action.reset().play();
      action.setLoop(THREE.LoopRepeat, Infinity);
      action.timeScale = playbackSpeed;
      sceneRef.current.currentAction = action;
      if (playOnBoth && pszMixer) {
        const retargeted = buildRetargetedClip(clip, mappings);
        if (retargeted) {
          const pszAction = pszMixer.clipAction(retargeted);
          pszAction.reset().play();
          pszAction.setLoop(THREE.LoopRepeat, Infinity);
          pszAction.timeScale = playbackSpeed;
          sceneRef.current.currentPszAction = pszAction;
        }
      }
    }
  }, [selectedAnimation, playOnBoth, mappings, buildRetargetedClip]);

  useEffect(() => {
    if (sceneRef.current?.currentAction) sceneRef.current.currentAction.paused = !isPlaying;
    if (sceneRef.current?.currentPszAction) sceneRef.current.currentPszAction.paused = !isPlaying;
  }, [isPlaying]);

  useEffect(() => {
    if (sceneRef.current?.currentAction) sceneRef.current.currentAction.timeScale = playbackSpeed;
    if (sceneRef.current?.currentPszAction) sceneRef.current.currentPszAction.timeScale = playbackSpeed;
  }, [playbackSpeed]);

  const addMapping = useCallback(() => {
    if (selectedPszBone && selectedPsoBone) {
      setMappings((prev) => ({ ...prev, [selectedPsoBone]: selectedPszBone }));
    }
  }, [selectedPszBone, selectedPsoBone]);

  const removeMapping = useCallback((psoKey: string) => {
    setMappings((prev) => { const next = { ...prev }; delete next[psoKey]; return next; });
  }, []);

  const exportMappings = useCallback(() => {
    navigator.clipboard.writeText(JSON.stringify(mappings, null, 2));
  }, [mappings]);

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: '16px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: '16px', height: '100%' }}>
        {/* Left panel - Bones + Mappings */}
        <div style={{ width: '260px', background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {/* Mappings */}
          {Object.keys(mappings).length > 0 && (
            <div style={{ borderBottom: '1px solid #3a3a5a', paddingBottom: '8px' }}>
              <h3 style={{ fontSize: '12px', color: '#8888ff', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
                Mappings ({Object.keys(mappings).length})
              </h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                {Object.entries(mappings).map(([pso, psz]) => (
                  <div key={pso} style={{
                    display: 'flex', alignItems: 'center', gap: '6px',
                    padding: '3px 6px', background: '#1a1a2e', borderRadius: '3px', fontSize: '10px',
                  }}>
                    <span style={{ color: '#ff4444', fontFamily: 'monospace', flex: 1 }}>{pso}</span>
                    <span style={{ color: '#666' }}>&rarr;</span>
                    <span style={{ color: '#44ff44', fontFamily: 'monospace', flex: 1 }}>{psz}</span>
                    <button
                      onClick={() => removeMapping(pso)}
                      style={{
                        padding: '1px 5px', background: '#4a2a2a', border: '1px solid #644',
                        borderRadius: '3px', color: '#f66', cursor: 'pointer', fontSize: '9px',
                      }}
                    >
                      x
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* PSZ Bones (collapsible) */}
          <div>
            <button
              onClick={() => setPszBonesOpen((v) => !v)}
              style={{
                display: 'flex', alignItems: 'center', gap: '6px', width: '100%',
                background: 'transparent', border: 'none', cursor: 'pointer', padding: '0 0 8px 0',
              }}
            >
              <span style={{ color: '#666', fontSize: '9px' }}>{pszBonesOpen ? '\u25bc' : '\u25b6'}</span>
              <h3 style={{ fontSize: '12px', color: '#44ff44', margin: 0, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                PSZ Bones ({pszBones.length})
              </h3>
            </button>
            {pszBonesOpen && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '1px' }}>
                {pszTree.map((node) => (
                  <BoneTreeRow
                    key={node.info.name}
                    node={node}
                    selectedBone={selectedPszBone}
                    onSelect={setSelectedPszBone}
                    collapsed={pszCollapsed}
                    onToggleCollapse={toggleCollapse(setPszCollapsed)}
                    color="#aaa"
                    selectedColor="#44ff44"
                    side="psz"
                  />
                ))}
              </div>
            )}
          </div>

          {/* PSO Bones (collapsible) */}
          <div>
            <button
              onClick={() => setPsoBonesOpen((v) => !v)}
              style={{
                display: 'flex', alignItems: 'center', gap: '6px', width: '100%',
                background: 'transparent', border: 'none', cursor: 'pointer', padding: '0 0 8px 0',
              }}
            >
              <span style={{ color: '#666', fontSize: '9px' }}>{psoBonesOpen ? '\u25bc' : '\u25b6'}</span>
              <h3 style={{ fontSize: '12px', color: '#ff4444', margin: 0, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                PSO Bones ({psoBones.length - disabledPsoBones.size}/{psoBones.length})
              </h3>
            </button>
            {psoBonesOpen && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '1px' }}>
                {psoTree.map((node) => (
                  <BoneTreeRow
                    key={node.info.name}
                    node={node}
                    selectedBone={selectedPsoBone}
                    onSelect={setSelectedPsoBone}
                    collapsed={psoCollapsed}
                    onToggleCollapse={toggleCollapse(setPsoCollapsed)}
                    color="#aaa"
                    selectedColor="#ff4444"
                    mappings={mappings}
                    disabledBones={disabledPsoBones}
                    onToggleDisable={toggleDisablePsoBone}
                    side="pso"
                  />
                ))}
              </div>
            )}
          </div>

          {/* Animation order reference */}
          <div style={{ borderTop: '1px solid #3a3a5a', paddingTop: '8px' }}>
            <h3 style={{ fontSize: '12px', color: '#6b8afd', margin: '0 0 6px 0', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
              Animation Order (Saber)
            </h3>
            <div style={{ fontSize: '10px', fontFamily: 'monospace', color: '#888', display: 'flex', flexDirection: 'column', gap: '1px' }}>
              {[
                'atk1', 'atk2', 'atk3', 'wait', 'block',
                'walk', 'dam_h', 'dam_d_wa', 'dam_n', 'dam_d',
                'press', 'pb', 'run', 'walk_ready', 'tec',
              ].map((name, i) => (
                <div key={name} style={{ display: 'flex', gap: '6px', padding: '1px 4px' }}>
                  <span style={{ color: '#555', minWidth: '16px', textAlign: 'right' }}>{i + 1}.</span>
                  <span>{name}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Center - 3D Canvas + Controls */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{
            background: '#2d2d44', borderRadius: '8px', padding: '10px 16px',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}>
            <span style={{ fontSize: '14px', fontWeight: 'bold' }}>
              <span style={{ color: pszLoaded ? '#44ff44' : '#666' }}>PSZ {!pszLoaded && '(loading...)'}</span>
              {' vs '}
              <span style={{ color: psoLoaded ? '#ff4444' : psoLoadError ? '#ff6666' : '#666' }}>
                PSO {psoLoadError ? '(FAILED)' : !psoLoaded ? `(loading ${psoLoadProgress}%...)` : ''}
              </span>
              {' Skeleton Comparison'}
            </span>
            <div style={{ display: 'flex', gap: '8px' }}>
              <label style={{ fontSize: '11px', color: '#888', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={showMeshes} onChange={(e) => setShowMeshes(e.target.checked)} />
                Meshes
              </label>
              <label style={{ fontSize: '11px', color: '#888', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={showMarkers} onChange={(e) => setShowMarkers(e.target.checked)} />
                Bones
              </label>
              <label style={{ fontSize: '11px', color: '#888', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={showSkeleton} onChange={(e) => setShowSkeleton(e.target.checked)} />
                Skeleton
              </label>
              <label style={{ fontSize: '11px', color: '#c84', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={zeroedPsoRest} onChange={(e) => setZeroedPsoRest(e.target.checked)} />
                Zero PSO Rest
              </label>
              <label style={{ fontSize: '11px', color: Object.keys(mappings).length > 0 ? '#8888ff' : '#555', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={playOnBoth} onChange={(e) => setPlayOnBoth(e.target.checked)} disabled={Object.keys(mappings).length === 0} />
                Retarget
              </label>
            </div>
          </div>
          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: '8px', overflow: 'hidden', position: 'relative' }} ref={containerRef}>
            <div
              ref={tooltipRef}
              style={{
                display: 'none', position: 'absolute', pointerEvents: 'none',
                padding: '4px 8px', background: 'rgba(0,0,0,0.85)',
                border: `1px solid ${hoveredBone?.side === 'psz' ? '#44ff44' : '#ff4444'}`,
                borderRadius: '4px', fontSize: '11px', fontFamily: 'monospace',
                color: hoveredBone?.side === 'psz' ? '#44ff44' : '#ff4444',
                zIndex: 10, whiteSpace: 'nowrap',
              }}
            >
              {hoveredBone && (
                <>
                  <span style={{ color: '#888', fontSize: '9px' }}>{hoveredBone.side.toUpperCase()} </span>
                  {hoveredBone.name}
                </>
              )}
            </div>
            {psoLoadError && (
              <div style={{ position: 'absolute', bottom: 12, left: 12, right: 12, padding: '8px 12px', background: 'rgba(100,20,20,0.9)', borderRadius: '6px', fontSize: '11px', color: '#f88' }}>
                {psoLoadError}
              </div>
            )}
          </div>

          {/* Mapping controls */}
          <div style={{
            background: '#2d2d44', borderRadius: '8px', padding: '10px 16px',
            display: 'flex', alignItems: 'center', gap: '12px',
          }}>
            <span style={{ fontSize: '11px', color: '#44ff44', fontFamily: 'monospace' }}>
              {selectedPszBone || '(select PSZ)'}
            </span>
            <span style={{ fontSize: '11px', color: '#666' }}>&larr;</span>
            <span style={{ fontSize: '11px', color: '#ff4444', fontFamily: 'monospace' }}>
              {selectedPsoBone || '(select PSO)'}
            </span>
            <button
              onClick={addMapping}
              disabled={!selectedPszBone || !selectedPsoBone}
              style={{
                padding: '4px 12px', background: '#4a4a6a', border: '1px solid #6b8afd',
                borderRadius: '4px', color: '#fff', cursor: 'pointer', fontSize: '11px',
                opacity: selectedPszBone && selectedPsoBone ? 1 : 0.4,
              }}
            >
              Map
            </button>
            <button
              onClick={exportMappings}
              style={{
                padding: '4px 12px', background: '#2d5a2d', border: '1px solid #4a4',
                borderRadius: '4px', color: '#6f6', cursor: 'pointer', fontSize: '11px',
                marginLeft: 'auto',
              }}
            >
              Copy JSON ({Object.keys(mappings).length})
            </button>
          </div>
        </div>

        {/* Right panel - Animations */}
        <div style={{ width: '320px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {/* Animations + Mapping */}
          <div style={{ flex: 1, background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px' }}>
            {/* Header + progress + jump-to */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '6px' }}>
              <h3 style={{ fontSize: '12px', color: '#6b8afd', margin: 0, textTransform: 'uppercase' }}>
                Animations
              </h3>
              <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input
                  type="number"
                  min={0}
                  max={totalAnims - 1}
                  placeholder="#"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      const val = parseInt((e.target as HTMLInputElement).value);
                      const name = `plymotiondata_${String(val).padStart(3, '0')}`;
                      if (psoAnimations.includes(name)) {
                        setSelectedAnimation(name);
                        setIsPlaying(true);
                      }
                    }
                  }}
                  style={{
                    width: '48px', padding: '2px 4px', background: '#1a1a2e', border: '1px solid #444',
                    borderRadius: '3px', color: '#aaa', fontSize: '10px', fontFamily: 'monospace',
                    outline: 'none',
                  }}
                />
                <span style={{ fontSize: '10px', color: mappedCount > 0 ? '#6f6' : '#666' }}>
                  {mappedCount}/{totalAnims}
                </span>
              </div>
            </div>

            {/* Progress bar */}
            {totalAnims > 0 && (
              <div style={{ height: '4px', background: '#1a1a2e', borderRadius: '2px', overflow: 'hidden' }}>
                <div style={{
                  height: '100%', width: `${(mappedCount / totalAnims) * 100}%`,
                  background: '#4a4', borderRadius: '2px', transition: 'width 0.3s',
                }} />
              </div>
            )}

            {/* Name assignment for current animation */}
            {selectedAnimation && (
              <div style={{ background: '#1a1a2e', borderRadius: '4px', padding: '8px', display: 'flex', flexDirection: 'column', gap: '4px' }}>
                <div style={{ fontSize: '10px', color: '#888' }}>
                  Assign name to <span style={{ color: '#6b8afd' }}>{selectedAnimation}</span>:
                </div>
                <div style={{ display: 'flex', gap: '4px' }}>
                  <input
                    type="text"
                    value={nameInput}
                    onChange={(e) => setNameInput(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') assignAnimationName(); }}
                    placeholder="e.g. pmsa_atk1"
                    style={{
                      flex: 1, padding: '4px 8px', background: '#2d2d44', border: '1px solid #444',
                      borderRadius: '3px', color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                      outline: 'none',
                    }}
                  />
                  <button
                    onClick={assignAnimationName}
                    style={{
                      padding: '4px 10px', background: nameInput.trim() ? '#2d5a2d' : '#4a2a2a',
                      border: `1px solid ${nameInput.trim() ? '#4a4' : '#644'}`,
                      borderRadius: '3px', color: nameInput.trim() ? '#6f6' : '#f66',
                      cursor: 'pointer', fontSize: '10px',
                    }}
                  >
                    {nameInput.trim() ? 'Set' : 'Clear'}
                  </button>
                </div>
              </div>
            )}

            {/* Controls row */}
            <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
              <button
                onClick={() => navigateAnimation(-1)}
                title="Previous animation"
                style={{
                  padding: '4px 6px', background: '#1a1a2e', border: '1px solid #444',
                  borderRadius: '4px', color: '#aaa', cursor: 'pointer', fontSize: '11px',
                }}
              >
                &#9664;
              </button>
              <button
                onClick={() => setIsPlaying(!isPlaying)}
                style={{
                  padding: '4px 8px',
                  background: isPlaying ? '#2d5a2d' : '#1a1a2e',
                  border: isPlaying ? '1px solid #4a4' : '1px solid #444',
                  borderRadius: '4px', color: isPlaying ? '#6f6' : '#aaa',
                  cursor: 'pointer', fontSize: '11px',
                }}
              >
                {isPlaying ? 'Pause' : 'Play'}
              </button>
              <button
                onClick={() => navigateAnimation(1)}
                title="Next animation"
                style={{
                  padding: '4px 6px', background: '#1a1a2e', border: '1px solid #444',
                  borderRadius: '4px', color: '#aaa', cursor: 'pointer', fontSize: '11px',
                }}
              >
                &#9654;
              </button>
              <div style={{ flex: 1 }} />
              {/* Filter buttons */}
              {(['all', 'mapped', 'unmapped'] as const).map((f) => (
                <button
                  key={f}
                  onClick={() => setAnimFilter(f)}
                  style={{
                    padding: '3px 6px', fontSize: '9px',
                    background: animFilter === f ? '#4a4a6a' : 'transparent',
                    border: animFilter === f ? '1px solid #6b8afd' : '1px solid #444',
                    borderRadius: '3px',
                    color: animFilter === f ? '#fff' : '#888',
                    cursor: 'pointer', textTransform: 'capitalize',
                  }}
                >
                  {f}
                </button>
              ))}
            </div>

            {/* Speed slider */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <label style={{ fontSize: '10px', color: '#888', whiteSpace: 'nowrap' }}>Speed: {playbackSpeed.toFixed(1)}x</label>
              <input type="range" min="0.1" max="2" step="0.1" value={playbackSpeed}
                onChange={(e) => setPlaybackSpeed(parseFloat(e.target.value))}
                style={{ flex: 1 }} />
            </div>

            {/* Animation list */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', flex: 1, overflowY: 'auto' }}>
              {filteredAnimations.map((name) => {
                const idx = name.replace('plymotiondata_', '');
                const mappedName = animationNameMap[idx];
                return (
                  <button
                    key={name}
                    onClick={() => { setSelectedAnimation(name); setIsPlaying(true); }}
                    style={{
                      padding: '3px 6px',
                      display: 'flex', alignItems: 'center', gap: '4px',
                      background: selectedAnimation === name ? '#4a4a6a' : 'transparent',
                      border: selectedAnimation === name ? '1px solid #6b8afd' : '1px solid transparent',
                      borderRadius: '3px',
                      color: selectedAnimation === name ? '#fff' : mappedName ? '#8c8' : '#aaa',
                      cursor: 'pointer', fontSize: '10px', textAlign: 'left', fontFamily: 'monospace',
                    }}
                  >
                    <span style={{
                      fontSize: '9px', color: '#666', background: mappedName ? '#1a3a1a' : '#1a1a2e',
                      padding: '1px 4px', borderRadius: '2px', minWidth: '24px', textAlign: 'center',
                    }}>
                      {idx}
                    </span>
                    <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {mappedName || name}
                    </span>
                    {mappedName && (
                      <span style={{ color: '#4a4', fontSize: '9px', flexShrink: 0 }}>&#10003;</span>
                    )}
                  </button>
                );
              })}
            </div>

            {/* Export buttons */}
            <div style={{ display: 'flex', gap: '4px' }}>
              <button
                onClick={exportAnimationMap}
                style={{
                  flex: 1, padding: '4px 8px', background: '#2d5a2d', border: '1px solid #4a4',
                  borderRadius: '4px', color: '#6f6', cursor: 'pointer', fontSize: '10px',
                }}
              >
                Copy JSON
              </button>
              <button
                onClick={downloadAnimationMap}
                style={{
                  flex: 1, padding: '4px 8px', background: '#2d2d5a', border: '1px solid #44a',
                  borderRadius: '4px', color: '#88f', cursor: 'pointer', fontSize: '10px',
                }}
              >
                Download
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
