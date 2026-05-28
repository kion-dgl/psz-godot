import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, StatRow, ActionButton, C } from '../pszui';

type Recipe = { name: string; type: string; rarity: string; mats: string; cost: number };
const RECIPES: Recipe[] = [
  { name: 'Flame Sword', type: 'Sword', rarity: '★', mats: 'Ore 3', cost: 250 },
  { name: 'Ice Rifle', type: 'Rifle', rarity: '★★', mats: 'Metal Alloy 2, Ice Essence 1', cost: 600 },
  { name: 'Dark Staff', type: 'Staff', rarity: '★★★', mats: 'Dark Matter 1, Amethyst 2', cost: 1500 },
];

type Board = { name: string; rarity: string; yield: string; cost: number };
const BOARDS: Board[] = [
  { name: 'Monogrinder Board', rarity: '★★', yield: 'x2', cost: 500 },
  { name: 'Digrinder Board', rarity: '★★★', yield: 'x1', cost: 1000 },
];

const ELEMENT_NOTE = 'Choose a photon crystal (Im / El / Ban / Ray / Zon / Megi / Gra) to set the weapon’s element & special-attack tier (rolled by rarity).';

export default function CraftingShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = tab === 0 ? RECIPES : BOARDS;
  const i = Math.min(sel, list.length - 1);

  return (
    <ShopFrame>
      <Panel title="Synthesis Shop" width={400} hint="Left/Right: Switch Mode   Up/Down: Select   Enter: Confirm   Esc: Leave">
        <TabBar tabs={['Craft', 'Boards']} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} />
        {tab === 0
          ? RECIPES.map((r, idx) => (
              <PillRow
                key={r.name}
                label={`${r.name} ${r.rarity} (${r.mats})`}
                rightText={`${r.cost.toLocaleString()} M`}
                selected={i === idx}
                onClick={() => setSel(idx)}
              />
            ))
          : BOARDS.map((b, idx) => (
              <PillRow
                key={b.name}
                label={`${b.name} ${b.rarity} [${b.yield}]`}
                rightText={`${b.cost.toLocaleString()} M`}
                selected={i === idx}
                onClick={() => setSel(idx)}
              />
            ))}
      </Panel>
      <Panel title="Detail" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (() => {
            const r = RECIPES[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 2 }}>{r.name}</div>
                <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{r.rarity} · {r.type}</div>
                <Divider />
                <div style={{ fontSize: 13, color: C.text, marginBottom: 4 }}>Materials:</div>
                <div style={{ fontSize: 12, color: C.textLight, lineHeight: 1.5 }}>{r.mats}</div>
                <Divider />
                <StatRow label="Cost" value={`${r.cost.toLocaleString()} M`} />
                <div style={{ fontSize: 11, color: C.textLight, lineHeight: 1.5, marginTop: 8 }}>{ELEMENT_NOTE}</div>
                <ActionButton label="Craft" />
              </>
            );
          })() : (() => {
            const b = BOARDS[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 2 }}>{b.name}</div>
                <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{b.rarity}</div>
                <Divider />
                <div style={{ fontSize: 13, color: C.text, marginBottom: 4 }}>Materials:</div>
                <div style={{ fontSize: 12, color: C.textLight, lineHeight: 1.5 }}>Crafts {b.yield} per board.</div>
                <Divider />
                <StatRow label="Cost" value={`${b.cost.toLocaleString()} M`} />
                <ActionButton label="Craft" />
              </>
            );
          })()}
        </div>
      </Panel>
    </ShopFrame>
  );
}
