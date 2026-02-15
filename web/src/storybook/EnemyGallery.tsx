import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, useGLTF, Environment } from '@react-three/drei';
import { Suspense, useState, useEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import {
  ENEMY_CATEGORIES,
  ALL_ENEMY_IDS,
  getEnemyCategory,
  getEnemyGlbPath,
  getEnemyDisplayName,
  getEnemyElement,
  getBaseEnemyId,
  isEnemyBoss,
  isEnemyRare,
  type EnemyCategory,
  type EnemyElement,
} from './enemyData';

function EnemyModel({
  enemyId,
  animationSourcePath,
  selectedAnimation,
  isPlaying,
  onAnimationsLoaded,
}: {
  enemyId: string;
  animationSourcePath: string | null;
  selectedAnimation: string | null;
  isPlaying: boolean;
  onAnimationsLoaded?: (animationNames: string[]) => void;
}) {
  const glbPath = getEnemyGlbPath(enemyId);
  const { scene, animations: modelAnimations } = useGLTF(glbPath);
  const animSourceGltf = useGLTF(animationSourcePath || glbPath);
  const animations = animationSourcePath ? animSourceGltf.animations : modelAnimations;

  const mixerRef = useRef<THREE.AnimationMixer | null>(null);
  const actionRef = useRef<THREE.AnimationAction | null>(null);

  const clonedScene = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((obj) => {
      if (obj instanceof THREE.Mesh && obj.geometry) {
        obj.geometry.computeVertexNormals();
      }
    });
    const box = new THREE.Box3().setFromObject(clone);
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    clone.position.x = -center.x;
    clone.position.z = -center.z;
    const maxDim = Math.max(size.x, size.y, size.z);
    if (maxDim > 3) {
      clone.scale.setScalar(3 / maxDim);
    }
    const scaledBox = new THREE.Box3().setFromObject(clone);
    clone.position.y = -scaledBox.min.y;
    clone.traverse((obj) => {
      if (obj instanceof THREE.Mesh && obj.material instanceof THREE.Material) {
        obj.material = obj.material.clone();
        obj.material.side = THREE.FrontSide;
      }
    });
    return clone;
  }, [scene]);

  useEffect(() => {
    mixerRef.current = new THREE.AnimationMixer(clonedScene);
    return () => {
      mixerRef.current?.stopAllAction();
      mixerRef.current = null;
    };
  }, [clonedScene]);

  useEffect(() => {
    if (!mixerRef.current) return;
    if (actionRef.current) {
      actionRef.current.stop();
      actionRef.current = null;
    }
    if (selectedAnimation && isPlaying) {
      const clip = animations.find((c) => c.name === selectedAnimation);
      if (clip) {
        const action = mixerRef.current.clipAction(clip);
        action.reset().setLoop(THREE.LoopRepeat, Infinity).play();
        actionRef.current = action;
      }
    }
  }, [selectedAnimation, isPlaying, animations]);

  useFrame((_, delta) => {
    if (mixerRef.current && isPlaying) {
      mixerRef.current.update(delta);
    }
  });

  useEffect(() => {
    const names = animations.map((a) => a.name);
    onAnimationsLoaded?.(names);
  }, [animations, enemyId, onAnimationsLoaded]);

  return <primitive object={clonedScene} />;
}

function LoadingSpinner() {
  return (
    <mesh>
      <boxGeometry args={[0.5, 0.5, 0.5]} />
      <meshBasicMaterial color="#4a9eff" wireframe />
    </mesh>
  );
}

const ELEMENT_COLORS: Record<EnemyElement, string> = {
  Native: '#4ade80', Beast: '#f97316', Machine: '#60a5fa', Dark: '#a855f7',
};

function CategoryItem({ category, count, selected, onClick }: {
  category: EnemyCategory; count: number; selected: boolean; onClick: () => void;
}) {
  return (
    <button onClick={onClick} style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '6px 8px', background: selected ? '#4a9eff' : 'transparent',
      color: selected ? 'white' : '#ccc', border: 'none', borderRadius: '4px',
      cursor: 'pointer', fontSize: '11px', textAlign: 'left', width: '100%',
    }}>
      <span>{category.label}</span>
      <span style={{ opacity: 0.6, fontSize: '10px' }}>{count}</span>
    </button>
  );
}

function EnemyItem({ enemyId, selected, onClick }: {
  enemyId: string; selected: boolean; onClick: () => void;
}) {
  const isBoss = isEnemyBoss(enemyId);
  const isRare = isEnemyRare(enemyId);
  const element = getEnemyElement(enemyId);
  let color = '#ccc';
  if (isBoss) color = '#ff4444';
  else if (isRare) color = '#ffcc00';
  else if (element) color = ELEMENT_COLORS[element];

  return (
    <button onClick={onClick} style={{
      display: 'block', width: '100%', padding: '6px 8px',
      background: selected ? '#2a3a5e' : 'transparent',
      border: selected ? '1px solid #4a9eff' : '1px solid transparent',
      borderRadius: '4px', cursor: 'pointer', textAlign: 'left', fontSize: '10px', color,
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontWeight: 'bold' }}>{isBoss && '* '}{getEnemyDisplayName(enemyId)}</span>
        {isRare && <span style={{ fontSize: '8px', color: '#ffcc00' }}>RARE</span>}
      </div>
    </button>
  );
}

export default function EnemyGallery() {
  const [selectedCategory, setSelectedCategory] = useState<string>('gurhacia');
  const [selectedEnemy, setSelectedEnemy] = useState<string | null>(null);
  const [glbAnimationNames, setGlbAnimationNames] = useState<string[]>([]);
  const [selectedAnimation, setSelectedAnimation] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);

  const enemiesByCategory = useMemo(() => {
    const grouped: Record<string, string[]> = {};
    for (const cat of ENEMY_CATEGORIES) grouped[cat.id] = [];
    for (const id of ALL_ENEMY_IDS) {
      const cat = getEnemyCategory(id);
      if (cat) grouped[cat.id].push(id);
    }
    return grouped;
  }, []);

  const displayedEnemies = enemiesByCategory[selectedCategory] || [];

  const animationSourcePath = useMemo(() => {
    if (!selectedEnemy) return null;
    const baseId = getBaseEnemyId(selectedEnemy);
    if (!baseId) return null;
    return getEnemyGlbPath(baseId);
  }, [selectedEnemy]);

  useEffect(() => {
    setGlbAnimationNames([]);
    setSelectedAnimation(null);
    setIsPlaying(false);
  }, [selectedEnemy]);

  return (
    <div style={{
      width: '100%', height: '100%', background: '#0a0a12', color: 'white',
      display: 'flex', overflow: 'hidden',
    }}>
      {/* Categories */}
      <div style={{
        width: '160px', flexShrink: 0, borderRight: '1px solid #333',
        padding: '8px', overflowY: 'auto', display: 'flex', flexDirection: 'column',
      }}>
        <h3 style={{ margin: '0 0 8px 0', fontSize: '12px', color: '#4a9eff' }}>Areas</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1px' }}>
          {ENEMY_CATEGORIES.map((cat) => (
            <CategoryItem key={cat.id} category={cat}
              count={enemiesByCategory[cat.id]?.length || 0}
              selected={selectedCategory === cat.id}
              onClick={() => setSelectedCategory(cat.id)} />
          ))}
        </div>
      </div>

      {/* Enemy List */}
      <div style={{
        width: '180px', flexShrink: 0, borderRight: '1px solid #333',
        padding: '8px', overflowY: 'auto',
      }}>
        <h3 style={{ margin: '0 0 8px 0', fontSize: '12px' }}>
          Enemies <span style={{ color: '#666', fontWeight: 'normal' }}>({displayedEnemies.length})</span>
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
          {displayedEnemies.map((id) => (
            <EnemyItem key={id} enemyId={id}
              selected={selectedEnemy === id}
              onClick={() => setSelectedEnemy(id)} />
          ))}
        </div>
      </div>

      {/* 3D Preview */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {selectedEnemy && (
          <div style={{ padding: '8px 12px', background: '#111', borderBottom: '1px solid #333' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '4px' }}>
              <span style={{ fontWeight: 'bold', fontSize: '14px' }}>
                {getEnemyDisplayName(selectedEnemy)}
              </span>
              {isEnemyRare(selectedEnemy) && (
                <span style={{ padding: '2px 6px', background: '#ffcc00', borderRadius: '4px', fontSize: '10px', color: 'black' }}>RARE</span>
              )}
              {getEnemyElement(selectedEnemy) && (
                <span style={{ padding: '2px 6px', background: ELEMENT_COLORS[getEnemyElement(selectedEnemy)!], borderRadius: '4px', fontSize: '10px', color: 'white' }}>
                  {getEnemyElement(selectedEnemy)}
                </span>
              )}
            </div>
            <div style={{ fontSize: '10px', color: '#666' }}>
              Model: {selectedEnemy} | Animations: {glbAnimationNames.length}
            </div>
          </div>
        )}

        <div style={{ flex: 1, background: '#0a0a12' }}>
          {selectedEnemy ? (
            <Canvas camera={{ position: [3, 2, 3], fov: 45 }}>
              <ambientLight intensity={0.5} />
              <directionalLight position={[5, 5, 5]} intensity={1} />
              <directionalLight position={[-5, -5, -5]} intensity={0.3} />
              <Suspense fallback={<LoadingSpinner />}>
                <EnemyModel key={selectedEnemy} enemyId={selectedEnemy}
                  animationSourcePath={animationSourcePath}
                  selectedAnimation={selectedAnimation}
                  isPlaying={isPlaying}
                  onAnimationsLoaded={setGlbAnimationNames} />
              </Suspense>
              <OrbitControls makeDefault />
              <Environment preset="studio" />
              <gridHelper args={[10, 10, '#333', '#222']} />
            </Canvas>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#666' }}>
              Select an enemy to preview
            </div>
          )}
        </div>
      </div>

      {/* Animations Panel */}
      {selectedEnemy && (
        <div style={{
          width: '200px', flexShrink: 0, borderLeft: '1px solid #333',
          padding: '8px', overflowY: 'auto',
        }}>
          <h3 style={{ margin: '0 0 8px 0', fontSize: '12px', color: '#4a9eff' }}>
            Animations <span style={{ color: '#666', fontWeight: 'normal' }}>({glbAnimationNames.length})</span>
          </h3>
          {glbAnimationNames.length > 0 ? (
            <>
              <div style={{ display: 'flex', gap: '4px', marginBottom: '8px' }}>
                <button onClick={() => setIsPlaying(!isPlaying)}
                  disabled={!selectedAnimation}
                  style={{
                    padding: '4px 8px', background: isPlaying ? '#ff4444' : '#4a9eff',
                    color: 'white', border: 'none', borderRadius: '4px',
                    cursor: selectedAnimation ? 'pointer' : 'not-allowed',
                    fontSize: '10px', opacity: selectedAnimation ? 1 : 0.5,
                  }}>
                  {isPlaying ? 'Stop' : 'Play'}
                </button>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                {glbAnimationNames.map((name) => (
                  <button key={name}
                    onClick={() => { setSelectedAnimation(name); setIsPlaying(true); }}
                    style={{
                      display: 'block', width: '100%', padding: '4px 8px',
                      background: selectedAnimation === name ? '#2a3a5e' : 'transparent',
                      border: selectedAnimation === name ? '1px solid #4a9eff' : '1px solid transparent',
                      borderRadius: '4px', cursor: 'pointer', textAlign: 'left',
                      fontSize: '10px', color: selectedAnimation === name ? '#4a9eff' : '#ccc',
                    }}>
                    {name}
                  </button>
                ))}
              </div>
            </>
          ) : (
            <div style={{ color: '#666', fontSize: '10px' }}>No animations in GLB</div>
          )}
        </div>
      )}
    </div>
  );
}
