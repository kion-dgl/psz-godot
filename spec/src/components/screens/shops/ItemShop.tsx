import { useState, type CSSProperties } from 'react';
import { ShopScreen, PillRow, TabBar, Divider, StatRow, ActionButton, C, DetailPanel } from '../pszui';

const ITEMS = [
  { name: 'Monomate', price: 50, desc: 'Restores a small amount of HP.', max: 10, have: 5 },
  { name: 'Dimate', price: 300, desc: 'Restores a moderate amount of HP.', max: 10, have: 2 },
  { name: 'Trimate', price: 2000, desc: 'Fully restores HP.', max: 10, have: 0 },
  { name: 'Telepipe', price: 350, desc: 'Warps back to the city from the field.', max: 10, have: 3 },
  { name: 'Moon Atomizer', price: 500, desc: 'Revives a fallen ally.', max: 10, have: 1 },
];

const MATERIALS = [
  { name: 'Photon Drop', price: 0, desc: 'Debug materials (dev builds only).' },
  { name: 'Grinder Base C', price: 0, desc: 'Debug materials (dev builds only).' },
];

type Disk = {
  name: string; price: number; element: string; target: string;
  power: string; pp: string; reqLevel: string;
};
const DISKS: Disk[] = [
  { name: 'Foie Lv.1', price: 200, element: 'Fire', target: 'Single', power: '32', pp: '4', reqLevel: '1' },
  { name: 'Barta Lv.1', price: 200, element: 'Ice', target: 'Single', power: '30', pp: '4', reqLevel: '1' },
  { name: 'Resta Lv.1', price: 300, element: 'Heal', target: 'Multi', power: '40 HP', pp: '5', reqLevel: '3' },
  { name: 'Grants Lv.1', price: 500, element: 'Light', target: 'Single', power: '60', pp: '12', reqLevel: '15' },
];

const SELL = [
  { name: 'Monomate', price: 25, desc: 'Sells for half its buy price.', max: 10, have: 5 },
  { name: 'Telepipe', price: 175, desc: 'Sells for half its buy price.', max: 10, have: 3 },
];

// Small ◀ N ▶ stepper for the buy/sell quantity.
function QtyStepper({ qty, max, onChange, total }: { qty: number; max: number; onChange: (q: number) => void; total: string }) {
  const btn: CSSProperties = {
    width: 24, height: 24, fontSize: 13, fontWeight: 800, lineHeight: '22px',
    background: C.itemBg, border: '1px solid rgba(150,180,210,0.5)', borderRadius: 4,
    color: C.text, cursor: 'pointer', padding: 0,
  };
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 13 }}>
        <span style={{ color: C.textLight }}>Quantity</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button style={btn} onClick={() => onChange(Math.max(1, qty - 1))}>◀</button>
          <span style={{ fontWeight: 800, minWidth: 22, textAlign: 'center' }}>{qty}</span>
          <button style={btn} onClick={() => onChange(Math.min(max, qty + 1))}>▶</button>
        </div>
      </div>
      <StatRow label="Total" value={total} />
    </div>
  );
}

const TABS = ['Items', 'Materials', 'Disks', 'Sell'];

export default function ItemShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const [qty, setQty] = useState(1);
  const list = [ITEMS, MATERIALS, DISKS, SELL][tab];
  const i = Math.min(sel, list.length - 1);

  return (
    <ShopScreen
      title="Item Shop"
      hint="Left/Right: Category   Up/Down: Select   Enter: Buy   Esc: Leave"
      portrait="item-shop"
      info={
        <DetailPanel>
          {tab === 2 ? (() => {
            const d = DISKS[i];
            return (
              <>
                <div style={{ fontSize: 12, fontWeight: 600, color: '#886600', marginBottom: 8 }}>{d.price.toLocaleString()} M</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="Element" value={d.element} />
                  <StatRow label="Target" value={d.target} />
                  <StatRow label="Power" value={d.power} />
                  <StatRow label="PP Cost" value={d.pp} />
                  <StatRow label="Req. Level" value={d.reqLevel} />
                </div>
                <Divider />
                <div style={{ fontSize: 12, color: C.textLight, lineHeight: 1.5 }}>Use from inventory to learn. Disks are buy-1-only.</div>
                <ActionButton label="Buy" />
              </>
            );
          })() : (() => {
            const it = list[i] as { name: string; price: number; desc: string; max?: number; have?: number };
            const isDebug = tab === 1; // Materials tab = debug, not purchasable
            const max = it.max ?? 10;
            const have = it.have ?? 0;
            // Buy up to the free stack space; sell up to what you own.
            const maxQty = Math.max(1, tab === 3 ? have : max - have);
            const q = Math.min(Math.max(1, qty), maxQty);
            return (
              <>
                <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{it.desc}</div>
                {!isDebug && (
                  <>
                    <Divider />
                    <StatRow label={tab === 3 ? 'Sell price' : 'Cost'} value={`${it.price.toLocaleString()} M each`} />
                    <StatRow label="Max stack" value={`${max}`} />
                    <StatRow label="You have" value={`${have} / ${max}`} />
                    <QtyStepper qty={q} max={maxQty} onChange={setQty} total={`${(it.price * q).toLocaleString()} M`} />
                    <ActionButton label={tab === 3 ? `Sell ${q}` : `Buy ${q}`} />
                  </>
                )}
              </>
            );
          })()}
        </DetailPanel>
      }
    >
      <TabBar tabs={TABS} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} right="12,450 M" />
      {list.map((it, idx) => (
        <PillRow
          key={it.name}
          label={it.name}
          rightText={tab === 1 ? 'debug' : `${(it as { price: number }).price.toLocaleString()} M`}
          selected={i === idx}
          onClick={() => setSel(idx)}
        />
      ))}
    </ShopScreen>
  );
}
