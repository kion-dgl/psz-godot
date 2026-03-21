import { Canvas } from '@react-three/fiber';
import { OrbitControls, useGLTF, Grid } from '@react-three/drei';
import { Suspense, useEffect, useRef, forwardRef, useImperativeHandle, Component, type ReactNode } from 'react';
import * as THREE from 'three';
import { getGlbPath, getAreaFromMapId, getSkyboxPath } from './constants';

/** Silent error boundary — renders nothing if children fail to load */
class SilentBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() { return this.state.failed ? null : this.props.children; }
}

interface StageModelProps {
  mapId: string;
  onSceneReady?: (scene: THREE.Group) => void;
}

function StageModel({ mapId, onSceneReady }: StageModelProps) {
  const areaKey = getAreaFromMapId(mapId) || 'valley';
  const glbPath = getGlbPath(areaKey, mapId);
  const { scene } = useGLTF(glbPath);

  useEffect(() => {
    if (scene && onSceneReady) {
      onSceneReady(scene as THREE.Group);
    }
  }, [scene, onSceneReady]);

  return <primitive object={scene} />;
}

function SkyboxModel({ mapId }: { mapId: string }) {
  const areaKey = getAreaFromMapId(mapId) || 'valley';
  const skyboxPath = getSkyboxPath(areaKey, mapId);
  if (!skyboxPath) return null;
  return <SkyboxGlb path={skyboxPath} />;
}

function SkyboxGlb({ path }: { path: string }) {
  const { scene } = useGLTF(path);
  return <primitive object={scene} />;
}

interface StageCanvasProps {
  mapId: string;
  children?: React.ReactNode;
  onSceneReady?: (scene: THREE.Group) => void;
  showGrid?: boolean;
  showStage?: boolean;
  gridSize?: number;
  cameraPosition?: [number, number, number];
  orthographic?: boolean;
}

export interface StageCanvasRef {
  getScene: () => THREE.Scene | null;
}

const StageCanvas = forwardRef<StageCanvasRef, StageCanvasProps>(function StageCanvas(
  {
    mapId,
    children,
    onSceneReady,
    showGrid = true,
    showStage = true,
    gridSize = 100,
    cameraPosition = [0, 50, 50],
    orthographic = false,
  },
  ref
) {
  const sceneRef = useRef<THREE.Scene | null>(null);

  useImperativeHandle(ref, () => ({
    getScene: () => sceneRef.current,
  }));

  return (
    <Canvas
      camera={
        orthographic
          ? undefined
          : { position: cameraPosition, fov: 50 }
      }
      onCreated={({ scene }) => {
        sceneRef.current = scene;
      }}
    >
      <color attach="background" args={['#1a1a2e']} />
      <ambientLight intensity={0.6} />
      <directionalLight position={[10, 20, 10]} intensity={0.8} />

      <Suspense fallback={null}>
        <group visible={showStage}>
          <StageModel mapId={mapId} onSceneReady={onSceneReady} />
          <SilentBoundary>
            <SkyboxModel mapId={mapId} />
          </SilentBoundary>
        </group>
      </Suspense>

      {showGrid && (
        <Grid
          args={[gridSize, gridSize]}
          position={[0, 0.01, 0]}
          cellSize={1}
          cellThickness={0.5}
          cellColor="#444"
          sectionSize={10}
          sectionThickness={1}
          sectionColor="#666"
          fadeDistance={gridSize}
          fadeStrength={1}
        />
      )}

      {children}

      <OrbitControls makeDefault />
    </Canvas>
  );
});

export default StageCanvas;

// Loading placeholder component
export function LoadingPlaceholder() {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: '100%',
        height: '100%',
        background: '#1a1a2e',
        color: '#666',
      }}
    >
      Loading...
    </div>
  );
}
