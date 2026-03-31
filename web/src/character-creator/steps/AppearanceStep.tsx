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

function ArrowSelector({ label, current, total, isActive, onPrev, onNext, onClick }: {
  label: string;
  current: number;
  total: number;
  isActive: boolean;
  onPrev: () => void;
  onNext: () => void;
  onClick: () => void;
}) {
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex',
        alignItems: 'center',
        padding: '12px 14px',
        background: isActive
          ? 'linear-gradient(to right, #f0a830, #e8c040, #f0a830)'
          : 'linear-gradient(to bottom, #e8e8f0, #d8d8e4)',
        border: isActive ? '1px solid #c08020' : '1px solid #b8b8c8',
        borderRadius: 3,
        cursor: 'pointer',
      }}
    >
      <span style={{
        flex: 1,
        fontSize: 14, fontWeight: isActive ? 700 : 500,
        color: isActive ? '#3a2000' : '#2a2a3a',
      }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <span
          onClick={(e) => { e.stopPropagation(); onPrev(); }}
          style={{
            fontSize: 16, fontWeight: 800, cursor: 'pointer',
            color: '#2a8a2a',
            userSelect: 'none',
          }}
        >◀</span>
        <span style={{
          fontSize: 13, fontWeight: 600, minWidth: 42, textAlign: 'center',
          color: isActive ? '#3a2000' : '#4a4a5a',
          background: 'rgba(255,255,255,0.4)',
          borderRadius: 8,
          padding: '1px 8px',
        }}>
          {current + 1}/{total}
        </span>
        <span
          onClick={(e) => { e.stopPropagation(); onNext(); }}
          style={{
            fontSize: 16, fontWeight: 800, cursor: 'pointer',
            color: '#2a8a2a',
            userSelect: 'none',
          }}
        >▶</span>
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
    <div style={{
      display: 'flex', flexDirection: 'column',
      justifyContent: 'center',
      padding: '20px 12px',
      height: '100%',
      background: 'rgba(0,0,0,0.15)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <ArrowSelector
          label={labels.head}
          current={state.variationIndex}
          total={HEAD_VARIATIONS}
          isActive={true}
          onPrev={() => dispatch({ type: 'SET_VARIATION', index: wrap(state.variationIndex, -1, HEAD_VARIATIONS) })}
          onNext={() => dispatch({ type: 'SET_VARIATION', index: wrap(state.variationIndex, 1, HEAD_VARIATIONS) })}
          onClick={() => {}}
        />
        <ArrowSelector
          label={labels.hair}
          current={state.hairColorIndex}
          total={HAIR_COLORS.length}
          isActive={false}
          onPrev={() => dispatch({ type: 'SET_HAIR_COLOR', index: wrap(state.hairColorIndex, -1, HAIR_COLORS.length) })}
          onNext={() => dispatch({ type: 'SET_HAIR_COLOR', index: wrap(state.hairColorIndex, 1, HAIR_COLORS.length) })}
          onClick={() => {}}
        />
        <ArrowSelector
          label={labels.body}
          current={state.bodyColorIndex}
          total={BODY_COLORS.length}
          isActive={false}
          onPrev={() => dispatch({ type: 'SET_BODY_COLOR', index: wrap(state.bodyColorIndex, -1, BODY_COLORS.length) })}
          onNext={() => dispatch({ type: 'SET_BODY_COLOR', index: wrap(state.bodyColorIndex, 1, BODY_COLORS.length) })}
          onClick={() => {}}
        />
        <ArrowSelector
          label={labels.skin}
          current={state.skinToneIndex}
          total={SKIN_TONES.length}
          isActive={false}
          onPrev={() => dispatch({ type: 'SET_SKIN_TONE', index: wrap(state.skinToneIndex, -1, SKIN_TONES.length) })}
          onNext={() => dispatch({ type: 'SET_SKIN_TONE', index: wrap(state.skinToneIndex, 1, SKIN_TONES.length) })}
          onClick={() => {}}
        />
        <ArrowSelector
          label="Voice Type"
          current={0}
          total={8}
          isActive={false}
          onPrev={() => {}}
          onNext={() => {}}
          onClick={() => {}}
        />
        <ArrowSelector
          label="Mag Color"
          current={0}
          total={5}
          isActive={false}
          onPrev={() => {}}
          onNext={() => {}}
          onClick={() => {}}
        />
      </div>
    </div>
  );
}
