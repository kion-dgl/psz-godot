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
      position: 'relative',
    }}>
      {/* Drifting white particles overlay */}
      <style>{`
        @keyframes particleDrift {
          0% { transform: translate(0, 0); }
          25% { transform: translate(var(--dx), var(--dy)); }
          50% { transform: translate(calc(var(--dx) * -0.5), calc(var(--dy) * 1.5)); }
          75% { transform: translate(calc(var(--dx) * 0.8), calc(var(--dy) * -0.3)); }
          100% { transform: translate(0, 0); }
        }
      `}</style>
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
        pointerEvents: 'none', zIndex: 0, overflow: 'hidden',
      }}>
        {Array.from({ length: 150 }).map((_, i) => {
          const size = Math.random() * 3 + 1;
          const dx = (Math.random() - 0.5) * 40;
          const dy = (Math.random() - 0.5) * 30;
          const duration = 15 + Math.random() * 25;
          const delay = Math.random() * -duration;
          return (
            <div key={i} style={{
              position: 'absolute',
              left: `${Math.random() * 100}%`,
              top: `${Math.random() * 100}%`,
              width: size,
              height: size,
              borderRadius: '50%',
              background: `rgba(255, 255, 255, ${Math.random() * 0.4 + 0.15})`,
              '--dx': `${dx}px`,
              '--dy': `${dy}px`,
              animation: `particleDrift ${duration}s ${delay}s ease-in-out infinite`,
            } as React.CSSProperties} />
          );
        })}
      </div>

      {/* Title bar — metallic grey */}
      <div style={{
        height: 44,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'linear-gradient(to bottom, #d0d4dc, #a8aab4, #888c98, #a0a4b0)',
        borderBottom: '2px solid #686c78',
        position: 'relative',
        flexShrink: 0,
        zIndex: 1,
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
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden', position: 'relative', zIndex: 1 }}>
        <div style={{
          width: showPreview ? 300 : 1280,
          flexShrink: 0,
          display: 'flex',
          overflow: 'hidden',
        }}>
          {renderStep()}
        </div>

        {showPreview && (
          <div style={{
            flex: 1, background: 'transparent',
            position: 'relative',
            left: -80, top: 40,
          }}>
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
        zIndex: 1,
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
