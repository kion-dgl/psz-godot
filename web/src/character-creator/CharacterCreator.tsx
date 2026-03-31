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
      height: '100%', background: '#222',
    }}>
    {/* Fixed 720p viewport */}
    <div style={{
      width: 1280,
      height: 720,
      display: 'flex',
      flexDirection: 'column',
      background: 'linear-gradient(to bottom, #a8c8e8, #7aa8d0, #90b8dc)',
      color: '#1a2a3a',
      overflow: 'hidden',
    }}>
      {/* Title bar — metallic grey */}
      <div style={{
        height: 44,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'linear-gradient(to bottom, #d0d4dc, #a8aab4, #888c98, #a0a4b0)',
        borderBottom: '2px solid #686c78',
        position: 'relative',
        flexShrink: 0,
      }}>
        <span style={{
          fontSize: 22,
          fontWeight: 800,
          color: '#3a4a5a',
          textShadow: '1px 1px 0 rgba(255,255,255,0.4)',
          letterSpacing: 3,
        }}>
          Create Character
        </span>
        {/* Bottom accent lines */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0, height: 2,
          background: 'linear-gradient(90deg, #888 0%, #bbb 20%, #bbb 80%, #888 100%)',
        }} />
      </div>

      {/* Main content */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        <div style={{
          width: showPreview ? 420 : 1280,
          flexShrink: 0,
          display: 'flex',
          overflow: 'hidden',
        }}>
          {renderStep()}
        </div>

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

      {/* Bottom nav bar — metallic */}
      <div style={{
        height: 40,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 20px',
        background: 'linear-gradient(to top, #888c98, #a0a4b0, #b8bcc8)',
        borderTop: '2px solid #686c78',
        flexShrink: 0,
      }}>
        {canGoBack ? (
          <button
            onClick={() => dispatch({ type: 'PREV_STEP' })}
            style={{
              padding: '4px 16px',
              background: 'linear-gradient(to bottom, #e0e4ec, #c0c4cc)',
              border: '1px solid #888',
              borderRadius: 4,
              color: '#3a4a5a',
              fontSize: 13,
              fontWeight: 600,
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
              padding: '4px 22px',
              background: canGoNext
                ? 'linear-gradient(to bottom, #ffe080, #f0b830)'
                : 'linear-gradient(to bottom, #d0d4dc, #b0b4bc)',
              border: canGoNext ? '1px solid #c89020' : '1px solid #888',
              borderRadius: 4,
              color: canGoNext ? '#4a3000' : '#888',
              fontSize: 13,
              fontWeight: 700,
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
