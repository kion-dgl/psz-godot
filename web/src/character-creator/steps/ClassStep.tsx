import { useState } from 'react';
import { ALL_CLASSES, type ClassInfo } from '../data/classData';
import { getClassArtPath } from '../data/constants';
import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';

type SelectorStyle = 'dreamcast' | 'gamecube' | 'psz';

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;
const TYPE_COLORS: Record<string, string> = {
  Hunter: '#ff6b6b',
  Ranger: '#51cf66',
  Force: '#6b8afd',
};

// ── Dreamcast Style ─────────────────────────────────────────────────────────

function DreamcastSelector({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  return (
    <div style={{ display: 'flex', flex: 1, gap: 0, overflow: 'hidden', borderRadius: 6 }}>
      {ALL_CLASSES.map(cls => {
        const isSelected = state.classId === cls.id;
        const color = TYPE_COLORS[cls.type];

        return (
          <div
            key={cls.id}
            onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
            style={{
              flex: isSelected ? 6 : 1,
              display: 'flex',
              flexDirection: 'column',
              cursor: 'pointer',
              transition: 'flex 0.3s ease',
              overflow: 'hidden',
              minWidth: 0,
              position: 'relative',
              borderTop: `3px solid ${color}`,
            }}
          >
            <img
              src={getClassArtPath(cls.id)}
              alt={cls.name}
              style={{
                position: 'absolute', top: 3, left: 0, right: 0, bottom: 0,
                width: '100%', height: '100%',
                objectFit: 'cover', objectPosition: 'center top',
                opacity: isSelected ? 1 : 0.35,
                transition: 'opacity 0.25s',
              }}
            />
            {isSelected && (
              <div style={{
                position: 'absolute',
                bottom: 0, left: 0, right: 0,
                padding: '30px 12px 12px',
                background: 'linear-gradient(transparent, rgba(0,0,0,0.9))',
                zIndex: 1,
              }}>
                <div style={{ fontSize: 18, fontWeight: 700, color: '#e0e0e0' }}>{cls.name}</div>
                <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                  <span style={{
                    fontSize: 11, padding: '1px 6px', borderRadius: 3,
                    background: cls.gender === 'Male' ? '#2a4a8a' : '#6a2a5a',
                    color: cls.gender === 'Male' ? '#88aaff' : '#dd88cc',
                  }}>{cls.gender}</span>
                  <span style={{ fontSize: 11, color: '#888' }}>{cls.race}</span>
                  <span style={{ fontSize: 11, color, fontWeight: 600 }}>{cls.type}</span>
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}


// ── Gamecube Style ──────────────────────────────────────────────────────────

const TYPE_INFO: Record<string, string> = {
  Hunter: 'Proficient with melee weapons. Hunters have excellent attack power and HP, making them ideal front-line fighters.',
  Ranger: 'Proficient with guns. Rangers have excellent accuracy that allows them to hit from a distance, but lack attack power.',
  Force: 'Proficient with techniques. Forces can cast powerful spells and support allies, but have lower HP and defense.',
};

function GamecubeSelector({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [hoveredClass, setHoveredClass] = useState<string | null>(null);

  const focusedId = hoveredClass || state.classId;
  const focusedCls = focusedId ? ALL_CLASSES.find(c => c.id === focusedId) : null;
  const activeType = focusedCls?.type || (state.classId ? ALL_CLASSES.find(c => c.id === state.classId)?.type : null) || 'Hunter';
  const activeColor = TYPE_COLORS[activeType];
  const activeClasses = ALL_CLASSES.filter(c => c.type === activeType);

  return (
    <div style={{ display: 'flex', flex: 1, gap: 0, overflow: 'hidden' }}>
      {/* Left column: all classes under type headers with thumbnails */}
      <div style={{
        width: 200, flexShrink: 0,
        display: 'flex', flexDirection: 'column',
        background: '#0e0e1e',
        borderRight: '1px solid #2a2a4a',
        overflow: 'hidden',
      }}>
        {TYPE_ORDER.map(type => {
          const color = TYPE_COLORS[type];
          const classes = ALL_CLASSES.filter(c => c.type === type);
          const isActiveType = activeType === type;

          return (
            <div key={type} style={{ flex: classes.length, display: 'flex', flexDirection: 'column' }}>
              {/* Type header with vertical label */}
              <div style={{
                display: 'flex', alignItems: 'stretch', flex: 1,
                background: isActiveType ? `${color}22` : 'transparent',
                borderBottom: '1px solid #1a1a3a',
              }}>
                <div style={{
                  width: 28, flexShrink: 0,
                  background: color,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <span style={{
                    writingMode: 'vertical-rl', textOrientation: 'mixed',
                    fontSize: 11, fontWeight: 800, color: '#000',
                    letterSpacing: 1, textTransform: 'uppercase',
                  }}>{type}</span>
                </div>
                <div style={{ flex: 1 }}>
                  {classes.map(cls => {
                    const isSelected = state.classId === cls.id;
                    const isFocused = focusedId === cls.id;
                    return (
                      <div
                        key={cls.id}
                        onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
                        onMouseEnter={() => setHoveredClass(cls.id)}
                        onMouseLeave={() => setHoveredClass(null)}
                        style={{
                          display: 'flex', alignItems: 'center', gap: 8,
                          padding: '4px 8px',
                          cursor: 'pointer',
                          background: isSelected ? `${color}44` : isFocused ? `${color}22` : 'transparent',
                          transition: 'background 0.1s',
                        }}
                      >
                        {/* Small thumbnail */}
                        <img
                          src={getClassArtPath(cls.id)}
                          alt=""
                          style={{
                            width: 28, height: 32,
                            objectFit: 'cover', objectPosition: 'top center',
                            borderRadius: 3, flexShrink: 0,
                            border: isSelected ? `1px solid ${color}` : '1px solid transparent',
                          }}
                        />
                        <span style={{
                          fontSize: 13, fontWeight: isSelected ? 700 : 400,
                          color: isSelected ? '#e0e0e0' : isFocused ? '#ccc' : '#999',
                        }}>{cls.name}</span>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Right panel: type name + group art + info */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        background: '#0a0a16', overflow: 'hidden',
      }}>
        {/* Type name header */}
        <div style={{
          padding: '10px 16px',
          textAlign: 'center',
          borderBottom: `2px solid ${activeColor}`,
        }}>
          <span style={{ fontSize: 20, fontWeight: 800, color: activeColor }}>{activeType}</span>
        </div>

        {/* Class art — all type's classes shown, focused one highlighted */}
        <div style={{
          flex: 1, position: 'relative', overflow: 'hidden',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
          padding: '8px',
        }}>
          {activeClasses.map((cls, i) => {
            const isFocused = cls.id === focusedId;
            const count = activeClasses.length;
            // Offset each character horizontally so they stand side by side
            const spread = Math.min(80, 300 / count);
            const offsetX = (i - (count - 1) / 2) * spread;
            return (
              <img
                key={cls.id}
                src={getClassArtPath(cls.id)}
                alt={cls.name}
                style={{
                  position: 'absolute',
                  bottom: 0,
                  left: '50%',
                  height: '85%',
                  transform: `translateX(calc(-50% + ${offsetX}px))`,
                  objectFit: 'contain',
                  opacity: focusedId ? (isFocused ? 1 : 0.3) : 0.8,
                  transition: 'opacity 0.2s, transform 0.2s',
                  zIndex: isFocused ? 10 : 5 - Math.abs(i - (count - 1) / 2),
                  filter: isFocused ? 'brightness(1.1)' : 'brightness(0.8)',
                }}
              />
            );
          })}
        </div>

        {/* Info box */}
        <div style={{
          margin: '0 12px 12px',
          padding: '10px 14px',
          background: '#12122a',
          border: `1px solid ${activeColor}44`,
          borderRadius: 6,
        }}>
          {focusedCls ? (
            <>
              <div style={{ fontSize: 14, fontWeight: 700, color: '#e0e0e0', marginBottom: 4 }}>{focusedCls.name}</div>
              <div style={{ fontSize: 11, color: '#888' }}>{focusedCls.race} · {focusedCls.gender}</div>
              {focusedCls.bonuses.length > 0 && (
                <div style={{ fontSize: 10, color: '#8a8', marginTop: 4 }}>{focusedCls.bonuses.join(' · ')}</div>
              )}
            </>
          ) : (
            <div style={{ fontSize: 12, color: '#888' }}>{TYPE_INFO[activeType]}</div>
          )}
        </div>
      </div>
    </div>
  );
}


// ── PSZ Style ───────────────────────────────────────────────────────────────
// Step 1: pick Hunter/Ranger/Force (shows all profiles for each type).
// Step 2: pick specific class within that type (one profile at a time).

function PszSelector({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [hoveredClass, setHoveredClass] = useState<string | null>(null);

  // If a class is already selected, derive the type
  const currentType = selectedType || (state.classId ? ALL_CLASSES.find(c => c.id === state.classId)?.type || null : null);
  const focusedId = hoveredClass || state.classId;

  // Sub-step 1: pick type
  if (!currentType) {
    return (
      <div style={{ display: 'flex', flex: 1, gap: 2, overflow: 'hidden' }}>
        {TYPE_ORDER.map(type => {
          const color = TYPE_COLORS[type];
          const classes = ALL_CLASSES.filter(c => c.type === type);
          return (
            <div
              key={type}
              onClick={() => setSelectedType(type)}
              style={{
                flex: 1, cursor: 'pointer', position: 'relative',
                overflow: 'hidden', borderRadius: 6,
                border: `2px solid transparent`,
                transition: 'border-color 0.2s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = color)}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = 'transparent')}
            >
              {/* All class art spread horizontally */}
              <div style={{
                position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                display: 'flex',
              }}>
                {classes.map(cls => (
                  <div key={cls.id} style={{ flex: 1, overflow: 'hidden' }}>
                    <img
                      src={getClassArtPath(cls.id)}
                      alt={cls.name}
                      style={{
                        width: '100%', height: '100%',
                        objectFit: 'cover', objectPosition: 'center top',
                        opacity: 0.6,
                      }}
                    />
                  </div>
                ))}
              </div>
              {/* Type label overlay */}
              <div style={{
                position: 'relative', zIndex: 1,
                height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <div style={{
                  fontSize: 28, fontWeight: 800, color,
                  textShadow: '0 2px 12px rgba(0,0,0,0.9), 0 0 30px rgba(0,0,0,0.7)',
                  letterSpacing: 3,
                  textTransform: 'uppercase',
                }}>
                  {type}
                </div>
              </div>
              {/* Bottom gradient with class count */}
              <div style={{
                position: 'absolute', bottom: 0, left: 0, right: 0,
                padding: '20px 12px 10px',
                background: 'linear-gradient(transparent, rgba(0,0,0,0.8))',
                textAlign: 'center', zIndex: 1,
              }}>
                <span style={{ fontSize: 11, color: '#888' }}>{classes.length} classes</span>
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  // Sub-step 2: pick specific class within selected type
  const classes = ALL_CLASSES.filter(c => c.type === currentType);
  const color = TYPE_COLORS[currentType];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
      {/* Back to type selection */}
      <div
        onClick={() => { setSelectedType(null); setHoveredClass(null); }}
        style={{
          padding: '8px 14px', cursor: 'pointer',
          color, fontSize: 12, display: 'flex', alignItems: 'center', gap: 6,
        }}
      >
        <span style={{ fontSize: 16 }}>←</span> {currentType}
      </div>

      {/* Class profiles */}
      <div style={{ display: 'flex', flex: 1, gap: 2, overflow: 'hidden' }}>
        {classes.map(cls => {
          const isSelected = state.classId === cls.id;
          const isFocused = focusedId === cls.id;

          return (
            <div
              key={cls.id}
              onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
              onMouseEnter={() => setHoveredClass(cls.id)}
              onMouseLeave={() => setHoveredClass(null)}
              style={{
                flex: isFocused ? 3 : 1,
                position: 'relative', overflow: 'hidden',
                cursor: 'pointer',
                border: isSelected ? `2px solid ${color}` : '2px solid transparent',
                borderRadius: 6,
                transition: 'flex 0.25s ease, border-color 0.15s',
              }}
            >
              <img
                src={getClassArtPath(cls.id)}
                alt={cls.name}
                style={{
                  position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                  width: '100%', height: '100%',
                  objectFit: 'cover', objectPosition: 'center top',
                  opacity: isFocused ? 1 : 0.4,
                  transition: 'opacity 0.2s',
                }}
              />
              {/* Name overlay */}
              <div style={{
                position: 'absolute',
                bottom: 0, left: 0, right: 0,
                padding: '24px 8px 8px',
                background: 'linear-gradient(transparent, rgba(0,0,0,0.9))',
                zIndex: 1,
              }}>
                <div style={{
                  fontSize: isFocused ? 16 : 11,
                  fontWeight: 700, color: '#e0e0e0',
                  transition: 'font-size 0.2s',
                  textAlign: 'center',
                }}>
                  {cls.name}
                </div>
                {isFocused && (
                  <div style={{ fontSize: 10, color: '#888', textAlign: 'center', marginTop: 2 }}>
                    {cls.race} · {cls.gender}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}


// ── Main ClassStep ──────────────────────────────────────────────────────────

export default function ClassStep({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  return (
    <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
      <GamecubeSelector state={state} dispatch={dispatch} />
    </div>
  );
}
