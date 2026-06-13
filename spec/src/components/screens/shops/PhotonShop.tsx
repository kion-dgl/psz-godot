import { useState } from 'react';
import { ShopScreen, PillRow, Divider, StatRow, ActionButton, C, DetailPanel } from '../pszui';

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
        <DetailPanel>
          <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{item.cat}</div>
          <Divider />
          <StatRow label="Cost" value={`${item.cost} Photon Drops`} color="#4488ee" />
          <ActionButton label="Exchange" />
        </DetailPanel>
      }
    >
      {/* No TABS here, so the balance pins to the top of the LIST. */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 8 }}>
        <span style={{ fontSize: 12, fontWeight: 800, color: C.pp, background: 'rgba(255,255,255,0.8)', border: '1px solid rgba(150,180,210,0.5)', borderRadius: 10, padding: '3px 10px' }}>12 Photon Drops</span>
      </div>
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
    </ShopScreen>
  );
}
