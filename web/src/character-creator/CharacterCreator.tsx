import { useCharacterState } from './hooks/useCharacterState';
import CharacterPreview from './CharacterPreview';
import ClassStep from './steps/ClassStep';
import AppearanceStep from './steps/AppearanceStep';
import NameStep from './steps/NameStep';
import ConfirmStep from './steps/ConfirmStep';

export default function CharacterCreator() {
  const { state, dispatch, canGoNext, canGoBack } = useCharacterState();
  const showPreview = state.classId !== null && state.step !== 'class';

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
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      height: '100%', background: '#0a0a16',
    }}>
    {/* Fixed 720p viewport */}
    <div style={{
      width: 1280,
      height: 720,
      display: 'flex',
      flexDirection: 'column',
      background: '#1a1a2e',
      color: '#e0e0e0',
      overflow: 'hidden',
    }}>
      {/* Title bar */}
      <div style={{
        height: 44,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'linear-gradient(to bottom, #3a4a6a, #1e2a44)',
        borderBottom: '2px solid #5a6a8a',
        position: 'relative',
        flexShrink: 0,
      }}>
        <span style={{
          fontSize: 20,
          fontWeight: 800,
          color: '#c8d8f8',
          textShadow: '1px 1px 0 #1a2a44, 2px 2px 0 #0a1a2a',
          letterSpacing: 3,
          textTransform: 'uppercase',
        }}>
          Create Character
        </span>
        {/* Decorative line accents */}
        <div style={{
          position: 'absolute', bottom: -2, left: 0, right: 0, height: 2,
          background: 'linear-gradient(90deg, transparent 10%, #7a8aaa 30%, #7a8aaa 70%, transparent 90%)',
        }} />
      </div>

      {/* Main content */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Step content — full width on class step, left panel otherwise */}
        <div style={{
          width: showPreview ? 420 : 1280,
          flexShrink: 0,
          display: 'flex',
          overflow: 'hidden',
        }}>
          {renderStep()}
        </div>

        {/* 3D preview (appearance step onward) */}
        {showPreview && (
          <div style={{ flex: 1, padding: 12 }}>
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

      {/* Bottom nav bar */}
      <div style={{
        height: 44,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 20px',
        background: 'linear-gradient(to top, #2a3a5a, #1a2a44)',
        borderTop: '1px solid #3a4a6a',
        flexShrink: 0,
      }}>
        {canGoBack ? (
          <button
            onClick={() => dispatch({ type: 'PREV_STEP' })}
            style={{
              padding: '6px 18px',
              background: 'transparent',
              border: '1px solid #4a5a7a',
              borderRadius: 4,
              color: '#8899bb',
              fontSize: 13,
              cursor: 'pointer',
            }}
          >
            ← Back
          </button>
        ) : <div />}

        {state.step !== 'confirm' ? (
          <button
            onClick={() => canGoNext && dispatch({ type: 'NEXT_STEP' })}
            style={{
              padding: '6px 24px',
              background: canGoNext ? '#4a6aaa' : '#2a3a5a',
              border: canGoNext ? '1px solid #6a8acc' : '1px solid #3a4a6a',
              borderRadius: 4,
              color: canGoNext ? '#e0e8ff' : '#556',
              fontSize: 13,
              fontWeight: 600,
              cursor: canGoNext ? 'pointer' : 'default',
            }}
          >
            OK →
          </button>
        ) : <div />}
      </div>
    </div>
    </div>
  );
}
