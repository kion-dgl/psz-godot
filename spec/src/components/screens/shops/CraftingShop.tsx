import { useState } from 'react';
import { ShopScreen, PillRow, TabBar, Divider, StatRow, ActionButton, C, DetailPanel } from '../pszui';

// A required material: how many you have vs how many the recipe needs.
type Mat = { name: string; need: number; have: number };

type Recipe = { name: string; type: string; rarity: string; materials: Mat[]; cost: number };
const RECIPES: Recipe[] = [
  { name: 'Flame Sword', type: 'Sword', rarity: '★', cost: 250,
    materials: [{ name: 'Ore', need: 3, have: 2 }] },
  { name: 'Ice Rifle', type: 'Rifle', rarity: '★★', cost: 600,
    materials: [{ name: 'Metal Alloy', need: 2, have: 4 }, { name: 'Ice Essence', need: 1, have: 0 }] },
  { name: 'Dark Staff', type: 'Staff', rarity: '★★★', cost: 1500,
    materials: [{ name: 'Dark Matter', need: 1, have: 1 }, { name: 'Amethyst', need: 2, have: 3 }] },
];

type Board = { name: string; rarity: string; yield: string; materials: Mat[]; cost: number };
const BOARDS: Board[] = [
  { name: 'Monogrinder Board', rarity: '★★', yield: 'x2', cost: 500,
    materials: [{ name: 'Photon Drop', need: 2, have: 12 }] },
  { name: 'Digrinder Board', rarity: '★★★', yield: 'x1', cost: 1000,
    materials: [{ name: 'Photon Sphere', need: 1, have: 0 }] },
];

const ELEMENT_NOTE = 'Choose a photon crystal (Im / El / Ban / Ray / Zon / Megi / Gra) to set the weapon’s element & special-attack tier (rolled by rarity).';

// Each required material as "have of need" — red when short, green when met.
function Materials({ materials }: { materials: Mat[] }) {
  return (
    <>
      <div style={{ fontSize: 13, color: C.text, marginBottom: 4 }}>Materials</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {materials.map((m) => (
          <StatRow key={m.name} label={m.name} value={`${m.have} of ${m.need}`}
            color={m.have < m.need ? C.rare : '#338844'} />
        ))}
      </div>
    </>
  );
}

export default function CraftingShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = tab === 0 ? RECIPES : BOARDS;
  const i = Math.min(sel, list.length - 1);

  return (
    <ShopScreen
      title="Synthesis Shop"
      hint="Left/Right: Switch Mode   Up/Down: Select   Enter: Confirm   Esc: Leave"
      portrait="synth-shop"
      info={
        <DetailPanel>
          {tab === 0 ? (() => {
            const r = RECIPES[i];
            return (
              <>
                <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{r.rarity} · {r.type}</div>
                <Divider />
                <Materials materials={r.materials} />
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
                <div style={{ fontSize: 12, color: C.textLight, marginBottom: 8 }}>{b.rarity} · crafts {b.yield} per board</div>
                <Divider />
                <Materials materials={b.materials} />
                <Divider />
                <StatRow label="Cost" value={`${b.cost.toLocaleString()} M`} />
                <ActionButton label="Craft" />
              </>
            );
          })()}
        </DetailPanel>
      }
    >
      <TabBar tabs={['Craft', 'Boards']} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} right="12,450 M" />
      {tab === 0
        ? RECIPES.map((r, idx) => (
            <PillRow
              key={r.name}
              label={`${r.name} ${r.rarity}`}
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
    </ShopScreen>
  );
}
