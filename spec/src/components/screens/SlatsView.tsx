import { assetUrl } from '../../utils/assets';
import type { VariantProps } from './charSelectTypes';
import { DARK_SLATS_PALETTE, type SlatsPalette } from './slatsPalettes';

function getClassArtPath(classId: string): string {
  const FILE_MAP: Record<string, string> = {
    hucast: 'hucast', hucaseal: 'hucasteal',
    racast: 'racast', racaseal: 'racasteal',
  };
  const filename = FILE_MAP[classId] || classId;
  return assetUrl(`assets/images/${filename}.png`);
}

const TYPE_ORDER = ['Hunter', 'Ranger', 'Force'] as const;

export default function SlatsView({
  classes,
  selectedId,
  onSelect,
  palette = DARK_SLATS_PALETTE,
}: VariantProps & { palette?: SlatsPalette }) {
  // Group by type so unselected slats read left-to-right Hunter → Ranger → Force.
  const sorted = TYPE_ORDER.flatMap((t) => classes.filter((c) => c.type === t));
  const selected = classes.find((c) => c.id === selectedId)!;
  const accent = palette.typeColors[selected.type as keyof typeof palette.typeColors];

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: palette.rootBg,
        color: palette.titleColor,
        fontFamily: '"Outfit", system-ui, sans-serif',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        position: 'relative',
      }}
    >
      {/* Scanlines overlay (PSZ DS texture). Sits above bg, below content. */}
      {palette.scanlinesPattern && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            backgroundImage: palette.scanlinesPattern,
            pointerEvents: 'none',
            zIndex: 1,
          }}
        />
      )}

      {/* per-type accent glow on the active class */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `radial-gradient(ellipse at center 30%, ${accent}${palette.ambientGlowAlpha} 0%, transparent 55%)`,
          pointerEvents: 'none',
          transition: 'background 0.3s ease',
          zIndex: 1,
        }}
      />

      {/* PSZ top accent bar (yellow gradient stripe) */}
      {palette.topAccentBar && palette.topAccentBarHeight > 0 && (
        <div
          style={{
            height: palette.topAccentBarHeight,
            background: palette.topAccentBar,
            flexShrink: 0,
            boxShadow: '0 2px 4px rgba(0, 0, 0, 0.2)',
            zIndex: 3,
          }}
        />
      )}

      {/* Header — optional dark-navy panel bg when palette opts in */}
      <div
        style={{
          padding: '14px 32px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
          background: palette.headerBg,
          borderBottom: `1px solid ${palette.headerBorderColor}`,
          boxShadow: `0 1px 0 ${palette.headerShadowColor}`,
          zIndex: 3,
        }}
      >
        <div>
          <div
            style={{
              fontSize: 10,
              letterSpacing: '0.32em',
              color: palette.eyebrowColor,
              textTransform: 'uppercase',
            }}
          >
            New Character · Step 1
          </div>
          <div
            style={{
              fontFamily: '"Orbitron", "Outfit", sans-serif',
              fontSize: 22,
              fontWeight: 900,
              fontStyle: palette.titleItalic ? 'italic' : 'normal',
              letterSpacing: '0.16em',
              color: palette.titleColor,
              textTransform: 'uppercase',
              textShadow: palette.titleShadow,
            }}
          >
            Choose your class
          </div>
        </div>
        <div style={{ textAlign: 'right', fontFamily: '"Share Tech Mono", monospace' }}>
          <span style={{ fontSize: 12, color: accent, fontWeight: 700 }}>{selected.name}</span>
          <div style={{ fontSize: 10, color: palette.rightSecondaryColor, opacity: 0.85 }}>
            {selected.race} · {selected.gender} · {selected.type}
          </div>
        </div>
      </div>

      {/* Slats row */}
      <div style={{ flex: 1, display: 'flex', minHeight: 0, position: 'relative', zIndex: 3 }}>
        {sorted.map((cls) => {
          const isSelected = cls.id === selectedId;
          const color = palette.typeColors[cls.type as keyof typeof palette.typeColors];
          return (
            <div
              key={cls.id}
              onClick={() => onSelect(cls.id)}
              style={{
                flex: isSelected ? 5 : 1,
                minWidth: 0,
                position: 'relative',
                cursor: 'pointer',
                overflow: 'hidden',
                transition: 'flex 0.35s cubic-bezier(0.4, 0, 0.2, 1)',
                borderTop: `4px solid ${isSelected ? color : 'transparent'}`,
                borderBottom: `4px solid ${isSelected ? color : 'transparent'}`,
                backgroundImage: `linear-gradient(180deg, ${color}22 0%, transparent 30%)`,
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
                  opacity: isSelected ? 1 : palette.unselectedOpacity,
                  transition: 'opacity 0.3s',
                  filter: isSelected ? 'none' : palette.unselectedFilter,
                }}
              />

              {/* Vertical class label on unselected slats */}
              {!isSelected && (
                <div
                  style={{
                    position: 'absolute',
                    top: 14,
                    left: 0,
                    right: 0,
                    display: 'flex',
                    justifyContent: 'center',
                    pointerEvents: 'none',
                  }}
                >
                  <span
                    style={{
                      writingMode: 'vertical-rl',
                      transform: 'rotate(180deg)',
                      fontSize: 11,
                      fontWeight: 700,
                      letterSpacing: '0.2em',
                      color: palette.vertNameColor,
                      textShadow: palette.vertNameShadow,
                    }}
                  >
                    {cls.name}
                  </span>
                </div>
              )}

              {/* Expanded info panel */}
              {isSelected && (
                <div
                  style={{
                    position: 'absolute',
                    left: 0,
                    right: 0,
                    bottom: 0,
                    padding: '22px 18px 18px',
                    background: palette.panelGradient,
                  }}
                >
                  <div
                    style={{
                      fontFamily: '"Orbitron", "Outfit", sans-serif',
                      fontSize: 28,
                      fontWeight: 900,
                      letterSpacing: '0.08em',
                      color: palette.expandedNameColor,
                      textShadow: `0 0 14px ${color}${palette.expandedNameShadowAlpha}`,
                    }}
                  >
                    {cls.name}
                  </div>
                  <div
                    style={{
                      fontSize: 11,
                      letterSpacing: '0.2em',
                      color,
                      textTransform: 'uppercase',
                      fontWeight: 700,
                      marginTop: 2,
                      marginBottom: 12,
                    }}
                  >
                    {cls.race} · {cls.gender} · {cls.type}
                  </div>

                  {/* Flavor tagline replaces the stat bars — keeps focus on
                      the character's role in the world, not RPG numbers. */}
                  <div
                    style={{
                      padding: '8px 12px',
                      borderLeft: `3px solid ${color}`,
                      fontStyle: 'italic',
                      fontSize: 14,
                      color: palette.expandedNameColor,
                      lineHeight: 1.4,
                    }}
                  >
                    {cls.tagline}
                  </div>

                  {cls.bonuses.length > 0 && (
                    <div
                      style={{
                        marginTop: 10,
                        padding: '6px 10px',
                        background: `${color}${palette.bonusBgAlpha}`,
                        borderLeft: `2px solid ${color}`,
                        fontSize: 10,
                        color: palette.bonusTextColor,
                        lineHeight: 1.4,
                      }}
                    >
                      <span style={{ color, fontWeight: 700, letterSpacing: '0.2em' }}>
                        TRAITS{' '}
                      </span>
                      {cls.bonuses.join(' · ')}
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Footer */}
      <div
        style={{
          padding: '6px 28px 6px 32px',
          fontSize: 11,
          color: palette.footerColor,
          background: palette.footerBg,
          fontFamily: '"Share Tech Mono", monospace',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          borderTop: `1px solid ${palette.footerBorderColor}`,
          zIndex: 3,
        }}
      >
        <span>◀ ▶ NAVIGATE · ESC CANCEL</span>
        <button
          type="button"
          style={{
            background: palette.confirmButtonBg,
            color: palette.confirmButtonText,
            border: `1px solid ${palette.confirmButtonBorder}`,
            borderRadius: 4,
            padding: '4px 14px',
            fontFamily: '"Orbitron", "Outfit", sans-serif',
            fontSize: 11,
            fontWeight: 800,
            letterSpacing: '0.18em',
            textTransform: 'uppercase',
            cursor: 'pointer',
            boxShadow: palette.confirmButtonShadow,
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            outline: 'none',
          }}
        >
          <span style={{ fontSize: 13, lineHeight: 1 }}>●</span> A · Confirm
        </button>
      </div>
    </div>
  );
}
