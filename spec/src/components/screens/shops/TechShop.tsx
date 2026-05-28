import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const DISKS = [
  { name: 'Foie Lv.1', price: 200, desc: 'Basic fire technique. Single target.' },
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

export default function TechShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Technique Disks" width={380} hint={`Use a disk from inventory to learn the technique.`}>
        <TabBar tabs={['Buy', 'Sell']} active={tab} onSelect={setTab} />
        {DISKS.map((d, i) => (
          <PillRow key={d.name} label={d.name} rightText={`${d.price} MST`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
        <Divider />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
          <span>Your Meseta:</span><span style={{ fontWeight: 700, color: '#886600' }}>12,450</span>
        </div>
      </Panel>
      <Panel title="Disk Info" width={260}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{DISKS[sel].name}</div>
          <div style={{ fontSize: 12, fontWeight: 600, color: '#886600', marginBottom: 8 }}>{DISKS[sel].price} MST</div>
          <Divider />
          <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{DISKS[sel].desc}</div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
