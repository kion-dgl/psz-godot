import { getClassArtPath } from '../character-creator/data/constants';
import { TYPE_COLORS, statBarSegments, type VariantProps } from './types';

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;

const BG = '#f3e6c4';
const PANEL = '#e8d6a8';
const BORDER = '#7a3a2a';
const ACCENT = '#a83a2a';
const INK = '#2a1a0a';

export default function PsoListView({ classes, selectedId, onSelect }: VariantProps) {
  const sorted = TYPE_ORDER.flatMap((type) => classes.filter((c) => c.type === type));
  const selected = classes.find((c) => c.id === selectedId)!;

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        background: BG,
        backgroundImage:
          'repeating-linear-gradient(0deg, rgba(122, 58, 42, 0.04) 0 2px, transparent 2px 4px)',
        fontFamily: '"Share Tech Mono", "Courier New", monospace',
        color: INK,
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      <header
        style={{
          padding: '14px 28px',
          background: ACCENT,
          color: '#f6e4b0',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          borderBottom: `3px double ${INK}`,
          letterSpacing: '0.18em',
          fontWeight: 700,
        }}
      >
        <span style={{ fontSize: 16 }}>SELECT CHARACTER CLASS</span>
        <span style={{ fontSize: 11, opacity: 0.85 }}>SLOT 1 / 4 — NEW</span>
      </header>

      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        {/* Left list */}
        <div
          style={{
            width: 360,
            background: PANEL,
            borderRight: `2px solid ${BORDER}`,
            display: 'flex',
            flexDirection: 'column',
            overflow: 'auto',
          }}
        >
          {sorted.map((cls, i) => {
            const isSelected = cls.id === selectedId;
            const isTypeStart = i === 0 || sorted[i - 1].type !== cls.type;
            return (
              <div key={cls.id}>
                {isTypeStart && (
                  <div
                    style={{
                      padding: '8px 16px 4px',
                      fontSize: 10,
                      letterSpacing: '0.3em',
                      color: TYPE_COLORS[cls.type],
                      textTransform: 'uppercase',
                      fontWeight: 700,
                      borderTop: i === 0 ? 'none' : `1px solid ${BORDER}`,
                    }}
                  >
                    ▸ {cls.type}
                  </div>
                )}
                <div
                  onClick={() => onSelect(cls.id)}
                  style={{
                    padding: '8px 16px',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 10,
                    cursor: 'pointer',
                    background: isSelected ? ACCENT : 'transparent',
                    color: isSelected ? '#f6e4b0' : INK,
                  }}
                >
                  <span
                    style={{
                      width: 14,
                      display: 'inline-block',
                      color: isSelected ? '#f6e4b0' : 'transparent',
                    }}
                  >
                    ▶
                  </span>
                  <div
                    style={{
                      width: 32,
                      height: 32,
                      borderRadius: 2,
                      border: `1px solid ${isSelected ? '#f6e4b0' : BORDER}`,
                      overflow: 'hidden',
                      background: '#1a1410',
                      flexShrink: 0,
                    }}
                  >
                    <img
                      src={getClassArtPath(cls.id)}
                      alt=""
                      style={{
                        width: '110%',
                        height: '110%',
                        objectFit: 'cover',
                        objectPosition: 'top center',
                      }}
                    />
                  </div>
                  <span style={{ fontSize: 14, flex: 1, fontWeight: isSelected ? 700 : 500 }}>
                    {cls.name}
                  </span>
                  <span
                    style={{
                      fontSize: 10,
                      color: isSelected ? 'rgba(246, 228, 176, 0.7)' : '#7a5a3a',
                    }}
                  >
                    {cls.gender === 'Male' ? '♂' : '♀'}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Right detail */}
        <div
          style={{
            flex: 1,
            display: 'flex',
            padding: 24,
            gap: 24,
            background: BG,
            minWidth: 0,
          }}
        >
          {/* Portrait */}
          <div
            style={{
              width: 340,
              flexShrink: 0,
              border: `2px solid ${BORDER}`,
              background: '#1a1410',
              position: 'relative',
              overflow: 'hidden',
            }}
          >
            <img
              src={getClassArtPath(selected.id)}
              alt={selected.name}
              style={{
                width: '100%',
                height: '100%',
                objectFit: 'contain',
                objectPosition: 'center bottom',
              }}
            />
            <div
              style={{
                position: 'absolute',
                inset: 0,
                background:
                  'linear-gradient(180deg, rgba(168, 58, 42, 0.0) 60%, rgba(168, 58, 42, 0.4) 100%)',
                pointerEvents: 'none',
              }}
            />
            <div
              style={{
                position: 'absolute',
                top: 8,
                left: 8,
                fontSize: 10,
                letterSpacing: '0.2em',
                color: '#f6e4b0',
                background: 'rgba(0,0,0,0.5)',
                padding: '2px 6px',
              }}
            >
              PROFILE
            </div>
          </div>

          {/* Stats */}
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
            <div
              style={{
                fontSize: 32,
                fontWeight: 800,
                color: ACCENT,
                letterSpacing: '0.1em',
                lineHeight: 1,
              }}
            >
              {selected.name}
            </div>
            <div style={{ fontSize: 12, color: '#5a3a1a', marginBottom: 6 }}>
              {selected.race} · {selected.gender} ·{' '}
              <span style={{ color: TYPE_COLORS[selected.type], fontWeight: 700 }}>
                {selected.type.toUpperCase()}
              </span>
            </div>

            {(['hp', 'pp', 'attack', 'defense', 'accuracy', 'evasion', 'technique'] as const).map(
              (key) => {
                const v = selected.stats[key];
                const segs = statBarSegments(v);
                return (
                  <div
                    key={key}
                    style={{
                      display: 'grid',
                      gridTemplateColumns: '80px 1fr 36px',
                      gap: 8,
                      fontSize: 12,
                      alignItems: 'center',
                    }}
                  >
                    <span style={{ textTransform: 'uppercase', letterSpacing: '0.15em', color: '#5a3a1a' }}>
                      {key}
                    </span>
                    <span style={{ color: ACCENT, letterSpacing: 2, fontWeight: 700 }}>
                      {'█'.repeat(segs)}
                      <span style={{ color: '#c8b08a' }}>{'░'.repeat(10 - segs)}</span>
                    </span>
                    <span style={{ textAlign: 'right', color: INK, fontWeight: 700 }}>{v}</span>
                  </div>
                );
              },
            )}

            {selected.bonuses.length > 0 && (
              <div
                style={{
                  marginTop: 10,
                  padding: '8px 12px',
                  border: `1px dashed ${BORDER}`,
                  fontSize: 11,
                  color: '#5a3a1a',
                  lineHeight: 1.5,
                }}
              >
                <div style={{ fontSize: 9, letterSpacing: '0.25em', color: ACCENT, marginBottom: 2 }}>
                  CLASS BONUSES
                </div>
                {selected.bonuses.join(' · ')}
              </div>
            )}
          </div>
        </div>
      </div>

      <footer
        style={{
          padding: '10px 28px',
          background: ACCENT,
          color: '#f6e4b0',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          borderTop: `3px double ${INK}`,
          fontSize: 12,
          letterSpacing: '0.15em',
        }}
      >
        <span>▲▼ NAVIGATE</span>
        <span>SPACE: SELECT · ESC: BACK</span>
        <span style={{ fontWeight: 700 }}>CONTINUE ▶</span>
      </footer>
    </div>
  );
}
