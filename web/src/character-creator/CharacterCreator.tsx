import { useCharacterState, type Step } from './hooks/useCharacterState';
import CharacterPreview from './CharacterPreview';
import ClassStep from './steps/ClassStep';
import AppearanceStep from './steps/AppearanceStep';
import NameStep from './steps/NameStep';
import ConfirmStep from './steps/ConfirmStep';

const STEP_LABELS: Record<Step, string> = {
  class: 'Class',
  appearance: 'Appearance',
  name: 'Name',
  confirm: 'Confirm',
};

const STEPS: Step[] = ['class', 'appearance', 'name', 'confirm'];

function StepIndicator({ current }: { current: number }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'center', padding: '12px 0' }}>
      {STEPS.map((s, i) => {
        const isActive = i === current;
        const isDone = i < current;
        return (
          <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 12,
              fontWeight: 600,
              background: isActive ? '#6b8afd' : isDone ? '#3a4a8a' : '#2a2a4a',
              color: isActive ? '#fff' : isDone ? '#8899cc' : '#555',
              transition: 'background 0.2s, color 0.2s',
            }}>
              {isDone ? '\u2713' : i + 1}
            </div>
            <span style={{
              fontSize: 11,
              color: isActive ? '#e0e0e0' : '#666',
            }}>
              {STEP_LABELS[s]}
            </span>
            {i < STEPS.length - 1 && (
              <div style={{ width: 20, height: 1, background: '#2a2a4a' }} />
            )}
          </div>
        );
      })}
    </div>
  );
}

export default function CharacterCreator() {
  const { state, dispatch, stepIndex, stepCount, canGoNext, canGoBack } = useCharacterState();
  const showPreview = state.classId !== null;

  const renderStep = () => {
    switch (state.step) {
      case 'class': return <ClassStep state={state} dispatch={dispatch} />;
      case 'appearance': return <AppearanceStep state={state} dispatch={dispatch} />;
      case 'name': return <NameStep state={state} dispatch={dispatch} />;
      case 'confirm': return <ConfirmStep state={state} dispatch={dispatch} />;
    }
  };

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      background: '#1a1a2e',
      color: '#e0e0e0',
      overflow: 'hidden',
    }}>
      {/* Step indicator */}
      <div style={{ padding: '8px 24px', borderBottom: '1px solid #2a2a4a', background: '#16162a' }}>
        <StepIndicator current={stepIndex} />
      </div>

      {/* Main content */}
      <div style={{
        flex: 1,
        display: 'flex',
        overflow: 'hidden',
      }}>
        {/* Left panel: step content */}
        <div style={{
          width: showPreview ? '420px' : '100%',
          maxWidth: showPreview ? '420px' : '100%',
          padding: '24px',
          overflowY: 'auto',
          flexShrink: 0,
        }}>
          {renderStep()}
        </div>

        {/* Right panel: 3D preview */}
        {showPreview && (
          <div style={{ flex: 1, padding: '16px 16px 16px 0' }}>
            <CharacterPreview
              classId={state.classId}
              variationIndex={state.variationIndex}
              hairColorIndex={state.hairColorIndex}
              skinToneIndex={state.skinToneIndex}
              bodyColorIndex={state.bodyColorIndex}
            />
          </div>
        )}
      </div>

      {/* Navigation buttons */}
      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: '12px 24px',
        borderTop: '1px solid #2a2a4a',
        background: '#16162a',
      }}>
        <button
          onClick={() => dispatch({ type: 'PREV_STEP' })}
          disabled={!canGoBack}
          style={{
            padding: '8px 20px',
            background: canGoBack ? '#2a2a4a' : 'transparent',
            border: '1px solid #2a2a4a',
            borderRadius: 6,
            color: canGoBack ? '#e0e0e0' : '#444',
            fontSize: 13,
            cursor: canGoBack ? 'pointer' : 'default',
            opacity: canGoBack ? 1 : 0.5,
          }}
        >
          Back
        </button>
        <span style={{ fontSize: 12, color: '#666' }}>
          Step {stepIndex + 1} of {stepCount}
        </span>
        {state.step !== 'confirm' ? (
          <button
            onClick={() => dispatch({ type: 'NEXT_STEP' })}
            disabled={!canGoNext}
            style={{
              padding: '8px 20px',
              background: canGoNext ? '#6b8afd' : '#2a2a4a',
              border: 'none',
              borderRadius: 6,
              color: canGoNext ? '#fff' : '#555',
              fontSize: 13,
              fontWeight: 600,
              cursor: canGoNext ? 'pointer' : 'default',
              opacity: canGoNext ? 1 : 0.5,
            }}
          >
            Next
          </button>
        ) : (
          <div style={{ width: 74 }} />
        )}
      </div>
    </div>
  );
}
