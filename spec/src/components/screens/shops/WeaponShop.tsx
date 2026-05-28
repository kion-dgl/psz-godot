import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const WEAPONS = [
  { name: 'Saber', price: 100, type: 'Saber' },
  { name: 'Brand', price: 350, type: 'Saber' },
  { name: 'Buster', price: 800, type: 'Saber' },
  { name: 'Dagger', price: 100, type: 'Dagger' },
  { name: 'Knife', price: 350, type: 'Dagger' },
  { name: 'Sword', price: 200, type: 'Sword' },
  { name: 'Gigush', price: 550, type: 'Sword' },
];

export default function WeaponShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Weapon Shop" width={380} hint={`Press ENTER to buy - ${WEAPONS[sel].price} MST`}>
        <TabBar tabs={['Weapons', 'Armor', 'Units', 'Sell']} active={tab} onSelect={setTab} />
        {WEAPONS.map((w, i) => (
          <PillRow key={w.name} label={w.name} rightText={`${w.price.toLocaleString()} MST`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
        <Divider />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
          <span>Your Meseta:</span><span style={{ fontWeight: 700, color: '#886600' }}>12,450</span>
        </div>
      </Panel>
      <Panel title="Detail" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{WEAPONS[sel].name}</div>
          <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>{WEAPONS[sel].type}-type</div>
          <Divider />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13 }}>
            {[['ATK', '40'], ['ATA', '35'], ['Req. Level', '1']].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: C.textLight }}>{k}</span><span style={{ fontWeight: 700, color: C.text }}>{v}</span>
              </div>
            ))}
          </div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
