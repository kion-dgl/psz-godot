import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, C } from '../pszui';

const UNIDENTIFIED = [
  { name: '??? Saber', slots: '???' },
  { name: '??? Sword', slots: '???' },
  { name: '??? Handgun', slots: '???' },
];
const GRINDABLE = [
  { name: 'Saber', grind: '+0', maxGrind: '+9', cost: 100 },
  { name: 'Brand', grind: '+3', maxGrind: '+12', cost: 300 },
  { name: 'Buster', grind: '+1', maxGrind: '+15', cost: 500 },
];

export default function Tekker() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  return (
    <ShopFrame>
      <Panel title="Tekker" width={380} hint={tab === 0 ? 'Identify a mysterious weapon.' : 'Grind your weapon for ATK bonus.'}>
        <TabBar tabs={['Identify', 'Grind']} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        {tab === 0 ? (
          UNIDENTIFIED.map((w, i) => <PillRow key={`${w.name}-${i}`} label={w.name} rightText={w.slots} selected={sel === i} onClick={() => setSel(i)} />)
        ) : (
          <>
            {GRINDABLE.map((w, i) => <PillRow key={w.name} label={w.name} rightText={`${w.grind} / ${w.maxGrind}`} selected={sel === i} onClick={() => setSel(i)} />)}
            <Divider />
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
              <span>Grind Cost:</span><span style={{ fontWeight: 700, color: '#886600' }}>{GRINDABLE[sel]?.cost.toLocaleString()} MST</span>
            </div>
          </>
        )}
      </Panel>
      <Panel title="Detail" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (
            <>
              <div style={{ fontSize: 15, fontWeight: 700, color: C.rare, marginBottom: 4 }}>{UNIDENTIFIED[sel]?.name}</div>
              <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>Unidentified weapon</div>
              <Divider />
              <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>This weapon must be identified before it can be equipped. The Tekker will reveal its true stats and element.</div>
              <div style={{ marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600, background: C.selectedGradient, border: '2px solid #d08010', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>Identify (100 MST)</div>
            </>
          ) : (
            <>
              <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 4 }}>{GRINDABLE[sel]?.name}</div>
              <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>Current grind: {GRINDABLE[sel]?.grind}</div>
              <Divider />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13 }}>
                {[['ATK Bonus', `+${parseInt(GRINDABLE[sel]?.grind.replace('+', '') || '0') * 2}`], ['Max Grind', GRINDABLE[sel]?.maxGrind || ''], ['Success Rate', '90%']].map(([k, v]) => (
                  <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}><span style={{ color: C.textLight }}>{k}</span><span style={{ fontWeight: 700, color: C.text }}>{v}</span></div>
                ))}
              </div>
              <div style={{ marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600, background: C.selectedGradient, border: '2px solid #d08010', borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center' }}>Grind ({GRINDABLE[sel]?.cost} MST)</div>
            </>
          )}
        </div>
      </Panel>
    </ShopFrame>
  );
}
