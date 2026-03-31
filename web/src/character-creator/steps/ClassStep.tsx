import { useState } from 'react';
import { ALL_CLASSES, type ClassInfo } from '../data/classData';
import { getClassArtPath } from '../data/constants';
import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';

type SelectorStyle = 'dreamcast' | 'gamecube';

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;
const TYPE_COLORS: Record<string, string> = {
  Hunter: '#ff6b6b',
  Ranger: '#51cf66',
  Force: '#6b8afd',
};

// ── Dreamcast Style ─────────────────────────────────────────────────────────
// All 14 classes as vertical slivers. Selected one expands to full width.
// Colored top border indicates type (red/green/blue).

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
            {/* Character art fills the panel */}
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

            {/* Name overlay — only when expanded */}
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
// Left: type list (Hunter/Ranger/Force) then class names.
// Right: class art panel. All class images shown, selected is full opacity.

function GamecubeSelector({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [activeType, setActiveType] = useState<string>('Hunter');

  const filteredClasses = ALL_CLASSES.filter(c => c.type === activeType);
  const selectedCls = ALL_CLASSES.find(c => c.id === state.classId);

  return (
    <div style={{ display: 'flex', flex: 1, gap: 0, overflow: 'hidden' }}>
      {/* Left panel: type tabs + class list */}
      <div style={{
        width: 160, flexShrink: 0,
        display: 'flex', flexDirection: 'column',
        background: '#0e0e1e',
        borderRight: '1px solid #2a2a4a',
      }}>
        {/* Type tabs */}
        {TYPE_ORDER.map(type => (
          <div
            key={type}
            onClick={() => setActiveType(type)}
            style={{
              padding: '10px 14px',
              cursor: 'pointer',
              background: activeType === type ? '#1a1a3a' : 'transparent',
              borderLeft: `3px solid ${activeType === type ? TYPE_COLORS[type] : 'transparent'}`,
              color: activeType === type ? TYPE_COLORS[type] : '#666',
              fontSize: 13,
              fontWeight: activeType === type ? 700 : 400,
              transition: 'all 0.15s',
            }}
          >
            {type}
          </div>
        ))}
        <div style={{ height: 1, background: '#2a2a4a', margin: '4px 0' }} />
        {/* Class list */}
        {filteredClasses.map(cls => {
          const isSelected = state.classId === cls.id;
          return (
            <div
              key={cls.id}
              onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
              style={{
                padding: '8px 14px',
                cursor: 'pointer',
                background: isSelected ? '#2a3a6a' : 'transparent',
                color: isSelected ? '#e0e0e0' : '#888',
                fontSize: 12,
                fontWeight: isSelected ? 600 : 400,
                transition: 'all 0.15s',
                display: 'flex', alignItems: 'center', gap: 6,
              }}
            >
              <span style={{
                fontSize: 9,
                color: cls.gender === 'Male' ? '#88aaff' : '#dd88cc',
              }}>{cls.gender === 'Male' ? '♂' : '♀'}</span>
              {cls.name}
            </div>
          );
        })}
      </div>

      {/* Right panel: class art gallery */}
      <div style={{
        flex: 1, position: 'relative', overflow: 'hidden',
        background: '#0a0a16',
      }}>
        {/* All class images stacked, only selected visible */}
        {filteredClasses.map(cls => (
          <img
            key={cls.id}
            src={getClassArtPath(cls.id)}
            alt={cls.name}
            style={{
              position: 'absolute',
              top: 0, left: 0, right: 0, bottom: 0,
              width: '100%', height: '100%',
              objectFit: 'contain', objectPosition: 'center',
              opacity: state.classId === cls.id ? 1 : 0.08,
              transition: 'opacity 0.3s',
            }}
          />
        ))}

        {/* Selected class name overlay */}
        {selectedCls && (
          <div style={{
            position: 'absolute',
            bottom: 0, left: 0, right: 0,
            padding: '40px 16px 16px',
            background: 'linear-gradient(transparent, rgba(0,0,0,0.85))',
            zIndex: 1,
          }}>
            <div style={{ fontSize: 20, fontWeight: 700, color: '#e0e0e0' }}>{selectedCls.name}</div>
            <div style={{ fontSize: 12, color: '#888', marginTop: 2 }}>
              {selectedCls.race} · {selectedCls.gender} · {selectedCls.type}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}


// ── Main ClassStep ──────────────────────────────────────────────────────────

export default function ClassStep({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [style, setStyle] = useState<SelectorStyle>('dreamcast');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Style toggle */}
      <div style={{ display: 'flex', justifyContent: 'center', gap: 8, padding: '8px 0' }}>
        {(['dreamcast', 'gamecube'] as SelectorStyle[]).map(s => (
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

      {/* Selected style */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {style === 'dreamcast' ? (
          <DreamcastSelector state={state} dispatch={dispatch} />
        ) : (
          <GamecubeSelector state={state} dispatch={dispatch} />
        )}
      </div>
    </div>
  );
}
