import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const ITEMS = [
  { name: 'Monomate', price: 50, desc: 'Restores a small amount of HP.' },
  { name: 'Dimate', price: 300, desc: 'Restores a moderate amount of HP.' },
  { name: 'Trimate', price: 2000, desc: 'Fully restores HP.' },
  { name: 'Monofluid', price: 100, desc: 'Restores a small amount of PP.' },
  { name: 'Difluid', price: 600, desc: 'Restores a moderate amount of PP.' },
  { name: 'Telepipe', price: 350, desc: 'Warps back to the city from the field.' },
  { name: 'Moon Atomizer', price: 500, desc: 'Revives a fallen ally.' },
  { name: 'Star Atomizer', price: 5000, desc: 'Fully restores HP of all nearby allies.' },
  { name: 'Sol Atomizer', price: 200, desc: 'Cures status effects for all nearby allies.' },
];

export default function ItemShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Item Shop" width={380} hint={`Press ENTER to buy - ${ITEMS[sel].price} MST`}>
        <TabBar tabs={['Buy', 'Sell']} active={tab} onSelect={setTab} />
        {ITEMS.map((item, i) => (
          <PillRow key={item.name} label={item.name} rightText={`${item.price.toLocaleString()} MST`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
        <Divider />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
          <span>Your Meseta:</span><span style={{ fontWeight: 700, color: '#886600' }}>12,450</span>
        </div>
      </Panel>
      <Panel title="Item Info" width={260}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{ITEMS[sel].name}</div>
          <div style={{ fontSize: 12, fontWeight: 600, color: '#886600', marginBottom: 8 }}>{ITEMS[sel].price.toLocaleString()} MST</div>
          <Divider />
          <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{ITEMS[sel].desc}</div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
