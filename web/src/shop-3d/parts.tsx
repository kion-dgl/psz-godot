// Composable overlay pieces shared by the shop-menu variations. Each variation
// arranges these differently (side column, lower third, floating holo panels,
// right-hand terminal) but the list rows, detail card, currency footer and
// speech bubble are the same PSZ-styled building blocks throughout.
import type { CSSProperties } from 'react';
import { C, SCANLINES, glassPanelBg, FONT } from './theme';
import { Panel, PillRow, TabBar, Divider, StatRow, ActionButton, WalletHeader } from './components';
import type { ShopDef, ShopItem } from './shopData';

export { WalletHeader };

const MARKER: Record<'E' | 'x', { txt: string; color: string }> = {
  E: { txt: '[E]', color: C.textLight },
  x: { txt: '✕', color: C.rare },
};

export function currentItems(shop: ShopDef, tab: number): ShopItem[] {
  return shop.tabs[Math.min(tab, shop.tabs.length - 1)]?.items ?? [];
}

/** Tabs (when the shop has >1) + the scrolling pill list + currency footer.
 * Fills its container height: the pill list flex-grows and scrolls, the currency
 * footer pins to the bottom. Wrap it in a fixed-height box to size it. */
export function ItemList({
  shop, tab, setTab, sel, setSel, title, hint, width, glass = true,
}: {
  shop: ShopDef;
  tab: number; setTab: (i: number) => void;
  sel: number; setSel: (i: number) => void;
  title?: string; hint?: string;
  width?: number | string;
  glass?: boolean;
}) {
  const tabs = shop.tabs.map((t) => t.label).filter(Boolean);
  const items = currentItems(shop, tab);
  return (
    <Panel title={title ?? shop.title} width={width} hint={hint} glass={glass}
      style={{ height: '100%' }}
      bodyStyle={{ display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      {tabs.length > 1 && (
        <TabBar tabs={tabs} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
      )}
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', paddingRight: 2 }}>
        {items.map((it, i) => (
          <PillRow
            key={`${it.name}-${i}`}
            label={it.marker ? `${MARKER[it.marker].txt} ${it.name}` : it.name}
            sub={it.sub}
            rightText={it.right}
            rarity={it.rarity}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
      </div>
      {shop.currency !== 'none' && (
        <>
          <Divider />
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
            <span>{shop.currency === 'photon' ? 'Photon Drops:' : 'Your Meseta:'}</span>
            <span style={{ fontWeight: 800, color: shop.currency === 'photon' ? C.photon : C.meseta }}>
              {shop.currency === 'photon' ? (shop.photons ?? 0) : shop.meseta.toLocaleString()}
            </span>
          </div>
        </>
      )}
    </Panel>
  );
}

// The canonical shop layout the variations share: a tall LIST panel on the far
// left (~90% of frame height) with the INFO panel to its right (~40% height).
// `variant` only changes the panel chrome, not the geometry.
export type ShopColumnsVariant = 'glass' | 'holo' | 'solid' | 'vignette';

export function ShopColumns({
  shop, tab, setTab, sel, setSel, variant = 'glass',
}: {
  shop: ShopDef;
  tab: number; setTab: (i: number) => void;
  sel: number; setSel: (i: number) => void;
  variant?: ShopColumnsVariant;
}) {
  const item = currentItems(shop, tab)[sel];
  const accentHex = `#${shop.accent.toString(16).padStart(6, '0')}`;
  const LIST_LEFT = 24, LIST_W = 380, GAP = 14;
  const glass = variant !== 'solid';

  // Panel chrome per variant.
  const wrapStyle = (): CSSProperties => {
    if (variant === 'holo') return { borderRadius: 8, boxShadow: `0 0 0 1px ${accentHex}, 0 0 22px -3px ${accentHex}, 0 10px 30px rgba(0,0,0,0.5)` };
    if (variant === 'solid') return { borderRadius: 8, boxShadow: `0 0 0 2px ${accentHex}, 0 10px 26px rgba(0,0,0,0.5)` };
    return {};
  };

  return (
    <>
      {variant === 'vignette' && (
        <div style={{
          position: 'absolute', left: 0, top: 0, bottom: 0, width: 720, pointerEvents: 'none',
          background: 'linear-gradient(90deg, rgba(10,14,26,0.6) 0%, rgba(10,14,26,0.28) 55%, rgba(10,14,26,0) 100%)',
        }} />
      )}
      {/* LIST — far left, ~90% height */}
      <div style={{ position: 'absolute', left: LIST_LEFT, top: 40, bottom: 32, width: LIST_W, pointerEvents: 'auto', ...wrapStyle() }}>
        <ItemList shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} hint={shop.hint} glass={glass} />
      </div>
      {/* INFO — right of the list, ~40% height */}
      <div style={{ position: 'absolute', left: LIST_LEFT + LIST_W + GAP, top: 40, width: 320, height: 288, pointerEvents: 'auto', ...wrapStyle() }}>
        <DetailCard shop={shop} item={item} glass={glass} />
      </div>
    </>
  );
}

/** The white scan-lined detail card for the selected row. */
export function DetailCard({ shop, item, width, title = 'Detail', style, glass = true }: {
  shop: ShopDef; item: ShopItem | undefined; width?: number | string; title?: string; style?: CSSProperties; glass?: boolean;
}) {
  return (
    <Panel title={title} width={width} glass={glass} style={{ height: '100%', ...style }}
      bodyStyle={{ display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      <div style={{
        background: 'rgba(255,255,255,0.9)', borderRadius: 4,
        padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column',
      }}>
        {!item ? (
          <div style={{ color: C.textLight, fontSize: 13 }}>—</div>
        ) : (
          <>
            {/* Scrollable detail; the confirm action stays pinned below it so it
                never gets clipped by the (short) info panel. */}
            <div style={{ flex: 1, minHeight: 0, overflowY: 'auto' }}>
              <div style={{ fontSize: 16, fontWeight: 800, color: item.rarity === 'rare' ? C.rare : C.text, marginBottom: 2 }}>
                {item.name}
              </div>
              {item.detail.subtitle && (
                <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>{item.detail.subtitle}</div>
              )}
              {item.detail.stats && (
                <>
                  <Divider />
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4, margin: '2px 0 8px' }}>
                    {item.detail.stats.map(([k, v]) => (
                      <StatRow key={k} k={k} v={v}
                        accent={/short|None|Cannot|No$|MAX/i.test(v) ? C.rare : undefined} />
                    ))}
                  </div>
                </>
              )}
              {item.detail.desc && (
                <>
                  <Divider />
                  <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{item.detail.desc}</div>
                </>
              )}
            </div>
            {item.detail.action && (
              <ActionButton label={item.detail.action} style={{ marginTop: 10, flexShrink: 0 }} />
            )}
          </>
        )}
      </div>
    </Panel>
  );
}

/** A pointed speech bubble for the NPC's greeting line. */
export function SpeechBubble({ text, accent, style, pointer = 'bottom' }: {
  text: string; accent: number; style?: CSSProperties; pointer?: 'bottom' | 'left' | 'none';
}) {
  const hex = `#${accent.toString(16).padStart(6, '0')}`;
  return (
    <div style={{ position: 'relative', ...style }}>
      <div style={{
        background: glassPanelBg(0.9), backgroundImage: SCANLINES,
        border: `2px solid ${hex}`, borderRadius: 12,
        padding: '10px 16px', maxWidth: 380, fontSize: 14, lineHeight: 1.45,
        color: C.text, fontStyle: 'italic', fontFamily: FONT,
        filter: 'drop-shadow(0 3px 10px rgba(0,0,0,0.45))',
      }}>
        {text}
      </div>
      {pointer === 'bottom' && (
        <div style={{
          position: 'absolute', bottom: -9, left: 40, width: 16, height: 16,
          background: glassPanelBg(0.9), borderRight: `2px solid ${hex}`, borderBottom: `2px solid ${hex}`,
          transform: 'rotate(45deg)',
        }} />
      )}
    </div>
  );
}

/** Full-height frame around an overlay, used by the "terminal" variations. */
export function overlayFrame(children: React.ReactNode, style?: CSSProperties) {
  return (
    <div style={{
      position: 'absolute', inset: 0, pointerEvents: 'none', fontFamily: FONT, ...style,
    }}>
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
        <div style={{ pointerEvents: 'auto', width: '100%', height: '100%' }}>{children}</div>
      </div>
    </div>
  );
}
