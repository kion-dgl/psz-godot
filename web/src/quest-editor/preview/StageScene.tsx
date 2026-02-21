/**
 * StageScene — Three.js scene for the quest editor walkthrough preview
 *
 * Architecture: The GLB model AND portal markers are children of a single
 * rotated group. Cell rotation is applied once to the group — portal positions
 * use raw model-local coords from the config and get rotated automatically.
 *
 * Player moves in world space. For trigger detection, the player's world
 * position is inverse-rotated into model-local space.
 */

import { useRef, useEffect, useMemo } from 'react';
import { useFrame } from '@react-three/fiber';
import { useGLTF, Text, Grid, PerspectiveCamera } from '@react-three/drei';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import { getGlbPath } from '../../stage-editor/constants';
import { assetUrl } from '../../utils/assets';

// ============================================================================
// Types
// ============================================================================

export interface PortalData {
  gate: [number, number, number];
  spawn: [number, number, number];
  trigger: [number, number, number];
  gate_rot?: [number, number, number];
  compass_label?: string;
}

export interface CellPortals {
  connections: Record<string, string>;
  portals: Record<string, PortalData>;
  stage_id: string;
  pos: string;
}

interface StageSceneProps {
  areaKey: string;
  stageId: string;
  /** Portal data in model-local space (3D view is unrotated) */
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  initialPosition: [number, number, number];
  initialYaw: number;
  onPositionReport: (x: number, y: number, z: number) => void;
  onTriggerEnter: (direction: string, targetCellPos: string) => void;
}

// ============================================================================
// GLB Model
// ============================================================================

function StageModel({ areaKey, stageId, modelRef }: {
  areaKey: string;
  stageId: string;
  modelRef: React.RefObject<THREE.Object3D | null>;
}) {
  const glbPath = getGlbPath(areaKey, stageId);
  const { scene } = useGLTF(glbPath);
  const cloned = useMemo(() => scene.clone(), [scene]);
  return <primitive ref={modelRef} object={cloned} />;
}

// ============================================================================
// Gate model path
// ============================================================================

const GATE_MODEL_PATH = assetUrl('assets/objects/valley/o0c_gate.glb');

// ============================================================================
// Portal Markers — matching stage editor (PortalOverlay.tsx)
// All positions are in MODEL-LOCAL space (rotated by parent group)
// ============================================================================

const GATE_WIDTH = 6.0;

/** Spawn marker: green sphere + ground ring + direction arrow */
function SpawnMarker({ position, rotation }: {
  position: [number, number, number]; rotation: number;
}) {
  return (
    <group position={position}>
      <mesh>
        <sphereGeometry args={[0.8, 16, 16]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.7} />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]}>
        <ringGeometry args={[1, 1.3, 32]} />
        <meshBasicMaterial color="#00ff00" side={THREE.DoubleSide} />
      </mesh>
      <group rotation={[0, rotation, 0]}>
        <mesh position={[0, 0.3, 1]}>
          <boxGeometry args={[0.2, 0.2, 1.5]} />
          <meshBasicMaterial color="#00ff00" />
        </mesh>
        <mesh position={[0, 0.3, 2]} rotation={[Math.PI / 2, 0, 0]}>
          <coneGeometry args={[0.4, 0.6, 8]} />
          <meshBasicMaterial color="#00ff00" />
        </mesh>
      </group>
    </group>
  );
}

/** Trigger zone: orange semi-transparent box + wireframe edges */
function TriggerMarker({ position, rotation }: {
  position: [number, number, number]; rotation: number;
}) {
  const edgesGeo = useMemo(() => new THREE.EdgesGeometry(new THREE.BoxGeometry(GATE_WIDTH, 3, 2)), []);
  return (
    <group position={position} rotation={[0, rotation, 0]}>
      <mesh position={[0, 1.5, 0]}>
        <boxGeometry args={[GATE_WIDTH, 3, 2]} />
        <meshBasicMaterial color="#ff6600" transparent opacity={0.3} />
      </mesh>
      <lineSegments position={[0, 1.5, 0]} geometry={edgesGeo}>
        <lineBasicMaterial color="#ff6600" />
      </lineSegments>
    </group>
  );
}

/** Gate bounding box: cyan wireframe */
function GateBoundingBox({ position, rotation }: {
  position: [number, number, number]; rotation: number;
}) {
  const edgesGeo = useMemo(() => new THREE.EdgesGeometry(new THREE.BoxGeometry(GATE_WIDTH, 4, 1)), []);
  return (
    <group position={position} rotation={[0, rotation, 0]}>
      <mesh position={[0, 2, 0]}>
        <boxGeometry args={[GATE_WIDTH, 4, 1]} />
        <meshBasicMaterial color="#00ffff" transparent opacity={0.15} />
      </mesh>
      <lineSegments position={[0, 2, 0]} geometry={edgesGeo}>
        <lineBasicMaterial color="#00ffff" />
      </lineSegments>
    </group>
  );
}

/** Gate GLB model */
function GateModel({ position, rotation }: {
  position: [number, number, number]; rotation: number;
}) {
  const { scene } = useGLTF(GATE_MODEL_PATH);
  const cloned = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materials.forEach((mat) => {
          const material = mat as THREE.MeshStandardMaterial;
          material.transparent = true;
          material.opacity = 0.8;
          material.needsUpdate = true;
        });
      }
    });
    return clone;
  }, [scene]);

  return (
    <group position={position} rotation={[0, rotation, 0]}>
      <primitive object={cloned} />
    </group>
  );
}

/** Portal markers using model-local positions (parent group handles rotation) */
function PortalMarkers({ portals, connections }: {
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
}) {
  return (
    <>
      {Object.entries(portals).map(([dir, portal]) => {
        if (dir === 'default') return null;
        const targetCell = connections[dir];
        const label = `${dir[0].toUpperCase()}${targetCell ? ` → ${targetCell}` : ''}`;
        const gateRotY = portal.gate_rot ? portal.gate_rot[1] : 0;

        return (
          <group key={dir}>
            <GateModel position={portal.gate} rotation={gateRotY} />
            <GateBoundingBox position={portal.gate} rotation={gateRotY} />
            <SpawnMarker position={portal.spawn} rotation={gateRotY} />
            <TriggerMarker position={portal.trigger} rotation={gateRotY} />
            <Text
              position={[portal.gate[0], portal.gate[1] + 5, portal.gate[2]]}
              fontSize={1.2}
              color="#ffffff"
              anchorX="center"
              anchorY="bottom"
              outlineWidth={0.08}
              outlineColor="#000000"
            >
              {label}
            </Text>
          </group>
        );
      })}
    </>
  );
}

// ============================================================================
// Constants
// ============================================================================

const MOVE_SPEED = 12;
const TURN_SPEED = 2.5;
const PLAYER_HEIGHT = 2;
const FLOOR_RAYCAST_HEIGHT = 50;
const FLOOR_FALLBACK_Y = 0;
const REPORT_INTERVAL = 1 / 15;

const TRIGGER_HALF_W = GATE_WIDTH / 2; // 3
const TRIGGER_HALF_D = 1; // depth/2
const TRIGGER_GRACE_PERIOD = 0.5;

const _raycaster = new THREE.Raycaster();
const _rayOrigin = new THREE.Vector3();
const _rayDir = new THREE.Vector3(0, -1, 0);

// ============================================================================
// Main Scene
// ============================================================================

export default function StageScene({
  areaKey,
  stageId,
  portals,
  connections,
  initialPosition,
  initialYaw,
  onPositionReport,
  onTriggerEnter,
}: StageSceneProps) {
  const playerGroupRef = useRef<THREE.Group>(null);
  const modelRef = useRef<THREE.Object3D>(null);
  const posRef = useRef(new THREE.Vector3(...initialPosition));
  const yawRef = useRef(initialYaw);
  const keysRef = useRef<Set<string>>(new Set());
  const triggeredRef = useRef<Set<string>>(new Set());
  const reportTimerRef = useRef(0);
  const graceTimerRef = useRef(TRIGGER_GRACE_PERIOD);

  // Snap player on cell switch
  useEffect(() => {
    posRef.current.set(...initialPosition);
    yawRef.current = initialYaw;
    triggeredRef.current.clear();
    graceTimerRef.current = TRIGGER_GRACE_PERIOD;
    reportTimerRef.current = 0;
    onPositionReport(initialPosition[0], initialPosition[1], initialPosition[2]);
  }, [initialPosition, initialYaw]);

  // Keyboard
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      keysRef.current.add(e.key.toLowerCase());
    };
    const up = (e: KeyboardEvent) => keysRef.current.delete(e.key.toLowerCase());
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => { window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); };
  }, []);

  const getFloorY = (x: number, z: number): number => {
    if (!modelRef.current) return FLOOR_FALLBACK_Y;
    _rayOrigin.set(x, FLOOR_RAYCAST_HEIGHT, z);
    _raycaster.set(_rayOrigin, _rayDir);
    const hits = _raycaster.intersectObject(modelRef.current, true);
    return hits.length > 0 ? hits[0].point.y : FLOOR_FALLBACK_Y;
  };

  /** Check if point (px, pz) is inside a trigger box at (cx, cz) with Y rotation.
   *  All coordinates are in model-local space. */
  const isInsideTriggerBox = (px: number, pz: number, cx: number, cz: number, rotY: number): boolean => {
    const dx = px - cx;
    const dz = pz - cz;
    const cos = Math.cos(-rotY);
    const sin = Math.sin(-rotY);
    const localX = dx * cos - dz * sin;
    const localZ = dx * sin + dz * cos;
    return Math.abs(localX) <= TRIGGER_HALF_W && Math.abs(localZ) <= TRIGGER_HALF_D;
  };

  useFrame((_, delta) => {
    const dt = Math.min(delta, 0.05);
    const keys = keysRef.current;
    const pos = posRef.current;

    // Turn
    let turn = 0;
    if (keys.has('a') || keys.has('arrowleft')) turn += 1;
    if (keys.has('d') || keys.has('arrowright')) turn -= 1;
    if (turn !== 0) yawRef.current += turn * TURN_SPEED * dt;

    // Move (world space)
    let move = 0;
    if (keys.has('w') || keys.has('arrowup')) move += 1;
    if (keys.has('s') || keys.has('arrowdown')) move -= 1;
    if (move !== 0) {
      const yaw = yawRef.current;
      pos.x += -Math.sin(yaw) * move * MOVE_SPEED * dt;
      pos.z += -Math.cos(yaw) * move * MOVE_SPEED * dt;
      pos.y = getFloorY(pos.x, pos.z) + PLAYER_HEIGHT;
    }

    // Update player group
    const pg = playerGroupRef.current;
    if (pg) {
      pg.position.copy(pos);
      pg.rotation.y = yawRef.current;
    }

    // Position report
    reportTimerRef.current += dt;
    if (reportTimerRef.current >= REPORT_INTERVAL) {
      reportTimerRef.current = 0;
      onPositionReport(pos.x, pos.y, pos.z);
    }

    // Grace period countdown
    if (graceTimerRef.current > 0) {
      graceTimerRef.current -= dt;
      return;
    }

    // Trigger detection — player and portals are both in model-local space (no rotation)
    for (const [dir, portal] of Object.entries(portals)) {
      if (dir === 'default') continue;
      const target = connections[dir];
      if (!target) continue;
      if (triggeredRef.current.has(dir)) continue;

      const rotY = portal.gate_rot ? portal.gate_rot[1] : 0;
      if (isInsideTriggerBox(pos.x, pos.z, portal.trigger[0], portal.trigger[2], rotY)) {
        triggeredRef.current.add(dir);
        onTriggerEnter(dir, target);
      }
    }
  });

  return (
    <>
      <color attach="background" args={['#1a1a2e']} />
      <ambientLight intensity={0.6} />
      <directionalLight position={[10, 30, 10]} intensity={0.8} />
      <hemisphereLight args={['#8888cc', '#444422', 0.4]} />

      {/* Stage model + portal markers — unrotated (model-local space) */}
      <StageModel areaKey={areaKey} stageId={stageId} modelRef={modelRef} />
      <PortalMarkers portals={portals} connections={connections} />

      <Grid
        args={[100, 100]}
        position={[0, 0.02, 0]}
        cellSize={5}
        cellThickness={0.5}
        cellColor="#333"
        sectionSize={10}
        sectionThickness={1}
        sectionColor="#555"
        fadeDistance={80}
        fadeStrength={1}
      />

      {/* Player group — capsule + camera as children (world space) */}
      <group ref={playerGroupRef}>
        <mesh>
          <capsuleGeometry args={[0.4, 1.2, 8, 16]} />
          <meshStandardMaterial color="#5588ff" emissive="#223366" />
        </mesh>
        <mesh position={[0, 0.5, -1.2]} rotation={[Math.PI / 2, 0, 0]}>
          <coneGeometry args={[0.25, 0.6, 8]} />
          <meshStandardMaterial color="#ffcc44" emissive="#886600" />
        </mesh>
        <PerspectiveCamera
          makeDefault
          fov={50}
          near={0.1}
          far={1000}
          position={[0, 8, 14]}
          rotation={[-0.5, 0, 0]}
        />
      </group>
    </>
  );
}

// Preload gate model
useGLTF.preload(GATE_MODEL_PATH);
