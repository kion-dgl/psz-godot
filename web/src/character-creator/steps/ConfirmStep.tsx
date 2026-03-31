import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';
import { getClassById } from '../data/classData';
import { HAIR_COLORS, SKIN_TONES, BODY_COLORS } from '../data/constants';

interface Props {
  state: CharacterState;
  dispatch: React.Dispatch<CharacterAction>;
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid #2a2a4a' }}>
      <span style={{ color: '#888', fontSize: 13 }}>{label}</span>
      <span style={{ color: '#e0e0e0', fontSize: 13, fontWeight: 500 }}>{value}</span>
    </div>
  );
}

export default function ConfirmStep({ state, dispatch }: Props) {
  const cls = state.classId ? getClassById(state.classId) : null;
  const isCast = cls?.race === 'Cast';

  const exportCharacter = () => {
    const data = {
      name: state.name,
      class_id: state.classId,
      appearance: {
        variation_index: state.variationIndex,
        hair_color_index: state.hairColorIndex,
        skin_tone_index: state.skinToneIndex,
        body_color_index: state.bodyColorIndex,
      },
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${state.name.trim() || 'character'}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <h2 style={{ margin: 0, color: '#e0e0e0', fontSize: 20 }}>Confirm Character</h2>
      <p style={{ margin: 0, color: '#888', fontSize: 13 }}>
        Review your choices before finalizing.
      </p>
      <div style={{
        background: '#16162a',
        borderRadius: 8,
        padding: '12px 16px',
        border: '1px solid #2a2a4a',
        marginTop: 4,
      }}>
        <SummaryRow label="Name" value={state.name || '(unnamed)'} />
        <SummaryRow label="Race" value={state.race || '--'} />
        <SummaryRow label="Class" value={cls?.name || '--'} />
        <SummaryRow label="Type" value={cls?.type || '--'} />
        <SummaryRow label="Gender" value={cls?.gender || '--'} />
        <SummaryRow label="Head Variation" value={`Type ${state.variationIndex + 1}`} />
        <SummaryRow label={isCast ? 'Body Color A' : 'Hair Color'} value={isCast ? `Color ${state.hairColorIndex + 1}` : (HAIR_COLORS[state.hairColorIndex] || '--')} />
        <SummaryRow label={isCast ? 'Body Color C' : 'Skin Tone'} value={isCast ? `Color ${state.skinToneIndex + 1}` : (SKIN_TONES[state.skinToneIndex] || '--')} />
        <SummaryRow label={isCast ? 'Body Color B' : 'Costume Color'} value={isCast ? `Color ${state.bodyColorIndex + 1}` : (BODY_COLORS[state.bodyColorIndex] || '--')} />
      </div>

      {cls && cls.bonuses.length > 0 && (
        <div style={{ background: '#16162a', borderRadius: 8, padding: '12px 16px', border: '1px solid #2a2a4a' }}>
          <div style={{ color: '#888', fontSize: 12, marginBottom: 6, textTransform: 'uppercase', letterSpacing: 1 }}>Bonuses</div>
          {cls.bonuses.map((b, i) => (
            <div key={i} style={{ color: '#8888cc', fontSize: 13, padding: '2px 0' }}>{b}</div>
          ))}
        </div>
      )}

      <div style={{ display: 'flex', gap: 12, marginTop: 8 }}>
        <button
          onClick={exportCharacter}
          style={{
            flex: 1,
            padding: '12px 16px',
            background: '#6b8afd',
            border: 'none',
            borderRadius: 8,
            color: '#fff',
            fontSize: 14,
            fontWeight: 600,
            cursor: 'pointer',
          }}
        >
          Export JSON
        </button>
        <button
          onClick={() => dispatch({ type: 'RESET' })}
          style={{
            padding: '12px 16px',
            background: 'transparent',
            border: '1px solid #2a2a4a',
            borderRadius: 8,
            color: '#888',
            fontSize: 14,
            cursor: 'pointer',
          }}
        >
          Start Over
        </button>
      </div>
    </div>
  );
}
