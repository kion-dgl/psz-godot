import { useState } from 'react';

// PSZ color palette — pale icy blue with white items, black text
const C = {
  // Backgrounds
  bgLight: '#a8cce8',       // Pale icy blue (main panel bg)
  bgMid: '#8ab8d8',         // Slightly darker blue
  bgDark: '#2a3448',        // Dark navy (title bar, dividers)
  bgDarker: '#1e2838',      // Darker navy
  // Items
  itemBg: 'rgba(255,255,255,0.85)',  // White pill rows
  itemBgHover: 'rgba(255,255,255,0.95)',
  selectedGradient: 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)',  // Orange/yellow
  // Text
  text: '#1a1a2a',          // Near-black text
  textLight: '#3a4a5a',     // Lighter for secondary info
  textWhite: '#ffffff',      // White text on dark bg
  textOnSelected: '#1a1a2a', // Black text on orange selection
  // Accents
  hintBg: 'rgba(255,255,255,0.7)',   // Hint bar background
  hintBorder: '#8aa8c8',
  separator: '#7aa0c0',     // Horizontal line separators
  // HP/PP
  hp: '#44bb44',
  hpBg: '#d8e8d8',
  pp: '#4488ee',
  ppBg: '#d8d8f0',
  // Rarity
  rare: '#cc2222',
  common: '#1a1a2a',
};

// Scanline overlay for that DS texture feel
const SCANLINES = `repeating-linear-gradient(
  0deg,
  transparent,
  transparent 2px,
  rgba(120,160,200,0.08) 2px,
  rgba(120,160,200,0.08) 4px
)`;

// --- Shared Components ---

function Panel({ title, children, width, hint, style }: {
  title?: string;
  children: React.ReactNode;
  width?: number | string;
  hint?: string;
  style?: React.CSSProperties;
}) {
  return (
    <div style={{
      width: width || '100%',
      display: 'flex', flexDirection: 'column',
      filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.25))',
      ...style,
    }}>
      {/* Title bar with diagonal cut */}
      {title && (
        <div style={{ position: 'relative', height: '36px', marginBottom: '-1px' }}>
          <div style={{
            position: 'absolute', inset: 0,
            background: C.bgDark,
            clipPath: 'polygon(0 0, 85% 0, 80% 100%, 0 100%)',
          }} />
          {/* Dark stripe accent */}
          <div style={{
            position: 'absolute', top: 0, right: 0, bottom: 0, width: '30%',
            background: `linear-gradient(135deg, transparent 30%, ${C.bgDarker} 30%, ${C.bgDarker} 35%, ${C.bgDark} 35%)`,
          }} />
          <div style={{
            position: 'relative', padding: '6px 16px',
            fontSize: '16px', fontWeight: 800, color: C.textWhite,
            fontStyle: 'italic', letterSpacing: '0.5px',
            textShadow: '1px 1px 0 rgba(0,0,0,0.5)',
            zIndex: 1,
          }}>
            {title}
          </div>
        </div>
      )}

      {/* Main body */}
      <div style={{
        flex: 1,
        background: C.bgLight,
        backgroundImage: SCANLINES,
        borderTop: `2px solid ${C.bgDark}`,
        borderBottom: hint ? 'none' : `2px solid ${C.separator}`,
        padding: '8px',
      }}>
        {children}
      </div>

      {/* Bottom hint bar */}
      {hint && (
        <div style={{
          background: C.hintBg,
          backgroundImage: SCANLINES,
          border: `1px solid ${C.hintBorder}`,
          borderRadius: '0 0 20px 20px',
          padding: '8px 20px',
          fontSize: '14px', color: C.text,
          marginTop: '8px',
          textAlign: 'center',
        }}>
          {hint}
        </div>
      )}
    </div>
  );
}

function PillRow({ label, selected, rightText, onClick }: {
  label: string;
  selected?: boolean;
  rightText?: string;
  onClick?: () => void;
}) {
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        padding: '7px 14px', marginBottom: '3px',
        background: selected ? C.selectedGradient : C.itemBg,
        borderRadius: '3px',
        border: selected ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
        cursor: 'pointer', fontSize: '14px', fontWeight: 600,
        color: C.text,
        transition: 'background 0.1s ease',
      }}
    >
      <span>{label}</span>
      {rightText && <span style={{ fontSize: '12px', color: C.textLight }}>{rightText}</span>}
    </div>
  );
}

function StatBar({ label, current, max, color, bgColor }: {
  label: string; current: number; max: number; color: string; bgColor: string;
}) {
  const pct = Math.min(100, (current / max) * 100);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
      <span style={{ fontSize: '12px', color: C.text, width: '24px', fontWeight: 700 }}>{label}</span>
      <div style={{
        flex: 1, height: '12px', background: bgColor,
        borderRadius: '6px', overflow: 'hidden', border: '1px solid rgba(0,0,0,0.15)',
      }}>
        <div style={{
          width: `${pct}%`, height: '100%', background: color,
          borderRadius: '6px',
        }} />
      </div>
      <span style={{ fontSize: '11px', color: C.text, width: '65px', textAlign: 'right', fontWeight: 600 }}>
        {current}/{max}
      </span>
    </div>
  );
}

function TabBar({ tabs, active, onSelect }: {
  tabs: string[]; active: number; onSelect: (i: number) => void;
}) {
  return (
    <div style={{
      display: 'flex', gap: '3px', marginBottom: '8px',
    }}>
      {tabs.map((tab, i) => (
        <button
          key={tab}
          onClick={() => onSelect(i)}
          style={{
            padding: '5px 14px', fontSize: '12px', fontWeight: 700,
            background: active === i ? C.selectedGradient : C.itemBg,
            color: C.text,
            border: active === i ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
            borderRadius: '4px', cursor: 'pointer',
          }}
        >
          {tab}
        </button>
      ))}
    </div>
  );
}

function Divider() {
  return <div style={{ height: '2px', background: C.separator, margin: '6px 0', opacity: 0.5 }} />;
}

// --- Menu Mockups ---

function PauseMenu() {
  const [sel, setSel] = useState(0);
  const items = ['Equipment', 'Inventory', 'Techniques', 'Status', 'Options', 'Quit Mission'];
  return (
    <Panel title="Menu" width={320} hint="Select from the Menu.">
      {items.map((item, i) => (
        <PillRow key={item} label={item} selected={sel === i} onClick={() => setSel(i)} />
      ))}
    </Panel>
  );
}

function HUD() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', width: '400px' }}>
      {/* Player HUD */}
      <div style={{
        background: C.bgLight, backgroundImage: SCANLINES,
        border: `2px solid ${C.separator}`, borderRadius: '8px',
        padding: '10px 14px',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
          <span style={{ fontSize: '14px', fontWeight: 700, color: C.text }}>HUmar Lv.42</span>
          <span style={{ fontSize: '12px', fontWeight: 600, color: '#886600' }}>12,450 MST</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <StatBar label="HP" current={342} max={480} color={C.hp} bgColor={C.hpBg} />
          <StatBar label="PP" current={86} max={120} color={C.pp} bgColor={C.ppBg} />
        </div>
      </div>

      {/* Target */}
      <div style={{
        background: C.bgLight, backgroundImage: SCANLINES,
        border: `2px solid ${C.separator}`, borderRadius: '8px',
        padding: '8px 14px', width: '220px',
      }}>
        <div style={{ fontSize: '13px', fontWeight: 700, color: C.rare, marginBottom: '4px' }}>Booma</div>
        <StatBar label="HP" current={120} max={200} color="#cc4444" bgColor="#e8d0d0" />
      </div>
    </div>
  );
}

function EquipmentMenu() {
  const [sel, setSel] = useState(0);
  const slots = [
    { slot: 'Weapon', item: 'Blade' },
    { slot: 'Frame', item: 'Chef Apron' },
    { slot: 'Mag', item: 'Mag' },
    { slot: 'Unit 1', item: 'Ace/Power' },
    { slot: 'Unit 2', item: 'Ace/HP' },
    { slot: 'Unit 3', item: 'Ace/Hit' },
    { slot: 'Unit 4', item: 'Ace/Guard' },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Equipment" width={340} hint="Select equipment slot.">
        {slots.map((s, i) => (
          <PillRow
            key={s.slot}
            label={s.item}
            rightText={s.slot}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
      </Panel>

      <Panel title="Detail" width={280}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '4px' }}>
            {slots[sel].item}
          </div>
          <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
            Saber-type weapon
          </div>
          <Divider />
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '13px' }}>
            {[['ATK', '40'], ['ATA', '35'], ['Grind', '+0'], ['Element', 'None']].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: C.textLight }}>{k}</span>
                <span style={{ fontWeight: 700, color: C.text }}>{v}</span>
              </div>
            ))}
          </div>
        </div>
      </Panel>
    </div>
  );
}

function ShopMenu() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const weapons = [
    { name: 'Saber', price: 100, type: 'Saber' },
    { name: 'Brand', price: 350, type: 'Saber' },
    { name: 'Buster', price: 800, type: 'Saber' },
    { name: 'Dagger', price: 100, type: 'Dagger' },
    { name: 'Knife', price: 350, type: 'Dagger' },
    { name: 'Sword', price: 200, type: 'Sword' },
    { name: 'Gigush', price: 550, type: 'Sword' },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Weapon Shop" width={380} hint={`Press ENTER to buy - ${weapons[sel].price} MST`}>
        <TabBar tabs={['Weapons', 'Armor', 'Units', 'Sell']} active={tab} onSelect={setTab} />
        {weapons.map((w, i) => (
          <PillRow
            key={w.name}
            label={w.name}
            rightText={`${w.price.toLocaleString()} MST`}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
        <Divider />
        <div style={{
          display: 'flex', justifyContent: 'space-between',
          fontSize: '13px', color: C.text, padding: '2px 4px',
        }}>
          <span>Your Meseta:</span>
          <span style={{ fontWeight: 700, color: '#886600' }}>12,450</span>
        </div>
      </Panel>

      <Panel title="Detail" width={280}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '4px' }}>
            {weapons[sel].name}
          </div>
          <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
            {weapons[sel].type}-type
          </div>
          <Divider />
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '13px' }}>
            {[['ATK', '40'], ['ATA', '35'], ['Req. Level', '1']].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: C.textLight }}>{k}</span>
                <span style={{ fontWeight: 700, color: C.text }}>{v}</span>
              </div>
            ))}
          </div>
        </div>
      </Panel>
    </div>
  );
}

function InventoryMenu() {
  const [sel, setSel] = useState(0);
  const items = [
    { name: 'Monomate', qty: 8 },
    { name: 'Dimate', qty: 3 },
    { name: 'Trimate', qty: 1 },
    { name: 'Monofluid', qty: 5 },
    { name: 'Difluid', qty: 2 },
    { name: 'Telepipe', qty: 4 },
    { name: 'Moon Atomizer', qty: 1 },
    { name: 'Photon Drop', qty: 6 },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Inventory" width={360} hint="Select an item.">
        <div style={{
          display: 'flex', justifyContent: 'space-between',
          fontSize: '12px', color: C.textLight, padding: '0 4px', marginBottom: '6px',
        }}>
          <span>{items.length}/40 items</span>
          <span style={{ fontWeight: 600, color: '#886600' }}>12,450 MST</span>
        </div>
        {items.map((item, i) => (
          <PillRow
            key={item.name}
            label={item.name}
            rightText={`x${item.qty}`}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
      </Panel>

      <Panel title="Item Info" width={260}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '8px' }}>
            {items[sel].name}
          </div>
          <Divider />
          <div style={{ fontSize: '13px', color: C.text, lineHeight: '1.5' }}>
            Restores a small amount of HP. Basic healing item used by all hunters.
          </div>
        </div>
        <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
          {['Use', 'Drop'].map((action) => (
            <div key={action} style={{
              flex: 1, padding: '7px', fontSize: '13px', fontWeight: 600,
              background: C.itemBg, border: '1px solid rgba(150,180,210,0.4)',
              borderRadius: '4px', color: C.text, cursor: 'pointer', textAlign: 'center',
            }}>
              {action}
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}

function StatusScreen() {
  return (
    <Panel title="Status" width={520}>
      <div style={{ display: 'flex', gap: '16px' }}>
        <div style={{ flex: 1 }}>
          <div style={{
            background: C.itemBg, borderRadius: '4px',
            padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
            marginBottom: '8px',
          }}>
            <div style={{ fontSize: '16px', fontWeight: 700, color: C.text }}>Kion</div>
            <div style={{ fontSize: '12px', color: C.textLight }}>HUmar — Lv. 42</div>
          </div>
          <div style={{
            background: C.itemBg, borderRadius: '4px',
            padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '5px' }}>
              <StatBar label="HP" current={342} max={480} color={C.hp} bgColor={C.hpBg} />
              <StatBar label="PP" current={86} max={120} color={C.pp} bgColor={C.ppBg} />
            </div>
            <Divider />
            <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '4px' }}>EXP to next level</div>
            <StatBar label="" current={14200} max={18500} color="#c09030" bgColor="#e8dcc8" />
            <div style={{ fontSize: '10px', color: C.textLight, textAlign: 'right', marginTop: '2px' }}>
              Next: 4,300
            </div>
          </div>
        </div>

        <div style={{ width: '200px' }}>
          <div style={{
            background: C.itemBg, borderRadius: '4px',
            padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
          }}>
            <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px', fontWeight: 700 }}>STATS</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '5px', fontSize: '13px' }}>
              {[
                ['ATK', '286'], ['DEF', '194'], ['ATA', '152'],
                ['EVP', '98'], ['MST', '45'], ['LCK', '12'],
              ].map(([k, v]) => (
                <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: C.textLight }}>{k}</span>
                  <span style={{ fontWeight: 700, color: C.text }}>{v}</span>
                </div>
              ))}
            </div>
            <Divider />
            <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '4px', fontWeight: 700 }}>PLAY TIME</div>
            <div style={{ fontSize: '14px', fontWeight: 700, color: C.text }}>24:13:45</div>
          </div>
        </div>
      </div>
    </Panel>
  );
}

function GuildCounter() {
  const [sel, setSel] = useState(0);
  const quests = [
    { name: 'Valley Patrol', area: 'Gurhacia Valley', diff: 'Normal', rank: 'C' },
    { name: 'Swamp Sweep', area: 'Ozette Wetlands', diff: 'Normal', rank: 'C' },
    { name: 'Forest Recon', area: 'Rioh Snowfield', diff: 'Hard', rank: 'B' },
    { name: 'Desert Storm', area: 'Makara Desert', diff: 'Hard', rank: 'B' },
    { name: 'Tower Ascent', area: 'Eternal Tower', diff: 'Super Hard', rank: 'A' },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Guild Counter" width={420} hint="Select a quest.">
        {quests.map((q, i) => (
          <PillRow
            key={q.name}
            label={q.name}
            rightText={`${q.diff} [${q.rank}]`}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
      </Panel>

      <Panel title="Quest Info" width={280}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '2px' }}>
            {quests[sel].name}
          </div>
          <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
            {quests[sel].area} — {quests[sel].diff}
          </div>
          <Divider />
          <div style={{ fontSize: '13px', color: C.text, lineHeight: '1.5' }}>
            Patrol the area and eliminate any hostile creatures. Report back to the guild upon completion.
          </div>
        </div>
      </Panel>
    </div>
  );
}

// --- Main Page ---

const MENU_DEMOS = [
  { id: 'hud', label: 'HUD', component: HUD },
  { id: 'pause', label: 'Pause Menu', component: PauseMenu },
  { id: 'equipment', label: 'Equipment', component: EquipmentMenu },
  { id: 'inventory', label: 'Inventory', component: InventoryMenu },
  { id: 'shop', label: 'Weapon Shop', component: ShopMenu },
  { id: 'status', label: 'Status', component: StatusScreen },
  { id: 'guild', label: 'Guild Counter', component: GuildCounter },
];

export default function MenuDesign() {
  const [activeMenu, setActiveMenu] = useState('pause');
  const ActiveComponent = MENU_DEMOS.find((m) => m.id === activeMenu)?.component || PauseMenu;

  return (
    <div style={{
      width: '100%', height: '100%',
      background: `linear-gradient(180deg, #b8d8f0 0%, #88b8e0 40%, #a0c8e8 100%)`,
      backgroundImage: `${SCANLINES}, linear-gradient(180deg, #b8d8f0 0%, #88b8e0 40%, #a0c8e8 100%)`,
      color: C.text, display: 'flex', overflow: 'hidden',
      fontFamily: "'Segoe UI', 'Helvetica Neue', Arial, sans-serif",
    }}>
      {/* Sidebar (dev only — not part of game UI) */}
      <div style={{
        width: '150px', flexShrink: 0,
        background: 'rgba(30,40,60,0.9)',
        padding: '12px', display: 'flex', flexDirection: 'column', gap: '3px',
      }}>
        <div style={{
          fontSize: '10px', color: '#8899aa', marginBottom: '8px',
          textTransform: 'uppercase', letterSpacing: '1px',
        }}>
          Menu Designs
        </div>
        {MENU_DEMOS.map((demo) => (
          <button
            key={demo.id}
            onClick={() => setActiveMenu(demo.id)}
            style={{
              display: 'block', width: '100%', padding: '7px 10px',
              background: activeMenu === demo.id ? 'rgba(240,160,30,0.2)' : 'transparent',
              border: activeMenu === demo.id ? '1px solid #f0a020' : '1px solid transparent',
              borderRadius: '4px', cursor: 'pointer', textAlign: 'left',
              fontSize: '12px',
              color: activeMenu === demo.id ? '#f8c840' : '#aabbcc',
            }}
          >
            {demo.label}
          </button>
        ))}
      </div>

      {/* Preview area */}
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '32px',
      }}>
        <ActiveComponent />
      </div>
    </div>
  );
}
