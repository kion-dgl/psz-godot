/**
 * ContentTab — 3D cell preview with key/gate placement
 *
 * Left: Mini grid for cell selection
 * Center: 3D StageCanvas showing the selected cell's GLB
 * Right: Cell content inspector (key position, gate info)
 */

import { useState, useCallback, useMemo, useRef, useEffect, Suspense } from 'react';
import { Canvas, useThree, useFrame } from '@react-three/fiber';
import { OrbitControls, useGLTF, Grid } from '@react-three/drei';
import * as THREE from 'three';
import type { QuestProject, Direction, CellObject, CellObjectType } from '../types';
import { ROLE_COLORS, CELL_OBJECT_COLORS, CELL_OBJECT_LABELS } from '../types';
import { getRotatedGates, getStageConfig, getStageSuffix } from '../hooks/useStageConfigs';
import { getGlbPath, getAreaFromMapId } from '../constants';
import { assetUrl } from '../../utils/assets';
import type { GateConfig } from '../types';

/** NPC ID → GLB asset path mapping (mirrors field_npc.gd NPC_MODELS) */
const NPC_MODELS: Record<string, string> = {
  sarisa: 'assets/npcs/sarisa/pc_a00_000.glb',
  kai: 'assets/npcs/kai/pc_a01_000.glb',
};

// ============================================================================
// Enemy Data (loaded from /data/enemies.json)
// ============================================================================

interface EnemyInfo {
  id: string;
  name: string;
  model_id: string;
  element: string;
  locations: string[];
  is_rare: boolean;
  is_boss: boolean;
}

/** Map editor areaKey to enemy locations key */
const AREA_TO_LOCATION: Record<string, string> = {
  valley: 'valley',
  wetlands: 'wetlands',
  snowfield: 'snowfield',
  makara: 'makara',
  paru: 'paru',
  arca: 'arca',
  shrine: 'shrine',
  tower: 'tower',
};

let _enemyListCache: EnemyInfo[] | null = null;

function useEnemyList(): EnemyInfo[] {
  const [enemies, setEnemies] = useState<EnemyInfo[]>(_enemyListCache || []);

  useEffect(() => {
    if (_enemyListCache) return;
    const base = import.meta.env.BASE_URL || '/';
    fetch(`${base}data/enemies.json`)
      .then(r => r.json())
      .then((data: EnemyInfo[]) => {
        _enemyListCache = data;
        setEnemies(data);
      })
      .catch(() => {
        console.warn('Failed to load enemies.json');
      });
  }, []);

  return enemies;
}

// ============================================================================
// Types
// ============================================================================

interface ContentTabProps {
  project: QuestProject;
  onUpdateProject: (updater: (prev: QuestProject) => QuestProject) => void;
}

// ============================================================================
// 3D Marker components
// ============================================================================

/** Gate marker — cyan wireframe box at gate position */
function GateMarker({ gate, isLocked }: { gate: GateConfig; isLocked: boolean }) {
  const boxWidth = 6;
  const boxHeight = 4;
  const boxDepth = 1;
  const color = isLocked ? '#ff66ff' : '#00ffff';

  // Rotation based on gate edge
  const rotation = gate.edge === 'north' ? Math.PI
    : gate.edge === 'south' ? 0
    : gate.edge === 'east' ? Math.PI / 2
    : -Math.PI / 2;

  return (
    <group position={[gate.x, 0, gate.z]} rotation={[0, rotation, 0]}>
      <mesh position={[0, boxHeight / 2, 0]}>
        <boxGeometry args={[boxWidth, boxHeight, boxDepth]} />
        <meshBasicMaterial color={color} transparent opacity={0.2} />
      </mesh>
      <lineSegments position={[0, boxHeight / 2, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(boxWidth, boxHeight, boxDepth)]} />
        <lineBasicMaterial color={color} />
      </lineSegments>
      {/* Label */}
      <mesh position={[0, boxHeight + 0.5, 0]}>
        <sphereGeometry args={[0.3, 8, 8]} />
        <meshBasicMaterial color={color} />
      </mesh>
    </group>
  );
}

/** Key marker — pink sphere that shows authored key position */
function KeyMarker({ position }: { position: [number, number, number] }) {
  return (
    <group position={position}>
      {/* Main sphere */}
      <mesh>
        <sphereGeometry args={[1.0, 16, 16]} />
        <meshBasicMaterial color="#ff66aa" transparent opacity={0.8} />
      </mesh>
      {/* Ring on ground */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -position[1] + 0.05, 0]}>
        <ringGeometry args={[1.2, 1.5, 32]} />
        <meshBasicMaterial color="#ff66aa" side={THREE.DoubleSide} transparent opacity={0.5} />
      </mesh>
      {/* Vertical line to ground */}
      <mesh position={[0, -position[1] / 2, 0]}>
        <cylinderGeometry args={[0.05, 0.05, position[1], 8]} />
        <meshBasicMaterial color="#ff66aa" transparent opacity={0.4} />
      </mesh>
    </group>
  );
}

/** Spawn point marker — green sphere with arrow */
function SpawnMarker({ position, edge }: { position: [number, number, number]; edge: string }) {
  const rotation = edge === 'north' ? Math.PI
    : edge === 'south' ? 0
    : edge === 'east' ? Math.PI / 2
    : -Math.PI / 2;

  return (
    <group position={position}>
      <mesh>
        <sphereGeometry args={[0.6, 16, 16]} />
        <meshBasicMaterial color="#00ff00" transparent opacity={0.5} />
      </mesh>
      {/* Direction arrow */}
      <group rotation={[0, rotation, 0]}>
        <mesh position={[0, 0.3, 1]}>
          <boxGeometry args={[0.15, 0.15, 1.0]} />
          <meshBasicMaterial color="#00ff00" transparent opacity={0.5} />
        </mesh>
        <mesh position={[0, 0.3, 1.8]} rotation={[Math.PI / 2, 0, 0]}>
          <coneGeometry args={[0.3, 0.5, 8]} />
          <meshBasicMaterial color="#00ff00" transparent opacity={0.5} />
        </mesh>
      </group>
    </group>
  );
}

// ============================================================================
// Object Markers (3D representations of placed objects)
// ============================================================================

/** Box marker — brown/gold cube */
function BoxMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const color = obj.type === 'rare_box' ? '#ddaa33' : '#aa6633';
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, 0.5, 0]}>
        <boxGeometry args={[1, 1, 1]} />
        <meshBasicMaterial color={color} transparent opacity={selected ? 0.9 : 0.6} />
      </mesh>
      <lineSegments position={[0, 0.5, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(1, 1, 1)]} />
        <lineBasicMaterial color={selected ? '#ffffff' : color} />
      </lineSegments>
    </group>
  );
}

/** Enemy marker — red sphere with label */
function EnemyMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, 0.8, 0]}>
        <sphereGeometry args={[0.8, 16, 16]} />
        <meshBasicMaterial color="#cc4444" transparent opacity={selected ? 0.9 : 0.5} />
      </mesh>
      {selected && (
        <mesh position={[0, 0.8, 0]}>
          <sphereGeometry args={[0.9, 16, 16]} />
          <meshBasicMaterial color="#ffffff" wireframe transparent opacity={0.4} />
        </mesh>
      )}
    </group>
  );
}

/** Fence marker — blue horizontal bar */
function FenceMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const yRot = ((obj.rotation || 0) * Math.PI) / 180;
  return (
    <group position={obj.position} rotation={[0, yRot, 0]} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, 1, 0]}>
        <boxGeometry args={[3, 2, 0.3]} />
        <meshBasicMaterial color="#4488cc" transparent opacity={selected ? 0.7 : 0.4} />
      </mesh>
      <lineSegments position={[0, 1, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(3, 2, 0.3)]} />
        <lineBasicMaterial color={selected ? '#ffffff' : '#4488cc'} />
      </lineSegments>
    </group>
  );
}

/** Switch marker — green flat disc */
function SwitchMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.05, 0]}>
        <cylinderGeometry args={[0.8, 0.8, 0.1, 16]} />
        <meshBasicMaterial color="#44cc66" transparent opacity={selected ? 0.9 : 0.5} />
      </mesh>
      {selected && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.06, 0]}>
          <ringGeometry args={[0.9, 1.1, 16]} />
          <meshBasicMaterial color="#ffffff" side={THREE.DoubleSide} transparent opacity={0.5} />
        </mesh>
      )}
    </group>
  );
}

/** Message marker — purple cylinder */
function MessageMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, 0.6, 0]}>
        <cylinderGeometry args={[0.5, 0.5, 1.2, 8]} />
        <meshBasicMaterial color="#cc66ff" transparent opacity={selected ? 0.9 : 0.5} />
      </mesh>
      {/* Top cap */}
      <mesh position={[0, 1.3, 0]}>
        <sphereGeometry args={[0.3, 8, 8]} />
        <meshBasicMaterial color="#cc66ff" transparent opacity={selected ? 0.9 : 0.5} />
      </mesh>
      {selected && (
        <mesh position={[0, 0.6, 0]}>
          <cylinderGeometry args={[0.6, 0.6, 1.4, 8]} />
          <meshBasicMaterial color="#ffffff" wireframe transparent opacity={0.4} />
        </mesh>
      )}
    </group>
  );
}

/** Story prop GLB model loader */
function StoryPropModel({ propPath }: { propPath: string }) {
  const url = assetUrl(`/${propPath}`);
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(true), [scene]);
  return <primitive object={cloned} />;
}

/** Story prop marker — loads GLB if available, falls back to yellow cube */
function StoryPropMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const yRot = ((obj.rotation || 0) * Math.PI) / 180;
  return (
    <group position={obj.position} rotation={[0, yRot, 0]} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      {obj.prop_path ? (
        <Suspense fallback={
          <mesh position={[0, 0.75, 0]}>
            <boxGeometry args={[1.5, 1.5, 1.5]} />
            <meshBasicMaterial color="#cccc44" transparent opacity={0.3} wireframe />
          </mesh>
        }>
          <StoryPropModel propPath={obj.prop_path} />
        </Suspense>
      ) : (
        <mesh position={[0, 0.75, 0]}>
          <boxGeometry args={[1.5, 1.5, 1.5]} />
          <meshBasicMaterial color="#cccc44" transparent opacity={selected ? 0.9 : 0.5} />
        </mesh>
      )}
      {selected && (
        <lineSegments position={[0, 0.75, 0]}>
          <edgesGeometry args={[new THREE.BoxGeometry(1.5, 1.5, 1.5)]} />
          <lineBasicMaterial color="#ffffff" />
        </lineSegments>
      )}
    </group>
  );
}

/** Dialog trigger marker — cyan wireframe box matching trigger_size */
function DialogTriggerMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const size = obj.trigger_size || [4, 3, 4];
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, size[1] / 2, 0]}>
        <boxGeometry args={[size[0], size[1], size[2]]} />
        <meshBasicMaterial color="#44cccc" transparent opacity={selected ? 0.25 : 0.12} />
      </mesh>
      <lineSegments position={[0, size[1] / 2, 0]}>
        <edgesGeometry args={[new THREE.BoxGeometry(size[0], size[1], size[2])]} />
        <lineBasicMaterial color={selected ? '#ffffff' : '#44cccc'} />
      </lineSegments>
    </group>
  );
}

/** NPC GLB model loader */
function NpcModel({ npcId }: { npcId: string }) {
  const glbPath = NPC_MODELS[npcId];
  const url = glbPath ? assetUrl(`/${glbPath}`) : '';
  const { scene } = useGLTF(url);
  const cloned = useMemo(() => scene.clone(), [scene]);
  return <primitive object={cloned} />;
}

/** NPC marker — loads GLB if known npc_id, falls back to green cylinder */
function NpcMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const yRot = ((obj.rotation || 0) * Math.PI) / 180;
  const hasModel = obj.npc_id && NPC_MODELS[obj.npc_id];
  return (
    <group position={obj.position} rotation={[0, yRot, 0]} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      {hasModel ? (
        <Suspense fallback={
          <mesh position={[0, 0.9, 0]}>
            <cylinderGeometry args={[0.4, 0.4, 1.8, 12]} />
            <meshBasicMaterial color="#44cc44" transparent opacity={0.3} wireframe />
          </mesh>
        }>
          <NpcModel npcId={obj.npc_id!} />
        </Suspense>
      ) : (
        <>
          <mesh position={[0, 0.9, 0]}>
            <cylinderGeometry args={[0.4, 0.4, 1.8, 12]} />
            <meshBasicMaterial color="#44cc44" transparent opacity={selected ? 0.9 : 0.5} />
          </mesh>
          <mesh position={[0, 2.0, 0]}>
            <sphereGeometry args={[0.4, 12, 12]} />
            <meshBasicMaterial color="#44cc44" transparent opacity={selected ? 0.9 : 0.5} />
          </mesh>
        </>
      )}
      {selected && (
        <mesh position={[0, 0.9, 0]}>
          <cylinderGeometry args={[0.5, 0.5, 2.0, 12]} />
          <meshBasicMaterial color="#ffffff" wireframe transparent opacity={0.4} />
        </mesh>
      )}
    </group>
  );
}

/** Telepipe marker — cyan glowing cylinder */
function TelepipeMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  const isDeferred = obj.spawn_condition === 'room_clear';
  return (
    <group position={obj.position} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <mesh position={[0, 1.5, 0]}>
        <cylinderGeometry args={[0.8, 0.8, 3.0, 16]} />
        <meshBasicMaterial color={isDeferred ? '#4488cc' : '#66ccff'} transparent opacity={selected ? 0.8 : 0.5} />
      </mesh>
      {selected && (
        <mesh position={[0, 1.5, 0]}>
          <cylinderGeometry args={[0.9, 0.9, 3.1, 16]} />
          <meshBasicMaterial color="#ffffff" wireframe transparent opacity={0.4} />
        </mesh>
      )}
    </group>
  );
}

/** Renders the appropriate marker for a CellObject */
function ObjectMarker({ obj, selected, onClick }: { obj: CellObject; selected: boolean; onClick: () => void }) {
  switch (obj.type) {
    case 'box':
    case 'rare_box':
      return <BoxMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'enemy':
      return <EnemyMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'fence':
      return <FenceMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'step_switch':
      return <SwitchMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'message':
      return <MessageMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'story_prop':
      return <StoryPropMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'dialog_trigger':
      return <DialogTriggerMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'npc':
      return <NpcMarker obj={obj} selected={selected} onClick={onClick} />;
    case 'telepipe':
      return <TelepipeMarker obj={obj} selected={selected} onClick={onClick} />;
    default:
      return null;
  }
}

/** Object placement cursor — follows mouse on ground plane */
function ObjectPlacementCursor({ objectType }: { objectType: CellObjectType }) {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);
  const color = CELL_OBJECT_COLORS[objectType];

  useFrame(() => {
    if (!groupRef.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 0, intersection.z);
    }
  });

  return (
    <group ref={groupRef}>
      {(objectType === 'box' || objectType === 'rare_box') && (
        <mesh position={[0, 0.5, 0]}>
          <boxGeometry args={[1, 1, 1]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'enemy' && (
        <mesh position={[0, 0.8, 0]}>
          <sphereGeometry args={[0.8, 16, 16]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'fence' && (
        <mesh position={[0, 1, 0]}>
          <boxGeometry args={[3, 2, 0.3]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'step_switch' && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.05, 0]}>
          <cylinderGeometry args={[0.8, 0.8, 0.1, 16]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'message' && (
        <mesh position={[0, 0.6, 0]}>
          <cylinderGeometry args={[0.5, 0.5, 1.2, 8]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'story_prop' && (
        <mesh position={[0, 0.75, 0]}>
          <boxGeometry args={[1.5, 1.5, 1.5]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'dialog_trigger' && (
        <mesh position={[0, 1, 0]}>
          <sphereGeometry args={[1.2, 16, 16]} />
          <meshBasicMaterial color={color} wireframe transparent opacity={0.3} />
        </mesh>
      )}
      {objectType === 'npc' && (
        <>
          <mesh position={[0, 0.9, 0]}>
            <cylinderGeometry args={[0.4, 0.4, 1.8, 12]} />
            <meshBasicMaterial color={color} transparent opacity={0.3} />
          </mesh>
          <mesh position={[0, 2.0, 0]}>
            <sphereGeometry args={[0.4, 12, 12]} />
            <meshBasicMaterial color={color} transparent opacity={0.3} />
          </mesh>
        </>
      )}
      {objectType === 'telepipe' && (
        <mesh position={[0, 1.5, 0]}>
          <cylinderGeometry args={[0.8, 0.8, 3.0, 16]} />
          <meshBasicMaterial color={color} transparent opacity={0.3} />
        </mesh>
      )}
      {/* Ground ring */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.02, 0]}>
        <ringGeometry args={[1.2, 1.5, 32]} />
        <meshBasicMaterial color={color} side={THREE.DoubleSide} transparent opacity={0.3} />
      </mesh>
    </group>
  );
}

/** Ground click handler for object placement */
function ObjectClickPlane({ onPlace }: { onPlace: (pos: [number, number, number]) => void }) {
  const { camera, raycaster, pointer } = useThree();
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  const handleClick = useCallback(() => {
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      onPlace([
        Math.round(intersection.x * 10) / 10,
        0,
        Math.round(intersection.z * 10) / 10,
      ]);
    }
  }, [raycaster, pointer, camera, groundPlane, intersection, onPlace]);

  return (
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.01, 0]} onClick={handleClick}>
      <planeGeometry args={[200, 200]} />
      <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
    </mesh>
  );
}

/** Placement cursor — follows mouse, shows where key will be placed */
function KeyPlacementCursor() {
  const { camera, raycaster, pointer } = useThree();
  const groupRef = useRef<THREE.Group>(null);
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), -1), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  useFrame(() => {
    if (!groupRef.current) return;
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      groupRef.current.position.set(intersection.x, 1, intersection.z);
    }
  });

  return (
    <group ref={groupRef}>
      <mesh>
        <sphereGeometry args={[1.0, 16, 16]} />
        <meshBasicMaterial color="#ff66aa" transparent opacity={0.4} />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -1 + 0.05, 0]}>
        <ringGeometry args={[1.2, 1.5, 32]} />
        <meshBasicMaterial color="#ff66aa" side={THREE.DoubleSide} transparent opacity={0.3} />
      </mesh>
    </group>
  );
}

/** Ground click handler — invisible plane for click-to-place */
function GroundClickPlane({ onPlace }: { onPlace: (pos: [number, number, number]) => void }) {
  const { camera, raycaster, pointer } = useThree();
  const groundPlane = useMemo(() => new THREE.Plane(new THREE.Vector3(0, 1, 0), -1), []);
  const intersection = useMemo(() => new THREE.Vector3(), []);

  const handleClick = useCallback(() => {
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.ray.intersectPlane(groundPlane, intersection)) {
      onPlace([
        Math.round(intersection.x * 10) / 10,
        1,
        Math.round(intersection.z * 10) / 10,
      ]);
    }
  }, [raycaster, pointer, camera, groundPlane, intersection, onPlace]);

  return (
    <mesh
      rotation={[-Math.PI / 2, 0, 0]}
      position={[0, 0.01, 0]}
      onClick={handleClick}
    >
      <planeGeometry args={[200, 200]} />
      <meshBasicMaterial transparent opacity={0} side={THREE.DoubleSide} />
    </mesh>
  );
}

/** Stage model loader */
function StageModel({ mapId }: { mapId: string }) {
  const areaKey = getAreaFromMapId(mapId) || 'valley';
  const glbPath = getGlbPath(areaKey, mapId);
  const { scene } = useGLTF(glbPath);
  return <primitive object={scene} />;
}

// ============================================================================
// Mini Grid (compact version for left panel)
// ============================================================================

function MiniGrid({
  project,
  selectedCell,
  onCellSelect,
}: {
  project: QuestProject;
  selectedCell: string | null;
  onCellSelect: (pos: string) => void;
}) {
  const CELL_SIZE = 48;

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      gap: '1px',
      background: '#111',
      padding: '4px',
      borderRadius: '6px',
    }}>
      {Array.from({ length: project.gridSize }, (_, row) => (
        <div key={row} style={{ display: 'flex', gap: '1px' }}>
          {Array.from({ length: project.gridSize }, (_, col) => {
            const pos = `${row},${col}`;
            const cell = project.cells[pos];
            const isSelected = selectedCell === pos;
            const isStart = project.startPos === pos;
            const isEnd = project.endPos === pos;
            const hasKey = Object.values(project.keyLinks).includes(pos);
            const isKeyGate = pos in project.keyLinks;
            const hasKeyPosition = cell?.keyPosition != null;
            const hasObjects = (cell?.objects?.length || 0) > 0;

            if (!cell) {
              return (
                <div key={col} style={{
                  width: CELL_SIZE,
                  height: CELL_SIZE,
                  background: '#1a1a2e',
                  border: '1px solid #222',
                }} />
              );
            }

            return (
              <div
                key={col}
                onClick={() => onCellSelect(pos)}
                style={{
                  width: CELL_SIZE,
                  height: CELL_SIZE,
                  background: isSelected ? '#3a3a6a' : '#2a2a4a',
                  border: `2px solid ${isSelected ? '#88aaff' : ROLE_COLORS[cell.role]}`,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  position: 'relative',
                  fontSize: '9px',
                  color: '#fff',
                  fontWeight: 600,
                }}
              >
                {getStageSuffix(cell.stageName)}
                {/* Badges */}
                {isStart && <div style={{ position: 'absolute', top: 1, left: 1, width: 6, height: 6, background: '#66aaff', borderRadius: '50%' }} />}
                {isEnd && <div style={{ position: 'absolute', top: 1, left: 1, width: 6, height: 6, background: '#ffaa66', borderRadius: '50%' }} />}
                {hasKey && <div style={{ position: 'absolute', top: 1, right: 1, width: 6, height: 6, background: hasKeyPosition ? '#88ff88' : '#ff66aa', borderRadius: '50%' }} />}
                {isKeyGate && <div style={{ position: 'absolute', bottom: 1, right: 1, width: 6, height: 6, background: '#ff66ff', borderRadius: 1 }} />}
                {hasObjects && <div style={{ position: 'absolute', bottom: 1, left: 1, width: 6, height: 6, background: '#ffaa33', borderRadius: '50%' }} />}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

// ============================================================================
// Enemy ID Picker (dropdown filtered by area)
// ============================================================================

function EnemyIdPicker({ value, areaKey, onChange }: {
  value: string;
  areaKey: string;
  onChange: (id: string) => void;
}) {
  const allEnemies = useEnemyList();
  const [showAll, setShowAll] = useState(false);
  const locationKey = AREA_TO_LOCATION[areaKey] || areaKey;

  const filtered = useMemo(() => {
    if (showAll || !locationKey) return allEnemies;
    return allEnemies.filter(e => e.locations.includes(locationKey));
  }, [allEnemies, locationKey, showAll]);

  if (allEnemies.length === 0) {
    // Fallback to text input while loading
    return (
      <div style={{ marginTop: '4px' }}>
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="enemy_id (e.g. ghowl)"
          onClick={(e) => e.stopPropagation()}
          style={{
            width: '100%', padding: '4px', background: '#111',
            border: '1px solid #444', borderRadius: '3px',
            color: '#fff', fontSize: '11px', fontFamily: 'monospace',
          }}
        />
      </div>
    );
  }

  return (
    <div style={{ marginTop: '4px' }}>
      <select
        value={value}
        onChange={(e) => { e.stopPropagation(); onChange(e.target.value); }}
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', padding: '4px', background: '#111',
          border: '1px solid #444', borderRadius: '3px',
          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
        }}
      >
        <option value="">-- select enemy --</option>
        {filtered.map(e => (
          <option key={e.id} value={e.id}>
            {e.name} ({e.id}) [{e.element}]{e.is_boss ? ' BOSS' : ''}{e.is_rare ? ' RARE' : ''}
          </option>
        ))}
      </select>
      <div style={{ marginTop: '2px' }}>
        <label style={{ fontSize: '9px', color: '#666', cursor: 'pointer' }} onClick={(e) => e.stopPropagation()}>
          <input
            type="checkbox"
            checked={showAll}
            onChange={(e) => { e.stopPropagation(); setShowAll(e.target.checked); }}
            style={{ marginRight: '4px' }}
          />
          Show all enemies ({allEnemies.length})
        </label>
      </div>
    </div>
  );
}

// ============================================================================
// Cell Content Inspector (right panel)
// ============================================================================

function CellContentInspector({
  project,
  selectedCell,
  placingKey,
  onTogglePlaceKey,
  onClearKeyPosition,
  onSetKeyPosition,
  placingObject,
  onSetPlacingObject,
  selectedObjectId,
  onSelectObject,
  onDeleteObject,
  onUpdateObject,
}: {
  project: QuestProject;
  selectedCell: string;
  placingKey: boolean;
  onTogglePlaceKey: () => void;
  onClearKeyPosition: () => void;
  onSetKeyPosition: (pos: [number, number, number]) => void;
  placingObject: CellObjectType | null;
  onSetPlacingObject: (type: CellObjectType | null) => void;
  selectedObjectId: string | null;
  onSelectObject: (id: string | null) => void;
  onDeleteObject: (id: string) => void;
  onUpdateObject: (id: string, updates: Partial<CellObject>) => void;
}) {
  const cell = project.cells[selectedCell];
  if (!cell) {
    return (
      <div style={{ padding: '1rem', color: '#888' }}>
        <div style={labelStyle}>Empty Cell</div>
        <p style={{ fontSize: '13px' }}>Select an occupied cell from the grid.</p>
      </div>
    );
  }

  const config = getStageConfig(cell.stageName);
  const gates = getRotatedGates(cell.stageName, cell.rotation ?? 0);
  const isStart = project.startPos === selectedCell;
  const isEnd = project.endPos === selectedCell;
  const hasKey = Object.values(project.keyLinks).includes(selectedCell);
  const isKeyGate = selectedCell in project.keyLinks;
  const keyPos = cell.keyPosition;

  return (
    <div style={{ padding: '1rem', overflowY: 'auto', maxHeight: 'calc(100vh - 200px)' }}>
      {/* Header */}
      <div style={sectionStyle}>
        <div style={{ fontSize: '16px', fontWeight: 700, color: '#fff', marginBottom: '4px' }}>
          {getStageSuffix(cell.stageName)}
        </div>
        <div style={{ fontSize: '11px', color: '#888' }}>
          {cell.stageName} at {selectedCell}
        </div>
        <div style={{ display: 'flex', gap: '6px', marginTop: '6px', flexWrap: 'wrap' }}>
          {isStart && <span style={badgeStyle('#66aaff')}>START</span>}
          {isEnd && <span style={badgeStyle('#ffaa66')}>END</span>}
          {hasKey && <span style={badgeStyle('#ff66aa')}>KEY</span>}
          {isKeyGate && <span style={badgeStyle('#ff66ff')}>GATE</span>}
          <span style={badgeStyle(ROLE_COLORS[cell.role])}>{cell.role.toUpperCase()}</span>
        </div>
      </div>

      {/* Gate info */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Gates ({gates.size})</div>
        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
          {(['north', 'south', 'east', 'west'] as Direction[]).map(dir => {
            const hasGate = gates.has(dir);
            const isLocked = cell.lockedGate === dir;
            return (
              <div key={dir} style={{
                padding: '3px 8px',
                background: isLocked ? '#ff66ff33' : hasGate ? '#00ffff22' : '#222',
                border: `1px solid ${isLocked ? '#ff66ff' : hasGate ? '#00ffff' : '#333'}`,
                borderRadius: '4px',
                fontSize: '10px',
                color: isLocked ? '#ff66ff' : hasGate ? '#00ffff' : '#555',
                fontWeight: 600,
              }}>
                {dir[0].toUpperCase()}
                {isLocked && ' locked'}
              </div>
            );
          })}
        </div>
        {config && (
          <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
            Grid: {config.gridSize} | Offset: [{config.gridOffset.join(', ')}]
          </div>
        )}
      </div>

      {/* Key placement */}
      {hasKey && (
        <div style={sectionStyle}>
          <div style={labelStyle}>Key Position</div>
          {keyPos ? (
            <>
              <div style={{
                padding: '8px',
                background: '#88ff8822',
                border: '1px solid #88ff88',
                borderRadius: '4px',
                fontSize: '12px',
                color: '#88ff88',
                fontFamily: 'monospace',
                marginBottom: '8px',
              }}>
                [{keyPos[0]}, {keyPos[1]}, {keyPos[2]}]
              </div>
              <div style={{ display: 'flex', gap: '6px' }}>
                <button
                  onClick={onTogglePlaceKey}
                  style={{
                    ...btnStyle,
                    background: placingKey ? '#ff66aa' : '#555588',
                  }}
                >
                  {placingKey ? 'Placing...' : 'Reposition'}
                </button>
                <button
                  onClick={onClearKeyPosition}
                  style={{ ...btnStyle, background: '#884444' }}
                >
                  Clear
                </button>
              </div>
            </>
          ) : (
            <>
              <div style={{ fontSize: '12px', color: '#ff8888', marginBottom: '8px' }}>
                No position set. Click the 3D view to place the key.
              </div>
              <button
                onClick={onTogglePlaceKey}
                style={{
                  ...btnStyle,
                  background: placingKey ? '#ff66aa' : '#448844',
                  width: '100%',
                }}
              >
                {placingKey ? 'Click 3D view to place...' : 'Place Key'}
              </button>
            </>
          )}
          <div style={{ fontSize: '10px', color: '#888', marginTop: '6px' }}>
            Unlocks: {Object.entries(project.keyLinks).find(([_, v]) => v === selectedCell)?.[0] || 'unlinked'}
          </div>
        </div>
      )}

      {/* Key-gate info */}
      {isKeyGate && (
        <div style={sectionStyle}>
          <div style={labelStyle}>Key-Gate</div>
          <div style={{ fontSize: '12px', color: '#cc88ff' }}>
            Locked gate: {cell.lockedGate || 'not set'}
          </div>
          <div style={{ fontSize: '12px', color: '#cc88ff', marginTop: '2px' }}>
            Key at: {project.keyLinks[selectedCell] || 'unlinked'}
          </div>
        </div>
      )}

      {/* Spawn points from config */}
      {config && config.spawnPoints.length > 0 && (
        <div style={sectionStyle}>
          <div style={labelStyle}>Spawn Points</div>
          {config.spawnPoints.map((sp, i) => (
            <div key={i} style={{ fontSize: '11px', color: '#88ff88', fontFamily: 'monospace', marginBottom: '2px' }}>
              {sp.label}: [{sp.position.map(v => v.toFixed(0)).join(', ')}]
            </div>
          ))}
        </div>
      )}

      {/* Objects */}
      <div style={sectionStyle}>
        <div style={labelStyle}>Objects ({cell.objects?.length || 0})</div>

        {/* Object palette */}
        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginBottom: '8px' }}>
          {(['box', 'rare_box', 'enemy', 'fence', 'step_switch', 'message', 'story_prop', 'dialog_trigger', 'npc', 'telepipe'] as CellObjectType[]).map(type => (
            <button
              key={type}
              onClick={() => onSetPlacingObject(placingObject === type ? null : type)}
              style={{
                ...btnStyle,
                padding: '4px 8px',
                fontSize: '10px',
                background: placingObject === type ? CELL_OBJECT_COLORS[type] : '#2a2a4a',
                border: `1px solid ${CELL_OBJECT_COLORS[type]}`,
                color: placingObject === type ? '#fff' : CELL_OBJECT_COLORS[type],
              }}
            >
              + {CELL_OBJECT_LABELS[type]}
            </button>
          ))}
        </div>

        {placingObject && (
          <div style={{ fontSize: '11px', color: CELL_OBJECT_COLORS[placingObject], marginBottom: '8px' }}>
            Click in 3D view to place {CELL_OBJECT_LABELS[placingObject]}
          </div>
        )}

        {/* Object list */}
        {cell.objects && cell.objects.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
            {cell.objects.map(obj => {
              const isSel = selectedObjectId === obj.id;
              return (
                <div
                  key={obj.id}
                  onClick={() => onSelectObject(isSel ? null : obj.id)}
                  style={{
                    padding: '6px 8px',
                    background: isSel ? '#3a3a6a' : '#222',
                    border: `1px solid ${isSel ? '#88aaff' : CELL_OBJECT_COLORS[obj.type]}`,
                    borderRadius: '4px',
                    cursor: 'pointer',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: '11px', color: CELL_OBJECT_COLORS[obj.type], fontWeight: 600 }}>
                      {CELL_OBJECT_LABELS[obj.type]}
                    </span>
                    <button
                      onClick={(e) => { e.stopPropagation(); onDeleteObject(obj.id); }}
                      style={{ ...btnStyle, padding: '2px 6px', fontSize: '9px', background: '#884444' }}
                    >
                      DEL
                    </button>
                  </div>
                  <div style={{ fontSize: '10px', color: '#888', fontFamily: 'monospace', marginTop: '2px' }}>
                    [{obj.position[0]}, {obj.position[1]}, {obj.position[2]}]
                  </div>

                  {/* Enemy ID picker */}
                  {isSel && obj.type === 'enemy' && (
                    <EnemyIdPicker
                      value={obj.enemy_id || ''}
                      areaKey={project.areaKey}
                      onChange={(val) => onUpdateObject(obj.id, { enemy_id: val || undefined })}
                    />
                  )}

                  {/* Wave number for enemies */}
                  {isSel && obj.type === 'enemy' && (
                    <div style={{ marginTop: '4px', display: 'flex', gap: '4px', alignItems: 'center' }}>
                      <span style={{ fontSize: '10px', color: '#888' }}>Wave:</span>
                      {[1, 2, 3].map(w => (
                        <button
                          key={w}
                          onClick={(e) => { e.stopPropagation(); onUpdateObject(obj.id, { wave: w === 1 ? undefined : w }); }}
                          style={{
                            ...btnStyle, padding: '2px 6px', fontSize: '9px',
                            background: (obj.wave || 1) === w ? '#cc4444' : '#333',
                          }}
                        >
                          {w}
                        </button>
                      ))}
                    </div>
                  )}

                  {/* Message text */}
                  {isSel && obj.type === 'message' && (
                    <div style={{ marginTop: '4px' }}>
                      <textarea
                        value={obj.text || ''}
                        onChange={(e) => onUpdateObject(obj.id, { text: e.target.value || undefined })}
                        placeholder="Message text..."
                        onClick={(e) => e.stopPropagation()}
                        rows={3}
                        style={{
                          width: '100%', padding: '4px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                          resize: 'vertical',
                        }}
                      />
                    </div>
                  )}

                  {/* Link ID for fences and switches */}
                  {isSel && (obj.type === 'fence' || obj.type === 'step_switch') && (
                    <div style={{ marginTop: '4px' }}>
                      <input
                        type="text"
                        value={obj.link_id || ''}
                        onChange={(e) => onUpdateObject(obj.id, { link_id: e.target.value || undefined })}
                        placeholder="link_id (e.g. a)"
                        onClick={(e) => e.stopPropagation()}
                        style={{
                          width: '100%', padding: '4px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                        }}
                      />
                    </div>
                  )}

                  {/* Rotation for fences */}
                  {isSel && obj.type === 'fence' && (
                    <div style={{ marginTop: '4px', display: 'flex', gap: '4px', alignItems: 'center' }}>
                      <span style={{ fontSize: '10px', color: '#888' }}>Rot:</span>
                      {[0, 90].map(deg => (
                        <button
                          key={deg}
                          onClick={(e) => { e.stopPropagation(); onUpdateObject(obj.id, { rotation: deg || undefined }); }}
                          style={{
                            ...btnStyle, padding: '2px 6px', fontSize: '9px',
                            background: (obj.rotation || 0) === deg ? '#4488cc' : '#333',
                          }}
                        >
                          {deg}&deg;
                        </button>
                      ))}
                    </div>
                  )}

                  {/* Story prop editor */}
                  {isSel && obj.type === 'story_prop' && (
                    <div style={{ marginTop: '4px' }} onClick={(e) => e.stopPropagation()}>
                      <span style={{ fontSize: '10px', color: '#888' }}>Prop GLB:</span>
                      <select
                        value={obj.prop_path || ''}
                        onChange={(e) => onUpdateObject(obj.id, { prop_path: e.target.value || undefined })}
                        style={{
                          width: '100%', padding: '3px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                          marginBottom: '2px',
                        }}
                      >
                        <option value="">-- select prop --</option>
                        <option value="assets/objects/story/dropship_crash.glb">Dropship (crashed)</option>
                      </select>
                      <input
                        type="text"
                        value={obj.prop_path || ''}
                        onChange={(e) => onUpdateObject(obj.id, { prop_path: e.target.value || undefined })}
                        placeholder="Or type custom path..."
                        style={{
                          width: '100%', padding: '4px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                          marginBottom: '4px',
                        }}
                      />
                      <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Rot:</span>
                        {[0, 90, 180, 270].map(deg => (
                          <button
                            key={deg}
                            onClick={() => onUpdateObject(obj.id, { rotation: deg || undefined })}
                            style={{
                              ...btnStyle, padding: '2px 5px', fontSize: '9px',
                              background: (obj.rotation || 0) === deg ? '#cccc44' : '#333',
                            }}
                          >
                            {deg}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Dialog trigger editor */}
                  {isSel && obj.type === 'dialog_trigger' && (
                    <div style={{ marginTop: '4px' }} onClick={(e) => e.stopPropagation()}>
                      <input
                        type="text"
                        value={obj.trigger_id || ''}
                        onChange={(e) => onUpdateObject(obj.id, { trigger_id: e.target.value || undefined })}
                        placeholder="trigger_id (e.g. post_battle)"
                        style={{
                          width: '100%', padding: '4px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                          marginBottom: '4px',
                        }}
                      />
                      <div style={{ marginBottom: '4px' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Size (X / Y / Z):</span>
                        <div style={{ display: 'flex', gap: '4px', marginTop: '2px' }}>
                          {[0, 1, 2].map(axis => (
                            <input
                              key={axis}
                              type="number"
                              step={0.5}
                              value={obj.trigger_size ? obj.trigger_size[axis] : [4, 3, 4][axis]}
                              onChange={(e) => {
                                const cur = obj.trigger_size ? [...obj.trigger_size] : [4, 3, 4];
                                cur[axis] = parseFloat(e.target.value) || 0;
                                const isDefault = cur[0] === 4 && cur[1] === 3 && cur[2] === 4;
                                onUpdateObject(obj.id, { trigger_size: isDefault ? undefined : cur as [number, number, number] });
                              }}
                              onClick={(e) => e.stopPropagation()}
                              style={{
                                flex: 1, padding: '3px', background: '#111',
                                border: '1px solid #444', borderRadius: '3px',
                                color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                                textAlign: 'center', width: '50px',
                              }}
                            />
                          ))}
                        </div>
                      </div>
                      <div style={{ marginBottom: '4px' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Condition:</span>
                        <div style={{ display: 'flex', gap: '4px', marginTop: '2px' }}>
                          {(['enter', 'room_clear'] as const).map(cond => (
                            <button
                              key={cond}
                              onClick={() => onUpdateObject(obj.id, { trigger_condition: cond })}
                              style={{
                                ...btnStyle, padding: '2px 8px', fontSize: '9px',
                                background: (obj.trigger_condition || 'enter') === cond ? '#44cccc' : '#333',
                              }}
                            >
                              {cond}
                            </button>
                          ))}
                        </div>
                      </div>
                      <div style={{ marginBottom: '4px' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Actions:</span>
                        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginTop: '2px' }}>
                          {['complete_quest', 'telepipe'].map(action => {
                            const active = (obj.actions || []).includes(action);
                            return (
                              <button
                                key={action}
                                onClick={() => {
                                  const current = obj.actions || [];
                                  const updated = active ? current.filter(a => a !== action) : [...current, action];
                                  onUpdateObject(obj.id, { actions: updated });
                                }}
                                style={{
                                  ...btnStyle, padding: '2px 8px', fontSize: '9px',
                                  background: active ? '#44cccc' : '#333',
                                  border: `1px solid ${active ? '#44cccc' : '#555'}`,
                                }}
                              >
                                {action}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    </div>
                  )}

                  {/* NPC editor */}
                  {isSel && obj.type === 'npc' && (
                    <div style={{ marginTop: '4px', display: 'flex', flexDirection: 'column', gap: '4px' }} onClick={(e) => e.stopPropagation()}>
                      <div>
                        <span style={{ fontSize: '10px', color: '#888' }}>NPC Model:</span>
                        <select
                          value={obj.npc_id || ''}
                          onChange={(e) => onUpdateObject(obj.id, { npc_id: e.target.value || undefined })}
                          style={{
                            width: '100%', padding: '3px', background: '#111',
                            border: '1px solid #444', borderRadius: '3px',
                            color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                          }}
                        >
                          <option value="">-- select --</option>
                          <option value="kai">Kai</option>
                          <option value="sarisa">Sarisa</option>
                        </select>
                      </div>
                      <input
                        type="text"
                        value={obj.npc_name || ''}
                        onChange={(e) => onUpdateObject(obj.id, { npc_name: e.target.value || undefined })}
                        placeholder="Display name (e.g. Sarisa)"
                        style={{
                          width: '100%', padding: '4px', background: '#111',
                          border: '1px solid #444', borderRadius: '3px',
                          color: '#fff', fontSize: '11px', fontFamily: 'monospace',
                        }}
                      />
                      <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Rot:</span>
                        {[0, 90, 180, 270].map(deg => (
                          <button
                            key={deg}
                            onClick={() => onUpdateObject(obj.id, { rotation: deg || undefined })}
                            style={{
                              ...btnStyle, padding: '2px 5px', fontSize: '9px',
                              background: (obj.rotation || 0) === deg ? '#44cc44' : '#333',
                            }}
                          >
                            {deg}
                          </button>
                        ))}
                      </div>
                      <div style={{ display: 'flex', gap: '4px', alignItems: 'center', marginTop: '4px' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Anim:</span>
                        <input
                          type="text"
                          value={obj.animation || ''}
                          onChange={(e) => onUpdateObject(obj.id, { animation: e.target.value || undefined })}
                          placeholder="e.g. dam_h"
                          style={{
                            flex: 1, padding: '3px', background: '#111',
                            border: '1px solid #444', borderRadius: '3px',
                            color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                          }}
                        />
                        <span style={{ fontSize: '10px', color: '#888' }}>Frame:</span>
                        <input
                          type="number"
                          min={0}
                          value={obj.animation_frame ?? ''}
                          onChange={(e) => {
                            const v = e.target.value;
                            onUpdateObject(obj.id, { animation_frame: v === '' ? undefined : parseInt(v) });
                          }}
                          style={{
                            width: '40px', padding: '3px', background: '#111',
                            border: '1px solid #444', borderRadius: '3px',
                            color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                            textAlign: 'center',
                          }}
                        />
                      </div>
                    </div>
                  )}

                  {/* Telepipe spawn condition */}
                  {isSel && obj.type === 'telepipe' && (
                    <div style={{ marginTop: '4px' }}>
                      <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                        <span style={{ fontSize: '10px', color: '#888', minWidth: '60px' }}>Spawn</span>
                        <select
                          value={obj.spawn_condition || 'immediate'}
                          onChange={(e) => onUpdateObject(obj.id, { spawn_condition: e.target.value as 'immediate' | 'room_clear' })}
                          style={{
                            flex: 1, padding: '2px 4px', background: '#111',
                            border: '1px solid #444', borderRadius: '2px',
                            color: '#fff', fontSize: '10px',
                          }}
                        >
                          <option value="immediate">Immediate</option>
                          <option value="room_clear">After Room Clear</option>
                        </select>
                      </div>
                    </div>
                  )}

                  {/* Dialog editor for dialog_trigger and npc */}
                  {isSel && (obj.type === 'dialog_trigger' || obj.type === 'npc') && (
                    <div style={{ marginTop: '4px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                        <span style={{ fontSize: '10px', color: '#888' }}>Dialog ({obj.dialog?.length || 0} pages)</span>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            const pages = [...(obj.dialog || []), { speaker: '', text: '' }];
                            onUpdateObject(obj.id, { dialog: pages });
                          }}
                          style={{ ...btnStyle, padding: '2px 6px', fontSize: '9px', background: '#448844' }}
                        >
                          + Page
                        </button>
                      </div>
                      {obj.dialog?.map((page, pi) => (
                        <div key={pi} style={{
                          padding: '4px', background: '#1a1a2e',
                          border: '1px solid #333', borderRadius: '3px',
                          marginBottom: '4px',
                        }}>
                          <div style={{ display: 'flex', gap: '4px', marginBottom: '2px' }}>
                            <input
                              type="text"
                              value={page.speaker}
                              onChange={(e) => {
                                const pages = [...(obj.dialog || [])];
                                pages[pi] = { ...pages[pi], speaker: e.target.value };
                                onUpdateObject(obj.id, { dialog: pages });
                              }}
                              placeholder="Speaker"
                              onClick={(e) => e.stopPropagation()}
                              style={{
                                flex: 1, padding: '2px 4px', background: '#111',
                                border: '1px solid #444', borderRadius: '2px',
                                color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                              }}
                            />
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                const pages = (obj.dialog || []).filter((_, i) => i !== pi);
                                onUpdateObject(obj.id, { dialog: pages.length > 0 ? pages : undefined });
                              }}
                              style={{ ...btnStyle, padding: '2px 4px', fontSize: '9px', background: '#884444' }}
                            >
                              X
                            </button>
                          </div>
                          <textarea
                            value={page.text}
                            onChange={(e) => {
                              const pages = [...(obj.dialog || [])];
                              pages[pi] = { ...pages[pi], text: e.target.value };
                              onUpdateObject(obj.id, { dialog: pages });
                            }}
                            placeholder="Dialog text..."
                            onClick={(e) => e.stopPropagation()}
                            rows={2}
                            style={{
                              width: '100%', padding: '2px 4px', background: '#111',
                              border: '1px solid #444', borderRadius: '2px',
                              color: '#fff', fontSize: '10px', fontFamily: 'monospace',
                              resize: 'vertical',
                            }}
                          />
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Notes */}
      {cell.notes && (
        <div style={sectionStyle}>
          <div style={labelStyle}>Notes</div>
          <div style={{ fontSize: '12px', color: '#aaa', fontStyle: 'italic' }}>
            {cell.notes}
          </div>
        </div>
      )}
    </div>
  );
}

const labelStyle: React.CSSProperties = {
  fontSize: '11px',
  color: '#888',
  textTransform: 'uppercase',
  letterSpacing: '0.5px',
  marginBottom: '6px',
};

const sectionStyle: React.CSSProperties = {
  marginBottom: '16px',
};

const btnStyle: React.CSSProperties = {
  padding: '6px 12px',
  border: 'none',
  borderRadius: '4px',
  color: '#fff',
  fontSize: '11px',
  cursor: 'pointer',
};

function badgeStyle(color: string): React.CSSProperties {
  return {
    padding: '2px 6px',
    background: color + '33',
    border: `1px solid ${color}`,
    borderRadius: '3px',
    fontSize: '9px',
    fontWeight: 700,
    color,
  };
}

// ============================================================================
// Main ContentTab
// ============================================================================

export default function ContentTab({ project, onUpdateProject }: ContentTabProps) {
  const [selectedCell, setSelectedCell] = useState<string | null>(null);
  const [placingKey, setPlacingKey] = useState(false);
  const [placingObject, setPlacingObject] = useState<CellObjectType | null>(null);
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);

  const cell = selectedCell ? project.cells[selectedCell] : null;
  const config = cell ? getStageConfig(cell.stageName) : null;
  const hasKey = selectedCell ? Object.values(project.keyLinks).includes(selectedCell) : false;

  const handlePlaceKey = useCallback((pos: [number, number, number]) => {
    if (!selectedCell) return;
    onUpdateProject(prev => ({
      ...prev,
      cells: {
        ...prev.cells,
        [selectedCell]: { ...prev.cells[selectedCell], keyPosition: pos },
      },
    }));
    setPlacingKey(false);
  }, [selectedCell, onUpdateProject]);

  const handleClearKeyPosition = useCallback(() => {
    if (!selectedCell) return;
    onUpdateProject(prev => {
      const updated = { ...prev.cells[selectedCell] };
      delete updated.keyPosition;
      return {
        ...prev,
        cells: { ...prev.cells, [selectedCell]: updated },
      };
    });
  }, [selectedCell, onUpdateProject]);

  const handleTogglePlaceKey = useCallback(() => {
    setPlacingKey(p => !p);
    setPlacingObject(null);
  }, []);

  const handleSetPlacingObject = useCallback((type: CellObjectType | null) => {
    setPlacingObject(type);
    setPlacingKey(false);
  }, []);

  const handlePlaceObject = useCallback((pos: [number, number, number]) => {
    if (!selectedCell || !placingObject) return;
    onUpdateProject(prev => {
      const cellData = prev.cells[selectedCell];
      const objects = [...(cellData.objects || [])];
      const typeCount = objects.filter(o => o.type === placingObject).length;
      const newObj: CellObject = {
        id: `${placingObject}_${typeCount}`,
        type: placingObject,
        position: pos,
      };
      if (placingObject === 'enemy') newObj.enemy_id = 'lizard';
      if (placingObject === 'message') newObj.text = '';
      if (placingObject === 'story_prop') newObj.prop_path = '';
      if (placingObject === 'dialog_trigger') { newObj.trigger_id = ''; newObj.trigger_condition = 'enter'; newObj.dialog = []; newObj.actions = []; }
      if (placingObject === 'npc') { newObj.npc_id = ''; newObj.npc_name = ''; newObj.dialog = []; }
      return {
        ...prev,
        cells: {
          ...prev.cells,
          [selectedCell]: { ...cellData, objects: [...objects, newObj] },
        },
      };
    });
  }, [selectedCell, placingObject, onUpdateProject]);

  const handleDeleteObject = useCallback((objId: string) => {
    if (!selectedCell) return;
    onUpdateProject(prev => {
      const cellData = prev.cells[selectedCell];
      return {
        ...prev,
        cells: {
          ...prev.cells,
          [selectedCell]: {
            ...cellData,
            objects: (cellData.objects || []).filter(o => o.id !== objId),
          },
        },
      };
    });
    if (selectedObjectId === objId) setSelectedObjectId(null);
  }, [selectedCell, selectedObjectId, onUpdateProject]);

  const handleUpdateObject = useCallback((objId: string, updates: Partial<CellObject>) => {
    if (!selectedCell) return;
    onUpdateProject(prev => {
      const cellData = prev.cells[selectedCell];
      return {
        ...prev,
        cells: {
          ...prev.cells,
          [selectedCell]: {
            ...cellData,
            objects: (cellData.objects || []).map(o =>
              o.id === objId ? { ...o, ...updates } : o
            ),
          },
        },
      };
    });
  }, [selectedCell, onUpdateProject]);

  // Select first cell with a key if none selected
  const handleCellSelect = useCallback((pos: string) => {
    setSelectedCell(pos);
    setPlacingKey(false);
    setPlacingObject(null);
    setSelectedObjectId(null);
  }, []);

  return (
    <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
      {/* Left panel — Mini grid */}
      <div style={{
        width: '260px',
        borderRight: '1px solid #333',
        background: '#151525',
        padding: '12px',
        overflowY: 'auto',
        display: 'flex',
        flexDirection: 'column',
        gap: '12px',
      }}>
        <div style={{ fontSize: '11px', color: '#888', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
          Select Cell
        </div>
        <MiniGrid
          project={project}
          selectedCell={selectedCell}
          onCellSelect={handleCellSelect}
        />
        <div style={{ fontSize: '11px', color: '#666', lineHeight: 1.5 }}>
          <div><span style={{ display: 'inline-block', width: 8, height: 8, background: '#ff66aa', borderRadius: '50%', marginRight: 4 }} />Key (no position)</div>
          <div><span style={{ display: 'inline-block', width: 8, height: 8, background: '#88ff88', borderRadius: '50%', marginRight: 4 }} />Key (placed)</div>
          <div><span style={{ display: 'inline-block', width: 8, height: 8, background: '#ff66ff', borderRadius: 1, marginRight: 4 }} />Key-Gate</div>
        </div>
      </div>

      {/* Center — 3D preview */}
      <div style={{ flex: 1, position: 'relative', background: '#1a1a2e' }}>
        {cell ? (
          <>
            <Canvas
              camera={{ position: [0, 40, 40], fov: 50 }}
            >
              <color attach="background" args={['#1a1a2e']} />
              <ambientLight intensity={0.6} />
              <directionalLight position={[10, 20, 10]} intensity={0.8} />

              <Suspense fallback={null}>
                <StageModel mapId={cell.stageName} />
              </Suspense>

              {/* Ground grid */}
              <Grid
                args={[100, 100]}
                position={[0, 0.01, 0]}
                cellSize={1}
                cellThickness={0.5}
                cellColor="#333"
                sectionSize={10}
                sectionThickness={1}
                sectionColor="#555"
                fadeDistance={100}
                fadeStrength={1}
              />

              {/* Gate markers */}
              {config?.gates.map((gate, i) => (
                <GateMarker
                  key={i}
                  gate={gate}
                  isLocked={cell.lockedGate === gate.edge}
                />
              ))}

              {/* Spawn points */}
              {config?.spawnPoints.map((sp, i) => (
                <SpawnMarker
                  key={i}
                  position={sp.position}
                  edge={config.gates[i]?.edge || 'north'}
                />
              ))}

              {/* Key marker (if this cell has a key with authored position) */}
              {hasKey && cell.keyPosition && !placingKey && (
                <KeyMarker position={cell.keyPosition} />
              )}

              {/* Object markers */}
              {cell.objects?.map(obj => (
                <ObjectMarker
                  key={obj.id}
                  obj={obj}
                  selected={selectedObjectId === obj.id}
                  onClick={() => setSelectedObjectId(prev => prev === obj.id ? null : obj.id)}
                />
              ))}

              {/* Key placement mode */}
              {placingKey && (
                <>
                  <KeyPlacementCursor />
                  <GroundClickPlane onPlace={handlePlaceKey} />
                </>
              )}

              {/* Object placement mode */}
              {placingObject && (
                <>
                  <ObjectPlacementCursor objectType={placingObject} />
                  <ObjectClickPlane onPlace={handlePlaceObject} />
                </>
              )}

              <OrbitControls makeDefault />
            </Canvas>

            {/* Overlay info */}
            <div style={{
              position: 'absolute', top: 12, left: 12,
              background: 'rgba(0,0,0,0.7)', padding: '8px 12px',
              borderRadius: '6px', fontSize: '12px', color: '#fff',
            }}>
              {cell.stageName}
              {(cell.rotation ?? 0) !== 0 && ` (rotated ${cell.rotation}deg)`}
            </div>

            {placingKey && (
              <div style={{
                position: 'absolute', bottom: 12, left: '50%', transform: 'translateX(-50%)',
                background: '#ff66aa', padding: '8px 20px',
                borderRadius: '20px', fontSize: '13px', color: '#fff', fontWeight: 600,
                cursor: 'pointer',
              }}
              onClick={() => setPlacingKey(false)}
              >
                Click in 3D view to place key | ESC to cancel
              </div>
            )}

            {placingObject && (
              <div style={{
                position: 'absolute', bottom: 12, left: '50%', transform: 'translateX(-50%)',
                background: CELL_OBJECT_COLORS[placingObject], padding: '8px 20px',
                borderRadius: '20px', fontSize: '13px', color: '#fff', fontWeight: 600,
                cursor: 'pointer',
              }}
              onClick={() => setPlacingObject(null)}
              >
                Click to place {CELL_OBJECT_LABELS[placingObject]} | Click here to cancel
              </div>
            )}
          </>
        ) : (
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            height: '100%', color: '#666', fontSize: '14px',
            flexDirection: 'column', gap: '8px',
          }}>
            <div style={{ fontSize: '32px', opacity: 0.3 }}>3D</div>
            <div>Select a cell to preview its stage</div>
          </div>
        )}
      </div>

      {/* Right panel — Inspector */}
      <div style={{
        width: '260px',
        borderLeft: '1px solid #333',
        background: '#151525',
        overflowY: 'auto',
      }}>
        {selectedCell ? (
          <CellContentInspector
            project={project}
            selectedCell={selectedCell}
            placingKey={placingKey}
            onTogglePlaceKey={handleTogglePlaceKey}
            onClearKeyPosition={handleClearKeyPosition}
            onSetKeyPosition={handlePlaceKey}
            placingObject={placingObject}
            onSetPlacingObject={handleSetPlacingObject}
            selectedObjectId={selectedObjectId}
            onSelectObject={setSelectedObjectId}
            onDeleteObject={handleDeleteObject}
            onUpdateObject={handleUpdateObject}
          />
        ) : (
          <div style={{ padding: '1rem', color: '#888', fontSize: '13px' }}>
            Select a cell from the grid to inspect and edit its content.
          </div>
        )}
      </div>
    </div>
  );
}

