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

/** Convert MeshBasicMaterial → MeshLambertMaterial so scene lights affect geometry.
 *  Also computes vertex normals if missing — without normals, point/directional lights
 *  have no effect (only ambient light works). */
function convertToLit(root: THREE.Object3D) {
  root.traverse((obj) => {
    if (!(obj as THREE.Mesh).isMesh) return;
    const mesh = obj as THREE.Mesh;

    // Ensure geometry has normals
    if (mesh.geometry && !mesh.geometry.getAttribute('normal')) {
      mesh.geometry.computeVertexNormals();
    }

    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const converted = materials.map((mat) => {
      if (mat instanceof THREE.MeshBasicMaterial) {
        const lambert = new THREE.MeshLambertMaterial({
          color: mat.color,
          map: mat.map,
          transparent: mat.transparent,
          opacity: mat.opacity,
          side: mat.side,
          alphaTest: mat.alphaTest,
          vertexColors: mat.vertexColors,
        });
        if (lambert.map) {
          lambert.map.colorSpace = THREE.SRGBColorSpace;
          lambert.map.needsUpdate = true;
        }
        return lambert;
      }
      return mat;
    });
    mesh.material = Array.isArray(mesh.material) ? converted : converted[0];
  });
}

function StageModel({ mapId, onSceneReady }: StageModelProps) {
  const areaKey = getAreaFromMapId(mapId) || 'valley';
  const glbPath = getGlbPath(areaKey, mapId);
  const { scene } = useGLTF(glbPath);
  const convertedRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!scene) return;
    // Convert once per GLB (useGLTF caches the scene)
    if (!convertedRef.current.has(glbPath)) {
      convertToLit(scene);
      convertedRef.current.add(glbPath);
    }
    if (onSceneReady) {
      onSceneReady(scene as THREE.Group);
    }
  }, [scene, glbPath, onSceneReady]);

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

export interface TimeOfDayLighting {
  ambientColor: [number, number, number];
  ambientIntensity: number;
  sunColor: [number, number, number];
  sunIntensity: number;
  sunPitch: number;
  moonIntensity: number;
  bgColor: string;
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
  lighting?: TimeOfDayLighting | null;
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
    lighting = null,
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
      <color attach="background" args={[lighting?.bgColor || '#1a1a2e']} />
      <ambientLight
        intensity={lighting?.ambientIntensity ?? 0.6}
        color={lighting ? new THREE.Color(...lighting.ambientColor) : undefined}
      />
      <directionalLight
        position={lighting ? [
          10 * Math.cos(lighting.sunPitch * Math.PI / 180),
          10 * Math.sin(-lighting.sunPitch * Math.PI / 180),
          10
        ] : [10, 20, 10]}
        intensity={lighting?.sunIntensity ?? 0.8}
        color={lighting ? new THREE.Color(...lighting.sunColor) : undefined}
      />
      {lighting && lighting.moonIntensity > 0.01 && (
        <directionalLight
          position={[-8, 12, -8]}
          intensity={lighting.moonIntensity}
          color={new THREE.Color(0.6, 0.7, 1.0)}
        />
      )}

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
