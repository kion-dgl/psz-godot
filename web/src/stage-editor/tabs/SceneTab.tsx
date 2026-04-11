/**
 * SceneTab — Time-of-day lighting and particle effect controls for the stage editor.
 *
 * Particle effects are split into three categories:
 *   - Placed:  localized emitters at specific positions (mushroom spores, campfire sparks)
 *   - Weather: global fill effects (snow, rain, sandstorm)
 *   - Floor:   rise from ground across the whole stage (ambient spores, mist)
 */

import { useCallback, useState } from 'react';
import type { TimeOfDayLighting } from '../StageCanvas';
import type { ParticleEffect, PlacedEffect, WeatherEffect, FloorEffect } from '../ParticleOverlay';

// ---------- Time-of-day lighting (mirrors TimeManager.gd) ----------

interface PhaseConfig {
  ambientColor: [number, number, number];
  ambientEnergy: number;
  lightColor: [number, number, number];
  lightEnergy: number;
  lightPitch: number;
  skyTop: [number, number, number];
}

const PHASES: Record<string, PhaseConfig> = {
  day: {
    ambientColor: [0.9, 0.92, 0.88], ambientEnergy: 1.1,
    lightColor: [1.0, 0.98, 0.94], lightEnergy: 0.5, lightPitch: -45,
    skyTop: [0.3, 0.55, 0.65],
  },
  sunset: {
    ambientColor: [0.85, 0.5, 0.2], ambientEnergy: 0.55,
    lightColor: [1.0, 0.5, 0.1], lightEnergy: 0.7, lightPitch: -12,
    skyTop: [0.2, 0.1, 0.3],
  },
  night: {
    ambientColor: [0.2, 0.25, 0.45], ambientEnergy: 0.5,
    lightColor: [0.6, 0.7, 1.0], lightEnergy: 0.25, lightPitch: -40,
    skyTop: [0.02, 0.02, 0.08],
  },
  sunrise: {
    ambientColor: [0.75, 0.6, 0.45], ambientEnergy: 0.55,
    lightColor: [1.0, 0.7, 0.4], lightEnergy: 0.5, lightPitch: -12,
    skyTop: [0.25, 0.35, 0.55],
  },
};

function lerp(a: number, b: number, t: number) { return a + (b - a) * t; }
function lerpArr(a: [number, number, number], b: [number, number, number], t: number): [number, number, number] {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
}
function lerpPhase(a: PhaseConfig, b: PhaseConfig, t: number): PhaseConfig {
  return {
    ambientColor: lerpArr(a.ambientColor, b.ambientColor, t),
    ambientEnergy: lerp(a.ambientEnergy, b.ambientEnergy, t),
    lightColor: lerpArr(a.lightColor, b.lightColor, t),
    lightEnergy: lerp(a.lightEnergy, b.lightEnergy, t),
    lightPitch: lerp(a.lightPitch, b.lightPitch, t),
    skyTop: lerpArr(a.skyTop, b.skyTop, t),
  };
}

function getMoonlight(hour: number): number {
  if (hour >= 21 || hour < 5) return 0.55;
  if (hour >= 17 && hour < 21) return lerp(0, 0.55, (hour - 17) / 4);
  if (hour >= 5 && hour < 7) return lerp(0.55, 0, (hour - 5) / 2);
  return 0;
}

function getPhaseConfig(hour: number): PhaseConfig {
  if (hour >= 21 || hour < 5) return PHASES.night;
  if (hour >= 5 && hour < 6) return lerpPhase(PHASES.night, PHASES.sunrise, hour - 5);
  if (hour >= 6 && hour < 7) return lerpPhase(PHASES.sunrise, PHASES.day, hour - 6);
  if (hour >= 7 && hour < 17) return PHASES.day;
  if (hour >= 17 && hour < 19) return lerpPhase(PHASES.day, PHASES.sunset, (hour - 17) / 2);
  return lerpPhase(PHASES.sunset, PHASES.night, (hour - 19) / 2);
}

export function computeLighting(hour: number): TimeOfDayLighting {
  const cfg = getPhaseConfig(hour);
  const [r, g, b] = cfg.skyTop;
  const bgHex = '#' + [r, g, b].map(c => Math.round(c * 255).toString(16).padStart(2, '0')).join('');
  return {
    ambientColor: cfg.ambientColor, ambientIntensity: cfg.ambientEnergy,
    sunColor: cfg.lightColor, sunIntensity: cfg.lightEnergy, sunPitch: cfg.lightPitch,
    moonIntensity: getMoonlight(hour), bgColor: bgHex,
  };
}

function formatHour(h: number): string {
  const hours = Math.floor(h) % 24;
  const mins = Math.floor((h % 1) * 60);
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`;
}

function getPhaseLabel(hour: number): string {
  if (hour >= 21 || hour < 5) return 'Night';
  if (hour >= 5 && hour < 7) return 'Sunrise';
  if (hour >= 7 && hour < 17) return 'Day';
  return 'Sunset';
}

// ---------- Presets ----------

export const PLACED_PRESETS: Record<string, Omit<PlacedEffect, 'id' | 'position'>> = {
  spores: {
    category: 'placed', preset: 'spores',
    color: [0.2, 1.0, 0.3], count: 60, speed: 1.2, size: 3.0,
    radius: 3, height: 5, lightIntensity: 2.0, lightRadius: 8,
  },
  embers: {
    category: 'placed', preset: 'embers',
    color: [1.0, 0.5, 0.1], count: 40, speed: 1.5, size: 2.5,
    radius: 2, height: 4, lightIntensity: 1.5, lightRadius: 6,
  },
};

const WEATHER_PRESETS: Record<string, Omit<WeatherEffect, 'id'>> = {
  snow: {
    category: 'weather', preset: 'snow',
    color: [0.9, 0.95, 1.0], count: 300, speed: 1.5, size: 3.0,
    area: 25, height: 15,
  },
  rain: {
    category: 'weather', preset: 'rain',
    color: [0.5, 0.6, 0.8], count: 400, speed: 8.0, size: 1.5,
    area: 25, height: 15,
  },
  sandstorm: {
    category: 'weather', preset: 'sandstorm',
    color: [0.8, 0.65, 0.35], count: 250, speed: 4.0, size: 4.0,
    area: 25, height: 6,
  },
};

const FLOOR_PRESETS: Record<string, Omit<FloorEffect, 'id'>> = {
  spores: {
    category: 'floor', preset: 'spores',
    color: [0.2, 1.0, 0.3], count: 120, speed: 1.2, size: 3.0,
    area: 15, height: 5,
  },
  mist: {
    category: 'floor', preset: 'mist',
    color: [0.6, 0.7, 0.8], count: 80, speed: 0.4, size: 6.0,
    area: 20, height: 3,
  },
};

// ---------- Component ----------

interface SceneTabProps {
  timeOfDay: number;
  onTimeChange: (hour: number) => void;
  particles: ParticleEffect[];
  onParticlesChange: (particles: ParticleEffect[]) => void;
  placementMode: boolean;
  onSetPlacementMode: (mode: boolean) => void;
  placementPreset: string;
  onSetPlacementPreset: (preset: string) => void;
  selectedEffectId: string | null;
  onSelectEffect: (id: string | null) => void;
  mapId: string;
  indoor: boolean;
  onIndoorChange: (indoor: boolean) => void;
  repositionEffectId: string | null;
  onStartReposition: (id: string) => void;
}

export default function SceneTab({
  timeOfDay, onTimeChange, particles, onParticlesChange,
  placementMode, onSetPlacementMode, placementPreset, onSetPlacementPreset,
  selectedEffectId, onSelectEffect,
  mapId, indoor, onIndoorChange,
  repositionEffectId, onStartReposition,
}: SceneTabProps) {
  const [copied, setCopied] = useState(false);
  const phase = getPhaseLabel(timeOfDay);
  const placed = particles.filter((p): p is PlacedEffect => p.category === 'placed');
  const weather = particles.filter((p): p is WeatherEffect => p.category === 'weather');
  const floor = particles.filter((p): p is FloorEffect => p.category === 'floor');

  const update = useCallback((id: string, changes: Partial<ParticleEffect>) => {
    onParticlesChange(particles.map(p => p.id === id ? { ...p, ...changes } as ParticleEffect : p));
  }, [particles, onParticlesChange]);

  const remove = useCallback((id: string) => {
    onParticlesChange(particles.filter(p => p.id !== id));
    if (selectedEffectId === id) onSelectEffect(null);
  }, [particles, onParticlesChange, selectedEffectId, onSelectEffect]);

  // --- Weather toggles ---
  const toggleWeather = (preset: string) => {
    const existing = weather.find(w => w.preset === preset);
    if (existing) {
      remove(existing.id);
    } else {
      const base = WEATHER_PRESETS[preset];
      if (base) onParticlesChange([...particles, { id: `weather_${preset}`, ...base }]);
    }
  };

  // --- Floor toggles ---
  const toggleFloor = (preset: string) => {
    const existing = floor.find(f => f.preset === preset);
    if (existing) {
      remove(existing.id);
    } else {
      const base = FLOOR_PRESETS[preset];
      if (base) onParticlesChange([...particles, { id: `floor_${preset}`, ...base }]);
    }
  };

  // --- Placed emitter (click-to-place) ---
  const startPlacement = (preset: string) => {
    onSetPlacementPreset(preset);
    onSetPlacementMode(true);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>

      {/* ── Time of Day ── */}
      <div>
        <div style={labelStyle}>Time of Day</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
          <span style={{ fontSize: '24px', fontFamily: 'monospace', color: '#fff', minWidth: '70px' }}>
            {formatHour(timeOfDay)}
          </span>
          <span style={{
            padding: '3px 10px',
            background: phase === 'Night' ? '#1a1a3a' : phase === 'Sunset' ? '#3a2a1a' : phase === 'Sunrise' ? '#3a2a2a' : '#2a3a2a',
            border: `1px solid ${phase === 'Night' ? '#446' : '#864'}`,
            borderRadius: '4px',
            color: phase === 'Night' ? '#88aaff' : phase === 'Sunset' ? '#ffaa44' : phase === 'Sunrise' ? '#ffaa66' : '#88ff88',
            fontSize: '11px',
          }}>
            {phase}
          </span>
        </div>
        <input
          type="range" min={0} max={24} step={0.1} value={timeOfDay}
          onChange={(e) => onTimeChange(parseFloat(e.target.value))}
          style={{ width: '100%', accentColor: '#4a9eff' }}
        />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: '#666', marginTop: '2px' }}>
          <span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>24:00</span>
        </div>
        <div style={{ display: 'flex', gap: '4px', marginTop: '8px', flexWrap: 'wrap' }}>
          {[{ label: 'Dawn', hour: 5.5 }, { label: 'Morning', hour: 9 }, { label: 'Noon', hour: 12 },
            { label: 'Dusk', hour: 19 }, { label: 'Night', hour: 23 }].map(p => (
            <button key={p.label} onClick={() => onTimeChange(p.hour)} style={presetBtnStyle}>
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Indoor / Outdoor ── */}
      <div>
        <div style={labelStyle}>Environment</div>
        <div style={{ display: 'flex', gap: '4px' }}>
          {([false, true] as const).map(val => {
            const active = indoor === val;
            return (
              <button
                key={String(val)}
                onClick={() => onIndoorChange(val)}
                style={{
                  ...toggleBtnStyle,
                  flex: 1,
                  background: active ? (val ? '#2a2a4a' : '#2a3a2a') : '#1a1a2e',
                  border: `1px solid ${active ? (val ? '#6666cc' : '#66aa66') : '#333'}`,
                  color: active ? (val ? '#aaaaff' : '#88ff88') : '#888',
                }}
              >
                {val ? 'Indoor (cave)' : 'Outdoor'}
              </button>
            );
          })}
        </div>
        <div style={{ fontSize: '10px', color: '#666', marginTop: '4px' }}>
          Indoor stages ignore the day/night cycle.
        </div>
      </div>

      {/* ── Placed Effects ── */}
      <div>
        <div style={labelStyle}>Placed Effects</div>
        <div style={{ fontSize: '10px', color: '#666', marginBottom: '6px' }}>
          Click in the scene to place an emitter. Each emitter includes a point light.
        </div>
        <div style={{ display: 'flex', gap: '4px', marginBottom: '8px' }}>
          {Object.keys(PLACED_PRESETS).map(key => (
            <button
              key={key}
              onClick={() => startPlacement(key)}
              style={{
                ...presetBtnStyle,
                background: placementMode && placementPreset === key ? '#4a9eff' : '#333',
                color: placementMode && placementPreset === key ? '#fff' : '#aaa',
              }}
            >
              {placementMode && placementPreset === key ? 'Click scene...' : `+ ${key}`}
            </button>
          ))}
        </div>
        {placementMode && (
          <div style={{ fontSize: '10px', color: '#4a9eff', marginBottom: '8px' }}>
            Click in the 3D scene to place the emitter. Press the button again to cancel.
          </div>
        )}

        {/* List of placed effects */}
        {placed.map(p => {
          const selected = p.id === selectedEffectId;
          return (
            <div key={p.id} style={{
              ...effectCardStyle,
              marginBottom: '6px',
              border: `1px solid ${selected ? '#4a9eff' : '#333'}`,
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                <span
                  style={{ fontSize: '12px', color: selected ? '#4a9eff' : '#ccc', cursor: 'pointer' }}
                  onClick={() => onSelectEffect(selected ? null : p.id)}
                >
                  {p.preset} ({p.position[0].toFixed(1)}, {p.position[1].toFixed(1)}, {p.position[2].toFixed(1)})
                </span>
                <div style={{ display: 'flex', gap: '3px' }}>
                  <button
                    onClick={() => onStartReposition(p.id)}
                    style={{
                      ...removeBtnStyle,
                      background: repositionEffectId === p.id ? '#2a3a5a' : '#222244',
                      border: `1px solid ${repositionEffectId === p.id ? '#4a9eff' : '#444466'}`,
                      color: repositionEffectId === p.id ? '#4a9eff' : '#8888aa',
                    }}
                  >
                    {repositionEffectId === p.id ? 'Click scene...' : 'Move'}
                  </button>
                  <button onClick={() => remove(p.id)} style={removeBtnStyle}>X</button>
                </div>
              </div>
              {selected && (
                <>
                  <SliderRow label="Radius" value={p.radius} min={1} max={10} step={0.5}
                    onChange={(v) => update(p.id, { radius: v })} />
                  <SliderRow label="Count" value={p.count} min={10} max={200} step={10}
                    onChange={(v) => update(p.id, { count: v })} />
                  <SliderRow label="Speed" value={p.speed} min={0.3} max={3} step={0.1}
                    onChange={(v) => update(p.id, { speed: v })} />
                  <SliderRow label="Light Intensity" value={p.lightIntensity} min={0} max={5} step={0.5}
                    onChange={(v) => update(p.id, { lightIntensity: v })} />
                  <SliderRow label="Light Radius" value={p.lightRadius} min={2} max={20} step={1}
                    onChange={(v) => update(p.id, { lightRadius: v })} />
                  <ColorPicker current={p.color} onChange={(c) => update(p.id, { color: c })} />
                </>
              )}
            </div>
          );
        })}
      </div>

      {/* ── Weather ── */}
      <div>
        <div style={labelStyle}>Weather</div>
        <div style={{ fontSize: '10px', color: '#666', marginBottom: '6px' }}>
          Global effects that fill the entire area.
        </div>
        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
          {Object.entries(WEATHER_PRESETS).map(([key, preset]) => {
            const active = weather.some(w => w.preset === key);
            return (
              <button key={key} onClick={() => toggleWeather(key)} style={{
                ...toggleBtnStyle,
                background: active ? '#2a3a4a' : '#1a1a2e',
                border: `1px solid ${active ? '#6688cc' : '#333'}`,
                color: active ? '#88bbff' : '#888',
              }}>
                {key}
              </button>
            );
          })}
        </div>
        {weather.map(w => (
          <div key={w.id} style={{ ...effectCardStyle, marginTop: '8px' }}>
            <span style={{ fontSize: '11px', color: '#aaa' }}>{w.preset}</span>
            <SliderRow label="Count" value={w.count} min={50} max={600} step={25}
              onChange={(v) => update(w.id, { count: v })} />
            <SliderRow label="Speed" value={w.speed} min={0.5} max={12} step={0.5}
              onChange={(v) => update(w.id, { speed: v })} />
            <SliderRow label="Area" value={w.area} min={10} max={50} step={5}
              onChange={(v) => update(w.id, { area: v })} />
          </div>
        ))}
      </div>

      {/* ── Floor Effects ── */}
      <div>
        <div style={labelStyle}>Floor Effects</div>
        <div style={{ fontSize: '10px', color: '#666', marginBottom: '6px' }}>
          Particles that rise from the ground across the stage.
        </div>
        <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
          {Object.entries(FLOOR_PRESETS).map(([key]) => {
            const active = floor.some(f => f.preset === key);
            return (
              <button key={key} onClick={() => toggleFloor(key)} style={{
                ...toggleBtnStyle,
                background: active ? '#2a4a2a' : '#1a1a2e',
                border: `1px solid ${active ? '#66aa66' : '#333'}`,
                color: active ? '#88ff88' : '#888',
              }}>
                {key}
              </button>
            );
          })}
        </div>
        {floor.map(f => (
          <div key={f.id} style={{ ...effectCardStyle, marginTop: '8px' }}>
            <span style={{ fontSize: '11px', color: '#aaa' }}>{f.preset}</span>
            <SliderRow label="Count" value={f.count} min={20} max={300} step={10}
              onChange={(v) => update(f.id, { count: v })} />
            <SliderRow label="Area" value={f.area} min={3} max={30} step={1}
              onChange={(v) => update(f.id, { area: v })} />
            <SliderRow label="Speed" value={f.speed} min={0.2} max={3} step={0.1}
              onChange={(v) => update(f.id, { speed: v })} />
            <SliderRow label="Height" value={f.height} min={2} max={15} step={1}
              onChange={(v) => update(f.id, { height: v })} />
            <ColorPicker current={f.color} onChange={(c) => update(f.id, { color: c })} />
          </div>
        ))}
      </div>

      {/* ── Copy JSON ── */}
      {(particles.length > 0 || indoor) && (
        <div>
          <button
            onClick={() => {
              const scene: Record<string, unknown> = {
                stage_id: mapId,
                ...(indoor ? { indoor: true } : {}),
                effects: particles.map(p => {
                  if (p.category === 'placed') {
                    return {
                      type: p.preset,
                      category: p.category,
                      position: p.position.map(v => Math.round(v * 10) / 10),
                      color: p.color,
                      count: p.count,
                      radius: p.radius,
                      height: p.height,
                      speed: p.speed,
                      light_intensity: p.lightIntensity,
                      light_radius: p.lightRadius,
                    };
                  }
                  if (p.category === 'weather') {
                    return {
                      type: p.preset,
                      category: p.category,
                      color: p.color,
                      count: p.count,
                      area: p.area,
                      height: p.height,
                      speed: p.speed,
                    };
                  }
                  return {
                    type: p.preset,
                    category: p.category,
                    color: p.color,
                    count: p.count,
                    area: (p as FloorEffect).area,
                    height: p.height,
                    speed: p.speed,
                  };
                }),
              };
              navigator.clipboard.writeText(JSON.stringify(scene, null, 2));
              setCopied(true);
              setTimeout(() => setCopied(false), 1500);
            }}
            style={{
              width: '100%', padding: '10px',
              background: copied ? '#2a4a2a' : '#1a1a2e',
              border: `1px solid ${copied ? '#66aa66' : '#444'}`,
              borderRadius: '6px',
              color: copied ? '#88ff88' : '#aaa',
              fontSize: '12px', cursor: 'pointer',
            }}
          >
            {copied ? 'Copied!' : 'Copy Scene JSON'}
          </button>
        </div>
      )}

      <div style={{ fontSize: '11px', color: '#555', lineHeight: 1.5 }}>
        Time-of-day mirrors in-game TimeManager. Particle effects are visual previews.
      </div>
    </div>
  );
}

// ---------- Shared UI ----------

function SliderRow({ label, value, min, max, step, onChange }: {
  label: string; value: number; min: number; max: number; step: number;
  onChange: (v: number) => void;
}) {
  return (
    <div style={{ marginBottom: '4px' }}>
      <div style={{ fontSize: '10px', color: '#777', marginBottom: '1px' }}>
        {label}: {Number.isInteger(step) ? value : value.toFixed(1)}
      </div>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ width: '100%', accentColor: '#66aa66' }} />
    </div>
  );
}

const COLOR_OPTIONS: { label: string; color: [number, number, number] }[] = [
  { label: 'Green', color: [0.2, 1.0, 0.3] },
  { label: 'Blue', color: [0.2, 0.5, 1.0] },
  { label: 'Gold', color: [1.0, 0.8, 0.2] },
  { label: 'Pink', color: [1.0, 0.3, 0.6] },
  { label: 'White', color: [0.8, 0.9, 1.0] },
];

function ColorPicker({ current, onChange }: {
  current: [number, number, number]; onChange: (c: [number, number, number]) => void;
}) {
  return (
    <div style={{ display: 'flex', gap: '3px', marginTop: '4px', flexWrap: 'wrap' }}>
      {COLOR_OPTIONS.map(c => {
        const active = current[0] === c.color[0] && current[1] === c.color[1] && current[2] === c.color[2];
        return (
          <button key={c.label} onClick={() => onChange(c.color)} style={{
            padding: '2px 8px', fontSize: '9px', borderRadius: '3px', cursor: 'pointer',
            background: active ? `rgba(${c.color.map(v => Math.round(v * 255)).join(',')}, 0.2)` : '#333',
            border: `1px solid ${active ? `rgb(${c.color.map(v => Math.round(v * 200)).join(',')})` : '#555'}`,
            color: active ? `rgb(${c.color.map(v => Math.round(v * 255)).join(',')})` : '#aaa',
          }}>
            {c.label}
          </button>
        );
      })}
    </div>
  );
}

// ---------- Styles ----------

const labelStyle: React.CSSProperties = {
  fontSize: '11px', color: '#888', textTransform: 'uppercase',
  letterSpacing: '0.5px', marginBottom: '8px',
};

const presetBtnStyle: React.CSSProperties = {
  padding: '4px 10px', fontSize: '10px', background: '#333',
  border: '1px solid #555', borderRadius: '4px', color: '#aaa', cursor: 'pointer',
};

const toggleBtnStyle: React.CSSProperties = {
  padding: '8px 14px', fontSize: '12px', borderRadius: '6px', cursor: 'pointer',
};

const effectCardStyle: React.CSSProperties = {
  padding: '8px', background: '#1a1a2e', border: '1px solid #333',
  borderRadius: '6px',
};

const removeBtnStyle: React.CSSProperties = {
  padding: '1px 6px', background: '#442222', border: '1px solid #664444',
  borderRadius: '3px', color: '#aa6666', fontSize: '10px', cursor: 'pointer',
};

const coordStyle: React.CSSProperties = {
  display: 'flex', alignItems: 'center', gap: '3px', fontSize: '10px', color: '#888', flex: 1,
};

const coordInputStyle: React.CSSProperties = {
  width: '100%', padding: '3px 4px', background: '#111', border: '1px solid #444',
  borderRadius: '3px', color: '#fff', fontSize: '11px', fontFamily: 'monospace',
};
