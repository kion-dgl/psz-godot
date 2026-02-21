/**
 * StageScene — Three.js scene for the quest editor walkthrough preview
 *
 * - GLB stage model (rotated by cell rotation)
 * - Portal markers (gate=yellow, spawn=green, trigger=red translucent)
 * - Capsule player with tank controls (W/S forward/back, A/D turn)
 * - Camera parented to capsule — fixed offset behind+above, zero jitter
 * - Raycast floor collision against the GLB mesh
 * - Trigger zone detection to fire cell-switch callbacks
 *
 * Player position lives in a useRef (not React state) so the game loop
 * never triggers React re-renders.  Position is reported to the parent
 * via a throttled callback for overlays (minimap, coordinate readout).
 */

import { useRef, useEffect, useMemo } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import { useGLTF, Text, Grid, PerspectiveCamera } from '@react-three/drei';
import * as THREE from 'three';
import { getGlbPath } from '../../stage-editor/constants';

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
  cellRotation: number; // degrees (0, 90, 180, 270)
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
  /** Initial world-space position when cell loads / switches */
  initialPosition: [number, number, number];
  /** Initial yaw in radians (facing direction) */
  initialYaw: number;
  /** Throttled position report for overlays (minimap, readout) */
  onPositionReport: (x: number, y: number, z: number) => void;
  onTriggerEnter: (direction: string, targetCellPos: string) => void;
}

// ============================================================================
// Rotation helper
// ============================================================================

function rotateVec3(v: [number, number, number], degY: number): [number, number, number] {
  if (degY === 0) return v;
  const rad = (degY * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  return [v[0] * cos + v[2] * sin, v[1], -v[0] * sin + v[2] * cos];
}

function rotatePortals(
  portals: Record<string, PortalData>,
  degY: number,
): Record<string, PortalData> {
  if (degY === 0) return portals;
  const rotated: Record<string, PortalData> = {};
  for (const [key, p] of Object.entries(portals)) {
    rotated[key] = {
      ...p,
      gate: rotateVec3(p.gate, degY),
      spawn: rotateVec3(p.spawn, degY),
      trigger: rotateVec3(p.trigger, degY),
    };
  }
  return rotated;
}

// ============================================================================
// GLB Model
// ============================================================================

function StageModel({ areaKey, stageId, groupRef }: {
  areaKey: string;
  stageId: string;
  groupRef: React.RefObject<THREE.Group | null>;
}) {
  const glbPath = getGlbPath(areaKey, stageId);
  const { scene } = useGLTF(glbPath);
  const cloned = useMemo(() => scene.clone(), [scene]);
  return <primitive ref={groupRef} object={cloned} />;
}

// ============================================================================
// Portal Markers
// ============================================================================

function PortalMarkers({ portals, connections }: {
  portals: Record<string, PortalData>;
  connections: Record<string, string>;
}) {
  return (
    <>
      {Object.entries(portals).map(([dir, portal]) => {
        if (dir === 'default') return null;
        const targetCell = connections[dir];
        const label = `${portal.compass_label || dir[0].toUpperCase()}${targetCell ? ` → ${targetCell}` : ''}`;

        return (
          <group key={dir}>
            <mesh position={portal.gate}>
              <sphereGeometry args={[0.8, 16, 16]} />
              <meshStandardMaterial color="#ddcc44" />
            </mesh>
            <mesh position={portal.spawn}>
              <sphereGeometry args={[0.5, 16, 16]} />
              <meshStandardMaterial color="#44cc66" />
            </mesh>
            <mesh position={portal.trigger}>
              <sphereGeometry args={[5, 16, 16]} />
              <meshStandardMaterial color="#cc4444" transparent opacity={0.15} side={THREE.DoubleSide} />
            </mesh>
            <mesh position={portal.trigger}>
              <sphereGeometry args={[5, 12, 12]} />
              <meshBasicMaterial color="#cc4444" wireframe transparent opacity={0.3} />
            </mesh>
            <Text
              position={[portal.gate[0], portal.gate[1] + 3, portal.gate[2]]}
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
const REPORT_INTERVAL = 1 / 15; // ~15 Hz overlay updates

const _raycaster = new THREE.Raycaster();
const _rayOrigin = new THREE.Vector3();
const _rayDir = new THREE.Vector3(0, -1, 0);

// ============================================================================
// Main Scene
// ============================================================================

export default function StageScene({
  areaKey,
  stageId,
  cellRotation,
  portals,
  connections,
  initialPosition,
  initialYaw,
  onPositionReport,
  onTriggerEnter,
}: StageSceneProps) {
  // All game-loop state lives in refs — no React re-renders during play
  const playerGroupRef = useRef<THREE.Group>(null);
  const stageGroupRef = useRef<THREE.Group>(null);
  const posRef = useRef(new THREE.Vector3(...initialPosition));
  const yawRef = useRef(initialYaw);
  const keysRef = useRef<Set<string>>(new Set());
  const triggeredRef = useRef<Set<string>>(new Set());
  const reportTimerRef = useRef(0);

  // Rotated portals for markers + triggers (world space)
  const rotatedPortals = useMemo(
    () => rotatePortals(portals, cellRotation),
    [portals, cellRotation],
  );
  const cellRotRad = (cellRotation * Math.PI) / 180;

  // Snap player to initialPosition when cell switches
  useEffect(() => {
    posRef.current.set(...initialPosition);
    yawRef.current = initialYaw;
    triggeredRef.current.clear();
    reportTimerRef.current = 0;
    // Immediate position report so overlays update on cell switch
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

  // Floor raycast (against the rotated model group's parent)
  const getFloorY = (x: number, z: number): number => {
    if (!stageGroupRef.current) return FLOOR_FALLBACK_Y;
    _rayOrigin.set(x, FLOOR_RAYCAST_HEIGHT, z);
    _raycaster.set(_rayOrigin, _rayDir);
    const hits = _raycaster.intersectObject(stageGroupRef.current, true);
    return hits.length > 0 ? hits[0].point.y : FLOOR_FALLBACK_Y;
  };

  // Game loop — everything reads/writes refs, never React state
  useFrame((_, delta) => {
    const dt = Math.min(delta, 0.05);
    const keys = keysRef.current;
    const pos = posRef.current;

    // Turn
    let turn = 0;
    if (keys.has('a') || keys.has('arrowleft')) turn += 1;
    if (keys.has('d') || keys.has('arrowright')) turn -= 1;
    if (turn !== 0) yawRef.current += turn * TURN_SPEED * dt;

    // Move forward/back
    let move = 0;
    if (keys.has('w') || keys.has('arrowup')) move += 1;
    if (keys.has('s') || keys.has('arrowdown')) move -= 1;
    if (move !== 0) {
      const yaw = yawRef.current;
      pos.x += -Math.sin(yaw) * move * MOVE_SPEED * dt;
      pos.z += -Math.cos(yaw) * move * MOVE_SPEED * dt;
      pos.y = getFloorY(pos.x, pos.z) + PLAYER_HEIGHT;
    }

    // Update the player group — camera is a child, so it follows automatically
    const pg = playerGroupRef.current;
    if (pg) {
      pg.position.copy(pos);
      pg.rotation.y = yawRef.current;
    }

    // Throttled position report for overlays
    reportTimerRef.current += dt;
    if (reportTimerRef.current >= REPORT_INTERVAL) {
      reportTimerRef.current = 0;
      onPositionReport(pos.x, pos.y, pos.z);
    }

    // Trigger zones
    for (const [dir, portal] of Object.entries(rotatedPortals)) {
      if (dir === 'default') continue;
      const target = connections[dir];
      if (!target) continue;
      const dx = pos.x - portal.trigger[0];
      const dz = pos.z - portal.trigger[2];
      if (dx * dx + dz * dz < 25 && !triggeredRef.current.has(dir)) {
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

      {/* Stage model — rotated by cell rotation */}
      <group ref={stageGroupRef} rotation={[0, cellRotRad, 0]}>
        <StageModel areaKey={areaKey} stageId={stageId} groupRef={stageGroupRef} />
      </group>

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

      <PortalMarkers portals={rotatedPortals} connections={connections} />

      {/* Player group — capsule + camera as children */}
      <group ref={playerGroupRef}>
        {/* Capsule body */}
        <mesh>
          <capsuleGeometry args={[0.4, 1.2, 8, 16]} />
          <meshStandardMaterial color="#5588ff" emissive="#223366" />
        </mesh>
        {/* Nose cone (forward indicator) */}
        <mesh position={[0, 0.5, -1.2]} rotation={[Math.PI / 2, 0, 0]}>
          <coneGeometry args={[0.25, 0.6, 8]} />
          <meshStandardMaterial color="#ffcc44" emissive="#886600" />
        </mesh>
        {/* Camera — fixed behind and above, looking forward */}
        <PerspectiveCamera
          makeDefault
          fov={50}
          near={0.1}
          far={1000}
          position={[0, 12, 16]}
          rotation={[-0.6, 0, 0]}
        />
      </group>
    </>
  );
}
