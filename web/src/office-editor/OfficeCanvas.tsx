import { Canvas } from '@react-three/fiber';
import { OrbitControls, useGLTF, Grid } from '@react-three/drei';
import { Suspense, useCallback } from 'react';
import * as THREE from 'three';
import { assetUrl } from '../utils/assets';
import type { OfficeLayoutData, PlacementMode } from './types';
import OfficeOverlay from './OfficeOverlay';

const ROOM_PATH = 'assets/stages/city_e/s00e_office/lndmd/s00e_office_m.glb';
const NPC_PATH = 'assets/npcs/principal/principal.glb';
const REFERENCE_PATH = 'assets/player/pc_000/pc_000_000.glb';

function RoomModel({ scale }: { scale: number }) {
  const { scene } = useGLTF(assetUrl(ROOM_PATH));
  return <primitive object={scene} scale={[scale, scale, scale]} />;
}

function ReferenceModel() {
  const { scene } = useGLTF(assetUrl(REFERENCE_PATH));
  return <primitive object={scene} position={[0, 0, 0]} />;
}

function PrincipalModel({ position, rotationY, scale }: { position: [number, number, number]; rotationY: number; scale: number }) {
  const { scene } = useGLTF(assetUrl(NPC_PATH));
  return (
    <primitive
      object={scene}
      position={position}
      rotation={[0, rotationY, 0]}
      scale={[scale, scale, scale]}
    />
  );
}

function FloorPlane({ onClick }: { onClick: (point: THREE.Vector3) => void }) {
  const handleClick = useCallback((e: { stopPropagation: () => void; point: THREE.Vector3 }) => {
    e.stopPropagation();
    onClick(e.point);
  }, [onClick]);

  return (
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.001, 0]} onClick={handleClick} visible={false}>
      <planeGeometry args={[200, 200]} />
      <meshBasicMaterial transparent opacity={0} />
    </mesh>
  );
}

interface OfficeCanvasProps {
  layout: OfficeLayoutData;
  placementMode: PlacementMode;
  onPlacePoint: (point: THREE.Vector3) => void;
}

export default function OfficeCanvas({ layout, placementMode, onPlacePoint }: OfficeCanvasProps) {
  return (
    <Canvas camera={{ position: [0, 15, 20], fov: 50 }}>
      <color attach="background" args={['#1a1a2e']} />
      <ambientLight intensity={0.6} />
      <directionalLight position={[10, 20, 10]} intensity={0.8} />

      <Suspense fallback={null}>
        <RoomModel scale={layout.roomScale} />
        <PrincipalModel position={layout.npcPosition} rotationY={layout.npcRotationY} scale={layout.npcScale} />
        <ReferenceModel />
      </Suspense>

      <OfficeOverlay layout={layout} placementMode={placementMode} />

      {placementMode !== 'none' && <FloorPlane onClick={onPlacePoint} />}

      <Grid
        args={[100, 100]}
        position={[0, 0.01, 0]}
        cellSize={1}
        cellThickness={0.5}
        cellColor="#444"
        sectionSize={10}
        sectionThickness={1}
        sectionColor="#666"
        fadeDistance={50}
        fadeStrength={1}
      />

      <OrbitControls makeDefault />
    </Canvas>
  );
}
