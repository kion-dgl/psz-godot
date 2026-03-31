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

function GamecubeSelector({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [hoveredType, setHoveredType] = useState<string | null>(null);
  const [hoveredClass, setHoveredClass] = useState<string | null>(null);

  // Which classes to show art for
  const visibleType = hoveredType || (state.classId ? ALL_CLASSES.find(c => c.id === state.classId)?.type || null : null);
  const visibleClasses = visibleType ? ALL_CLASSES.filter(c => c.type === visibleType) : [];
  const focusedClassId = hoveredClass || state.classId;

  return (
    <div style={{ display: 'flex', flex: 1, gap: 0, overflow: 'hidden' }}>
      {/* Left: accordion sections */}
      <div style={{
        width: 170, flexShrink: 0,
        display: 'flex', flexDirection: 'column',
        background: '#0e0e1e',
        borderRight: '1px solid #2a2a4a',
        overflowY: 'auto',
      }}>
        {TYPE_ORDER.map(type => {
          const color = TYPE_COLORS[type];
          const classes = ALL_CLASSES.filter(c => c.type === type);

          return (
            <div key={type}>
              {/* Type header */}
              <div
                onMouseEnter={() => { setHoveredType(type); setHoveredClass(null); }}
                onMouseLeave={() => setHoveredType(null)}
                style={{
                  padding: '10px 14px',
                  cursor: 'pointer',
                  borderLeft: `3px solid ${color}`,
                  background: visibleType === type ? '#1a1a3a' : 'transparent',
                  color: visibleType === type ? color : '#777',
                  fontSize: 14,
                  fontWeight: 700,
                  transition: 'all 0.15s',
                  letterSpacing: 0.5,
                }}
              >
                {type}
              </div>

              {/* Class items inside the section */}
              {classes.map(cls => {
                const isSelected = state.classId === cls.id;
                const isFocused = focusedClassId === cls.id;
                return (
                  <div
                    key={cls.id}
                    onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
                    onMouseEnter={() => { setHoveredType(type); setHoveredClass(cls.id); }}
                    onMouseLeave={() => setHoveredClass(null)}
                    style={{
                      padding: '6px 14px 6px 20px',
                      cursor: 'pointer',
                      background: isSelected ? '#2a3a6a' : isFocused ? '#1a2a4a' : 'transparent',
                      color: isSelected ? '#e0e0e0' : isFocused ? '#ccc' : '#666',
                      fontSize: 12,
                      fontWeight: isSelected ? 600 : 400,
                      transition: 'all 0.1s',
                      display: 'flex', alignItems: 'center', gap: 6,
                      borderLeft: `3px solid ${isSelected ? color : 'transparent'}`,
                    }}
                  >
                    <span style={{
                      fontSize: 9,
                      color: cls.gender === 'Male' ? '#88aaff' : '#dd88cc',
                    }}>{cls.gender === 'Male' ? '♂' : '♀'}</span>
                    {cls.name}
                    <span style={{ fontSize: 9, color: '#555', marginLeft: 'auto' }}>{cls.race}</span>
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>

      {/* Right: class art panel */}
      <div style={{
        flex: 1, position: 'relative', overflow: 'hidden',
        background: '#0a0a16',
      }}>
        {/* When hovering a type header: show all classes in that type spread out */}
        {visibleClasses.length > 0 && !focusedClassId && (
          <div style={{
            position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
            display: 'flex',
          }}>
            {visibleClasses.map(cls => (
              <div key={cls.id} style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
                <img
                  src={getClassArtPath(cls.id)}
                  alt={cls.name}
                  style={{
                    width: '100%', height: '100%',
                    objectFit: 'cover', objectPosition: 'center top',
                    opacity: 0.7,
                  }}
                />
                <div style={{
                  position: 'absolute', bottom: 0, left: 0, right: 0,
                  padding: '16px 6px 6px',
                  background: 'linear-gradient(transparent, rgba(0,0,0,0.85))',
                  textAlign: 'center',
                }}>
                  <div style={{ fontSize: 10, fontWeight: 600, color: '#ccc' }}>{cls.name}</div>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* When a specific class is focused/selected: full art with others faded */}
        {focusedClassId && visibleClasses.length > 0 && visibleClasses.map(cls => (
          <img
            key={cls.id}
            src={getClassArtPath(cls.id)}
            alt={cls.name}
            style={{
              position: 'absolute',
              top: 0, left: 0, right: 0, bottom: 0,
              width: '100%', height: '100%',
              objectFit: 'contain', objectPosition: 'center',
              opacity: cls.id === focusedClassId ? 1 : 0.06,
              transition: 'opacity 0.25s',
              zIndex: cls.id === focusedClassId ? 2 : 1,
            }}
          />
        ))}

        {/* Name overlay for focused class */}
        {focusedClassId && (() => {
          const cls = ALL_CLASSES.find(c => c.id === focusedClassId);
          if (!cls) return null;
          return (
            <div style={{
              position: 'absolute',
              bottom: 0, left: 0, right: 0,
              padding: '40px 16px 16px',
              background: 'linear-gradient(transparent, rgba(0,0,0,0.85))',
              zIndex: 3,
            }}>
              <div style={{ fontSize: 22, fontWeight: 700, color: '#e0e0e0' }}>{cls.name}</div>
              <div style={{ fontSize: 12, color: '#888', marginTop: 2 }}>
                {cls.race} · {cls.gender} · {cls.type}
              </div>
            </div>
          );
        })()}

        {/* Empty state */}
        {!visibleType && (
          <div style={{
            position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <span style={{ color: '#444', fontSize: 14 }}>Hover a class type to preview</span>
          </div>
        )}
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
  const [style, setStyle] = useState<SelectorStyle>('gamecube');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'center', gap: 8, padding: '8px 0' }}>
        {(['dreamcast', 'gamecube', 'psz'] as SelectorStyle[]).map(s => (
          <button
            key={s}
            onClick={() => setStyle(s)}
            style={{
              padding: '4px 14px',
              background: style === s ? '#6b8afd' : '#2a2a4a',
              border: 'none',
              borderRadius: 4,
              color: style === s ? '#fff' : '#888',
              fontSize: 11,
              fontWeight: style === s ? 600 : 400,
              cursor: 'pointer',
              textTransform: 'capitalize',
            }}
          >
            {s}
          </button>
        ))}
      </div>
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {style === 'dreamcast' && <DreamcastSelector state={state} dispatch={dispatch} />}
        {style === 'gamecube' && <GamecubeSelector state={state} dispatch={dispatch} />}
        {style === 'psz' && <PszSelector state={state} dispatch={dispatch} />}
      </div>
    </div>
  );
}
