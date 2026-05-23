import { useState } from 'react';
import { getClassArtPath } from '../character-creator/data/constants';
import { TYPE_COLORS, statBarSegments, type VariantProps } from './types';
import type { ClassInfo } from '../character-creator/data/classData';

const TYPES = ['Hunter', 'Ranger', 'Force'] as const;
type TypeName = (typeof TYPES)[number];

const TYPE_BLURB: Record<TypeName, string> = {
  Hunter: 'Melee specialists. High HP and attack power, the front line of any party.',
  Ranger: 'Marksmen. Top-tier accuracy and ranged damage; lightly armoured.',
  Force: 'Spellcasters. Devastating techniques and party support, fragile bodies.',
};

const RACES = ['Human', 'Newman', 'Cast'] as const;

export default function TypeFirstView({ classes, selectedId, onSelect }: VariantProps) {
  const selected = classes.find((c) => c.id === selectedId)!;
  // Local step state: start at type-pick, or jump straight into class-pick if a
  // class is already chosen (so flipping back to this variant restores context).
  const [pickedType, setPickedType] = useState<TypeName | null>(
    selected ? (selected.type as TypeName) : null,
  );

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: 'linear-gradient(to bottom, #7dd3fc 0%, #38bdf8 55%, #2563eb 100%)',
        fontFamily: '"Outfit", system-ui, sans-serif',
        color: '#0c1e3d',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: '14px 28px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
          borderBottom: '1px solid rgba(30, 58, 138, 0.25)',
          boxShadow: '0 2px 0 rgba(253, 224, 71, 0.4)',
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              letterSpacing: '0.32em',
              color: '#1e3a8a',
              textTransform: 'uppercase',
            }}
          >
            New Character — Step {pickedType ? 2 : 1} of 3
          </div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 22,
              letterSpacing: '0.16em',
              color: '#172554',
              fontWeight: 800,
              textTransform: 'uppercase',
            }}
          >
            {pickedType ? `${pickedType} — pick your race` : 'Choose your type'}
          </div>
        </div>
        {pickedType && (
          <button
            type="button"
            onClick={() => setPickedType(null)}
            style={{
              background: 'rgba(255,255,255,0.6)',
              border: '1px solid rgba(30, 58, 138, 0.4)',
              borderRadius: 4,
              padding: '4px 12px',
              fontSize: 11,
              letterSpacing: '0.15em',
              color: '#172554',
              fontWeight: 700,
              cursor: 'pointer',
              textTransform: 'uppercase',
            }}
          >
            ← back to type
          </button>
        )}
      </div>

      {/* Body */}
      {pickedType === null ? (
        <TypePicker classes={classes} onPick={setPickedType} />
      ) : (
        <ClassPicker
          classes={classes}
          type={pickedType}
          selectedId={selectedId}
          onSelect={onSelect}
        />
      )}
    </div>
  );
}

function TypePicker({
  classes,
  onPick,
}: {
  classes: ClassInfo[];
  onPick: (t: TypeName) => void;
}) {
  return (
    <div style={{ flex: 1, display: 'flex', gap: 16, padding: '20px 28px', minHeight: 0 }}>
      {TYPES.map((type) => {
        const color = TYPE_COLORS[type];
        const typeClasses = classes.filter((c) => c.type === type);
        return (
          <button
            key={type}
            type="button"
            onClick={() => onPick(type)}
            style={{
              flex: 1,
              position: 'relative',
              border: `2px solid ${color}55`,
              borderRadius: 8,
              padding: 0,
              cursor: 'pointer',
              background: 'rgba(255, 255, 255, 0.4)',
              overflow: 'hidden',
              display: 'flex',
              flexDirection: 'column',
              transition: 'transform 0.2s, border-color 0.2s, box-shadow 0.2s',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = 'translateY(-4px)';
              e.currentTarget.style.borderColor = color;
              e.currentTarget.style.boxShadow = `0 12px 24px ${color}44`;
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = 'translateY(0)';
              e.currentTarget.style.borderColor = `${color}55`;
              e.currentTarget.style.boxShadow = 'none';
            }}
          >
            {/* Portrait montage */}
            <div style={{ flex: 1, display: 'flex', position: 'relative', minHeight: 0 }}>
              {typeClasses.map((c) => (
                <div key={c.id} style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
                  <img
                    src={getClassArtPath(c.id)}
                    alt=""
                    style={{
                      position: 'absolute',
                      inset: 0,
                      width: '100%',
                      height: '100%',
                      objectFit: 'cover',
                      objectPosition: 'center top',
                      opacity: 0.65,
                    }}
                  />
                </div>
              ))}
              {/* Color wash + glow */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `linear-gradient(180deg, ${color}22 0%, transparent 40%, rgba(12, 30, 61, 0.6) 100%)`,
                  pointerEvents: 'none',
                }}
              />
              {/* Big type label */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  pointerEvents: 'none',
                }}
              >
                <span
                  style={{
                    fontFamily: '"Orbitron", "Outfit", sans-serif',
                    fontSize: 56,
                    fontWeight: 900,
                    letterSpacing: '0.16em',
                    color,
                    textTransform: 'uppercase',
                    textShadow:
                      '0 4px 18px rgba(0,0,0,0.7), 0 0 36px rgba(0,0,0,0.5)',
                  }}
                >
                  {type}
                </span>
              </div>
            </div>

            {/* Blurb footer */}
            <div
              style={{
                padding: '12px 16px',
                background: 'rgba(255, 255, 255, 0.65)',
                borderTop: `1px solid ${color}55`,
                textAlign: 'left',
                color: '#172554',
              }}
            >
              <div style={{ fontSize: 12, lineHeight: 1.4 }}>{TYPE_BLURB[type]}</div>
              <div
                style={{
                  marginTop: 6,
                  fontSize: 10,
                  letterSpacing: '0.2em',
                  color: '#a16207',
                  fontWeight: 700,
                  fontFamily: '"Share Tech Mono", monospace',
                }}
              >
                {typeClasses.length} CLASSES →
              </div>
            </div>
          </button>
        );
      })}
    </div>
  );
}

function ClassPicker({
  classes,
  type,
  selectedId,
  onSelect,
}: {
  classes: ClassInfo[];
  type: TypeName;
  selectedId: string;
  onSelect: (id: string) => void;
}) {
  const color = TYPE_COLORS[type];
  const inType = classes.filter((c) => c.type === type);
  const selected = inType.find((c) => c.id === selectedId) ?? inType[0];

  return (
    <div style={{ flex: 1, display: 'flex', gap: 16, padding: '16px 28px', minHeight: 0 }}>
      {/* Left: race rows */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          gap: 8,
          minHeight: 0,
        }}
      >
        {RACES.map((race) => {
          const pair = inType.filter((c) => c.race === race);
          if (pair.length === 0) {
            return (
              <div
                key={race}
                style={{
                  flex: 1,
                  display: 'flex',
                  alignItems: 'center',
                  background: 'rgba(30, 58, 138, 0.08)',
                  border: '1px dashed rgba(30, 58, 138, 0.25)',
                  borderRadius: 6,
                  padding: '0 18px',
                }}
              >
                <div
                  style={{
                    width: 90,
                    fontWeight: 800,
                    fontSize: 13,
                    letterSpacing: '0.2em',
                    color: 'rgba(30, 58, 138, 0.45)',
                    textTransform: 'uppercase',
                  }}
                >
                  {race}
                </div>
                <div
                  style={{
                    flex: 1,
                    textAlign: 'center',
                    color: 'rgba(30, 58, 138, 0.4)',
                    fontFamily: '"Share Tech Mono", monospace',
                    fontSize: 12,
                  }}
                >
                  — no {type.toLowerCase()} variant for this race —
                </div>
              </div>
            );
          }
          return (
            <div
              key={race}
              style={{
                flex: 1,
                display: 'flex',
                gap: 8,
                background: 'rgba(255, 255, 255, 0.4)',
                border: `1px solid ${color}33`,
                borderRadius: 6,
                padding: 8,
                minHeight: 0,
              }}
            >
              <div
                style={{
                  width: 80,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 800,
                  fontSize: 13,
                  letterSpacing: '0.2em',
                  color: '#172554',
                  textTransform: 'uppercase',
                  flexShrink: 0,
                }}
              >
                {race}
              </div>
              {pair.map((c) => {
                const isSelected = c.id === selectedId;
                return (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => onSelect(c.id)}
                    style={{
                      flex: 1,
                      position: 'relative',
                      cursor: 'pointer',
                      background: isSelected
                        ? `linear-gradient(180deg, ${color}33, ${color}77)`
                        : 'rgba(255, 255, 255, 0.5)',
                      border: isSelected
                        ? `2px solid ${color}`
                        : '1px solid rgba(30, 58, 138, 0.18)',
                      borderRadius: 4,
                      padding: 0,
                      overflow: 'hidden',
                      display: 'flex',
                      flexDirection: 'column',
                    }}
                  >
                    <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
                      <img
                        src={getClassArtPath(c.id)}
                        alt={c.name}
                        style={{
                          position: 'absolute',
                          inset: 0,
                          width: '100%',
                          height: '100%',
                          objectFit: 'cover',
                          objectPosition: 'center top',
                          opacity: isSelected ? 1 : 0.75,
                        }}
                      />
                    </div>
                    <div
                      style={{
                        padding: '4px 6px',
                        background: isSelected ? '#fde047' : 'rgba(255,255,255,0.85)',
                        textAlign: 'center',
                        fontSize: 12,
                        fontWeight: 700,
                        color: '#0c1e3d',
                      }}
                    >
                      {c.gender === 'Male' ? '♂' : '♀'} {c.name}
                    </div>
                  </button>
                );
              })}
            </div>
          );
        })}
      </div>

      {/* Right: detail panel */}
      <div
        style={{
          width: 280,
          flexShrink: 0,
          background: 'rgba(255, 255, 255, 0.55)',
          border: `1px solid ${color}55`,
          borderRadius: 8,
          padding: 14,
          display: 'flex',
          flexDirection: 'column',
          gap: 10,
        }}
      >
        <div
          style={{
            height: 220,
            background: `linear-gradient(180deg, ${color}11, rgba(253,224,71,0.18))`,
            border: `1px solid ${color}55`,
            borderRadius: 6,
            overflow: 'hidden',
            position: 'relative',
          }}
        >
          <img
            src={getClassArtPath(selected.id)}
            alt={selected.name}
            style={{
              position: 'absolute',
              inset: 0,
              width: '100%',
              height: '100%',
              objectFit: 'contain',
              objectPosition: 'center bottom',
            }}
          />
        </div>
        <div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 24,
              fontWeight: 900,
              color: '#172554',
              letterSpacing: '0.08em',
            }}
          >
            {selected.name}
          </div>
          <div style={{ fontSize: 11, color: '#1e3a8a', marginTop: 1 }}>
            {selected.race} · {selected.gender} ·{' '}
            <span style={{ color, fontWeight: 700 }}>{selected.type}</span>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {(['hp', 'attack', 'defense', 'accuracy', 'technique'] as const).map((k) => {
            const v = selected.stats[k];
            const segs = statBarSegments(v);
            return (
              <div
                key={k}
                style={{
                  display: 'grid',
                  gridTemplateColumns: '60px 1fr 30px',
                  gap: 6,
                  fontSize: 11,
                  alignItems: 'center',
                }}
              >
                <span
                  style={{
                    textTransform: 'uppercase',
                    letterSpacing: '0.15em',
                    color: '#1e3a8a',
                    fontWeight: 600,
                  }}
                >
                  {k}
                </span>
                <span
                  style={{
                    display: 'inline-block',
                    height: 8,
                    background: 'rgba(30, 58, 138, 0.2)',
                    borderRadius: 4,
                    overflow: 'hidden',
                    position: 'relative',
                  }}
                >
                  <span
                    style={{
                      position: 'absolute',
                      inset: 0,
                      width: `${segs * 10}%`,
                      background: `linear-gradient(to right, ${color}, ${color}99)`,
                      borderRadius: 4,
                    }}
                  />
                </span>
                <span
                  style={{
                    textAlign: 'right',
                    fontFamily: '"Share Tech Mono", monospace',
                    color: '#172554',
                    fontWeight: 700,
                  }}
                >
                  {v}
                </span>
              </div>
            );
          })}
        </div>

        {selected.bonuses.length > 0 && (
          <div
            style={{
              marginTop: 2,
              padding: '6px 10px',
              background: 'rgba(253, 224, 71, 0.2)',
              border: '1px solid rgba(253, 224, 71, 0.55)',
              borderRadius: 4,
              fontSize: 10,
              color: '#3f2a02',
              lineHeight: 1.4,
            }}
          >
            {selected.bonuses.join(' · ')}
          </div>
        )}
      </div>
    </div>
  );
}
