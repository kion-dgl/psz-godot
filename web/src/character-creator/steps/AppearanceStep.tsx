import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';
import { getClassById } from '../data/classData';
import {
  HEAD_VARIATIONS, HAIR_COLORS, SKIN_TONES, BODY_COLORS,
  CAST_LABELS, HUMAN_LABELS,
} from '../data/constants';

interface Props {
  state: CharacterState;
  dispatch: React.Dispatch<CharacterAction>;
}

function ArrowSelector({ label, value, valueLabel, onPrev, onNext }: {
  label: string;
  value: number;
  valueLabel: string;
  onPrev: () => void;
  onNext: () => void;
}) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '10px 14px',
      background: '#16162a',
      borderRadius: 6,
      border: '1px solid #2a2a4a',
    }}>
      <span style={{ color: '#888', fontSize: 13, width: 120, flexShrink: 0 }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <button
          onClick={onPrev}
          style={{
            background: '#2a2a4a',
            border: 'none',
            color: '#e0e0e0',
            width: 28,
            height: 28,
            borderRadius: 4,
            cursor: 'pointer',
            fontSize: 14,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          &lt;
        </button>
        <span style={{ color: '#e0e0e0', fontSize: 13, minWidth: 80, textAlign: 'center' }}>
          {valueLabel}
        </span>
        <button
          onClick={onNext}
          style={{
            background: '#2a2a4a',
            border: 'none',
            color: '#e0e0e0',
            width: 28,
            height: 28,
            borderRadius: 4,
            cursor: 'pointer',
            fontSize: 14,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          &gt;
        </button>
      </div>
    </div>
  );
}

function wrap(value: number, delta: number, max: number): number {
  return ((value + delta) % max + max) % max;
}

export default function AppearanceStep({ state, dispatch }: Props) {
  if (!state.classId) return null;
  const cls = getClassById(state.classId);
  if (!cls) return null;

  const isCast = cls.race === 'Cast';
  const labels = isCast ? CAST_LABELS : HUMAN_LABELS;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <h2 style={{ margin: 0, color: '#e0e0e0', fontSize: 20 }}>Customize Appearance</h2>
      <p style={{ margin: 0, color: '#888', fontSize: 13 }}>
        Adjust your character's look. The preview updates in real time.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
        <ArrowSelector
          label={labels.head}
          value={state.variationIndex}
          valueLabel={`Type ${state.variationIndex + 1}`}
          onPrev={() => dispatch({ type: 'SET_VARIATION', index: wrap(state.variationIndex, -1, HEAD_VARIATIONS) })}
          onNext={() => dispatch({ type: 'SET_VARIATION', index: wrap(state.variationIndex, 1, HEAD_VARIATIONS) })}
        />
        <ArrowSelector
          label={labels.hair}
          value={state.hairColorIndex}
          valueLabel={isCast ? `Color ${state.hairColorIndex + 1}` : HAIR_COLORS[state.hairColorIndex]}
          onPrev={() => dispatch({ type: 'SET_HAIR_COLOR', index: wrap(state.hairColorIndex, -1, HAIR_COLORS.length) })}
          onNext={() => dispatch({ type: 'SET_HAIR_COLOR', index: wrap(state.hairColorIndex, 1, HAIR_COLORS.length) })}
        />
        <ArrowSelector
          label={labels.skin}
          value={state.skinToneIndex}
          valueLabel={isCast ? `Color ${state.skinToneIndex + 1}` : SKIN_TONES[state.skinToneIndex]}
          onPrev={() => dispatch({ type: 'SET_SKIN_TONE', index: wrap(state.skinToneIndex, -1, SKIN_TONES.length) })}
          onNext={() => dispatch({ type: 'SET_SKIN_TONE', index: wrap(state.skinToneIndex, 1, SKIN_TONES.length) })}
        />
        <ArrowSelector
          label={labels.body}
          value={state.bodyColorIndex}
          valueLabel={isCast ? `Color ${state.bodyColorIndex + 1}` : BODY_COLORS[state.bodyColorIndex]}
          onPrev={() => dispatch({ type: 'SET_BODY_COLOR', index: wrap(state.bodyColorIndex, -1, BODY_COLORS.length) })}
          onNext={() => dispatch({ type: 'SET_BODY_COLOR', index: wrap(state.bodyColorIndex, 1, BODY_COLORS.length) })}
        />
      </div>
    </div>
  );
}
