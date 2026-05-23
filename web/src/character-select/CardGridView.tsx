import { getClassArtPath } from '../character-creator/data/constants';
import { TYPE_COLORS, type VariantProps } from './types';

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;

export default function CardGridView({ classes, selectedId, onSelect }: VariantProps) {
  // Order so each row is somewhat type-clustered.
  const sorted = TYPE_ORDER.flatMap((t) => classes.filter((c) => c.type === t));
  const selected = classes.find((c) => c.id === selectedId)!;

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background:
          'radial-gradient(ellipse at top, #2a1b4a 0%, #14092a 45%, #0a0418 100%)',
        backgroundImage: `
          radial-gradient(ellipse at top, rgba(120, 80, 200, 0.25) 0%, transparent 55%),
          radial-gradient(circle at 20% 80%, rgba(80, 40, 160, 0.15), transparent 40%),
          radial-gradient(circle at 80% 60%, rgba(40, 100, 200, 0.15), transparent 40%)
        `,
        fontFamily: '"Outfit", system-ui, sans-serif',
        color: '#f4eed8',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: '14px 28px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          borderBottom: '1px solid rgba(244, 238, 216, 0.12)',
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              letterSpacing: '0.35em',
              color: '#c8b88a',
              textTransform: 'uppercase',
            }}
          >
            Hunter's License · Class Roster
          </div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 20,
              fontWeight: 900,
              letterSpacing: '0.18em',
              textTransform: 'uppercase',
              color: '#fff',
            }}
          >
            Select your class card
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: 11, color: '#c8b88a', opacity: 0.8 }}>
            currently viewing
          </div>
          <div
            style={{
              fontSize: 16,
              color: TYPE_COLORS[selected.type],
              fontWeight: 800,
              letterSpacing: '0.08em',
              fontFamily: '"Orbitron", "Outfit", sans-serif',
            }}
          >
            {selected.name}
          </div>
        </div>
      </div>

      {/* Card grid */}
      <div
        style={{
          flex: 1,
          padding: '16px 24px',
          display: 'grid',
          gridTemplateColumns: 'repeat(7, 1fr)',
          gridTemplateRows: 'repeat(2, 1fr)',
          gap: 10,
          minHeight: 0,
        }}
      >
        {sorted.map((cls) => (
          <ClassCard
            key={cls.id}
            cls={cls}
            isSelected={cls.id === selectedId}
            onClick={() => onSelect(cls.id)}
          />
        ))}
      </div>

      {/* Footer */}
      <div
        style={{
          padding: '10px 28px',
          fontSize: 11,
          color: 'rgba(244, 238, 216, 0.65)',
          fontFamily: '"Share Tech Mono", monospace',
          display: 'flex',
          justifyContent: 'space-between',
          borderTop: '1px solid rgba(244, 238, 216, 0.12)',
        }}
      >
        <span>
          {selected.race} · {selected.gender} ·{' '}
          <span style={{ color: TYPE_COLORS[selected.type], fontWeight: 700 }}>
            {selected.type}
          </span>
        </span>
        <span>
          HP {selected.stats.hp} · ATK {selected.stats.attack} · DEF {selected.stats.defense} · ACC{' '}
          {selected.stats.accuracy} · TEC {selected.stats.technique}
        </span>
        <span>
          <span style={{ color: '#fde047', fontWeight: 700 }}>● A</span> CONFIRM
        </span>
      </div>
    </div>
  );
}

function ClassCard({
  cls,
  isSelected,
  onClick,
}: {
  cls: VariantProps['classes'][number];
  isSelected: boolean;
  onClick: () => void;
}) {
  const color = TYPE_COLORS[cls.type];
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        position: 'relative',
        cursor: 'pointer',
        padding: 0,
        border: 'none',
        background: 'transparent',
        outline: 'none',
        transform: isSelected ? 'translateY(-6px) scale(1.04)' : 'translateY(0) scale(1)',
        transition: 'transform 0.2s ease-out, filter 0.2s',
        filter: isSelected ? 'none' : 'brightness(0.85)',
        zIndex: isSelected ? 10 : 1,
      }}
    >
      {/* Card frame */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: 6,
          background: `linear-gradient(135deg, ${color}66 0%, #c8a868 50%, ${color}66 100%)`,
          padding: 2,
          boxShadow: isSelected
            ? `0 0 18px ${color}aa, 0 6px 14px rgba(0,0,0,0.6)`
            : '0 2px 4px rgba(0,0,0,0.45)',
        }}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            borderRadius: 4,
            background: 'linear-gradient(180deg, #1a1228 0%, #0c0818 100%)',
            position: 'relative',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          {/* Type stripe at top */}
          <div
            style={{
              height: 4,
              background: `linear-gradient(90deg, transparent 0%, ${color} 50%, transparent 100%)`,
            }}
          />

          {/* Portrait area */}
          <div
            style={{
              flex: 1,
              position: 'relative',
              overflow: 'hidden',
              background: `radial-gradient(ellipse at 50% 80%, ${color}30 0%, transparent 60%)`,
            }}
          >
            <img
              src={getClassArtPath(cls.id)}
              alt={cls.name}
              style={{
                position: 'absolute',
                inset: 0,
                width: '100%',
                height: '100%',
                objectFit: 'cover',
                objectPosition: 'center top',
              }}
            />
            {/* Race/gender corner badge */}
            <div
              style={{
                position: 'absolute',
                top: 6,
                right: 6,
                background: 'rgba(0, 0, 0, 0.65)',
                color: '#c8b88a',
                fontSize: 10,
                padding: '2px 5px',
                borderRadius: 3,
                fontFamily: '"Share Tech Mono", monospace',
                letterSpacing: '0.06em',
              }}
            >
              {cls.race[0]}
              {cls.gender === 'Male' ? '♂' : '♀'}
            </div>
            {/* Type icon corner */}
            <div
              style={{
                position: 'absolute',
                top: 6,
                left: 6,
                width: 22,
                height: 22,
                borderRadius: '50%',
                background: color,
                color: '#0c0818',
                fontSize: 12,
                fontWeight: 900,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: '"Orbitron", "Outfit", sans-serif',
              }}
            >
              {cls.type[0]}
            </div>
          </div>

          {/* Name banner */}
          <div
            style={{
              background: `linear-gradient(180deg, ${color}33 0%, #1a1228 100%)`,
              borderTop: `1px solid ${color}77`,
              padding: '6px 8px 5px',
              textAlign: 'center',
            }}
          >
            <div
              style={{
                fontFamily: '"Orbitron", "Outfit", sans-serif',
                fontSize: 13,
                fontWeight: 800,
                letterSpacing: '0.08em',
                color: '#fff',
                lineHeight: 1.1,
              }}
            >
              {cls.name}
            </div>
            <div
              style={{
                marginTop: 3,
                fontFamily: '"Share Tech Mono", monospace',
                fontSize: 9,
                color: '#c8b88a',
                letterSpacing: '0.04em',
              }}
            >
              HP {cls.stats.hp} · ATK {cls.stats.attack}
            </div>
          </div>
        </div>
      </div>
    </button>
  );
}
