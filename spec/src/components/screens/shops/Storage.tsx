import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const STORED = [
  { name: 'Brand', type: 'Saber', rarity: 'common' },
  { name: 'Varista', type: 'Handgun', rarity: 'common' },
  { name: 'Photon Drop', type: 'Material', rarity: 'common' },
  { name: 'Grinder', type: 'Material', rarity: 'common' },
  { name: 'Resist/Fire', type: 'Unit', rarity: 'common' },
  { name: "DB's Saber", type: 'Saber', rarity: 'rare' },
  { name: 'Mag Cell', type: 'Material', rarity: 'rare' },
];
const INVENTORY = [
  { name: 'Monomate', qty: 8 },
  { name: 'Dimate', qty: 3 },
  { name: 'Telepipe', qty: 4 },
  { name: 'Saber', qty: 1 },
];

export default function Storage() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Storage" width={360} hint={tab === 0 ? 'Select item to withdraw.' : 'Select item to deposit.'}>
        <TabBar tabs={['Withdraw', 'Deposit']} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        <div style={{ fontSize: 11, color: C.textLight, padding: '0 4px', marginBottom: 6 }}>
          {tab === 0 ? `${STORED.length}/200 stored` : `${INVENTORY.length}/40 items`}
        </div>
        {(tab === 0 ? STORED : INVENTORY).map((item, i) => (
          <PillRow key={`${item.name}-${i}`} label={item.name} rightText={'type' in item ? (item as any).type : `x${(item as any).qty}`} selected={sel === i} onClick={() => setSel(i)} />
        ))}
      </Panel>
      <Panel title="Detail" width={240}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (
            <>
              <div style={{ fontSize: 15, fontWeight: 700, color: STORED[sel]?.rarity === 'rare' ? C.rare : C.text, marginBottom: 4 }}>{STORED[sel]?.name}</div>
              <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>{STORED[sel]?.type}</div>
            </>
          ) : (
            <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{INVENTORY[sel]?.name}</div>
          )}
          <Divider />
          <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
            {[tab === 0 ? 'Withdraw' : 'Deposit', 'Cancel'].map((a) => (
              <div key={a} style={{ flex: 1, padding: 7, fontSize: 13, fontWeight: 600, background: C.itemBg, border: '1px solid rgba(150,180,210,0.4)', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>{a}</div>
            ))}
          </div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
