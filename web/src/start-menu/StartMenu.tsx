import { useState } from 'react';

// ── Layout ─────────────────────────────────────────────────────────────────────
const VIEWPORT_W = 1280;
const VIEWPORT_H = 720;
const LEFT_PANEL_W = 240;
const BOTTOM_PANEL_H = 320;
const PANEL_PAD = 12;

// ── Colors ─────────────────────────────────────────────────────────────────────
const C = {
  backdropBg: 'rgba(40, 60, 100, 0.82)',
  backdropBorder: 'rgba(100, 150, 210, 0.6)',
  panelBg: 'rgba(200, 215, 235, 0.92)',
  panelBorder: 'rgba(120, 160, 210, 0.7)',
  panelShadow: 'rgba(30, 50, 80, 0.3)',
  textDark: '#1a2540',
  textMuted: '#4a5a78',
  textLight: '#e8eef8',
  selectBg: '#e08820',
  selectText: '#fff',
  hpGreen: '#28b848',
  ppBlue: '#2878d8',
  arrowGreen: '#30b850',
  pageBg: 'rgba(50, 80, 130, 0.6)',
  labelBg: 'rgba(50, 75, 120, 0.9)',
};

const TYPE_ICONS: Record<string, { color: string; label: string }> = {
  weapon: { color: '#cc4444', label: 'W' },
  armor: { color: '#4488cc', label: 'A' },
  shield: { color: '#44aaaa', label: 'S' },
  unit: { color: '#8844aa', label: 'U' },
  tool: { color: '#44aa44', label: 'T' },
  tech: { color: '#aa44cc', label: 'M' },
  material: { color: '#aa8833', label: 'R' },
  mag: { color: '#cc8844', label: 'G' },
};

// ── Mock data ──────────────────────────────────────────────────────────────────
interface InventoryItem {
  name: string;
  type: string;
  description: string;
  equipped?: boolean;
  stats?: string;
}

const MENU_ITEMS = ['Items', 'Equip', 'Palette', 'Mags', 'Quest', 'System'];
const MENU_DESCRIPTIONS: Record<string, string> = {
  Items: 'Use items.', Equip: 'Equip weapons and armor.',
  Palette: 'Edit the action palette.', Mags: 'Feed and manage your Mag.',
  Quest: 'View current quest objectives.', System: 'System settings and options.',
};

const INVENTORY: InventoryItem[] = [
  { name: 'Monomate', type: 'tool', description: 'Restores a small amount of HP.' },
  { name: 'Dimate', type: 'tool', description: 'Restores a moderate amount of HP.' },
  { name: 'Monofluid', type: 'tool', description: 'Restores a small amount of PP.' },
  { name: 'Antidote', type: 'tool', description: 'Cures poison status.' },
  { name: 'Telepipe', type: 'tool', description: 'Warps to the city.' },
  { name: 'Saber', type: 'weapon', description: 'A standard blade. ATP +30.' },
  { name: 'Saber +3', type: 'weapon', description: 'A reinforced blade. ATP +45, Heat special.', equipped: true, stats: 'ATP +45' },
  { name: 'Handgun', type: 'weapon', description: 'Standard ranged weapon. ATP +18.' },
  { name: 'Normal Frame', type: 'armor', description: 'Basic body armor. DFP +10.', equipped: true, stats: 'DFP +10' },
  { name: 'Barrier', type: 'shield', description: 'Basic shield. EVP +8.', equipped: true, stats: 'EVP +8' },
  { name: 'HP Material', type: 'material', description: 'Permanently increases max HP by 2.' },
  { name: 'Photon Drop', type: 'material', description: 'A rare crystal. Used for trading.' },
  { name: 'Grinder', type: 'material', description: 'Used to strengthen weapons.' },
];

const EQUIPMENT_SLOTS = [
  { slot: 'Weapon', item: 'Saber +3', type: 'weapon', description: 'A reinforced blade. ATP +45, Heat special.' },
  { slot: 'Frame', item: 'Normal Frame', type: 'armor', description: 'Basic body armor. DFP +10.' },
  { slot: 'Shield', item: 'Barrier', type: 'shield', description: 'Basic shield. EVP +8.' },
  { slot: 'Unit 1', item: '--', type: 'unit', description: 'No unit equipped.' },
  { slot: 'Unit 2', item: '--', type: 'unit', description: 'No unit equipped.' },
  { slot: 'Unit 3', item: '--', type: 'unit', description: 'No unit equipped.' },
  { slot: 'Unit 4', item: '--', type: 'unit', description: 'No unit equipped.' },
  { slot: 'Mag', item: 'Mag Lv12', type: 'mag', description: 'DEF 5 / POW 3 / DEX 2 / MIND 2' },
];

const PALETTE_PAGES = [
  ['Attack', 'Strong Attack', 'Monomate'],
  ['Foie', 'Resta', 'Dodge Roll'],
  ['Attack', 'Dimate', 'Telepipe'],
];

const PALETTE_ACTIONS = [
  'Attack', 'Strong Attack', 'Dodge Roll',
  'Monomate', 'Dimate', 'Trimate', 'Monofluid',
  'Foie', 'Barta', 'Zonde', 'Resta', 'Shifta', 'Deband',
  'Telepipe',
];

const MAGS: InventoryItem[] = [
  { name: 'Mag Lv12', type: 'mag', description: 'DEF 5 / POW 3 / DEX 2 / MIND 2. Feed items to evolve.', equipped: true },
];

const QUEST_INFO = {
  name: 'The Paru Pact',
  objective: 'Investigate the energy signatures deep in the Paru ruins.',
  client: 'Elio',
  area: 'Makara Ruins',
};

const SYSTEM_ITEMS = ['Save', 'Return to Title', 'Options'];

const TYPE_ORDER: Record<string, number> = { tool: 0, weapon: 1, armor: 2, shield: 3, unit: 4, tech: 5, material: 6 };
const SORTED_INVENTORY = [...INVENTORY].sort((a, b) => (TYPE_ORDER[a.type] ?? 9) - (TYPE_ORDER[b.type] ?? 9));

// ── Shared UI ──────────────────────────────────────────────────────────────────
function InnerPanel({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div style={{
      background: C.panelBg, border: `1.5px solid ${C.panelBorder}`,
      borderRadius: 4, boxShadow: `0 2px 6px ${C.panelShadow}`, ...style,
    }}>{children}</div>
  );
}

function SectionLabel({ text }: { text: string }) {
  return (
    <div style={{
      background: C.labelBg, padding: '6px 14px', borderRadius: 4,
      border: `1px solid ${C.backdropBorder}`,
    }}>
      <span style={{ color: C.textLight, fontSize: 15, fontFamily: 'monospace', fontWeight: 600, letterSpacing: 1 }}>{text}</span>
    </div>
  );
}

function CharacterStatus() {
  return (
    <InnerPanel style={{ padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{ width: 14, height: 14, borderRadius: 7, background: '#d03030', border: '1.5px solid #f06060', flexShrink: 0 }} />
        <span style={{ color: C.textDark, fontSize: 16, fontWeight: 700, fontFamily: 'monospace' }}>Flauros</span>
      </div>
      {[{ label: 'HP', pct: 85, c1: '#1a8830', c2: C.hpGreen }, { label: 'PP', pct: 100, c1: '#1858a8', c2: C.ppBlue }].map(bar => (
        <div key={bar.label} style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
          <span style={{ color: C.textMuted, fontSize: 10, fontFamily: 'monospace', width: 18 }}>{bar.label}</span>
          <div style={{ flex: 1, height: 10, background: 'rgba(0,0,0,0.15)', borderRadius: 2, border: '1px solid rgba(0,0,0,0.1)' }}>
            <div style={{ width: `${bar.pct}%`, height: '100%', background: `linear-gradient(to right, ${bar.c1}, ${bar.c2})`, borderRadius: 2 }} />
          </div>
        </div>
      ))}
    </InnerPanel>
  );
}

function ItemRow({ item, selected, onClick }: { item: InventoryItem; selected: boolean; onClick: () => void }) {
  const icon = TYPE_ICONS[item.type] || { color: '#888', label: '?' };
  return (
    <div onClick={onClick} style={{
      padding: '4px 8px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6,
      background: selected ? C.selectBg : 'transparent',
      color: selected ? C.selectText : C.textDark,
      fontSize: 13, fontFamily: 'monospace', fontWeight: selected ? 700 : 400,
    }}>
      <span style={{ width: 14, fontSize: 9, fontWeight: 700, color: selected ? '#fff' : '#e08820', opacity: item.equipped ? 1 : 0 }}>E</span>
      <span style={{ width: 16, height: 16, borderRadius: 3, background: selected ? 'rgba(255,255,255,0.3)' : icon.color, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, fontWeight: 700, color: '#fff', flexShrink: 0 }}>{icon.label}</span>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.name}</span>
    </div>
  );
}

function DescriptionBox({ text, style }: { text: string; style?: React.CSSProperties }) {
  return (
    <InnerPanel style={{ padding: '10px 14px', ...style }}>
      <span style={{ color: C.textDark, fontSize: 13, fontFamily: 'monospace' }}>{text}</span>
    </InnerPanel>
  );
}

function InfoPanel({ page, totalPages, onPrev, onNext }: { page: number; totalPages: number; onPrev: () => void; onNext: () => void }) {
  const pages = [
    { rows: [{ l: 'Lv', v: '14' }, { l: 'Type', v: 'HUmar' }, { l: 'Exp Pts', v: '12,480' }, { l: 'To Next Lv', v: '3,520' }, { l: 'Meseta', v: '8,250' }] },
    { rows: [{ l: 'ATP', v: '186' }, { l: 'ATA', v: '94' }, { l: 'Weapon', v: 'Saber +3' }, { l: 'Grind', v: '+3' }, { l: 'Special', v: 'Heat' }] },
    { rows: [{ l: 'DFP', v: '42' }, { l: 'EVP', v: '68' }, { l: 'Frame', v: 'Normal Frame' }, { l: 'Shield', v: 'Barrier' }, { l: 'Units', v: '0 / 4' }] },
    { rows: [{ l: 'MST', v: '30' }, { l: 'TP', v: '45 / 45' }, { l: 'Foie', v: 'Lv 3' }, { l: 'Resta', v: 'Lv 1' }, { l: 'Shifta', v: '--' }] },
  ];
  const info = pages[page];
  return (
    <InnerPanel style={{ padding: 0, height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 10, padding: '6px 0', borderBottom: '1px solid rgba(100,140,190,0.3)' }}>
        <span onClick={onPrev} style={{ color: C.arrowGreen, fontSize: 15, cursor: 'pointer', fontFamily: 'monospace', fontWeight: 700 }}>◀</span>
        <span style={{ color: C.textLight, fontSize: 13, fontFamily: 'monospace', background: C.pageBg, padding: '2px 12px', borderRadius: 3, border: '1px solid rgba(100,150,210,0.4)' }}>L {page + 1}/{totalPages} R</span>
        <span onClick={onNext} style={{ color: C.arrowGreen, fontSize: 15, cursor: 'pointer', fontFamily: 'monospace', fontWeight: 700 }}>▶</span>
      </div>
      <div style={{ padding: '8px 16px', flex: 1 }}>
        {info.rows.map(r => (
          <div key={r.l} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', fontFamily: 'monospace', fontSize: 16 }}>
            <span style={{ color: C.textMuted }}>{r.l}</span>
            <span style={{ color: C.textDark, fontWeight: 600 }}>{r.v}</span>
          </div>
        ))}
      </div>
    </InnerPanel>
  );
}

// ── Sub-views ──────────────────────────────────────────────────────────────────

function ItemsView({ idx, onSelect }: { idx: number; onSelect: (i: number) => void }) {
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="Items" />
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 300, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%', overflowY: 'auto' }}>
          {SORTED_INVENTORY.map((item, i) => <ItemRow key={`${item.name}-${i}`} item={item} selected={i === idx} onClick={() => onSelect(i)} />)}
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 310, bottom: 5, width: 200, height: 300 }}>
        <DescriptionBox text={SORTED_INVENTORY[idx]?.description ?? ''} style={{ height: '100%' }} />
      </div>
    </>
  );
}

function EquipView({ idx, onSelect }: { idx: number; onSelect: (i: number) => void }) {
  const sel = EQUIPMENT_SLOTS[idx];
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="Equip" />
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 300, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%', overflowY: 'auto' }}>
          {EQUIPMENT_SLOTS.map((eq, i) => {
            const icon = TYPE_ICONS[eq.type] || { color: '#888', label: '?' };
            const selected = i === idx;
            return (
              <div key={eq.slot} onClick={() => onSelect(i)} style={{
                padding: '6px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
                background: selected ? C.selectBg : 'transparent', color: selected ? C.selectText : C.textDark,
                fontSize: 13, fontFamily: 'monospace', fontWeight: selected ? 700 : 400,
              }}>
                <span style={{ width: 16, height: 16, borderRadius: 3, background: selected ? 'rgba(255,255,255,0.3)' : icon.color, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, fontWeight: 700, color: '#fff', flexShrink: 0 }}>{icon.label}</span>
                <span style={{ width: 60, color: selected ? 'rgba(255,255,255,0.7)' : C.textMuted, fontSize: 11 }}>{eq.slot}</span>
                <span>{eq.item}</span>
              </div>
            );
          })}
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 310, bottom: 5, width: 200, height: 300 }}>
        <DescriptionBox text={sel?.description ?? ''} style={{ height: '100%' }} />
      </div>
    </>
  );
}

function PaletteView({ pageIdx, slotIdx, picking, onPageChange, onSlotChange, onPick, onAssign, onBack }: {
  pageIdx: number; slotIdx: number; picking: boolean;
  onPageChange: (i: number) => void; onSlotChange: (i: number) => void;
  onPick: () => void; onAssign: (a: string) => void; onBack: () => void;
}) {
  const page = PALETTE_PAGES[pageIdx];
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="Palette" />
        {/* Page tabs */}
        <div style={{ display: 'flex', gap: 4 }}>
          {PALETTE_PAGES.map((_, i) => (
            <div key={i} onClick={() => onPageChange(i)} style={{
              flex: 1, textAlign: 'center', padding: '4px 0', borderRadius: 3, cursor: 'pointer',
              background: i === pageIdx ? C.selectBg : C.panelBg, color: i === pageIdx ? C.selectText : C.textDark,
              fontSize: 12, fontFamily: 'monospace', fontWeight: 700, border: `1px solid ${C.panelBorder}`,
            }}>P{i + 1}</div>
          ))}
        </div>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 300, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%', overflowY: 'auto' }}>
          {picking ? (
            <>
              <div style={{ padding: '6px 10px', fontSize: 11, fontFamily: 'monospace', color: C.textMuted }}>Assign to Slot {slotIdx + 1}:</div>
              {PALETTE_ACTIONS.map((action) => (
                <div key={action} onClick={() => onAssign(action)} style={{
                  padding: '5px 14px', cursor: 'pointer', fontSize: 13, fontFamily: 'monospace',
                  background: page[slotIdx] === action ? C.selectBg : 'transparent',
                  color: page[slotIdx] === action ? C.selectText : C.textDark,
                  fontWeight: page[slotIdx] === action ? 700 : 400,
                }}>{action}</div>
              ))}
            </>
          ) : (
            page.map((action, i) => (
              <div key={i} onClick={() => { onSlotChange(i); onPick(); }} style={{
                padding: '6px 14px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10,
                background: i === slotIdx ? C.selectBg : 'transparent', color: i === slotIdx ? C.selectText : C.textDark,
                fontSize: 14, fontFamily: 'monospace', fontWeight: i === slotIdx ? 700 : 400,
              }}>
                <span style={{ width: 24, height: 20, borderRadius: 4, background: 'rgba(40,60,80,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700, color: '#fff', flexShrink: 0 }}>{['X', 'A', 'B'][i]}</span>
                <span>{action}</span>
              </div>
            ))
          )}
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 310, bottom: 5, width: 200, height: 300 }}>
        <DescriptionBox text={picking ? 'Select an action to assign.' : `Slot ${slotIdx + 1}: ${page[slotIdx]}`} style={{ height: '100%' }} />
      </div>
    </>
  );
}

function MagsView({ idx, onSelect }: { idx: number; onSelect: (i: number) => void }) {
  const feedItems = SORTED_INVENTORY.filter(i => i.type === 'tool' || i.type === 'material');
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="Mags" />
        {/* Current mag */}
        <InnerPanel style={{ padding: '8px 12px' }}>
          <div style={{ fontFamily: 'monospace', fontSize: 14, fontWeight: 700, color: C.textDark, marginBottom: 4 }}>Mag Lv12</div>
          <div style={{ fontFamily: 'monospace', fontSize: 11, color: C.textMuted }}>DEF 5 / POW 3 / DEX 2 / MIND 2</div>
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 300, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%', overflowY: 'auto' }}>
          <div style={{ padding: '4px 10px', fontSize: 11, fontFamily: 'monospace', color: C.textMuted }}>Feed item:</div>
          {feedItems.map((item, i) => <ItemRow key={`${item.name}-${i}`} item={item} selected={i === idx} onClick={() => onSelect(i)} />)}
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 310, bottom: 5, width: 200, height: 300 }}>
        <DescriptionBox text={feedItems[idx]?.description ?? 'Select an item to feed.'} style={{ height: '100%' }} />
      </div>
    </>
  );
}

function QuestView() {
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="Quest" />
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 505, height: 300 }}>
        <InnerPanel style={{ padding: '16px 20px', height: '100%' }}>
          {[
            { label: 'Quest', value: QUEST_INFO.name },
            { label: 'Client', value: QUEST_INFO.client },
            { label: 'Area', value: QUEST_INFO.area },
          ].map(r => (
            <div key={r.label} style={{ display: 'flex', gap: 12, padding: '6px 0', fontFamily: 'monospace', fontSize: 15, borderBottom: '1px solid rgba(100,140,190,0.2)' }}>
              <span style={{ color: C.textMuted, width: 70 }}>{r.label}</span>
              <span style={{ color: C.textDark, fontWeight: 600 }}>{r.value}</span>
            </div>
          ))}
          <div style={{ marginTop: 12, fontFamily: 'monospace', fontSize: 13, color: C.textDark, lineHeight: 1.6 }}>
            {QUEST_INFO.objective}
          </div>
        </InnerPanel>
      </div>
    </>
  );
}

function SystemView({ idx, onSelect }: { idx: number; onSelect: (i: number) => void }) {
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <CharacterStatus />
        <SectionLabel text="System" />
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 300, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%' }}>
          {SYSTEM_ITEMS.map((item, i) => (
            <div key={item} onClick={() => onSelect(i)} style={{
              padding: '8px 16px', cursor: 'pointer', fontSize: 15, fontFamily: 'monospace',
              background: i === idx ? C.selectBg : 'transparent', color: i === idx ? C.selectText : C.textDark,
              fontWeight: i === idx ? 700 : 500,
            }}>{item}</div>
          ))}
        </InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: 310, bottom: 5, width: 200, height: 300 }}>
        <DescriptionBox text={['Save your progress.', 'Return to the title screen.', 'Adjust game settings.'][idx] ?? ''} style={{ height: '100%' }} />
      </div>
    </>
  );
}

// ── Main ────────────────────────────────────────────────────────────────────────
type MenuMode = 'main' | 'items' | 'equip' | 'palette' | 'mags' | 'quest' | 'system';

export default function StartMenu() {
  const [mode, setMode] = useState<MenuMode>('main');
  const [menuIdx, setMenuIdx] = useState(0);
  const [infoPage, setInfoPage] = useState(0);
  const [subIdx, setSubIdx] = useState(0);
  const [palettePageIdx, setPalettePageIdx] = useState(0);
  const [paletteSlotIdx, setPaletteSlotIdx] = useState(0);
  const [palettePicking, setPalettePicking] = useState(false);
  const [palettes, setPalettes] = useState(() => PALETTE_PAGES.map(p => [...p]));

  const openSub = (label: string) => {
    const m = label.toLowerCase() as MenuMode;
    if (['items', 'equip', 'palette', 'mags', 'quest', 'system'].includes(m)) {
      setMode(m);
      setSubIdx(0);
      setPalettePicking(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (mode === 'main') {
      switch (e.key) {
        case 'ArrowUp': setMenuIdx(p => (p - 1 + MENU_ITEMS.length) % MENU_ITEMS.length); break;
        case 'ArrowDown': setMenuIdx(p => (p + 1) % MENU_ITEMS.length); break;
        case 'ArrowLeft': setInfoPage(p => (p - 1 + 4) % 4); break;
        case 'ArrowRight': setInfoPage(p => (p + 1) % 4); break;
        case 'Enter': openSub(MENU_ITEMS[menuIdx]); break;
        default: return;
      }
    } else if (mode === 'palette' && palettePicking) {
      switch (e.key) {
        case 'ArrowUp': setSubIdx(p => (p - 1 + PALETTE_ACTIONS.length) % PALETTE_ACTIONS.length); break;
        case 'ArrowDown': setSubIdx(p => (p + 1) % PALETTE_ACTIONS.length); break;
        case 'Enter':
          setPalettes(prev => prev.map((pg, pi) => {
            if (pi !== palettePageIdx) return pg;
            const np = [...pg]; np[paletteSlotIdx] = PALETTE_ACTIONS[subIdx]; return np;
          }));
          setPalettePicking(false);
          break;
        case 'Escape': case 'Backspace': setPalettePicking(false); break;
        default: return;
      }
    } else {
      const listLen = mode === 'items' ? SORTED_INVENTORY.length
        : mode === 'equip' ? EQUIPMENT_SLOTS.length
        : mode === 'palette' ? palettes[palettePageIdx].length
        : mode === 'mags' ? SORTED_INVENTORY.filter(i => i.type === 'tool' || i.type === 'material').length
        : mode === 'system' ? SYSTEM_ITEMS.length : 0;
      switch (e.key) {
        case 'ArrowUp': if (listLen > 0) setSubIdx(p => (p - 1 + listLen) % listLen); break;
        case 'ArrowDown': if (listLen > 0) setSubIdx(p => (p + 1) % listLen); break;
        case 'ArrowLeft': if (mode === 'palette') setPalettePageIdx(p => (p - 1 + palettes.length) % palettes.length); break;
        case 'ArrowRight': if (mode === 'palette') setPalettePageIdx(p => (p + 1) % palettes.length); break;
        case 'Enter':
          if (mode === 'palette') { setPaletteSlotIdx(subIdx); setPalettePicking(true); setSubIdx(0); }
          break;
        case 'Escape': case 'Backspace': setMode('main'); break;
        default: return;
      }
    }
    e.preventDefault();
  };

  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%', background: '#0a0a1a' }}>
      <div tabIndex={0} onKeyDown={handleKeyDown} style={{
        width: VIEWPORT_W, height: VIEWPORT_H, position: 'relative', overflow: 'hidden', outline: 'none',
        background: 'linear-gradient(160deg, #1a2a3a 0%, #2a3a4a 30%, #1a2a3a 60%, #0a1a2a 100%)',
      }}>
        {/* Ground */}
        <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 360, background: 'linear-gradient(to bottom, rgba(40,50,60,0.3), rgba(60,70,50,0.5))' }} />

        {/* L-shaped backdrop */}
        <div style={{ position: 'absolute', zIndex: 1, top: 0, left: 0, width: LEFT_PANEL_W, height: VIEWPORT_H - BOTTOM_PANEL_H, background: C.backdropBg, borderRight: `1.5px solid ${C.backdropBorder}` }} />
        <div style={{ position: 'absolute', zIndex: 1, bottom: 0, left: LEFT_PANEL_W, right: 0, height: BOTTOM_PANEL_H, background: C.backdropBg, borderTop: `1.5px solid ${C.backdropBorder}` }} />
        <div style={{ position: 'absolute', zIndex: 1, bottom: 0, left: 0, width: LEFT_PANEL_W, height: BOTTOM_PANEL_H, background: C.backdropBg }} />

        {/* Content */}
        {mode === 'main' && (
          <>
            <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 10 }}>
              <CharacterStatus />
              <InnerPanel style={{ padding: '4px 0' }}>
                {MENU_ITEMS.map((item, i) => (
                  <div key={item} onClick={() => { setMenuIdx(i); openSub(item); }} style={{
                    padding: '7px 16px', cursor: 'pointer', fontSize: 17, fontFamily: 'monospace',
                    background: i === menuIdx ? C.selectBg : 'transparent', color: i === menuIdx ? C.selectText : C.textDark,
                    fontWeight: i === menuIdx ? 700 : 500, letterSpacing: 1,
                  }}>{item}</div>
                ))}
              </InnerPanel>
              <DescriptionBox text={MENU_DESCRIPTIONS[MENU_ITEMS[menuIdx]] ?? ''} />
            </div>
            <div style={{ position: 'absolute', zIndex: 2, bottom: 5, right: 30, top: VIEWPORT_H - BOTTOM_PANEL_H + 5, width: 440 }}>
              <InfoPanel page={infoPage} totalPages={4} onPrev={() => setInfoPage(p => (p - 1 + 4) % 4)} onNext={() => setInfoPage(p => (p + 1) % 4)} />
            </div>
          </>
        )}
        {mode === 'items' && <ItemsView idx={subIdx} onSelect={setSubIdx} />}
        {mode === 'equip' && <EquipView idx={subIdx} onSelect={setSubIdx} />}
        {mode === 'palette' && <PaletteView pageIdx={palettePageIdx} slotIdx={paletteSlotIdx} picking={palettePicking} onPageChange={setPalettePageIdx} onSlotChange={setPaletteSlotIdx} onPick={() => { setPaletteSlotIdx(subIdx); setPalettePicking(true); setSubIdx(0); }} onAssign={(a) => { setPalettes(prev => prev.map((pg, pi) => { if (pi !== palettePageIdx) return pg; const np = [...pg]; np[paletteSlotIdx] = a; return np; })); setPalettePicking(false); }} onBack={() => setPalettePicking(false)} />}
        {mode === 'mags' && <MagsView idx={subIdx} onSelect={setSubIdx} />}
        {mode === 'quest' && <QuestView />}
        {mode === 'system' && <SystemView idx={subIdx} onSelect={setSubIdx} />}

        {/* Hints */}
        <div style={{ position: 'absolute', zIndex: 2, bottom: 8, left: LEFT_PANEL_W + 16, fontSize: 11, fontFamily: 'monospace', color: 'rgba(180,200,230,0.5)', display: 'flex', gap: 16 }}>
          {mode === 'main' ? <><span>↑↓ Navigate</span><span>←→ Info Pages</span><span>Enter: Select</span></> : <><span>↑↓ Navigate</span><span>Esc: Back</span>{mode === 'palette' && <span>←→ Pages</span>}</>}
        </div>
      </div>
    </div>
  );
}
