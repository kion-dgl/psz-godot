import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, StatRow, ActionButton, C } from '../pszui';

type Grind = {
  name: string; grind: number; max: number; grinder: string; cost: number;
  missing?: boolean; atkFrom: string; atkTo: string; accFrom: string; accTo: string;
};
const GRINDABLE: Grind[] = [
  { name: 'Saber', grind: 2, max: 9, grinder: 'trigrinder', cost: 600, atkFrom: '45', atkTo: '48', accFrom: '82', accTo: '82' },
  { name: 'Brand', grind: 0, max: 12, grinder: 'digrinder', cost: 300, atkFrom: '60', atkTo: '63', accFrom: '70', accTo: '70' },
  { name: 'Buster', grind: 5, max: 15, grinder: 'monogrinder', cost: 150, atkFrom: '88', atkTo: '90', accFrom: '65', accTo: '65' },
  { name: 'Pallasch', grind: 1, max: 12, grinder: 'trigrinder', cost: 600, missing: true, atkFrom: '102', atkTo: '105', accFrom: '60', accTo: '60' },
];

const GRINDERS = [
  { name: 'Monogrinder', qty: 'x3' },
  { name: 'Digrinder', qty: 'x1' },
  { name: 'Trigrinder', qty: 'x0' },
];

type Unid = { name: string; stars: string; cost: number };
const UNIDENTIFIED: Unid[] = [
  { name: '??? Saber', stars: '7★', cost: 5000 },
  { name: '??? Rifle', stars: '5★', cost: 1000 },
  { name: '??? Cane', stars: '6★', cost: 3000 },
];

export default function Tekker() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = tab === 0 ? GRINDABLE : UNIDENTIFIED;
  const i = Math.min(sel, list.length - 1);

  return (
    <ShopFrame>
      <Panel title="Tekker" width={380} hint="Left/Right: Switch Mode   Up/Down: Select   Enter: Confirm   Esc: Leave">
        <TabBar tabs={['Grind', 'Identify']} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} />
        {tab === 0
          ? GRINDABLE.map((w, idx) => (
              <PillRow
                key={w.name}
                label={`${w.name} +${w.grind}/${w.max} [${w.grinder}]`}
                rightText={`${w.cost} M`}
                muted={w.missing}
                selected={i === idx}
                onClick={() => setSel(idx)}
              />
            ))
          : UNIDENTIFIED.map((w, idx) => (
              <PillRow
                key={w.name}
                label={`${w.name} [${w.stars}]`}
                rightText={`${w.cost.toLocaleString()} M`}
                selected={i === idx}
                onClick={() => setSel(idx)}
              />
            ))}
      </Panel>
      <Panel title="Detail" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (() => {
            const w = GRINDABLE[i];
            return (
              <>
                <div style={{ fontSize: 14, fontWeight: 700, color: C.text, marginBottom: 6 }}>Grinders</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  {GRINDERS.map((g) => <StatRow key={g.name} label={g.name} value={g.qty} />)}
                </div>
                <Divider />
                <div style={{ fontSize: 14, fontWeight: 700, color: C.text, marginBottom: 6 }}>After Grind</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="ATK" value={`${w.atkFrom} → ${w.atkTo} (+${Number(w.atkTo) - Number(w.atkFrom)})`} color="#338844" />
                  <StatRow label="ACC" value={`${w.accFrom} → ${w.accTo} (+0)`} color={C.textLight} />
                </div>
                <ActionButton label={`Grind — ${w.cost} M`} />
              </>
            );
          })() : (() => {
            const w = UNIDENTIFIED[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.rare, marginBottom: 4 }}>{w.name}</div>
                <div style={{ fontSize: 11, color: C.textLight, marginBottom: 8 }}>Unidentified weapon</div>
                <Divider />
                <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>The Tekker reveals its true stats and element.</div>
                <ActionButton label={`Identify — ${w.cost.toLocaleString()} M`} />
              </>
            );
          })()}
        </div>
      </Panel>
    </ShopFrame>
  );
}
