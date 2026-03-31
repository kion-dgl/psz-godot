import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';
import { ALL_CLASSES, type ClassInfo } from '../data/classData';

interface Props {
  state: CharacterState;
  dispatch: React.Dispatch<CharacterAction>;
}

const TYPE_COLORS: Record<string, string> = {
  Hunter: '#ff6b6b',
  Ranger: '#51cf66',
  Force: '#748ffc',
};

const STAT_MAX: Record<string, number> = {
  hp: 100,
  pp: 110,
  attack: 65,
  defense: 15,
  accuracy: 180,
  evasion: 25,
  technique: 60,
};

const STAT_LABELS: Record<string, string> = {
  hp: 'HP',
  pp: 'PP',
  attack: 'ATK',
  defense: 'DEF',
  accuracy: 'ACC',
  evasion: 'EVA',
  technique: 'TEC',
};

function StatBar({ label, value, max }: { label: string; value: number; max: number }) {
  const pct = Math.min(100, (value / max) * 100);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11 }}>
      <span style={{ color: '#888', width: 28, textAlign: 'right', flexShrink: 0 }}>{label}</span>
      <div style={{ flex: 1, height: 6, background: '#1a1a2e', borderRadius: 3, overflow: 'hidden' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: '#6b8afd', borderRadius: 3, transition: 'width 0.2s' }} />
      </div>
      <span style={{ color: '#aaa', width: 28, fontSize: 10, flexShrink: 0 }}>{value}</span>
    </div>
  );
}

function ClassCard({ cls, selected, onClick }: { cls: ClassInfo; selected: boolean; onClick: () => void }) {
  const typeColor = TYPE_COLORS[cls.type] || '#888';
  return (
    <button
      onClick={onClick}
      style={{
        background: selected ? '#2a2a5e' : '#16162a',
        border: selected ? '2px solid #6b8afd' : '2px solid #2a2a4a',
        borderRadius: 8,
        padding: '12px 14px',
        textAlign: 'left',
        cursor: 'pointer',
        transition: 'border-color 0.15s, background 0.15s',
        width: '100%',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
        <span style={{ color: '#e0e0e0', fontSize: 14, fontWeight: 600 }}>{cls.name}</span>
        <span style={{
          fontSize: 10,
          padding: '1px 6px',
          borderRadius: 3,
          background: typeColor + '22',
          color: typeColor,
          fontWeight: 600,
        }}>
          {cls.type}
        </span>
        <span style={{
          fontSize: 10,
          padding: '1px 6px',
          borderRadius: 3,
          background: cls.gender === 'Male' ? '#4488ff22' : '#ff448822',
          color: cls.gender === 'Male' ? '#6699ff' : '#ff6699',
        }}>
          {cls.gender}
        </span>
      </div>
      {cls.bonuses.length > 0 && (
        <div style={{ fontSize: 11, color: '#8888cc', marginBottom: 6 }}>
          {cls.bonuses.join(' / ')}
        </div>
      )}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        {Object.entries(cls.stats).map(([key, value]) => (
          <StatBar key={key} label={STAT_LABELS[key] || key} value={value} max={STAT_MAX[key] || 200} />
        ))}
      </div>
    </button>
  );
}

export default function ClassStep({ state, dispatch }: Props) {
  if (!state.race) return null;

  const filtered = ALL_CLASSES.filter((c) => c.race === state.race);
  const grouped: Record<string, ClassInfo[]> = {};
  for (const cls of filtered) {
    if (!grouped[cls.type]) grouped[cls.type] = [];
    grouped[cls.type].push(cls);
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <h2 style={{ margin: 0, color: '#e0e0e0', fontSize: 20 }}>Choose Your Class</h2>
      <p style={{ margin: 0, color: '#888', fontSize: 13 }}>
        {state.race} classes available. Select one to see their stats.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginTop: 4, overflowY: 'auto', maxHeight: 'calc(100vh - 280px)' }}>
        {Object.entries(grouped).map(([type, classes]) => (
          <div key={type}>
            <div style={{ color: TYPE_COLORS[type] || '#888', fontSize: 12, fontWeight: 600, marginBottom: 8, textTransform: 'uppercase', letterSpacing: 1 }}>
              {type}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {classes.map((cls) => (
                <ClassCard
                  key={cls.id}
                  cls={cls}
                  selected={state.classId === cls.id}
                  onClick={() => dispatch({ type: 'SET_CLASS', classId: cls.id })}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
