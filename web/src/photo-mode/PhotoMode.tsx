import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, useGLTF } from '@react-three/drei';
import { Suspense, useState, useEffect, useRef, useCallback, useMemo } from 'react';
import * as THREE from 'three';
import * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
import { assetUrl } from '../utils/assets';
import { STAGE_AREAS, getGlbPath, getAreaFromMapId, getAllMapsForArea } from '../stage-editor/constants';

const NPC_LIST = [
  { id: 'fern', name: 'Fern' },
  { id: 'kai', name: 'Kai' },
  { id: 'sarisa', name: 'Sarisa' },
  { id: 'dorn', name: 'Dorn' },
  { id: 'elio', name: 'Elio' },
  { id: 'mira', name: 'Mira' },
  { id: 'ren', name: 'Ren' },
  { id: 'vash', name: 'Vash' },
  { id: 'dr_carlo', name: 'Dr. Carlo' },
  { id: 'principal', name: 'Principal' },
];

const BONE_GROUPS: { label: string; bones: { name: string; label: string }[] }[] = [
  { label: 'Body', bones: [
    { name: '000_Root', label: 'Root' },
    { name: '010_Hip', label: 'Hip' },
    { name: '020_Spine', label: 'Spine' },
    { name: '090_Head', label: 'Head' },
  ]},
  { label: 'Left Arm', bones: [
    { name: '030_LArm01', label: 'Upper' },
    { name: '040_LArm02', label: 'Lower' },
  ]},
  { label: 'Right Arm', bones: [
    { name: '060_RArm01', label: 'Upper' },
    { name: '070_RArm02', label: 'Lower' },
  ]},
  { label: 'Left Leg', bones: [
    { name: '100_LLeg01', label: 'Upper' },
    { name: '110_LLeg02', label: 'Lower' },
  ]},
  { label: 'Right Leg', bones: [
    { name: '120_RLeg01', label: 'Upper' },
    { name: '130_RLeg02', label: 'Lower' },
  ]},
];

const LIGHTING_PRESETS: Record<string, { name: string; ambient: [number, number, number]; ambientIntensity: number; sunColor: [number, number, number]; sunIntensity: number; sunPitch: number; bg: string }> = {
  day: { name: 'Day', ambient: [0.9, 0.92, 0.88], ambientIntensity: 1.1, sunColor: [1, 0.98, 0.9], sunIntensity: 0.5, sunPitch: -45, bg: '#87CEEB' },
  sunset: { name: 'Sunset', ambient: [0.85, 0.5, 0.2], ambientIntensity: 0.55, sunColor: [1, 0.6, 0.2], sunIntensity: 0.7, sunPitch: -12, bg: '#E8734A' },
  night: { name: 'Night', ambient: [0.2, 0.25, 0.45], ambientIntensity: 0.5, sunColor: [0.4, 0.5, 0.8], sunIntensity: 0.25, sunPitch: -30, bg: '#1a1a3e' },
  studio: { name: 'Studio', ambient: [1, 1, 1], ambientIntensity: 0.8, sunColor: [1, 1, 1], sunIntensity: 0.6, sunPitch: -45, bg: '#2a2a2a' },
};

const PSZ_SCALE = 0.09;

type BonePoses = Record<string, [number, number, number]>;

function convertToLit(root: THREE.Object3D) {
  root.traverse((obj) => {
    if (!(obj as THREE.Mesh).isMesh) return;
    const mesh = obj as THREE.Mesh;
    if (mesh.geometry && !mesh.geometry.getAttribute('normal')) {
      mesh.geometry.computeVertexNormals();
    }
    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const converted = materials.map((mat) => {
      if (mat instanceof THREE.MeshBasicMaterial) {
        const lambert = new THREE.MeshLambertMaterial({
          color: mat.color, map: mat.map, transparent: mat.transparent,
          opacity: mat.opacity, side: mat.side, alphaTest: mat.alphaTest,
          vertexColors: mat.vertexColors,
        });
        if (lambert.map) { lambert.map.colorSpace = THREE.SRGBColorSpace; lambert.map.needsUpdate = true; }
        return lambert;
      }
      return mat;
    });
    mesh.material = Array.isArray(mesh.material) ? converted : converted[0];
  });
}

function StageModel({ mapId }: { mapId: string }) {
  const areaKey = getAreaFromMapId(mapId) || 'valley';
  const glbPath = getGlbPath(areaKey, mapId);
  const { scene } = useGLTF(glbPath);
  const convertedRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!scene) return;
    if (!convertedRef.current.has(glbPath)) {
      convertToLit(scene);
      convertedRef.current.add(glbPath);
    }
  }, [scene, glbPath]);

  return <primitive object={scene} />;
}

function NpcModel({ npcId, position, rotation, scale, bonePoses }: {
  npcId: string; position: [number, number, number]; rotation: number; scale: number;
  bonePoses: BonePoses;
}) {
  const glbPath = assetUrl(`assets/npcs/${npcId}/${npcId}.glb`);
  const { scene } = useGLTF(glbPath);
  const groupRef = useRef<THREE.Group>(null);

  const cloned = useMemo(() => {
    const clone = SkeletonUtils.clone(scene);
    clone.traverse((obj) => {
      if (obj instanceof THREE.Mesh) {
        if (obj.geometry) obj.geometry.computeVertexNormals();
        if (obj.material) {
          obj.material = obj.material.clone();
          obj.material.side = THREE.FrontSide;
        }
      }
    });
    convertToLit(clone);
    return clone;
  }, [scene]);

  useEffect(() => {
    cloned.traverse((obj) => {
      if (obj instanceof THREE.Bone) {
        const pose = bonePoses[obj.name];
        if (pose) {
          obj.rotation.set(pose[0], pose[1], pose[2]);
        }
      }
    });
  }, [cloned, bonePoses]);

  return (
    <group ref={groupRef} position={position} rotation={[0, rotation, 0]} scale={[scale, scale, scale]}>
      <primitive object={cloned} />
    </group>
  );
}

function FloorPlane({ onClick }: { onClick: (point: THREE.Vector3) => void }) {
  return (
    <mesh
      rotation={[-Math.PI / 2, 0, 0]}
      position={[0, 0.01, 0]}
      visible={false}
      onClick={(e) => { e.stopPropagation(); onClick(e.point); }}
    >
      <planeGeometry args={[200, 200]} />
      <meshBasicMaterial transparent opacity={0} />
    </mesh>
  );
}

function Screenshot({ onCapture }: { onCapture: () => void }) {
  const { gl, scene, camera } = useThree();
  const capture = useCallback(() => {
    gl.render(scene, camera);
    const dataUrl = gl.domElement.toDataURL('image/png');
    const link = document.createElement('a');
    link.download = 'psz-photo.png';
    link.href = dataUrl;
    link.click();
    onCapture();
  }, [gl, scene, camera, onCapture]);

  useEffect(() => {
    (window as any).__photoCapture = capture;
    return () => { delete (window as any).__photoCapture; };
  }, [capture]);

  return null;
}

function SceneContent({
  mapId, npcs, lighting, placementMode, onFloorClick, captureRequested, onCaptured,
}: {
  mapId: string;
  npcs: PlacedNpc[];
  lighting: string;
  placementMode: boolean;
  onFloorClick: (point: THREE.Vector3) => void;
  captureRequested: boolean;
  onCaptured: () => void;
}) {
  const preset = LIGHTING_PRESETS[lighting] || LIGHTING_PRESETS.day;
  const sunDir = new THREE.Vector3(0.5, Math.sin(preset.sunPitch * Math.PI / 180), -0.8).normalize();

  return (
    <>
      <ambientLight color={new THREE.Color(...preset.ambient)} intensity={preset.ambientIntensity} />
      <directionalLight
        color={new THREE.Color(...preset.sunColor)}
        intensity={preset.sunIntensity}
        position={[sunDir.x * 50, sunDir.y * 50, sunDir.z * 50]}
      />
      <Suspense fallback={null}>
        <StageModel mapId={mapId} />
        {npcs.map((npc) => (
          <NpcModel
            key={npc.id}
            npcId={npc.npcId}
            position={npc.position}
            rotation={npc.rotation}
            scale={npc.scale}
            bonePoses={npc.bonePoses}
          />
        ))}
      </Suspense>
      {placementMode && <FloorPlane onClick={onFloorClick} />}
      <OrbitControls makeDefault />
      {captureRequested && <Screenshot onCapture={onCaptured} />}
    </>
  );
}

interface PlacedNpc {
  id: string;
  npcId: string;
  position: [number, number, number];
  rotation: number;
  scale: number;
  bonePoses: BonePoses;
}

export default function PhotoMode() {
  const [selectedArea, setSelectedArea] = useState('wetlands');
  const [selectedMap, setSelectedMap] = useState('s02e_ia1');
  const [selectedNpc, setSelectedNpc] = useState('fern');
  const [placedNpcs, setPlacedNpcs] = useState<PlacedNpc[]>([]);
  const [selectedPlacedIdx, setSelectedPlacedIdx] = useState<number | null>(null);
  const [placementMode, setPlacementMode] = useState(false);
  const [lighting, setLighting] = useState('day');
  const [captureRequested, setCaptureRequested] = useState(false);
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);

  const availableMaps = useMemo(() => getAllMapsForArea(selectedArea), [selectedArea]);

  useEffect(() => {
    if (availableMaps.length > 0 && !availableMaps.includes(selectedMap)) {
      setSelectedMap(availableMaps[0]);
    }
  }, [availableMaps, selectedMap]);

  const handleFloorClick = useCallback((point: THREE.Vector3) => {
    const newNpc: PlacedNpc = {
      id: `npc_${Date.now()}`,
      npcId: selectedNpc,
      position: [point.x, point.y, point.z],
      rotation: 0,
      scale: PSZ_SCALE,
      bonePoses: {},
    };
    setPlacedNpcs((prev) => [...prev, newNpc]);
    setSelectedPlacedIdx(placedNpcs.length);
    setPlacementMode(false);
  }, [selectedNpc, placedNpcs.length]);

  const updateNpc = useCallback((idx: number, updates: Partial<PlacedNpc>) => {
    setPlacedNpcs((prev) => prev.map((npc, i) => i === idx ? { ...npc, ...updates } : npc));
  }, []);

  const updateBone = useCallback((idx: number, boneName: string, axis: number, value: number) => {
    setPlacedNpcs((prev) => prev.map((npc, i) => {
      if (i !== idx) return npc;
      const current = npc.bonePoses[boneName] || [0, 0, 0];
      const updated: [number, number, number] = [...current] as [number, number, number];
      updated[axis] = value;
      return { ...npc, bonePoses: { ...npc.bonePoses, [boneName]: updated } };
    }));
  }, []);

  const removeNpc = useCallback((idx: number) => {
    setPlacedNpcs((prev) => prev.filter((_, i) => i !== idx));
    setSelectedPlacedIdx(null);
  }, []);

  const resetPose = useCallback((idx: number) => {
    updateNpc(idx, { bonePoses: {} });
  }, [updateNpc]);

  const selectedNpcData = selectedPlacedIdx !== null ? placedNpcs[selectedPlacedIdx] : null;
  const preset = LIGHTING_PRESETS[lighting] || LIGHTING_PRESETS.day;

  return (
    <div style={{ display: 'flex', height: '100vh', background: '#1a1a2e', color: '#e0e0e0' }}>
      {/* Sidebar */}
      <div style={{ width: 300, padding: 16, overflowY: 'auto', borderRight: '1px solid #333', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>Photo Mode</h2>

        {/* Stage Selection */}
        <fieldset style={fieldsetStyle}>
          <legend style={legendStyle}>Stage</legend>
          <select value={selectedArea} onChange={(e) => setSelectedArea(e.target.value)} style={selectStyle}>
            {Object.entries(STAGE_AREAS).map(([key, area]) => (
              <option key={key} value={key}>{area.name}</option>
            ))}
          </select>
          <select value={selectedMap} onChange={(e) => setSelectedMap(e.target.value)} style={{ ...selectStyle, marginTop: 4 }}>
            {availableMaps.map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        </fieldset>

        {/* NPC Placement */}
        <fieldset style={fieldsetStyle}>
          <legend style={legendStyle}>Place NPC</legend>
          <select value={selectedNpc} onChange={(e) => setSelectedNpc(e.target.value)} style={selectStyle}>
            {NPC_LIST.map((npc) => <option key={npc.id} value={npc.id}>{npc.name}</option>)}
          </select>
          <button
            onClick={() => setPlacementMode(!placementMode)}
            style={{ ...buttonStyle, marginTop: 4, background: placementMode ? '#4a9eff' : '#444' }}
          >
            {placementMode ? 'Click stage to place...' : 'Place on Stage'}
          </button>
        </fieldset>

        {/* Placed NPCs */}
        {placedNpcs.length > 0 && (
          <fieldset style={fieldsetStyle}>
            <legend style={legendStyle}>Placed ({placedNpcs.length})</legend>
            {placedNpcs.map((npc, idx) => {
              const label = NPC_LIST.find((n) => n.id === npc.npcId)?.name || npc.npcId;
              return (
                <div
                  key={npc.id}
                  onClick={() => setSelectedPlacedIdx(idx)}
                  style={{
                    padding: '4px 8px', cursor: 'pointer', borderRadius: 4, marginBottom: 2,
                    background: selectedPlacedIdx === idx ? '#333' : 'transparent',
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  }}
                >
                  <span style={{ fontSize: 13 }}>{label}</span>
                  <button
                    onClick={(e) => { e.stopPropagation(); removeNpc(idx); }}
                    style={{ background: 'none', border: 'none', color: '#f44', cursor: 'pointer', fontSize: 14 }}
                  >X</button>
                </div>
              );
            })}
          </fieldset>
        )}

        {/* NPC Transform */}
        {selectedNpcData && selectedPlacedIdx !== null && (
          <fieldset style={fieldsetStyle}>
            <legend style={legendStyle}>
              {NPC_LIST.find((n) => n.id === selectedNpcData.npcId)?.name} Transform
            </legend>
            <SliderRow label="X" min={-30} max={30} step={0.1} value={selectedNpcData.position[0]}
              onChange={(v) => updateNpc(selectedPlacedIdx, { position: [v, selectedNpcData.position[1], selectedNpcData.position[2]] })}
              format={(v) => v.toFixed(1)} />
            <SliderRow label="Z" min={-30} max={30} step={0.1} value={selectedNpcData.position[2]}
              onChange={(v) => updateNpc(selectedPlacedIdx, { position: [selectedNpcData.position[0], selectedNpcData.position[1], v] })}
              format={(v) => v.toFixed(1)} />
            <SliderRow label="Rot" min={-180} max={180} step={1} value={selectedNpcData.rotation * 180 / Math.PI}
              onChange={(v) => updateNpc(selectedPlacedIdx, { rotation: v * Math.PI / 180 })}
              format={(v) => `${v.toFixed(0)}\u00B0`} />
            <SliderRow label="Scale" min={0.01} max={0.3} step={0.005} value={selectedNpcData.scale}
              onChange={(v) => updateNpc(selectedPlacedIdx, { scale: v })}
              format={(v) => v.toFixed(3)} />
          </fieldset>
        )}

        {/* Bone Pose */}
        {selectedNpcData && selectedPlacedIdx !== null && (
          <fieldset style={fieldsetStyle}>
            <legend style={legendStyle}>Pose</legend>
            <button onClick={() => resetPose(selectedPlacedIdx)} style={{ ...buttonStyle, background: '#555', marginBottom: 6 }}>
              Reset Pose
            </button>
            {BONE_GROUPS.map((group) => {
              const isOpen = expandedGroup === group.label;
              return (
                <div key={group.label} style={{ marginBottom: 2 }}>
                  <div
                    onClick={() => setExpandedGroup(isOpen ? null : group.label)}
                    style={{ cursor: 'pointer', padding: '4px 0', fontSize: 12, color: '#aaa', userSelect: 'none' }}
                  >
                    {isOpen ? '\u25BC' : '\u25B6'} {group.label}
                  </div>
                  {isOpen && group.bones.map((bone) => {
                    const pose = selectedNpcData.bonePoses[bone.name] || [0, 0, 0];
                    return (
                      <div key={bone.name} style={{ marginLeft: 12, marginBottom: 6 }}>
                        <div style={{ fontSize: 11, color: '#888', marginBottom: 2 }}>{bone.label}</div>
                        <SliderRow label="X" min={-180} max={180} step={1} value={pose[0] * 180 / Math.PI}
                          onChange={(v) => updateBone(selectedPlacedIdx, bone.name, 0, v * Math.PI / 180)}
                          format={(v) => `${v.toFixed(0)}\u00B0`} />
                        <SliderRow label="Y" min={-180} max={180} step={1} value={pose[1] * 180 / Math.PI}
                          onChange={(v) => updateBone(selectedPlacedIdx, bone.name, 1, v * Math.PI / 180)}
                          format={(v) => `${v.toFixed(0)}\u00B0`} />
                        <SliderRow label="Z" min={-180} max={180} step={1} value={pose[2] * 180 / Math.PI}
                          onChange={(v) => updateBone(selectedPlacedIdx, bone.name, 2, v * Math.PI / 180)}
                          format={(v) => `${v.toFixed(0)}\u00B0`} />
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </fieldset>
        )}

        {/* Lighting */}
        <fieldset style={fieldsetStyle}>
          <legend style={legendStyle}>Lighting</legend>
          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
            {Object.entries(LIGHTING_PRESETS).map(([key, p]) => (
              <button key={key} onClick={() => setLighting(key)}
                style={{ ...buttonStyle, background: lighting === key ? '#4a9eff' : '#444', flex: '1 0 45%' }}>
                {p.name}
              </button>
            ))}
          </div>
        </fieldset>

        {/* Screenshot */}
        <button onClick={() => setCaptureRequested(true)}
          style={{ ...buttonStyle, background: '#2a7a2a', fontSize: 14, padding: '10px 16px' }}>
          Take Screenshot
        </button>
      </div>

      {/* Canvas */}
      <div style={{ flex: 1, position: 'relative' }}>
        <Canvas
          gl={{ antialias: true, preserveDrawingBuffer: true }}
          camera={{ position: [15, 10, 15], fov: 45 }}
          style={{ background: preset.bg, cursor: placementMode ? 'crosshair' : 'grab' }}
        >
          <SceneContent
            mapId={selectedMap}
            npcs={placedNpcs}
            lighting={lighting}
            placementMode={placementMode}
            onFloorClick={handleFloorClick}
            captureRequested={captureRequested}
            onCaptured={() => setCaptureRequested(false)}
          />
        </Canvas>
        {placementMode && (
          <div style={{
            position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)',
            background: 'rgba(74, 158, 255, 0.9)', padding: '6px 16px', borderRadius: 4,
            fontSize: 13, pointerEvents: 'none',
          }}>
            Click on the stage to place {NPC_LIST.find((n) => n.id === selectedNpc)?.name}
          </div>
        )}
      </div>
    </div>
  );
}

function SliderRow({ label, min, max, step, value, onChange, format }: {
  label: string; min: number; max: number; step: number; value: number;
  onChange: (v: number) => void; format: (v: number) => string;
}) {
  return (
    <label style={labelStyle}>
      <span style={{ width: 24, fontSize: 11 }}>{label}</span>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))} style={{ flex: 1 }} />
      <span style={valStyle}>{format(value)}</span>
    </label>
  );
}

const fieldsetStyle: React.CSSProperties = { border: '1px solid #444', padding: 8, borderRadius: 4, margin: 0 };
const legendStyle: React.CSSProperties = { fontSize: 12, color: '#888' };
const selectStyle: React.CSSProperties = {
  width: '100%', padding: '6px 8px', background: '#2a2a3e', color: '#e0e0e0',
  border: '1px solid #555', borderRadius: 4, fontSize: 13,
};
const buttonStyle: React.CSSProperties = {
  padding: '6px 12px', border: 'none', borderRadius: 4, color: '#e0e0e0',
  cursor: 'pointer', fontSize: 12, width: '100%',
};
const labelStyle: React.CSSProperties = {
  display: 'flex', alignItems: 'center', gap: 4, fontSize: 11, marginBottom: 2,
};
const valStyle: React.CSSProperties = { width: 40, textAlign: 'right', fontSize: 10, color: '#999' };
