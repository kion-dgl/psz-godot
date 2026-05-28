import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const RECIPES = [
  { name: 'Brand', mats: 'Saber + Monogrinder', cost: 200 },
  { name: 'Buster', mats: 'Brand + Digrinder', cost: 500 },
  { name: 'Pallasch', mats: 'Buster + Trigrinder + Im Photon', cost: 1200 },
  { name: 'Gladius', mats: 'Knife + Digrinder', cost: 400 },
  { name: 'Claymore', mats: 'Gigush + Trigrinder', cost: 800 },
];
const PHOTONS = ['Im Photon', 'El Photon', 'Ban Photon', 'Ray Photon', 'Zon Photon', 'Megi Photon', 'Gra Photon'];

export default function CraftingShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Synthesis Shop" width={400} hint={tab === 0 ? 'Select a recipe to craft.' : 'Select a photon crystal to apply.'}>
        <TabBar tabs={['Craft', 'Boards']} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        {tab === 0 ? (
          RECIPES.map((r, i) => (
            <PillRow key={r.name} label={r.name} rightText={`${r.cost} MST`} selected={sel === i} onClick={() => setSel(i)} />
          ))
        ) : (
          PHOTONS.map((p, i) => (
            <PillRow key={p} label={p} selected={sel === i} onClick={() => setSel(i)} />
          ))
        )}
      </Panel>
      <Panel title="Detail" width={260}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (
            <>
              <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{RECIPES[sel]?.name}</div>
              <Divider />
              <div style={{ fontSize: 13, color: C.text, marginBottom: 4 }}>Materials:</div>
              <div style={{ fontSize: 12, color: C.textLight, lineHeight: 1.5 }}>{RECIPES[sel]?.mats}</div>
              <Divider />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
                <span style={{ color: C.textLight }}>Cost</span><span style={{ fontWeight: 700, color: '#886600' }}>{RECIPES[sel]?.cost} MST</span>
              </div>
              <div style={{ marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600, background: C.selectedGradient, border: '2px solid #d08010', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>Craft</div>
            </>
          ) : (
            <>
              <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{PHOTONS[sel]}</div>
              <Divider />
              <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>Apply this photon crystal to a weapon to add an elemental special attack. The tier is rolled based on weapon rarity.</div>
            </>
          )}
        </div>
      </Panel>
    </ShopFrame>
  );
}
