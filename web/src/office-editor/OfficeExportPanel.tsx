import { useState } from 'react';
import type { OfficeLayoutData, PlacementMode } from './types';

function vec3Str(v: [number, number, number]) {
  return `Vector3(${v[0].toFixed(3)}, ${v[1].toFixed(3)}, ${v[2].toFixed(3)})`;
}

function generateGDScript(layout: OfficeLayoutData): string {
  return [
    `const NPC_POSITION := ${vec3Str(layout.npcPosition)}`,
    `const NPC_ROTATION_Y := ${layout.npcRotationY.toFixed(3)}`,
    `const NPC_SCALE := ${layout.npcScale.toFixed(3)}`,
    ``,
    `const ROOM_SCALE := ${layout.roomScale.toFixed(3)}`,
    ``,
    `const DOOR_TRIGGER_POSITION := ${vec3Str(layout.doorTrigger.position)}`,
    `const DOOR_TRIGGER_SIZE := ${vec3Str(layout.doorTrigger.size)}`,
    ``,
    `const SPAWN_POSITION := ${vec3Str(layout.spawnPoint.position)}`,
    `const SPAWN_ROTATION_Y := ${layout.spawnPoint.rotationY.toFixed(3)}`,
  ].join('\n');
}

interface Vec3InputProps {
  label: string;
  value: [number, number, number];
  onChange: (v: [number, number, number]) => void;
}

function Vec3Input({ label, value, onChange }: Vec3InputProps) {
  const update = (i: number, val: number) => {
    const next = [...value] as [number, number, number];
    next[i] = val;
    onChange(next);
  };

  return (
    <div style={{ marginBottom: 6 }}>
      <div style={{ fontSize: 10, color: '#888', marginBottom: 2 }}>{label}</div>
      <div style={{ display: 'flex', gap: 4 }}>
        {['X', 'Y', 'Z'].map((axis, i) => (
          <label key={axis} style={{ display: 'flex', alignItems: 'center', gap: 2, fontSize: 10, color: '#aaa' }}>
            {axis}
            <input
              type="number"
              step={0.1}
              value={value[i]}
              onChange={(e) => update(i, parseFloat(e.target.value) || 0)}
              style={{
                width: 60, padding: '2px 4px', background: '#1a1a2e',
                border: '1px solid #333', borderRadius: 3, color: '#ccc', fontSize: 11,
              }}
            />
          </label>
        ))}
      </div>
    </div>
  );
}

function ScaleInput({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) {
  return (
    <div style={{ marginBottom: 6 }}>
      <div style={{ fontSize: 10, color: '#888', marginBottom: 2 }}>{label}: {value.toFixed(2)}</div>
      <input
        type="range"
        min={0.01}
        max={1}
        step={0.01}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ width: '100%' }}
      />
    </div>
  );
}

function RotationInput({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) {
  const degrees = (value * 180) / Math.PI;
  return (
    <div style={{ marginBottom: 6 }}>
      <div style={{ fontSize: 10, color: '#888', marginBottom: 2 }}>{label}: {degrees.toFixed(0)}&deg;</div>
      <input
        type="range"
        min={-180}
        max={180}
        value={degrees}
        onChange={(e) => onChange((parseFloat(e.target.value) * Math.PI) / 180)}
        style={{ width: '100%' }}
      />
    </div>
  );
}

interface OfficeExportPanelProps {
  layout: OfficeLayoutData;
  placementMode: PlacementMode;
  onLayoutChange: (layout: OfficeLayoutData) => void;
  onPlacementModeChange: (mode: PlacementMode) => void;
}

function PlaceButton({ label, mode, current, onToggle }: {
  label: string; mode: PlacementMode; current: PlacementMode;
  onToggle: (mode: PlacementMode) => void;
}) {
  const active = current === mode;
  return (
    <button
      onClick={() => onToggle(active ? 'none' : mode)}
      style={{
        padding: '4px 8px', fontSize: 10,
        background: active ? '#ffaa00' : '#2a2a4a',
        color: active ? '#000' : '#ccc',
        border: active ? '1px solid #ffaa00' : '1px solid #444',
        borderRadius: 3, cursor: 'pointer',
      }}
    >
      {active ? 'Placing...' : label}
    </button>
  );
}

export default function OfficeExportPanel({ layout, placementMode, onLayoutChange, onPlacementModeChange }: OfficeExportPanelProps) {
  const [copied, setCopied] = useState(false);

  const updateNpc = (partial: Partial<Pick<OfficeLayoutData, 'npcPosition' | 'npcRotationY' | 'npcScale'>>) => {
    onLayoutChange({ ...layout, ...partial });
  };

  const updateDoor = (partial: Partial<OfficeLayoutData['doorTrigger']>) => {
    onLayoutChange({ ...layout, doorTrigger: { ...layout.doorTrigger, ...partial } });
  };

  const updateSpawn = (partial: Partial<OfficeLayoutData['spawnPoint']>) => {
    onLayoutChange({ ...layout, spawnPoint: { ...layout.spawnPoint, ...partial } });
  };

  const gdScript = generateGDScript(layout);

  const handleCopy = () => {
    navigator.clipboard.writeText(gdScript).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  return (
    <div style={{
      width: 320, flexShrink: 0, background: '#12122a', borderRight: '1px solid #2a2a4a',
      padding: 12, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 16,
    }}>
      <h2 style={{ margin: 0, fontSize: 14, color: '#88aaff' }}>Office Layout</h2>

      {/* NPC Section */}
      <section>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: 12, color: '#ffaa44' }}>Principal NPC</h3>
          <PlaceButton label="Place" mode="npc" current={placementMode} onToggle={onPlacementModeChange} />
        </div>
        <Vec3Input label="Position" value={layout.npcPosition} onChange={(v) => updateNpc({ npcPosition: v })} />
        <RotationInput label="Rotation Y" value={layout.npcRotationY} onChange={(v) => updateNpc({ npcRotationY: v })} />
        <ScaleInput label="Scale" value={layout.npcScale} onChange={(v) => updateNpc({ npcScale: v })} />
      </section>

      {/* Room Section */}
      <section>
        <h3 style={{ margin: '0 0 8px', fontSize: 12, color: '#aa88ff' }}>Office Room</h3>
        <ScaleInput label="Scale" value={layout.roomScale} onChange={(v) => onLayoutChange({ ...layout, roomScale: v })} />
        <div style={{ fontSize: 9, color: '#666' }}>PSZ reference model at origin for comparison</div>
      </section>

      {/* Door Trigger Section */}
      <section>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: 12, color: '#4488ff' }}>Door Trigger</h3>
          <PlaceButton label="Place" mode="door" current={placementMode} onToggle={onPlacementModeChange} />
        </div>
        <Vec3Input label="Position" value={layout.doorTrigger.position} onChange={(v) => updateDoor({ position: v })} />
        <Vec3Input label="Size (W/H/D)" value={layout.doorTrigger.size} onChange={(v) => updateDoor({ size: v })} />
      </section>

      {/* Spawn Point Section */}
      <section>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: 12, color: '#44ff44' }}>Spawn Point</h3>
          <PlaceButton label="Place" mode="spawn" current={placementMode} onToggle={onPlacementModeChange} />
        </div>
        <Vec3Input label="Position" value={layout.spawnPoint.position} onChange={(v) => updateSpawn({ position: v })} />
        <RotationInput label="Rotation Y" value={layout.spawnPoint.rotationY} onChange={(v) => updateSpawn({ rotationY: v })} />
      </section>

      {/* Export Section */}
      <section>
        <h3 style={{ margin: '0 0 8px 0', fontSize: 12, color: '#88aaff' }}>Export</h3>
        <button
          onClick={handleCopy}
          style={{
            width: '100%', padding: '6px 12px', marginBottom: 8,
            background: copied ? '#44aa44' : '#4a9eff',
            color: '#fff', border: 'none', borderRadius: 4,
            cursor: 'pointer', fontSize: 11, fontWeight: 600,
          }}
        >
          {copied ? 'Copied!' : 'Copy GDScript'}
        </button>
        <textarea
          readOnly
          value={JSON.stringify(layout, null, 2)}
          style={{
            width: '100%', height: 180, padding: 8,
            background: '#0a0a12', border: '1px solid #333',
            borderRadius: 4, color: '#aaa', fontSize: 10,
            fontFamily: 'monospace', resize: 'vertical',
          }}
        />
      </section>
    </div>
  );
}
