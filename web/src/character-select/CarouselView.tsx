import { getClassArtPath } from '../character-creator/data/constants';
import { TYPE_COLORS, statBarSegments, type VariantProps } from './types';

export default function CarouselView({ classes, selectedId, onSelect }: VariantProps) {
  const idx = classes.findIndex((c) => c.id === selectedId);
  const selected = classes[idx];
  const total = classes.length;
  const next = () => onSelect(classes[(idx + 1) % total].id);
  const prev = () => onSelect(classes[(idx - 1 + total) % total].id);
  const accent = TYPE_COLORS[selected.type];

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        position: 'relative',
        background:
          'radial-gradient(ellipse at top, #1f2547 0%, #0a0d22 55%, #050714 100%)',
        fontFamily: '"Outfit", system-ui, sans-serif',
        color: '#e0e0f0',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* Glow tint per class type */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `radial-gradient(ellipse at center 30%, ${accent}26 0%, transparent 60%)`,
          pointerEvents: 'none',
          transition: 'background 0.3s ease',
        }}
      />

      {/* Header */}
      <div
        style={{
          padding: '18px 32px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          zIndex: 2,
          borderBottom: '1px solid rgba(255,255,255,0.06)',
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              letterSpacing: '0.35em',
              color: '#88aaff',
              textTransform: 'uppercase',
            }}
          >
            Phantasy Star Zero · Profile Setup
          </div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 22,
              fontWeight: 900,
              letterSpacing: '0.18em',
              color: '#fff',
              textTransform: 'uppercase',
            }}
          >
            Class
          </div>
        </div>
        <div
          style={{
            fontFamily: '"Share Tech Mono", monospace',
            fontSize: 12,
            color: '#88aaff',
          }}
        >
          {String(idx + 1).padStart(2, '0')} <span style={{ opacity: 0.5 }}>/ {total}</span>
        </div>
      </div>

      {/* Stage */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 24,
          padding: '12px 24px',
          position: 'relative',
          minHeight: 0,
          zIndex: 2,
        }}
      >
        <ArrowButton dir="prev" onClick={prev} />

        {/* Hero card */}
        <div
          style={{
            flex: '0 0 740px',
            height: '100%',
            maxHeight: 420,
            display: 'flex',
            background: 'linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0.01))',
            border: `1px solid ${accent}55`,
            borderRadius: 12,
            overflow: 'hidden',
            boxShadow: `0 0 36px ${accent}33, inset 0 0 30px rgba(0,0,0,0.4)`,
            position: 'relative',
          }}
        >
          {/* Portrait */}
          <div
            style={{
              flex: 1,
              position: 'relative',
              minWidth: 0,
              background: `radial-gradient(circle at center 70%, ${accent}1a, transparent 70%)`,
            }}
          >
            <img
              src={getClassArtPath(selected.id)}
              alt={selected.name}
              style={{
                position: 'absolute',
                inset: 0,
                width: '100%',
                height: '100%',
                objectFit: 'contain',
                objectPosition: 'center bottom',
                filter: `drop-shadow(0 18px 28px ${accent}88)`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                top: 12,
                left: 14,
                fontSize: 10,
                letterSpacing: '0.25em',
                color: accent,
                fontWeight: 700,
              }}
            >
              {selected.type.toUpperCase()}
            </div>
          </div>

          {/* Info column */}
          <div
            style={{
              width: 280,
              padding: 22,
              display: 'flex',
              flexDirection: 'column',
              gap: 10,
              borderLeft: `1px solid ${accent}33`,
            }}
          >
            <div>
              <div
                style={{
                  fontFamily: '"Orbitron", "Outfit", sans-serif',
                  fontSize: 36,
                  fontWeight: 900,
                  color: '#fff',
                  letterSpacing: '0.06em',
                  lineHeight: 1,
                }}
              >
                {selected.name}
              </div>
              <div
                style={{
                  marginTop: 4,
                  fontSize: 11,
                  letterSpacing: '0.18em',
                  color: '#a0b0d0',
                  textTransform: 'uppercase',
                }}
              >
                {selected.race} · {selected.gender}
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 4 }}>
              {(['hp', 'pp', 'attack', 'defense', 'accuracy', 'technique'] as const).map((k) => {
                const v = selected.stats[k];
                const segs = statBarSegments(v);
                return (
                  <div
                    key={k}
                    style={{
                      display: 'grid',
                      gridTemplateColumns: '60px 1fr 30px',
                      gap: 8,
                      alignItems: 'center',
                      fontSize: 11,
                    }}
                  >
                    <span
                      style={{
                        textTransform: 'uppercase',
                        letterSpacing: '0.18em',
                        color: '#788ab0',
                      }}
                    >
                      {k}
                    </span>
                    <span
                      style={{
                        height: 6,
                        background: 'rgba(255,255,255,0.07)',
                        borderRadius: 3,
                        overflow: 'hidden',
                        position: 'relative',
                      }}
                    >
                      <span
                        style={{
                          position: 'absolute',
                          inset: 0,
                          width: `${segs * 10}%`,
                          background: `linear-gradient(90deg, ${accent}, ${accent}cc)`,
                          boxShadow: `0 0 8px ${accent}aa`,
                        }}
                      />
                    </span>
                    <span
                      style={{
                        fontFamily: '"Share Tech Mono", monospace',
                        color: '#fff',
                        fontWeight: 700,
                        textAlign: 'right',
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
                  fontSize: 10,
                  color: '#a0b0d0',
                  letterSpacing: '0.04em',
                  lineHeight: 1.5,
                  padding: '8px 10px',
                  background: 'rgba(255,255,255,0.04)',
                  borderLeft: `2px solid ${accent}`,
                }}
              >
                <div
                  style={{
                    fontSize: 9,
                    letterSpacing: '0.3em',
                    color: accent,
                    marginBottom: 3,
                    fontWeight: 700,
                  }}
                >
                  TRAITS
                </div>
                {selected.bonuses.join(' · ')}
              </div>
            )}
          </div>
        </div>

        <ArrowButton dir="next" onClick={next} />
      </div>

      {/* Thumbnail strip */}
      <div
        style={{
          padding: '10px 32px 16px',
          display: 'flex',
          gap: 6,
          justifyContent: 'center',
          zIndex: 2,
        }}
      >
        {classes.map((c, i) => {
          const isSelected = i === idx;
          return (
            <button
              key={c.id}
              type="button"
              onClick={() => onSelect(c.id)}
              style={{
                width: 44,
                height: 44,
                border: isSelected
                  ? `2px solid ${TYPE_COLORS[c.type]}`
                  : '1px solid rgba(255,255,255,0.08)',
                borderRadius: 4,
                background: 'rgba(255,255,255,0.04)',
                cursor: 'pointer',
                overflow: 'hidden',
                padding: 0,
                position: 'relative',
                outline: 'none',
                boxShadow: isSelected ? `0 0 12px ${TYPE_COLORS[c.type]}88` : 'none',
                transition: 'transform 0.15s',
                transform: isSelected ? 'translateY(-2px)' : 'none',
              }}
            >
              <img
                src={getClassArtPath(c.id)}
                alt={c.name}
                style={{
                  width: '100%',
                  height: '100%',
                  objectFit: 'cover',
                  objectPosition: 'top center',
                  opacity: isSelected ? 1 : 0.5,
                }}
              />
            </button>
          );
        })}
      </div>
    </div>
  );
}

function ArrowButton({ dir, onClick }: { dir: 'prev' | 'next'; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        flexShrink: 0,
        width: 48,
        height: 96,
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.1)',
        borderRadius: 6,
        color: '#fff',
        cursor: 'pointer',
        fontSize: 24,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: 0.7,
      }}
      onMouseEnter={(e) => (e.currentTarget.style.opacity = '1')}
      onMouseLeave={(e) => (e.currentTarget.style.opacity = '0.7')}
    >
      {dir === 'prev' ? '‹' : '›'}
    </button>
  );
}
