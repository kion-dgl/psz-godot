import { useState } from 'react';
import { ShopFrame, Panel, PillRow, TabBar, C } from '../pszui';

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

  return (
    <ShopFrame>
      <Panel title="Storage" width={360} hint={isItems ? itemsHint : mesetaHint}>
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
      </Panel>
      <Panel title="Storage Keeper" width={240}>
        <div style={{
          height: '100%', minHeight: 320, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'rgba(40,52,72,0.25)', borderRadius: 4, border: '1px solid rgba(150,180,210,0.4)',
          fontSize: 16, fontWeight: 700, color: C.textLight, letterSpacing: '0.1em',
        }}>
          [ NPC ]
        </div>
      </Panel>
    </ShopFrame>
  );
}
