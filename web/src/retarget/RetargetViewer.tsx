import { useState, useEffect, useRef, useCallback } from 'react';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { assetUrl } from '../utils/assets';

// PSZ model — using humar (pc_000) as reference
const PSZ_MODEL_PATH = assetUrl('/player/pc_000/pc_000/pc_000_000.glb');
const PSZ_TEXTURE_PATH = assetUrl('/player/pc_000/textures/pc_000_000.png');

// PSO model — Humar with all animations
const PSO_MODEL_PATH = assetUrl('/data/retarget/Humar_body.glb');

interface BoneInfo {
  name: string;
  depth: number;
  worldPos: THREE.Vector3;
  bone: THREE.Bone;
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

function createBoneLabels(
  bones: BoneInfo[],
  color: string,
  scene: THREE.Scene,
  selectedBone: string | null,
): THREE.Sprite[] {
  const sprites: THREE.Sprite[] = [];
  for (const bone of bones) {
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 64;
    const ctx = canvas.getContext('2d')!;
    const isSelected = bone.name === selectedBone;
    ctx.font = isSelected ? 'bold 18px monospace' : '14px monospace';
    ctx.fillStyle = isSelected ? '#ffff00' : color;
    ctx.fillText(bone.name, 4, 20);

    const texture = new THREE.CanvasTexture(canvas);
    const material = new THREE.SpriteMaterial({ map: texture, depthTest: false });
    const sprite = new THREE.Sprite(material);
    sprite.scale.set(1.2, 0.3, 1);
    sprite.position.copy(bone.worldPos);
    sprite.position.y += 0.08;
    sprite.renderOrder = 999;
    scene.add(sprite);
    sprites.push(sprite);
  }
  return sprites;
}

function matchPsoScaleToPsz(pszModel: THREE.Object3D, psoModel: THREE.Object3D): void {
  const pszBox = new THREE.Box3().setFromObject(pszModel);
  const psoBox = new THREE.Box3().setFromObject(psoModel);
  const pszHeight = pszBox.max.y - pszBox.min.y;
  const psoHeight = psoBox.max.y - psoBox.min.y;
  if (psoHeight > 0 && pszHeight > 0) {
    const scale = pszHeight / psoHeight;
    psoModel.scale.multiplyScalar(scale);
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
  labelSprites: THREE.Sprite[];
}

export default function RetargetViewer() {
  const containerRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<SceneState | null>(null);

  const [pszBones, setPszBones] = useState<BoneInfo[]>([]);
  const [psoBones, setPsoBones] = useState<BoneInfo[]>([]);
  const [selectedPszBone, setSelectedPszBone] = useState<string | null>(null);
  const [selectedPsoBone, setSelectedPsoBone] = useState<string | null>(null);
  const [psoAnimations, setPsoAnimations] = useState<string[]>([]);
  const [selectedAnimation, setSelectedAnimation] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showMeshes, setShowMeshes] = useState(true);
  const [showLabels, setShowLabels] = useState(true);
  const [mappings, setMappings] = useState<Record<string, string>>({});
  const [pszLoaded, setPszLoaded] = useState(false);
  const [psoLoaded, setPsoLoaded] = useState(false);
  const [psoLoadError, setPsoLoadError] = useState<string | null>(null);
  const [psoLoadProgress, setPsoLoadProgress] = useState(0);
  const [playOnBoth, setPlayOnBoth] = useState(false);

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
      currentAction: null, currentPszAction: null, labelSprites: [],
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

    const handleResize = () => {
      const w = container.clientWidth;
      const h = container.clientHeight;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h);
    };
    window.addEventListener('resize', handleResize);

    // Load both models
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
            const mat = new THREE.MeshBasicMaterial({ map: texture });
            (child as THREE.Mesh).material = mat;
          }
        });
      });

      const helper = createSkeletonHelper(model, 0x44ff44);
      if (helper) {
        scene.add(helper);
        sceneRef.current!.pszHelper = helper;
      }
      const pszMixer = new THREE.AnimationMixer(model);
      sceneRef.current!.pszMixer = pszMixer;

      // Need to update world matrices before collecting bone positions
      model.updateMatrixWorld(true);
      setPszBones(collectBones(model));
      setPszLoaded(true);

      // If PSO already loaded, scale it to match
      if (sceneRef.current!.psoModel) {
        matchPsoScaleToPsz(model, sceneRef.current!.psoModel);
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

        const helper = createSkeletonHelper(model, 0xff4444);
        if (helper) {
          scene.add(helper);
          sceneRef.current!.psoHelper = helper;
        }

        const mixer = new THREE.AnimationMixer(model);
        sceneRef.current!.psoMixer = mixer;
        sceneRef.current!.psoAnimations = gltf.animations;
        const animNames = gltf.animations.map((a) => a.name);
        setPsoAnimations(animNames);

        // Scale PSO to match PSZ height
        if (sceneRef.current!.pszModel) {
          matchPsoScaleToPsz(sceneRef.current!.pszModel, model);
        }

        model.updateMatrixWorld(true);
        setPsoBones(collectBones(model));
        setPsoLoaded(true);
      },
      (progress) => {
        if (progress.total > 0) {
          setPsoLoadProgress(Math.round((progress.loaded / progress.total) * 100));
        }
      },
      (error) => {
        console.error('Failed to load PSO model:', error);
        setPsoLoadError(`Failed to load PSO model: ${error}`);
      },
    );

    return () => {
      window.removeEventListener('resize', handleResize);
      renderer.dispose();
      if (container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
    };
  }, []);

  // Update labels when selection changes
  useEffect(() => {
    if (!sceneRef.current || !showLabels) return;
    const { scene, labelSprites } = sceneRef.current;

    // Remove old labels
    for (const sprite of labelSprites) scene.remove(sprite);
    sceneRef.current.labelSprites = [];

    // Add new labels
    const pszLabels = createBoneLabels(pszBones, '#44ff44', scene, selectedPszBone);
    const psoLabels = createBoneLabels(psoBones, '#ff4444', scene, selectedPsoBone);
    sceneRef.current.labelSprites = [...pszLabels, ...psoLabels];
  }, [pszBones, psoBones, selectedPszBone, selectedPsoBone, showLabels]);

  // Toggle labels visibility
  useEffect(() => {
    if (!sceneRef.current) return;
    const { scene, labelSprites } = sceneRef.current;
    if (!showLabels) {
      for (const sprite of labelSprites) scene.remove(sprite);
      sceneRef.current.labelSprites = [];
    }
  }, [showLabels]);

  // Toggle meshes visibility
  useEffect(() => {
    if (!sceneRef.current) return;
    const { pszModel, psoModel } = sceneRef.current;
    const toggleMeshes = (model: THREE.Object3D | null) => {
      if (!model) return;
      model.traverse((child) => {
        if ((child as THREE.Mesh).isMesh) {
          (child as THREE.Mesh).visible = showMeshes;
        }
      });
    };
    toggleMeshes(pszModel);
    toggleMeshes(psoModel);
  }, [showMeshes]);

  // Build a retargeted clip that maps PSO bone tracks → PSZ bone names
  const buildRetargetedClip = useCallback((clip: THREE.AnimationClip, boneMap: Record<string, string>): THREE.AnimationClip | null => {
    if (Object.keys(boneMap).length === 0) return null;
    const tracks: THREE.KeyframeTrack[] = [];
    for (const track of clip.tracks) {
      // Track names are like "bone_000.quaternion" or "bone_000.position"
      const dotIdx = track.name.indexOf('.');
      if (dotIdx < 0) continue;
      const boneName = track.name.substring(0, dotIdx);
      const prop = track.name.substring(dotIdx);
      const pszBoneName = boneMap[boneName];
      if (pszBoneName) {
        const newTrack = track.clone();
        newTrack.name = pszBoneName + prop;
        tracks.push(newTrack);
      }
    }
    if (tracks.length === 0) return null;
    return new THREE.AnimationClip(clip.name + '_retargeted', clip.duration, tracks);
  }, []);

  // Play animation on PSO model (and optionally retarget to PSZ)
  useEffect(() => {
    if (!sceneRef.current?.psoMixer || !selectedAnimation) return;
    const { psoMixer, pszMixer, psoAnimations, currentAction, currentPszAction } = sceneRef.current;
    if (currentAction) currentAction.fadeOut(0.2);
    if (currentPszAction) currentPszAction.fadeOut(0.2);

    const clip = psoAnimations.find((a) => a.name === selectedAnimation);
    if (clip) {
      const action = psoMixer.clipAction(clip);
      action.reset().fadeIn(0.2).play();
      action.setLoop(THREE.LoopRepeat, Infinity);
      action.paused = !isPlaying;
      sceneRef.current.currentAction = action;

      // Retarget to PSZ if enabled and mappings exist
      if (playOnBoth && pszMixer) {
        const retargeted = buildRetargetedClip(clip, mappings);
        if (retargeted) {
          const pszAction = pszMixer.clipAction(retargeted);
          pszAction.reset().fadeIn(0.2).play();
          pszAction.setLoop(THREE.LoopRepeat, Infinity);
          pszAction.paused = !isPlaying;
          sceneRef.current.currentPszAction = pszAction;
        }
      }
    }
  }, [selectedAnimation, playOnBoth, mappings, buildRetargetedClip]);

  useEffect(() => {
    if (sceneRef.current?.currentAction) sceneRef.current.currentAction.paused = !isPlaying;
    if (sceneRef.current?.currentPszAction) sceneRef.current.currentPszAction.paused = !isPlaying;
  }, [isPlaying]);

  const addMapping = useCallback(() => {
    if (selectedPszBone && selectedPsoBone) {
      setMappings((prev) => ({ ...prev, [selectedPsoBone]: selectedPszBone }));
    }
  }, [selectedPszBone, selectedPsoBone]);

  const removeMapping = useCallback((psoKey: string) => {
    setMappings((prev) => {
      const next = { ...prev };
      delete next[psoKey];
      return next;
    });
  }, []);

  const exportMappings = useCallback(() => {
    const json = JSON.stringify(mappings, null, 2);
    navigator.clipboard.writeText(json);
  }, [mappings]);

  return (
    <div style={{ background: '#1a1a2e', height: '100%', color: '#fff', padding: '16px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', gap: '16px', height: '100%' }}>
        {/* Left panel - PSZ bones */}
        <div style={{ width: '220px', background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto' }}>
          <h3 style={{ fontSize: '12px', color: '#44ff44', margin: '0 0 10px 0', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
            PSZ Bones ({pszBones.length})
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
            {pszBones.map((bone) => (
              <button
                key={bone.name}
                onClick={() => setSelectedPszBone(bone.name)}
                style={{
                  padding: '4px 8px',
                  paddingLeft: `${8 + bone.depth * 12}px`,
                  background: selectedPszBone === bone.name ? '#2a4a2a' : 'transparent',
                  border: selectedPszBone === bone.name ? '1px solid #44ff44' : '1px solid transparent',
                  borderRadius: '3px',
                  color: selectedPszBone === bone.name ? '#44ff44' : '#aaa',
                  cursor: 'pointer',
                  fontSize: '11px',
                  textAlign: 'left',
                  fontFamily: 'monospace',
                }}
              >
                {bone.name}
              </button>
            ))}
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
                <input type="checkbox" checked={showLabels} onChange={(e) => setShowLabels(e.target.checked)} />
                Labels
              </label>
              <label style={{ fontSize: '11px', color: Object.keys(mappings).length > 0 ? '#8888ff' : '#555', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <input type="checkbox" checked={playOnBoth} onChange={(e) => setPlayOnBoth(e.target.checked)} disabled={Object.keys(mappings).length === 0} />
                Retarget
              </label>
            </div>
          </div>
          <div style={{ flex: 1, background: '#0a0a1a', borderRadius: '8px', overflow: 'hidden', position: 'relative' }} ref={containerRef}>
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

        {/* Right panel - PSO bones + animations + mappings */}
        <div style={{ width: '280px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {/* PSO Bones */}
          <div style={{ flex: 1, background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto' }}>
            <h3 style={{ fontSize: '12px', color: '#ff4444', margin: '0 0 10px 0', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
              PSO Bones ({psoBones.length})
            </h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
              {psoBones.map((bone) => {
                const isMapped = bone.name in mappings;
                return (
                  <button
                    key={bone.name}
                    onClick={() => setSelectedPsoBone(bone.name)}
                    style={{
                      padding: '4px 8px',
                      paddingLeft: `${8 + bone.depth * 12}px`,
                      background: selectedPsoBone === bone.name ? '#4a2a2a' : isMapped ? '#2a2a3a' : 'transparent',
                      border: selectedPsoBone === bone.name ? '1px solid #ff4444' : '1px solid transparent',
                      borderRadius: '3px',
                      color: selectedPsoBone === bone.name ? '#ff4444' : isMapped ? '#8888ff' : '#aaa',
                      cursor: 'pointer',
                      fontSize: '11px',
                      textAlign: 'left',
                      fontFamily: 'monospace',
                    }}
                  >
                    {bone.name}
                    {isMapped && (
                      <span style={{ color: '#44ff44', fontSize: '9px', marginLeft: '6px' }}>
                        &rarr; {mappings[bone.name]}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Animations */}
          <div style={{ maxHeight: '200px', background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto' }}>
            <h3 style={{ fontSize: '12px', color: '#6b8afd', margin: '0 0 8px 0', textTransform: 'uppercase' }}>
              PSO Animations ({psoAnimations.length})
            </h3>
            <button
              onClick={() => setIsPlaying(!isPlaying)}
              style={{
                padding: '4px 8px', width: '100%', marginBottom: '8px',
                background: isPlaying ? '#2d5a2d' : '#1a1a2e',
                border: isPlaying ? '1px solid #4a4' : '1px solid #444',
                borderRadius: '4px', color: isPlaying ? '#6f6' : '#aaa',
                cursor: 'pointer', fontSize: '11px',
              }}
            >
              {isPlaying ? 'Pause' : 'Play'}
            </button>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
              {psoAnimations.map((name) => (
                <button
                  key={name}
                  onClick={() => { setSelectedAnimation(name); setIsPlaying(true); }}
                  style={{
                    padding: '3px 6px',
                    background: selectedAnimation === name ? '#4a4a6a' : 'transparent',
                    border: selectedAnimation === name ? '1px solid #6b8afd' : '1px solid transparent',
                    borderRadius: '3px',
                    color: selectedAnimation === name ? '#fff' : '#aaa',
                    cursor: 'pointer',
                    fontSize: '10px',
                    textAlign: 'left',
                    fontFamily: 'monospace',
                  }}
                >
                  {name}
                </button>
              ))}
            </div>
          </div>

          {/* Mappings list */}
          {Object.keys(mappings).length > 0 && (
            <div style={{ maxHeight: '200px', background: '#2d2d44', borderRadius: '8px', padding: '12px', overflowY: 'auto' }}>
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
        </div>
      </div>
    </div>
  );
}
