import { useState } from 'react';
import { ALL_CLASSES, type ClassInfo } from '../data/classData';
import { getClassArtPath } from '../data/constants';
import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;
const TYPE_COLORS: Record<string, string> = {
  Hunter: '#ff6b6b',
  Ranger: '#51cf66',
  Force: '#6b8afd',
};

function ClassCard({ cls, selected, onClick }: { cls: ClassInfo; selected: boolean; onClick: () => void }) {
  return (
    <div
      onClick={onClick}
      style={{
        margin: '4px 0',
        borderRadius: 8,
        cursor: 'pointer',
        transition: 'all 0.15s',
        border: selected ? '2px solid #6b8afd' : '2px solid transparent',
        overflow: 'hidden',
        position: 'relative',
        background: '#0a0a1a',
      }}
    >
      {/* Full art as card background */}
      <img
        src={getClassArtPath(cls.id)}
        alt={cls.name}
        style={{
          width: '100%',
          height: 120,
          objectFit: 'cover',
          objectPosition: 'top center',
          display: 'block',
          filter: selected ? 'brightness(1.1)' : 'brightness(0.7)',
          transition: 'filter 0.2s',
        }}
      />
      {/* Name overlay at bottom */}
      <div style={{
        position: 'absolute',
        bottom: 0, left: 0, right: 0,
        padding: '20px 10px 8px',
        background: 'linear-gradient(transparent, rgba(0,0,0,0.85))',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontSize: 14, fontWeight: 700, color: '#e0e0e0' }}>{cls.name}</span>
          <span style={{
            fontSize: 9, padding: '1px 5px', borderRadius: 3,
            background: cls.gender === 'Male' ? '#2a4a8a' : '#6a2a5a',
            color: cls.gender === 'Male' ? '#88aaff' : '#dd88cc',
          }}>{cls.gender === 'Male' ? '♂' : '♀'}</span>
          <span style={{ fontSize: 10, color: '#888' }}>{cls.race}</span>
        </div>
      </div>
    </div>
  );
}

export default function ClassStep({ state, dispatch }: { state: CharacterState; dispatch: React.Dispatch<CharacterAction> }) {
  const [expandedType, setExpandedType] = useState<string | null>(null);

  const classesByType: Record<string, ClassInfo[]> = {};
  for (const type of TYPE_ORDER) {
    classesByType[type] = ALL_CLASSES.filter(c => c.type === type);
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 0, height: '100%' }}>
      <div style={{ fontSize: 13, color: '#888', marginBottom: 8, textAlign: 'center' }}>
        Select your class
      </div>
      <div style={{ display: 'flex', flex: 1, gap: 0, overflow: 'hidden' }}>
        {TYPE_ORDER.map(type => {
          const isExpanded = expandedType === type;
          const color = TYPE_COLORS[type];
          const classes = classesByType[type];

          return (
            <div
              key={type}
              onClick={() => !isExpanded && setExpandedType(type)}
              style={{
                flex: isExpanded ? 5 : 1,
                display: 'flex',
                flexDirection: 'column',
                background: isExpanded ? '#0e0e1e' : '#12122a',
                borderLeft: `3px solid ${color}`,
                cursor: isExpanded ? 'default' : 'pointer',
                transition: 'flex 0.3s ease',
                overflow: 'hidden',
                minWidth: 0,
                position: 'relative',
              }}
            >
              {/* Collapsed: vertical art slivers side by side */}
              {!isExpanded && (
                <>
                  {/* Class art as vertical strips */}
                  <div style={{
                    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                    display: 'flex', flexDirection: 'row',
                  }}>
                    {classes.map(cls => (
                      <div key={cls.id} style={{ flex: 1, overflow: 'hidden' }}>
                        <img
                          src={getClassArtPath(cls.id)}
                          alt=""
                          style={{
                            width: '100%', height: '100%',
                            objectFit: 'cover', objectPosition: 'center top',
                            opacity: state.classId === cls.id ? 0.6 : 0.2,
                            transition: 'opacity 0.2s',
                          }}
                        />
                      </div>
                    ))}
                  </div>
                  {/* Type label overlay */}
                  <div style={{
                    position: 'relative', zIndex: 1,
                    flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                    <div style={{
                      writingMode: 'vertical-rl',
                      textOrientation: 'mixed',
                      fontSize: 14, fontWeight: 700, color,
                      textShadow: '0 0 10px rgba(0,0,0,0.9), 0 0 20px rgba(0,0,0,0.7)',
                      letterSpacing: 2,
                    }}>
                      {type}
                    </div>
                  </div>
                </>
              )}

              {/* Expanded: type header + class cards */}
              {isExpanded && (
                <>
                  <div
                    onClick={(e) => { e.stopPropagation(); setExpandedType(null); }}
                    style={{
                      padding: '12px 14px 8px',
                      cursor: 'pointer',
                      borderBottom: `1px solid ${color}33`,
                    }}
                  >
                    <span style={{ fontSize: 18, fontWeight: 700, color }}>{type}</span>
                  </div>
                  <div style={{ flex: 1, overflowY: 'auto', padding: '4px 8px 8px' }}>
                    {classes.map(cls => (
                      <ClassCard
                        key={cls.id}
                        cls={cls}
                        selected={state.classId === cls.id}
                        onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
                      />
                    ))}
                  </div>
                </>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
