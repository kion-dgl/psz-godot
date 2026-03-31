import type { CharacterState, CharacterAction } from '../hooks/useCharacterState';

interface Props {
  state: CharacterState;
  dispatch: React.Dispatch<CharacterAction>;
}

const MAX_NAME_LENGTH = 16;

export default function NameStep({ state, dispatch }: Props) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <h2 style={{ margin: 0, color: '#e0e0e0', fontSize: 20 }}>Name Your Character</h2>
      <p style={{ margin: 0, color: '#888', fontSize: 13 }}>
        Choose a name that will be known across Ragol. Maximum {MAX_NAME_LENGTH} characters.
      </p>
      <div style={{ marginTop: 12 }}>
        <input
          type="text"
          value={state.name}
          onChange={(e) => {
            const value = e.target.value.slice(0, MAX_NAME_LENGTH);
            dispatch({ type: 'SET_NAME', name: value });
          }}
          placeholder="Enter character name..."
          maxLength={MAX_NAME_LENGTH}
          style={{
            width: '100%',
            padding: '12px 16px',
            fontSize: 16,
            background: '#16162a',
            border: '2px solid #2a2a4a',
            borderRadius: 8,
            color: '#e0e0e0',
            outline: 'none',
            boxSizing: 'border-box',
            transition: 'border-color 0.15s',
          }}
          onFocus={(e) => { e.currentTarget.style.borderColor = '#6b8afd'; }}
          onBlur={(e) => { e.currentTarget.style.borderColor = '#2a2a4a'; }}
          autoFocus
        />
        <div style={{ marginTop: 8, fontSize: 12, color: '#888', textAlign: 'right' }}>
          {state.name.length} / {MAX_NAME_LENGTH}
        </div>
      </div>
    </div>
  );
}
