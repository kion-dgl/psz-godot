import type { CSSProperties, ReactNode } from 'react';
import { assetUrl } from '../../../utils/assets';
import { SCANLINES } from '../pszui';

export type DetailChrome = 'blue-glass' | 'chamfer-plate' | 'legacy-white';

export type StatusTone = 'ok' | 'warn' | 'blocked' | 'equipped' | 'neutral';

export interface StatusPillData {
  text: string;
  tone: StatusTone;
}

export interface FooterStat {
  label: string;
  value: string;
  accent?: 'gold' | 'pd' | 'muted' | 'default';
}

export interface EquipStatRow {
  stat: string; // e.g. "ATK", "ACC", "DEF", "EVA", "Fire Res."
  itemVal: string; // e.g. "40–48", "+15", "+8"
  equipFrom?: number | string; // e.g. 152
  equipTo?: number | string; // e.g. 160
  diff?: number; // positive = green, negative = red, 0 = neutral
  diffSuffix?: string; // e.g. "%"
  equipNote?: string; // fallback when equipped ("[E] Current") or blocked ("✕ Class")
}

export type DetailSpec =
  | {
      kind: 'weapon';
      name: string;
      icon: string;
      rarity: number;
      weaponType: string;
      grindLabel: string;
      stats: EquipStatRow[];
      element?: { name: string; color: string };
      photonArt?: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'armor';
      name: string;
      icon: string;
      rarity: number;
      armorType: 'Armor' | 'Frame' | 'Robe';
      slotsUsed?: number;
      slotsMax: number;
      stats: EquipStatRow[]; // DEF, EVA, and elemental resists — one per row
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'unit';
      name: string;
      icon: string;
      rarity: number;
      category: string;
      stats: EquipStatRow[]; // e.g. ATK +15 | 160 -> 175 (+15)
      description?: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'disk';
      name: string;
      icon: string;
      element: { name: string; color: string };
      target: string;
      power: string;
      ppCost: string;
      reqLevel: string;
      knownState: string;
      knownUpgrade?: boolean;
      note?: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'consumable';
      name: string;
      icon: string;
      rarity?: number;
      category: string;
      held: number;
      maxStack: number;
      description: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'material';
      name: string;
      icon: string;
      rarity?: number;
      subkind: string;
      held: number;
      maxStack: number;
      effectSummary: string;
      elementTag?: { name: string; color: string };
      description: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'mag';
      name: string;
      icon: string;
      level: number;
      stageLabel: string;
      personality: string;
      colorName: string;
      stats: EquipStatRow[]; // POW, GRD, HIT, MND — one per row + equipped delta
      syncIq: string;
      photonBlast: string;
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'synthesis';
      mode: 'craft' | 'board';
      name: string;
      icon: string;
      rarity: number;
      outputType: string;
      outputStats?: EquipStatRow[]; // ATK / ACC preview if equipped
      ingredients: { name: string; have: number; need: number; optional?: boolean }[];
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    }
  | {
      kind: 'tekker';
      name: string;
      icon: string;
      rarity: number;
      weaponType: string;
      grindMax: number;
      rows: {
        label: string;
        before: string;
        after?: string;
        delta?: string;
        positive?: boolean;
      }[];
      requiredGrinder?: { name: string; held: number };
      allGrinders: { short: string; held: number; active?: boolean }[];
      footerStats: FooterStat[];
      status?: StatusPillData;
      legacyLines: string[];
    };

function rarityColor(rarity: number): string {
  if (rarity <= 3) return '#6ec2ff';
  if (rarity <= 6) return '#6be088';
  if (rarity <= 9) return '#ff7878';
  return '#ffd658';
}

function rarityIconPath(rarity: number): string {
  if (rarity <= 3) return 'assets/ui/pso2/icon_rarity_blue.png';
  if (rarity <= 6) return 'assets/ui/pso2/icon_rarity_green.png';
  if (rarity <= 9) return 'assets/ui/pso2/icon_rarity_red.png';
  return 'assets/ui/pso2/icon_rarity_gold.png';
}

function RarityStars({ rarity }: { rarity?: number }) {
  if (!rarity || rarity <= 0) return null;
  const clamped = Math.min(rarity, 10);
  const starIcon = assetUrl(rarityIconPath(rarity));
  return (
    <span
      title={`${rarity}-star rarity`}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 1,
        padding: '1px 4px',
        borderRadius: 3,
        background: 'rgba(10, 16, 26, 0.55)',
        border: '1px solid rgba(255,255,255,0.14)',
        flexShrink: 0,
      }}
    >
      {clamped <= 7 ? (
        Array.from({ length: clamped }).map((_, idx) => (
          <img
            key={idx}
            src={starIcon}
            alt=""
            style={{ width: 10, height: 10, imageRendering: 'pixelated', display: 'block' }}
          />
        ))
      ) : (
        <>
          <img src={starIcon} alt="" style={{ width: 11, height: 11, imageRendering: 'pixelated' }} />
          <span style={{ fontSize: 10, fontWeight: 800, color: rarityColor(rarity), marginLeft: 2 }}>
            ×{rarity}
          </span>
        </>
      )}
    </span>
  );
}

function StatusBadge({ status }: { status?: StatusPillData }) {
  if (!status) return null;
  const tones: Record<StatusTone, { bg: string; fg: string; border: string }> = {
    ok: { bg: 'rgba(52, 168, 90, 0.22)', fg: '#8ef0ab', border: 'rgba(110, 224, 142, 0.45)' },
    warn: { bg: 'rgba(240, 168, 32, 0.22)', fg: '#ffd470', border: 'rgba(248, 200, 64, 0.48)' },
    blocked: { bg: 'rgba(212, 62, 62, 0.24)', fg: '#ff9c9c', border: 'rgba(235, 100, 100, 0.5)' },
    equipped: { bg: 'rgba(92, 152, 230, 0.24)', fg: '#a8d4ff', border: 'rgba(130, 185, 250, 0.48)' },
    neutral: { bg: 'rgba(255,255,255,0.1)', fg: '#cfd9e6', border: 'rgba(255,255,255,0.2)' },
  };
  const t = tones[status.tone];
  return (
    <div
      style={{
        fontSize: 10.5,
        fontWeight: 700,
        letterSpacing: '0.02em',
        padding: '2px 7px',
        borderRadius: 3,
        background: t.bg,
        color: t.fg,
        border: `1px solid ${t.border}`,
        textAlign: 'center',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
      }}
    >
      {status.text}
    </div>
  );
}

function SubMetaBar({ left, right }: { left: ReactNode; right?: ReactNode }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 6,
        fontSize: 10.5,
        fontWeight: 700,
        color: '#34485e',
        padding: '0 2px 3px',
        borderBottom: '1px solid rgba(98, 134, 168, 0.35)',
        marginBottom: 2,
        flexShrink: 0,
      }}
    >
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{left}</span>
      {right && <span style={{ flexShrink: 0 }}>{right}</span>}
    </div>
  );
}

/**
 * Shared 1-attribute-per-row table for equipment stats + equipped preview delta.
 * Columns: STAT (left) | ITEM (mid-right) | IF EQUIPPED (far right: cur → next (+diff))
 */
function EquipComparisonTable({
  rows,
  midHeader = 'ITEM',
  rightHeader = 'EQUIPPED',
  compact = false,
}: {
  rows: EquipStatRow[];
  midHeader?: string;
  rightHeader?: string;
  compact?: boolean;
}) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: compact ? 1.5 : 2.5 }}>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'minmax(54px, 1fr) auto minmax(98px, auto)',
          gap: 6,
          alignItems: 'center',
          fontSize: 9,
          fontWeight: 800,
          letterSpacing: '0.05em',
          color: '#5b718a',
          padding: '0 4px',
        }}
      >
        <span>STAT</span>
        <span style={{ textAlign: 'right' }}>{midHeader}</span>
        <span style={{ textAlign: 'right' }}>{rightHeader}</span>
      </div>
      {rows.map((r) => {
        const diff = r.diff ?? 0;
        const deltaColor =
          diff > 0 ? '#166e32' : diff < 0 ? '#b42323' : '#586c82';
        const rowBg =
          diff > 0
            ? 'rgba(46, 160, 82, 0.08)'
            : diff < 0
              ? 'rgba(218, 68, 68, 0.08)'
              : 'rgba(255, 255, 255, 0.72)';
        const suffix = r.diffSuffix ?? '';
        const diffText =
          diff > 0 ? `+${diff}${suffix}` : diff < 0 ? `${diff}${suffix}` : `±0${suffix}`;

        return (
          <div
            key={r.stat}
            style={{
              display: 'grid',
              gridTemplateColumns: 'minmax(54px, 1fr) auto minmax(98px, auto)',
              gap: 6,
              alignItems: 'center',
              padding: compact ? '1.5px 5px' : '2.5px 6px',
              borderRadius: 3,
              background: rowBg,
              border: '1px solid rgba(130, 164, 196, 0.38)',
              fontSize: compact ? 10.5 : 11,
              lineHeight: 1.25,
              fontVariantNumeric: 'tabular-nums',
            }}
          >
            <span style={{ fontWeight: 700, color: '#2b3d52', whiteSpace: 'nowrap' }}>{r.stat}</span>
            <span style={{ fontWeight: 800, color: '#162232', textAlign: 'right', whiteSpace: 'nowrap' }}>
              {r.itemVal}
            </span>
            <span
              style={{
                fontWeight: 800,
                color: r.equipNote ? '#586c82' : deltaColor,
                textAlign: 'right',
                whiteSpace: 'nowrap',
              }}
            >
              {r.equipNote
                ? r.equipNote
                : r.equipFrom !== undefined && r.equipTo !== undefined
                  ? `${r.equipFrom}→${r.equipTo} (${diffText})`
                  : '—'}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function KVRow({
  label,
  value,
  valueNode,
  valueColor,
  subtleBg = false,
}: {
  label: string;
  value?: string;
  valueNode?: ReactNode;
  valueColor?: string;
  subtleBg?: boolean;
}) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 8,
        fontSize: 11,
        lineHeight: 1.3,
        padding: subtleBg ? '2.5px 6px' : '1.5px 3px',
        borderRadius: subtleBg ? 3 : 0,
        background: subtleBg ? 'rgba(255, 255, 255, 0.72)' : 'transparent',
        border: subtleBg ? '1px solid rgba(130, 164, 196, 0.35)' : 'none',
      }}
    >
      <span style={{ color: '#455a70', fontWeight: 700, flexShrink: 0 }}>{label}</span>
      {valueNode ?? (
        <span
          style={{
            fontWeight: 800,
            color: valueColor ?? '#182232',
            textAlign: 'right',
            fontVariantNumeric: 'tabular-nums',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {value}
        </span>
      )}
    </div>
  );
}

function ElementPill({ name, color }: { name: string; color: string }) {
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 4,
        fontSize: 10.5,
        fontWeight: 800,
        padding: '0.5px 6px',
        borderRadius: 3,
        background: 'rgba(26, 36, 52, 0.07)',
        border: `1px solid ${color}`,
        color: '#182232',
      }}
    >
      <span style={{ width: 6, height: 6, borderRadius: '50%', background: color, display: 'inline-block' }} />
      {name}
    </span>
  );
}

export function ItemDetailCard({
  spec,
  chrome = 'blue-glass',
  width = 320,
  height = 288,
}: {
  spec: DetailSpec;
  chrome?: DetailChrome;
  width?: number | string;
  height?: number | string;
}) {
  if (chrome === 'legacy-white') {
    return (
      <div
        style={{
          width,
          height,
          boxSizing: 'border-box',
          background: 'rgba(255, 255, 255, 0.85)',
          backgroundImage: SCANLINES,
          border: '1px solid rgba(150, 180, 210, 0.5)',
          borderTop: '3px solid #2a3448',
          borderRadius: 6,
          padding: '10px 12px',
          fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
          fontSize: 12,
          lineHeight: 1.4,
          color: '#1a1a2a',
          overflowY: 'auto',
          display: 'flex',
          flexDirection: 'column',
          gap: 3,
        }}
      >
        {spec.legacyLines.map((line, idx) =>
          line === '' ? (
            <div key={idx} style={{ height: 7, flexShrink: 0 }} />
          ) : (
            <div key={idx} style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
              {line}
            </div>
          ),
        )}
      </div>
    );
  }

  const isChamfer = chrome === 'chamfer-plate';
  const rarity = 'rarity' in spec ? spec.rarity : undefined;

  const outerStyle: CSSProperties = isChamfer
    ? {
        width,
        height,
        boxSizing: 'border-box',
        display: 'flex',
        flexDirection: 'column',
        fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
        background: '#142640',
        padding: 3,
        clipPath:
          'polygon(8px 0, calc(100% - 8px) 0, 100% 8px, 100% calc(100% - 8px), calc(100% - 8px) 100%, 8px 100%, 0 calc(100% - 8px), 0 8px)',
        filter: 'drop-shadow(0 3px 8px rgba(0,0,0,0.32))',
      }
    : {
        width,
        height,
        boxSizing: 'border-box',
        display: 'flex',
        flexDirection: 'column',
        fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
        background: 'rgba(168, 204, 232, 0.88)',
        backgroundImage: SCANLINES,
        border: '3px solid #2a3448',
        borderRadius: 7,
        overflow: 'hidden',
        boxShadow: '0 4px 12px rgba(14, 24, 38, 0.28)',
      };

  const innerSurface: CSSProperties = isChamfer
    ? {
        flex: 1,
        minHeight: 0,
        display: 'flex',
        flexDirection: 'column',
        background: '#dbe8f6',
        backgroundImage:
          'repeating-linear-gradient(0deg, rgba(255,255,255,0.38) 0px, rgba(255,255,255,0.38) 2px, rgba(188,212,236,0.38) 2px, rgba(188,212,236,0.38) 4px)',
        clipPath:
          'polygon(6px 0, calc(100% - 6px) 0, 100% 6px, 100% calc(100% - 6px), calc(100% - 6px) 100%, 6px 100%, 0 calc(100% - 6px), 0 6px)',
        overflow: 'hidden',
      }
    : {
        flex: 1,
        minHeight: 0,
        display: 'flex',
        flexDirection: 'column',
      };

  return (
    <div style={outerStyle}>
      <div style={innerSurface}>
        {/* HEADER BANNER */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 7,
            padding: '5px 9px',
            background: isChamfer
              ? 'linear-gradient(90deg, #152844 0%, #223b60 100%)'
              : 'linear-gradient(90deg, #1e2838 0%, #2a3850 100%)',
            borderBottom: '2px solid #f0a020',
            color: '#ffffff',
            flexShrink: 0,
          }}
        >
          <img
            src={assetUrl(spec.icon)}
            alt=""
            style={{
              width: 18,
              height: 18,
              imageRendering: 'pixelated',
              flexShrink: 0,
              filter: 'drop-shadow(0 1px 1px rgba(0,0,0,0.6))',
            }}
          />
          <span
            style={{
              flex: 1,
              minWidth: 0,
              fontSize: 13,
              fontWeight: 800,
              letterSpacing: '0.02em',
              color: '#ffffff',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              textShadow: '0 1px 1px rgba(0,0,0,0.55)',
            }}
          >
            {spec.name}
          </span>
          {spec.kind === 'mag' ? (
            <span
              style={{
                fontSize: 10.5,
                fontWeight: 800,
                padding: '1px 6px',
                borderRadius: 3,
                background: '#f0a020',
                color: '#1a1a2a',
                flexShrink: 0,
              }}
            >
              Lv.{spec.level}
            </span>
          ) : spec.kind === 'disk' ? (
            <span
              style={{
                fontSize: 10,
                fontWeight: 800,
                padding: '1px 6px',
                borderRadius: 3,
                background: 'rgba(255,255,255,0.14)',
                border: `1px solid ${spec.element.color}`,
                color: '#fff',
                flexShrink: 0,
              }}
            >
              {spec.element.name}
            </span>
          ) : (
            <RarityStars rarity={rarity} />
          )}
        </div>

        {/* BODY INSET — strictly one attribute per row */}
        <div
          style={{
            flex: 1,
            minHeight: 0,
            margin: '5px 6px 4px',
            padding: '5px 7px',
            borderRadius: isChamfer ? 3 : 5,
            background: isChamfer ? 'rgba(255,255,255,0.66)' : 'rgba(244, 249, 255, 0.88)',
            border: '1px solid rgba(110, 146, 180, 0.5)',
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: 3,
          }}
        >
          {spec.kind === 'weapon' && (
            <>
              <SubMetaBar left={spec.weaponType} right={`Grind ${spec.grindLabel}`} />
              <EquipComparisonTable rows={spec.stats} />
              <div style={{ marginTop: 2, display: 'flex', flexDirection: 'column', gap: 2.5 }}>
                <KVRow
                  subtleBg
                  label="Element"
                  valueNode={
                    spec.element ? (
                      <ElementPill name={spec.element.name} color={spec.element.color} />
                    ) : (
                      <span style={{ color: '#6b7e92', fontWeight: 700 }}>—</span>
                    )
                  }
                />
                <KVRow
                  subtleBg
                  label="Photon Art"
                  value={spec.photonArt ?? '—'}
                  valueColor={spec.photonArt ? '#1f4d88' : '#6b7e92'}
                />
              </div>
            </>
          )}

          {spec.kind === 'armor' && (
            <>
              <SubMetaBar
                left={spec.armorType}
                right={
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}>
                    <span>Slots</span>
                    <span style={{ letterSpacing: 1, color: '#1e3a5f' }}>
                      {Array.from({ length: 4 }).map((_, idx) =>
                        idx < spec.slotsMax ? (idx < (spec.slotsUsed ?? 0) ? '◆' : '◇') : '·',
                      )}
                    </span>
                    <span>({spec.slotsMax})</span>
                  </span>
                }
              />
              <EquipComparisonTable rows={spec.stats} compact={spec.stats.length > 5} />
            </>
          )}

          {spec.kind === 'unit' && (
            <>
              <SubMetaBar left={spec.category} right="Armor Slot ×1" />
              <EquipComparisonTable rows={spec.stats} />
              {spec.description && (
                <div style={{ fontSize: 10.5, lineHeight: 1.4, color: '#2b3a4c', marginTop: 3 }}>
                  {spec.description}
                </div>
              )}
            </>
          )}

          {spec.kind === 'disk' && (
            <>
              <SubMetaBar left="Technique Disk" right={`Target: ${spec.target}`} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
                <KVRow subtleBg label="Power" value={spec.power} />
                <KVRow subtleBg label="PP Cost" value={spec.ppCost} />
                <KVRow subtleBg label="Req. Level" value={spec.reqLevel} />
                <KVRow
                  subtleBg
                  label="Known"
                  value={spec.knownState}
                  valueColor={spec.knownUpgrade ? '#186a32' : '#182232'}
                />
              </div>
              {spec.note && (
                <div style={{ fontSize: 10, color: '#52657a', marginTop: 'auto', paddingTop: 2 }}>{spec.note}</div>
              )}
            </>
          )}

          {spec.kind === 'consumable' && (
            <>
              <SubMetaBar
                left={spec.category}
                right={
                  <span>
                    Held <strong>{spec.held}</strong> / {spec.maxStack}
                  </span>
                }
              />
              <div style={{ fontSize: 11, lineHeight: 1.44, color: '#1d2938', flex: 1 }}>
                {spec.description}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 'auto', paddingTop: 3 }}>
                <span style={{ fontSize: 9.5, fontWeight: 700, color: '#4d6278' }}>PACK</span>
                <div
                  style={{
                    flex: 1,
                    height: 6,
                    borderRadius: 3,
                    background: 'rgba(60, 90, 120, 0.16)',
                    overflow: 'hidden',
                  }}
                >
                  <div
                    style={{
                      width: `${Math.min(100, (spec.held / Math.max(1, spec.maxStack)) * 100)}%`,
                      height: '100%',
                      background: spec.held >= spec.maxStack ? '#e09820' : '#3a86cc',
                    }}
                  />
                </div>
                <span style={{ fontSize: 10, fontWeight: 800, color: '#223248', fontVariantNumeric: 'tabular-nums' }}>
                  {spec.held}/{spec.maxStack}
                </span>
              </div>
            </>
          )}

          {spec.kind === 'material' && (
            <>
              <SubMetaBar
                left={spec.subkind}
                right={
                  <span>
                    Held <strong>{spec.held}</strong> / {spec.maxStack}
                  </span>
                }
              />
              <KVRow
                subtleBg
                label="Effect"
                valueNode={
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontWeight: 800 }}>
                    <span>{spec.effectSummary}</span>
                    {spec.elementTag && <ElementPill name={spec.elementTag.name} color={spec.elementTag.color} />}
                  </span>
                }
              />
              <div style={{ fontSize: 10.5, lineHeight: 1.42, color: '#2a394b', marginTop: 2 }}>
                {spec.description}
              </div>
            </>
          )}

          {spec.kind === 'mag' && (
            <>
              <SubMetaBar left={`${spec.stageLabel} · ${spec.colorName}`} right={spec.personality} />
              <EquipComparisonTable rows={spec.stats} midHeader="MAG" compact />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 1.5, marginTop: 1 }}>
                <KVRow subtleBg label="Sync / IQ" value={spec.syncIq} />
                <KVRow subtleBg label="Photon Blast" value={spec.photonBlast} valueColor="#1f4d88" />
              </div>
            </>
          )}

          {spec.kind === 'synthesis' && (
            <>
              <SubMetaBar
                left={spec.mode === 'craft' ? 'Synthesis Recipe' : 'Recipe Board'}
                right={spec.outputType}
              />
              {spec.outputStats && spec.outputStats.length > 0 && (
                <EquipComparisonTable rows={spec.outputStats} midHeader="OUT" compact />
              )}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, marginTop: 1 }}>
                {spec.ingredients.map((ing) => {
                  const met = ing.have >= ing.need;
                  return (
                    <div
                      key={ing.name}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        gap: 6,
                        padding: '1.5px 6px',
                        borderRadius: 3,
                        background: met ? 'rgba(255,255,255,0.72)' : 'rgba(235, 90, 90, 0.1)',
                        border: `1px solid ${met ? 'rgba(130,165,198,0.4)' : 'rgba(210,100,100,0.45)'}`,
                        fontSize: 10.5,
                      }}
                    >
                      <span
                        style={{
                          color: '#202e40',
                          fontWeight: 600,
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {ing.name}
                        {ing.optional ? ' (opt.)' : ''}
                      </span>
                      <span
                        style={{
                          fontWeight: 800,
                          fontVariantNumeric: 'tabular-nums',
                          color: met ? '#1a6b35' : '#b32424',
                          flexShrink: 0,
                        }}
                      >
                        {ing.have} of {ing.need} {met ? '✓' : '✕'}
                      </span>
                    </div>
                  );
                })}
              </div>
            </>
          )}

          {spec.kind === 'tekker' && (
            <>
              <SubMetaBar left={spec.weaponType} right={`Max Grind +${spec.grindMax}`} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
                <div
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr auto',
                    fontSize: 9,
                    fontWeight: 800,
                    letterSpacing: '0.05em',
                    color: '#5b718a',
                    padding: '0 4px',
                  }}
                >
                  <span>STAT</span>
                  <span>BEFORE → AFTER</span>
                </div>
                {spec.rows.map((row) => (
                  <div
                    key={row.label}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 8,
                      padding: '2.5px 6px',
                      borderRadius: 3,
                      background: row.positive ? 'rgba(46, 160, 82, 0.09)' : 'rgba(255,255,255,0.72)',
                      border: '1px solid rgba(130, 164, 196, 0.38)',
                      fontSize: 11,
                      fontVariantNumeric: 'tabular-nums',
                    }}
                  >
                    <span style={{ fontWeight: 700, color: '#2b3d52' }}>{row.label}</span>
                    <span
                      style={{
                        fontWeight: 800,
                        color: row.positive ? '#166e32' : '#182232',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      {row.after
                        ? `${row.before} → ${row.after}${row.delta ? ` (${row.delta})` : ''}`
                        : row.before}
                    </span>
                  </div>
                ))}
              </div>
              {spec.requiredGrinder && (
                <KVRow
                  subtleBg
                  label="Requires"
                  value={`${spec.requiredGrinder.name} (${spec.requiredGrinder.held} held)`}
                  valueColor={spec.requiredGrinder.held > 0 ? '#166e32' : '#b32424'}
                />
              )}
              <KVRow
                subtleBg
                label="Grinders"
                valueNode={
                  <span style={{ display: 'inline-flex', gap: 6, fontSize: 10.5, fontVariantNumeric: 'tabular-nums' }}>
                    {spec.allGrinders.map((g) => (
                      <span
                        key={g.short}
                        style={{
                          fontWeight: g.active ? 800 : 600,
                          color: g.active ? '#9e5800' : '#4a5e74',
                          textDecoration: g.active ? 'underline' : 'none',
                        }}
                      >
                        {g.short}:{g.held}
                      </span>
                    ))}
                  </span>
                }
              />
            </>
          )}
        </div>

        {/* PINNED FOOTER */}
        <div
          style={{
            flexShrink: 0,
            padding: '5px 8px 6px',
            background: isChamfer ? '#152844' : 'rgba(30, 40, 56, 0.92)',
            borderTop: '1px solid rgba(255,255,255,0.14)',
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
            {spec.footerStats.map((fs) => {
              const valColor =
                fs.accent === 'gold'
                  ? '#ffd460'
                  : fs.accent === 'pd'
                    ? '#7cd4ff'
                    : fs.accent === 'muted'
                      ? '#9fb0c4'
                      : '#ffffff';
              return (
                <div
                  key={fs.label}
                  style={{
                    display: 'flex',
                    alignItems: 'baseline',
                    gap: 5,
                    fontSize: 11,
                  }}
                >
                  <span style={{ color: '#9cb0c9', fontWeight: 600, fontSize: 10 }}>{fs.label}</span>
                  <span style={{ color: valColor, fontWeight: 800, fontVariantNumeric: 'tabular-nums' }}>
                    {fs.value}
                  </span>
                </div>
              );
            })}
          </div>
          <StatusBadge status={spec.status} />
        </div>
      </div>
    </div>
  );
}
