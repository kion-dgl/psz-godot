import { useState } from 'react';
import { ShopScreen, PillRow, Divider, Balance, StatRow, ActionButton, C } from '../pszui';

const ITEMS = [
  { name: 'Monogrinder', cost: 1, cat: 'Grinders' },
  { name: 'Digrinder', cost: 3, cat: 'Grinders' },
  { name: 'Im Photon', cost: 1, cat: 'Photon Crystals' },
  { name: 'Ban Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Ray Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Grinder Base C', cost: 3, cat: 'Materials' },
  { name: 'Grinder Base B', cost: 5, cat: 'Materials' },
];

export default function PhotonShop() {
  const [sel, setSel] = useState(0);
  const item = ITEMS[sel];
  let lastCat = '';
  return (
    <ShopScreen
      title="Photon Collector"
      hint="Up/Down: Select   Enter: Exchange   Esc: Leave"
      portrait="photon-collector"
      info={
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{item.name}</div>
          <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{item.cat}</div>
          <Divider />
          <StatRow label="Cost" value={`${item.cost} Photon Drops`} color="#4488ee" />
          <ActionButton label="Exchange" />
        </div>
      }
    >
      {ITEMS.map((it, i) => {
        const showHeader = it.cat !== lastCat;
        lastCat = it.cat;
        return (
          <div key={it.name}>
            {showHeader && <div style={{ fontSize: 11, fontWeight: 700, color: C.textLight, padding: '6px 4px 2px', textTransform: 'uppercase', letterSpacing: '0.1em' }}>{it.cat}</div>}
            <PillRow label={it.name} rightText={`${it.cost} PD`} selected={sel === i} onClick={() => setSel(i)} />
          </div>
        );
      })}
      <Divider />
      <Balance label="Your Photon Drops:" value="12" color="#4488ee" />
    </ShopScreen>
  );
}
