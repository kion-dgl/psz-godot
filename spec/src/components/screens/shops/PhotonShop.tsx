import { useState } from 'react';
import { ShopFrame, Panel, PillRow, Divider, C } from '../pszui';

const ITEMS = [
  { name: 'Monogrinder', cost: 1, cat: 'Grinders' },
  { name: 'Digrinder', cost: 3, cat: 'Grinders' },
  { name: 'Trigrinder', cost: 5, cat: 'Grinders' },
  { name: 'Im Photon', cost: 1, cat: 'Photon Crystals' },
  { name: 'El Photon', cost: 3, cat: 'Photon Crystals' },
  { name: 'Ban Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Ray Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Zon Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Megi Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Gra Photon', cost: 2, cat: 'Photon Crystals' },
  { name: 'Grinder Base C', cost: 3, cat: 'Materials' },
  { name: 'Grinder Base B', cost: 5, cat: 'Materials' },
  { name: 'Grinder Base A', cost: 8, cat: 'Materials' },
];

export default function PhotonShop() {
  const [sel, setSel] = useState(0);
  let lastCat = '';
  return (
    <ShopFrame>
      <Panel title="Photon Collector" width={380} hint="Trade Photon Drops for materials.">
        {ITEMS.map((item, i) => {
          const showHeader = item.cat !== lastCat;
          lastCat = item.cat;
          return (
            <div key={item.name}>
              {showHeader && <div style={{ fontSize: 11, fontWeight: 700, color: C.textLight, padding: '6px 4px 2px', textTransform: 'uppercase', letterSpacing: '0.1em' }}>{item.cat}</div>}
              <PillRow label={item.name} rightText={`${item.cost} PD`} selected={sel === i} onClick={() => setSel(i)} />
            </div>
          );
        })}
        <Divider />
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
          <span>Your Photon Drops:</span><span style={{ fontWeight: 700, color: '#4488ee' }}>12</span>
        </div>
      </Panel>
      <Panel title="Detail" width={260}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{ITEMS[sel].name}</div>
          <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{ITEMS[sel].cat}</div>
          <Divider />
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
            <span style={{ color: C.textLight }}>Cost</span><span style={{ fontWeight: 700, color: '#4488ee' }}>{ITEMS[sel].cost} Photon Drops</span>
          </div>
          <div style={{ marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600, background: C.selectedGradient, border: '2px solid #d08010', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>Exchange</div>
        </div>
      </Panel>
    </ShopFrame>
  );
}
