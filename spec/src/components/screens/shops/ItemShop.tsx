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

const DISKS = [
  { name: 'Foie Lv.1', price: 200, desc: 'Basic fire technique. Single target. Use from inventory to learn.' },
  { name: 'Barta Lv.1', price: 200, desc: 'Basic ice technique. Single target.' },
  { name: 'Zonde Lv.1', price: 200, desc: 'Basic lightning technique. Single target.' },
  { name: 'Resta Lv.1', price: 300, desc: 'Heals the caster. Area effect at higher levels.' },
  { name: 'Anti Lv.1', price: 150, desc: 'Cures status effects on self.' },
  { name: 'Shifta Lv.1', price: 250, desc: 'Boosts attack power. Party-wide at higher levels.' },
  { name: 'Deband Lv.1', price: 250, desc: 'Boosts defense. Party-wide at higher levels.' },
  { name: 'Jellen Lv.1', price: 200, desc: 'Lowers enemy attack. Area effect.' },
  { name: 'Zalure Lv.1', price: 200, desc: 'Lowers enemy defense. Area effect.' },
  { name: 'Grants Lv.1', price: 500, desc: 'Light technique. High power, single target.' },
  { name: 'Megid Lv.1', price: 500, desc: 'Dark technique. Chance of instant death.' },
];

const SELL = [
  { name: 'Saber', price: 50, desc: 'Sells for half its buy price.' },
  { name: 'Monomate', price: 25, desc: 'Sells for half its buy price.' },
];

const TABS = ['Items', 'Disks', 'Sell'];
const DATA = [ITEMS, DISKS, SELL];

export default function ItemShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = DATA[tab];
  const item = list[Math.min(sel, list.length - 1)];
  const action = tab === 2 ? 'sell' : 'buy';

  return (
    <ShopFrame>
      <Panel title="Item Shop" width={380} hint={`Press ENTER to ${action} - ${item.price.toLocaleString()} MST`}>
        <TabBar tabs={TABS} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        {list.map((it, i) => (
          <PillRow key={it.name} label={it.name} rightText={`${it.price.toLocaleString()} MST`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
        <Divider />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
          <span>Your Meseta:</span><span style={{ fontWeight: 700, color: '#886600' }}>12,450</span>
        </div>
      </Panel>
      <Panel title={tab === 1 ? 'Disk Info' : 'Item Info'} width={260}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{item.name}</div>
          <div style={{ fontSize: 12, fontWeight: 600, color: '#886600', marginBottom: 8 }}>{item.price.toLocaleString()} MST</div>
          <Divider />
          <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{item.desc}</div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
