// Variation D — "Dossier Terminal": the merchant stands to the left in a wide
// 3/4 shot and all interaction lives in one tall right-hand terminal panel —
// header, wallet, tabs, list, and the selected item's dossier stacked in a
// single unbroken column. Densest / most "PC-station" of the four; good when the
// shop has a lot of stats to show at once.
import { C, SCANLINES, FONT, glassPanelBg } from '../theme';
import { TabBar, PillRow, Divider, StatRow, ActionButton } from '../components';
import { currentItems } from '../parts';
import type { Variation, VariationCtx } from './types';

const MARKER: Record<'E' | 'x', { txt: string; color: string }> = {
  E: { txt: '[E]', color: C.textLight },
  x: { txt: '✕', color: C.rare },
};

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  const items = currentItems(shop, tab);
  const item = items[sel];
  const tabs = shop.tabs.map((t) => t.label).filter(Boolean);
  const hex = `#${shop.accent.toString(16).padStart(6, '0')}`;

  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', fontFamily: FONT }}>
      {/* Greeting near the merchant on the left */}
      <div style={{
        position: 'absolute', left: 34, top: 40, maxWidth: 300, pointerEvents: 'auto',
        background: glassPanelBg(0.88), backgroundImage: SCANLINES, border: `2px solid ${hex}`,
        borderRadius: 12, padding: '10px 16px', fontSize: 14, fontStyle: 'italic', color: C.text,
        lineHeight: 1.45, filter: 'drop-shadow(0 3px 10px rgba(0,0,0,0.45))',
      }}>{shop.blurb}</div>

      {/* Right terminal */}
      <div style={{
        position: 'absolute', top: 0, right: 0, bottom: 0, width: 452,
        display: 'flex', flexDirection: 'column',
        background: glassPanelBg(0.86), backgroundImage: SCANLINES,
        borderLeft: `3px solid ${hex}`,
        boxShadow: '-14px 0 34px rgba(0,0,0,0.5)', pointerEvents: 'auto',
      }}>
        {/* Header */}
        <div style={{
          background: C.bgDark, color: C.textWhite, padding: '12px 18px',
          display: 'flex', alignItems: 'baseline', gap: 10,
        }}>
          <span style={{ fontSize: 19, fontWeight: 800, fontStyle: 'italic', letterSpacing: 0.5 }}>{shop.title}</span>
          <span style={{ marginLeft: 'auto', fontSize: 12, color: '#b8c6da' }}>
            {shop.currency === 'photon'
              ? <>PD <b style={{ color: '#e0b3ff' }}>{shop.photons}</b></>
              : shop.currency === 'none'
                ? 'Guild'
                : <>MST <b style={{ color: '#ffd27a' }}>{shop.meseta.toLocaleString()}</b></>}
          </span>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: 'auto', padding: 16 }}>
          {tabs.length > 1 && <TabBar tabs={tabs} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />}
          {items.map((it, i) => (
            <PillRow key={`${it.name}-${i}`}
              label={it.marker ? `${MARKER[it.marker].txt} ${it.name}` : it.name}
              sub={it.sub} rightText={it.right} rarity={it.rarity}
              selected={sel === i} onClick={() => setSel(i)} />
          ))}

          <Divider />

          {/* Inline dossier for the selected row */}
          {item && (
            <div style={{
              background: 'rgba(255,255,255,0.9)', borderRadius: 4, marginTop: 4,
              padding: '12px 14px', border: `1px solid ${hex}`,
            }}>
              <div style={{ fontSize: 17, fontWeight: 800, color: item.rarity === 'rare' ? C.rare : C.text }}>{item.name}</div>
              {item.detail.subtitle && <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>{item.detail.subtitle}</div>}
              {item.detail.stats && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 5, margin: '6px 0' }}>
                  {item.detail.stats.map(([k, v]) => (
                    <StatRow key={k} k={k} v={v} accent={/short|None|Cannot|No$|MAX/i.test(v) ? C.rare : undefined} />
                  ))}
                </div>
              )}
              {item.detail.desc && <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5, marginTop: 6 }}>{item.detail.desc}</div>}
              {item.detail.action && <ActionButton label={item.detail.action} style={{ marginTop: 14 }} />}
            </div>
          )}
        </div>

        {/* Hint footer */}
        <div style={{
          background: C.hintBg, borderTop: `1px solid ${C.hintBorder}`,
          padding: '8px 18px', fontSize: 13, color: C.text, textAlign: 'center',
        }}>{shop.hint}</div>
      </div>
    </div>
  );
}

export const Dossier: Variation = {
  id: 'dossier',
  label: 'D · Dossier',
  blurb: 'Wide 3/4 shot with the merchant left; one tall right-hand terminal holds the whole menu.',
  preset: { azimuthDeg: 24, elevationDeg: 5, distanceMul: 3.1, targetYFrac: 0.52, lateralShift: -0.18, fov: 31 },
  Overlay,
};
