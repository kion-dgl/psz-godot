import { useState } from 'react';
import { ShopScreen, PillRow, TabBar, StatRow, C, DetailPanel } from '../pszui';

type StorageItem = { name: string; qty: string; equipped?: boolean };
const INVENTORY: StorageItem[] = [
  { name: 'Saber +3 ★★★★', qty: '1', equipped: true },
  { name: 'Monomate', qty: 'x5' },
  { name: 'Mag ★', qty: '1', equipped: true },
  { name: 'Telepipe', qty: 'x3' },
];
const STORAGE: StorageItem[] = [
  { name: 'Brand +2 ★★', qty: '1' },
  { name: 'Spirit Robe', qty: '1' },
  { name: 'Dimate', qty: 'x9' },
  { name: 'Photon Drop', qty: 'x12' },
  { name: 'Heat Resist Lv1', qty: '1' },
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
            <>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <StatRow label="Qty" value={item.qty} />
                <StatRow label="Status" value={item.equipped ? 'Equipped — cannot deposit' : 'Storable'} />
              </div>
            </>
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
