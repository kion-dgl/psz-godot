import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, Divider, Balance, StatRow, ActionButton, C } from '../pszui';

type Weapon = {
  name: string; price: number; type: string; rarity: string;
  atk: string; acc: string; element: string; maxGrind: string;
};
type Armor = { name: string; price: number; slots: string; def: string };
type Unit = { name: string; price: number; effect: string };

const WEAPONS: Weapon[] = [
  { name: 'Saber', price: 75, type: 'Saber', rarity: '★', atk: '32–38', acc: '30', element: '—', maxGrind: '+9' },
  { name: 'Sword', price: 90, type: 'Sword', rarity: '★', atk: '40–48', acc: '35', element: 'Fire Lv.1', maxGrind: '+9' },
  { name: 'Dagger', price: 60, type: 'Dagger', rarity: '★', atk: '26–30', acc: '42', element: '—', maxGrind: '+12' },
  { name: 'Rod', price: 120, type: 'Rod', rarity: '★★', atk: '18–22', acc: '28', element: 'Ice Lv.1', maxGrind: '+5' },
  { name: 'Wand', price: 135, type: 'Wand', rarity: '★★', atk: '14–18', acc: '25', element: 'Light Lv.1', maxGrind: '+5' },
];

const ARMOR: Armor[] = [
  { name: 'Frame [1 slot]', price: 60, slots: '1', def: '12' },
  { name: 'Psy Armor [2 slots]', price: 110, slots: '2', def: '20' },
  { name: 'Spirit Robe [1 slot]', price: 130, slots: '1', def: '16' },
];

const UNITS: Unit[] = [
  { name: 'Rookie / HP', price: 100, effect: '+20 HP' },
  { name: 'Ace / Power', price: 500, effect: '+15 ATP' },
  { name: 'Heat Resist Lv1', price: 250, effect: 'Fire resist +10%' },
];

const SELL = [
  { name: 'Saber +2', price: 38, type: 'Saber' },
  { name: 'Handgun', price: 45, type: 'Handgun' },
  { name: 'Frame', price: 30, type: 'Armor' },
];

const TABS = ['Weapons', 'Armor', 'Units', 'Sell'];

export default function WeaponShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const list = [WEAPONS, ARMOR, UNITS, SELL][tab];
  const i = Math.min(sel, list.length - 1);

  return (
    <ShopFrame>
      <Panel title="Weapon Shop" width={380} hint="Left/Right: Category   Up/Down: Select   Enter: Buy   Esc: Leave">
        <TabBar tabs={TABS} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} />
        {list.map((it, idx) => (
          <PillRow key={it.name} label={it.name} rightText={`${it.price} M`} selected={i === idx} onClick={() => setSel(idx)} />
        ))}
        <Divider />
        <Balance label="Your Meseta:" value="12,450" />
      </Panel>
      <Panel title="Detail" width={280}>
        <div style={{ background: C.itemBg, borderRadius: 4, padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)' }}>
          {tab === 0 ? (() => {
            const w = WEAPONS[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 8 }}>{w.name}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="Type" value={w.type} />
                  <StatRow label="Rarity" value={w.rarity} />
                  <StatRow label="ATK" value={w.atk} />
                  <StatRow label="ACC" value={w.acc} />
                  <StatRow label="Element" value={w.element} />
                  <StatRow label="Max Grind" value={w.maxGrind} />
                </div>
                <Divider />
                <Balance label="Buy" value={`${w.price} M`} />
                <Balance label="Sell" value={`${Math.floor(w.price / 2)} M`} />
                <ActionButton label={`Buy — ${w.price} M`} />
              </>
            );
          })() : tab === 1 ? (() => {
            const a = ARMOR[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 8 }}>{a.name}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="Type" value="Armor" />
                  <StatRow label="Slots" value={a.slots} />
                  <StatRow label="DEF" value={a.def} />
                </div>
                <Divider />
                <Balance label="Buy" value={`${a.price} M`} />
                <Balance label="Sell" value={`${Math.floor(a.price / 2)} M`} />
                <ActionButton label={`Buy — ${a.price} M`} />
              </>
            );
          })() : tab === 2 ? (() => {
            const u = UNITS[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 8 }}>{u.name}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="Type" value="Unit" />
                  <StatRow label="Effect" value={u.effect} />
                </div>
                <Divider />
                <Balance label="Buy" value={`${u.price} M`} />
                <Balance label="Sell" value={`${Math.floor(u.price / 2)} M`} />
                <ActionButton label={`Buy — ${u.price} M`} />
              </>
            );
          })() : (() => {
            const s = SELL[i];
            return (
              <>
                <div style={{ fontSize: 15, fontWeight: 700, color: C.text, marginBottom: 8 }}>{s.name}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <StatRow label="Type" value={s.type} />
                </div>
                <Divider />
                <Balance label="Sell (half price)" value={`${s.price} M`} />
                <ActionButton label={`Sell — ${s.price} M`} />
              </>
            );
          })()}
        </div>
      </Panel>
    </ShopFrame>
  );
}
