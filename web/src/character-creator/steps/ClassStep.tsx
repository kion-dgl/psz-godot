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
const TYPE_DESCRIPTIONS: Record<string, string> = {
  Hunter: 'Melee combat specialists with high HP and attack power.',
  Ranger: 'Precision fighters with the highest accuracy and ranged weapons.',
  Force: 'Technique masters with powerful spells and high PP.',
};

const STAT_KEYS = ['hp', 'pp', 'attack', 'defense', 'accuracy', 'evasion', 'technique'] as const;
const STAT_LABELS: Record<string, string> = {
  hp: 'HP', pp: 'PP', attack: 'ATK', defense: 'DEF',
  accuracy: 'ACC', evasion: 'EVA', technique: 'TEC',
};

const STAT_MAX: Record<string, number> = {};
for (const key of STAT_KEYS) {
  STAT_MAX[key] = Math.max(...ALL_CLASSES.map(c => c.stats[key]));
}

function StatBar({ label, value, max }: { label: string; value: number; max: number }) {
  const pct = (value / max) * 100;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11 }}>
      <span style={{ width: 28, color: '#888', textAlign: 'right' }}>{label}</span>
      <div style={{ flex: 1, height: 6, background: '#1a1a2e', borderRadius: 3 }}>
        <div style={{ width: `${pct}%`, height: '100%', background: '#6b8afd', borderRadius: 3, transition: 'width 0.2s' }} />
      </div>
      <span style={{ width: 28, color: '#aaa', textAlign: 'right' }}>{value}</span>
    </div>
  );
}

function ClassCard({ cls, selected, onClick }: { cls: ClassInfo; selected: boolean; onClick: () => void }) {
  return (
    <div
      onClick={onClick}
      style={{
        padding: '8px 12px',
        margin: '2px 0',
        background: selected ? '#2a3a6a' : '#1e1e3a',
        border: selected ? '1px solid #6b8afd' : '1px solid transparent',
        borderRadius: 6,
        cursor: 'pointer',
        transition: 'all 0.15s',
        display: 'flex',
        gap: 10,
      }}
    >
      {/* Class art thumbnail */}
      <img
        src={getClassArtPath(cls.id)}
        alt={cls.name}
        style={{
          width: 48,
          height: 54,
          objectFit: 'cover',
          objectPosition: 'top center',
          borderRadius: 4,
          flexShrink: 0,
        }}
      />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 14, fontWeight: 600, color: '#e0e0e0' }}>{cls.name}</span>
          <span style={{
            fontSize: 10, padding: '1px 6px', borderRadius: 3,
            background: cls.gender === 'Male' ? '#2a4a8a' : '#6a2a5a',
            color: cls.gender === 'Male' ? '#88aaff' : '#dd88cc',
          }}>{cls.gender === 'Male' ? '♂' : '♀'}</span>
          <span style={{ fontSize: 10, color: '#666' }}>{cls.race}</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {STAT_KEYS.map(key => (
            <StatBar key={key} label={STAT_LABELS[key]} value={cls.stats[key]} max={STAT_MAX[key]} />
          ))}
        </div>
        {cls.bonuses.length > 0 && (
          <div style={{ marginTop: 4, fontSize: 10, color: '#8a8' }}>
            {cls.bonuses.join(' · ')}
          </div>
        )}
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
                flex: isExpanded ? 4 : 1,
                display: 'flex',
                flexDirection: 'column',
                background: isExpanded ? '#16162a' : '#1a1a2e',
                borderLeft: `3px solid ${color}`,
                cursor: isExpanded ? 'default' : 'pointer',
                transition: 'flex 0.3s ease',
                overflow: 'hidden',
                minWidth: 0,
              }}
            >
              {/* Type header */}
              <div
                onClick={(e) => {
                  if (isExpanded) { e.stopPropagation(); setExpandedType(null); }
                }}
                style={{
                  padding: isExpanded ? '10px 12px' : '10px 6px',
                  textAlign: 'center',
                  cursor: 'pointer',
                }}
              >
                <div style={{
                  fontSize: isExpanded ? 16 : 13,
                  fontWeight: 700,
                  color,
                  writingMode: isExpanded ? 'horizontal-tb' : 'vertical-rl',
                  textOrientation: 'mixed',
                  transition: 'font-size 0.2s',
                }}>
                  {type}
                </div>
                {isExpanded && (
                  <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>
                    {TYPE_DESCRIPTIONS[type]}
                  </div>
                )}
              </div>

              {/* Expanded: class cards */}
              {isExpanded && (
                <div style={{ flex: 1, overflowY: 'auto', padding: '0 8px 8px 8px' }}>
                  {classes.map(cls => (
                    <ClassCard
                      key={cls.id}
                      cls={cls}
                      selected={state.classId === cls.id}
                      onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
                    />
                  ))}
                </div>
              )}

              {/* Collapsed: class art + vertical names */}
              {!isExpanded && (
                <div style={{
                  flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center',
                  gap: 4, padding: '8px 2px', position: 'relative', overflow: 'hidden',
                }}>
                  {/* Background art (first class in group) */}
                  <img
                    src={getClassArtPath(classes[0].id)}
                    alt=""
                    style={{
                      position: 'absolute', top: 0, left: 0, width: '100%', height: '100%',
                      objectFit: 'cover', opacity: 0.15, pointerEvents: 'none',
                    }}
                  />
                  {classes.map(cls => (
                    <div key={cls.id} style={{
                      fontSize: 9,
                      color: state.classId === cls.id ? '#6b8afd' : '#888',
                      fontWeight: state.classId === cls.id ? 700 : 400,
                      writingMode: 'vertical-rl',
                      textOrientation: 'mixed',
                      position: 'relative',
                      zIndex: 1,
                    }}>
                      {cls.name}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
