import { useState } from 'react';
import { ShopScreen, PillRow, TabBar, Divider, StatRow, ActionButton, C, DetailPanel } from '../pszui';

const ITEMS = [
  { name: 'Monomate', price: 50, desc: 'Restores a small amount of HP.' },
  { name: 'Dimate', price: 300, desc: 'Restores a moderate amount of HP.' },
  { name: 'Trimate', price: 2000, desc: 'Fully restores HP.' },
  { name: 'Telepipe', price: 350, desc: 'Warps back to the city from the field.' },
  { name: 'Moon Atomizer', price: 500, desc: 'Revives a fallen ally.' },
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
  { name: 'Monomate', price: 25, desc: 'Sells for half its buy price.' },
  { name: 'Telepipe', price: 175, desc: 'Sells for half its buy price.' },
];

const TABS = ['Items', 'Materials', 'Disks', 'Sell'];

export default function ItemShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = [ITEMS, MATERIALS, DISKS, SELL][tab];
  const i = Math.min(sel, list.length - 1);
  const bulk = tab === 0 || tab === 1;

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
            const it = list[i] as { name: string; price: number; desc: string };
            return (
              <>
                {tab !== 1 && <div style={{ fontSize: 12, fontWeight: 600, color: '#886600', marginBottom: 8 }}>{it.price.toLocaleString()} M</div>}
                <Divider />
                <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{it.desc}</div>
                {tab !== 1 && (
                  <>
                    {bulk && <div style={{ fontSize: 11, color: C.textLight, marginTop: 8 }}>× quantity (bulk)</div>}
                    <ActionButton label={tab === 3 ? 'Sell' : 'Buy'} />
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
