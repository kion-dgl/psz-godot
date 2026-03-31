import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';

interface Props {
  state: CharacterState;
  dispatch: React.Dispatch<CharacterAction>;
}

const RACES: { id: 'Human' | 'Newman' | 'Cast'; label: string; description: string }[] = [
  {
    id: 'Human',
    label: 'Human',
    description: 'Balanced across all stats. Can use techniques and equip any weapon type. A solid choice for any role.',
  },
  {
    id: 'Newman',
    label: 'Newman',
    description: 'Descendants of genetically-enhanced humans. Higher technique power and natural PP recovery, but lower HP.',
  },
  {
    id: 'Cast',
    label: 'Cast',
    description: 'Androids built for combat. Highest HP and accuracy with natural HP recovery, but cannot use techniques.',
  },
];

export default function RaceStep({ state, dispatch }: Props) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <h2 style={{ margin: 0, color: '#e0e0e0', fontSize: 20 }}>Choose Your Race</h2>
      <p style={{ margin: 0, color: '#888', fontSize: 13 }}>
        Each race has unique strengths that shape your journey on Ragol.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 8 }}>
        {RACES.map((race) => {
          const selected = state.race === race.id;
          return (
            <button
              key={race.id}
              onClick={() => dispatch({ type: 'SET_RACE', race: race.id })}
              style={{
                background: selected ? '#2a2a5e' : '#16162a',
                border: selected ? '2px solid #6b8afd' : '2px solid #2a2a4a',
                borderRadius: 8,
                padding: '16px 20px',
                textAlign: 'left',
                cursor: 'pointer',
                transition: 'border-color 0.15s, background 0.15s',
              }}
            >
              <div style={{ color: '#e0e0e0', fontSize: 16, fontWeight: 600, marginBottom: 6 }}>
                {race.label}
              </div>
              <div style={{ color: '#888', fontSize: 13, lineHeight: 1.5 }}>
                {race.description}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
