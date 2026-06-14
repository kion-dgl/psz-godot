import { useState } from 'react';
import { ShopScreen, PillRow, TabBar, Divider, StatRow, C, DetailPanel } from '../pszui';

// A storage row. Gear (weapon/armor/unit/mag) carries stats; consumables carry
// an effect + a count. The detail panel renders one or the other.
type StorageItem = {
  name: string; qty: string; equipped?: boolean;
  kind: 'weapon' | 'armor' | 'unit' | 'mag' | 'item';
  stats?: { label: string; value: string }[];
  effect?: string;
};

const INVENTORY: StorageItem[] = [
  { name: 'Saber +3 ★★★★', qty: '1', equipped: true, kind: 'weapon',
    stats: [{ label: 'Type', value: 'Saber' }, { label: 'ATK', value: '48–54' }, { label: 'ACC', value: '38' }, { label: 'Element', value: 'Fire Lv.2' }, { label: 'Grind', value: '+3 / +9' }] },
  { name: 'Monomate', qty: 'x5', kind: 'item', effect: 'Restores a small amount of HP.' },
  { name: 'Mag ★', qty: '1', equipped: true, kind: 'mag',
    stats: [{ label: 'Level', value: '12' }, { label: 'DEF / POW', value: '5 / 7' }, { label: 'DEX / MIND', value: '0 / 0' }] },
  { name: 'Telepipe', qty: 'x3', kind: 'item', effect: 'Warps back to the city from the field.' },
];
const STORAGE: StorageItem[] = [
  { name: 'Brand +2 ★★', qty: '1', kind: 'weapon',
    stats: [{ label: 'Type', value: 'Sword' }, { label: 'ATK', value: '62–66' }, { label: 'ACC', value: '70' }, { label: 'Element', value: '—' }, { label: 'Grind', value: '+2 / +12' }] },
  { name: 'Spirit Robe', qty: '1', kind: 'armor',
    stats: [{ label: 'Type', value: 'Armor' }, { label: 'DEF', value: '16' }, { label: 'Slots', value: '1' }] },
  { name: 'Dimate', qty: 'x9', kind: 'item', effect: 'Restores a moderate amount of HP.' },
  { name: 'Photon Drop', qty: 'x12', kind: 'item', effect: 'Trade currency for the Photon Collector.' },
  { name: 'Heat Resist Lv1', qty: '1', kind: 'unit',
    stats: [{ label: 'Type', value: 'Unit' }, { label: 'Effect', value: 'Fire resist +10%' }] },
];

const TABS = ['Deposit Items', 'Withdraw Items', 'Deposit Meseta', 'Withdraw Meseta'];

export default function Storage() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const isItems = tab < 2;
  const itemsHint = 'Left/Right: Switch Tab   Up/Down: Select   Enter: Move   Esc: Back';
  const mesetaHint = 'Left/Right: Switch Tab   Enter: Transfer   Esc: Back';
  const list = tab === 0 ? INVENTORY : STORAGE;
  const i = Math.min(sel, list.length - 1);
  const item = list[i];

  return (
    <ShopScreen
      title="Storage"
      hint={isItems ? itemsHint : mesetaHint}
      portrait="storage-counter"
      info={
        <DetailPanel>
          {isItems ? (
            item.kind === 'item' ? (
              // Consumable / material — effect + count.
              <>
                <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>{item.effect}</div>
                <Divider />
                <StatRow label="Count" value={item.qty} />
                <StatRow label="Status" value="Storable" />
              </>
            ) : (
              // Gear — stats.
              <>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  {(item.stats ?? []).map((s) => <StatRow key={s.label} label={s.label} value={s.value} />)}
                </div>
                <Divider />
                <StatRow label="Status" value={item.equipped ? 'Equipped — cannot deposit' : 'Storable'} />
              </>
            )
          ) : (
            <div style={{ fontSize: 13, color: C.text, lineHeight: 1.5 }}>
              Transfer meseta between your wallet and the bank.
            </div>
          )}
        </DetailPanel>
      }
    >
      <TabBar tabs={TABS} active={tab} onSelect={(t) => { setTab(t); setSel(0); }} />
      {isItems ? (
        <>
          <div style={{ fontSize: 11, fontWeight: 700, color: C.textLight, padding: '2px 4px 6px', letterSpacing: '0.08em' }}>
            {tab === 0 ? 'INVENTORY (14/40)' : 'STORAGE (37/200)'}
          </div>
          {list.map((it, idx) => (
            <PillRow
              key={it.name}
              label={it.name}
              rightText={it.qty}
              tag={it.equipped ? { text: 'E', color: '#888' } : undefined}
              muted={it.equipped}
              selected={i === idx}
              onClick={() => setSel(idx)}
            />
          ))}
        </>
      ) : (
        <>
          <div style={{ fontSize: 11, fontWeight: 700, color: C.textLight, padding: '2px 4px 6px', letterSpacing: '0.08em' }}>
            WALLET: 50,000 M    BANK: 125,000 M
          </div>
          <PillRow label={tab === 2 ? 'Deposit Meseta…' : 'Withdraw Meseta…'} selected onClick={() => {}} />
        </>
      )}
    </ShopScreen>
  );
}
