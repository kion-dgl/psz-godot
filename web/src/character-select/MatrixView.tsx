import { getClassArtPath } from '../character-creator/data/constants';
import { TYPE_COLORS, statBarSegments, type VariantProps } from './types';

const TYPES = ['Hunter', 'Ranger', 'Force'] as const;
const RACES = ['Human', 'Newman', 'Cast'] as const;

export default function MatrixView({ classes, selectedId, onSelect }: VariantProps) {
  const selected = classes.find((c) => c.id === selectedId)!;

  // Each cell: pair of M/F classes for the given race+type, or empty.
  const cell = (race: string, type: string) => {
    const found = classes.filter((c) => c.race === race && c.type === type);
    return found.length ? found : null;
  };

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        background: 'linear-gradient(to bottom, #7dd3fc 0%, #38bdf8 55%, #2563eb 100%)',
        fontFamily: '"Outfit", "Inter", system-ui, sans-serif',
        color: '#0c1e3d',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: '18px 32px 14px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
          borderBottom: '1px solid rgba(30, 58, 138, 0.25)',
          boxShadow: '0 2px 0 rgba(253, 224, 71, 0.4)',
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              letterSpacing: '0.32em',
              color: '#1e3a8a',
              textTransform: 'uppercase',
            }}
          >
            New Character — Step 1 of 3
          </div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 22,
              letterSpacing: '0.16em',
              color: '#172554',
              fontWeight: 800,
              textTransform: 'uppercase',
            }}
          >
            Choose your class
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: 11, color: '#1e3a8a', opacity: 0.75 }}>
            14 classes · 3 types
          </div>
          <div
            style={{
              fontSize: 14,
              color: '#a16207',
              fontWeight: 700,
              fontFamily: '"Share Tech Mono", monospace',
            }}
          >
            {selected.name}
          </div>
        </div>
      </div>

      {/* Matrix grid */}
      <div style={{ flex: 1, display: 'flex', gap: 16, padding: '16px 32px', minHeight: 0 }}>
        {/* Left: 3x3 cells */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: '70px repeat(3, 1fr)',
            gridTemplateRows: '40px repeat(3, 1fr)',
            gap: 6,
            flex: 1,
            minWidth: 0,
          }}
        >
          {/* Top-left corner */}
          <div />
          {/* Column headers (types) */}
          {TYPES.map((type) => (
            <div
              key={type}
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: TYPE_COLORS[type],
                fontWeight: 800,
                fontSize: 13,
                letterSpacing: '0.25em',
                textTransform: 'uppercase',
                background: 'rgba(255, 255, 255, 0.35)',
                borderRadius: 6,
                border: `1px solid ${TYPE_COLORS[type]}66`,
              }}
            >
              {type}
            </div>
          ))}

          {/* Rows: race header + 3 cells */}
          {RACES.map((race) => (
            <Row key={race} race={race} cell={cell} selectedId={selectedId} onSelect={onSelect} />
          ))}
        </div>

        {/* Right: detail card */}
        <div
          style={{
            width: 280,
            flexShrink: 0,
            background: 'rgba(255, 255, 255, 0.55)',
            border: '1px solid rgba(30, 58, 138, 0.35)',
            borderRadius: 8,
            padding: 14,
            display: 'flex',
            flexDirection: 'column',
            gap: 10,
          }}
        >
          <div
            style={{
              height: 200,
              background: 'linear-gradient(180deg, rgba(255,255,255,0.4), rgba(253,224,71,0.18))',
              borderRadius: 6,
              border: '1px solid rgba(253, 224, 71, 0.5)',
              overflow: 'hidden',
              position: 'relative',
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
          </div>
          <div>
            <div
              style={{
                fontFamily: '"Orbitron", "Outfit", sans-serif',
                fontSize: 22,
                fontWeight: 900,
                color: '#172554',
                letterSpacing: '0.08em',
              }}
            >
              {selected.name}
            </div>
            <div style={{ fontSize: 11, color: '#1e3a8a', marginTop: 1 }}>
              {selected.race} · {selected.gender} ·{' '}
              <span style={{ color: TYPE_COLORS[selected.type], fontWeight: 700 }}>
                {selected.type}
              </span>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
            {(['hp', 'attack', 'defense', 'accuracy', 'technique'] as const).map((key) => {
              const v = selected.stats[key];
              const segs = statBarSegments(v);
              return (
                <div
                  key={key}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '60px 1fr 30px',
                    gap: 6,
                    fontSize: 11,
                    alignItems: 'center',
                  }}
                >
                  <span
                    style={{
                      textTransform: 'uppercase',
                      letterSpacing: '0.15em',
                      color: '#1e3a8a',
                      fontWeight: 600,
                    }}
                  >
                    {key}
                  </span>
                  <span
                    style={{
                      display: 'inline-block',
                      height: 8,
                      background: 'rgba(30, 58, 138, 0.2)',
                      borderRadius: 4,
                      overflow: 'hidden',
                      position: 'relative',
                    }}
                  >
                    <span
                      style={{
                        position: 'absolute',
                        top: 0,
                        left: 0,
                        bottom: 0,
                        width: `${segs * 10}%`,
                        background: 'linear-gradient(to right, #fde047, #f59e0b)',
                        borderRadius: 4,
                      }}
                    />
                  </span>
                  <span
                    style={{
                      textAlign: 'right',
                      fontFamily: '"Share Tech Mono", monospace',
                      color: '#172554',
                      fontWeight: 700,
                    }}
                  >
                    {v}
                  </span>
                </div>
              );
            })}
          </div>

          {selected.bonuses.length > 0 && (
            <div
              style={{
                marginTop: 4,
                padding: '6px 10px',
                background: 'rgba(253, 224, 71, 0.2)',
                border: '1px solid rgba(253, 224, 71, 0.55)',
                borderRadius: 4,
                fontSize: 10,
                color: '#3f2a02',
                lineHeight: 1.4,
              }}
            >
              {selected.bonuses.join(' · ')}
            </div>
          )}
        </div>
      </div>

      {/* Footer */}
      <div
        style={{
          padding: '10px 32px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          fontSize: 11,
          color: 'rgba(30, 58, 138, 0.7)',
          fontFamily: '"Share Tech Mono", monospace',
          borderTop: '1px solid rgba(30, 58, 138, 0.2)',
        }}
      >
        <span>D-PAD / TOUCH SELECTS A CELL</span>
        <span>
          <span style={{ color: '#a16207', fontWeight: 700 }}>● A</span> CONFIRM ·{' '}
          <span style={{ color: '#a16207', fontWeight: 700 }}>● B</span> CANCEL
        </span>
      </div>
    </div>
  );
}

function Row({
  race,
  cell,
  selectedId,
  onSelect,
}: {
  race: (typeof RACES)[number];
  cell: (r: string, t: string) => ReturnType<VariantProps['classes']['filter']> | null;
  selectedId: string;
  onSelect: (id: string) => void;
}) {
  return (
    <>
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#172554',
          fontWeight: 800,
          fontSize: 12,
          letterSpacing: '0.2em',
          textTransform: 'uppercase',
          background: 'rgba(255, 255, 255, 0.35)',
          borderRadius: 6,
          border: '1px solid rgba(30, 58, 138, 0.3)',
        }}
      >
        {race}
      </div>
      {TYPES.map((type) => {
        const entries = cell(race, type);
        if (!entries) {
          return (
            <div
              key={type}
              style={{
                background: 'rgba(30, 58, 138, 0.08)',
                border: '1px dashed rgba(30, 58, 138, 0.25)',
                borderRadius: 6,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'rgba(30, 58, 138, 0.4)',
                fontSize: 14,
                fontFamily: '"Share Tech Mono", monospace',
              }}
            >
              — locked —
            </div>
          );
        }
        return (
          <div
            key={type}
            style={{
              background: 'rgba(255, 255, 255, 0.5)',
              border: `1px solid ${TYPE_COLORS[type]}55`,
              borderRadius: 6,
              padding: 6,
              display: 'flex',
              gap: 6,
              minHeight: 0,
            }}
          >
            {entries.map((c) => {
              const isSelected = c.id === selectedId;
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => onSelect(c.id)}
                  style={{
                    flex: 1,
                    position: 'relative',
                    background: isSelected
                      ? `linear-gradient(180deg, ${TYPE_COLORS[type]}33, ${TYPE_COLORS[type]}88)`
                      : 'rgba(255, 255, 255, 0.4)',
                    border: isSelected
                      ? `2px solid ${TYPE_COLORS[type]}`
                      : '1px solid rgba(30, 58, 138, 0.15)',
                    borderRadius: 4,
                    padding: 0,
                    cursor: 'pointer',
                    overflow: 'hidden',
                    display: 'flex',
                    flexDirection: 'column',
                    minWidth: 0,
                  }}
                >
                  <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
                    <img
                      src={getClassArtPath(c.id)}
                      alt={c.name}
                      style={{
                        width: '100%',
                        height: '100%',
                        objectFit: 'cover',
                        objectPosition: 'center top',
                        opacity: isSelected ? 1 : 0.72,
                      }}
                    />
                  </div>
                  <div
                    style={{
                      padding: '3px 4px',
                      fontSize: 10,
                      fontWeight: 700,
                      color: isSelected ? '#0c1e3d' : '#1e3a8a',
                      background: isSelected ? '#fde047' : 'rgba(255,255,255,0.7)',
                      letterSpacing: '0.05em',
                      textAlign: 'center',
                    }}
                  >
                    {c.gender === 'Male' ? '♂' : '♀'} {c.name.slice(2)}
                  </div>
                </button>
              );
            })}
          </div>
        );
      })}
    </>
  );
}
