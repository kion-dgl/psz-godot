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
  iconBg: '#e8eef4',
  iconFg: '#2a3a50',
};

// ── PSO-style icons (white square, dark symbol) ────────────────────────────────
function TypeIcon({ type, size = 18, selected = false }: { type: string; size?: number; selected?: boolean }) {
  const bg = selected ? 'rgba(255,255,255,0.4)' : C.iconBg;
  const fg = selected ? '#fff' : C.iconFg;
  const symbols: Record<string, string> = {
    weapon: '⚔', armor: '🛡', shield: '◈', unit: '◆', tool: '♥',
    tech: '★', material: '●', mag: '◎', consumable: '♥',
  };
  return (
    <span style={{
      width: size, height: size, borderRadius: 3, flexShrink: 0,
      background: bg, border: `1px solid ${selected ? 'rgba(255,255,255,0.3)' : 'rgba(0,0,0,0.15)'}`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.55, color: fg, lineHeight: 1,
    }}>{symbols[type] || '?'}</span>
  );
}

// ── Data ────────────────────────────────────────────────────────────────────────
interface InvItem {
  name: string;
  type: string;
  description: string;
  equipped?: boolean;
  count?: number;
  usable?: boolean;
  stats?: Record<string, string | number>;
}

interface TechItem {
  name: string;
  level: number;
  pp: number;
  description: string;
}

const MENU_ITEMS = ['Items', 'Equip', 'Techs', 'Palette', 'Mags', 'Quest', 'System'];
const MENU_DESC: Record<string, string> = {
  Items: 'Use items.', Equip: 'Equip weapons and armor.', Techs: 'View learned techniques.',
  Palette: 'Edit the action palette.', Mags: 'Feed and manage your Mag.',
  Quest: 'View current quest objectives.', System: 'System settings and options.',
};

const INVENTORY: InvItem[] = [
  { name: 'Monomate', type: 'tool', description: 'Restores a small amount of HP.', count: 8, usable: true },
  { name: 'Dimate', type: 'tool', description: 'Restores a moderate amount of HP.', count: 3, usable: true },
  { name: 'Monofluid', type: 'tool', description: 'Restores a small amount of PP.', count: 5, usable: true },
  { name: 'Antidote', type: 'tool', description: 'Cures poison status.', count: 2, usable: true },
  { name: 'Telepipe', type: 'tool', description: 'Warps to the city.', count: 1, usable: true },
  { name: 'Saber', type: 'weapon', description: 'A standard blade.\nATP +30, ATA +35' },
  { name: 'Saber +3', type: 'weapon', description: 'A reinforced blade.\nATP +45, ATA +38\nSpecial: Heat', equipped: true },
  { name: 'Handgun', type: 'weapon', description: 'Standard ranged weapon.\nATP +18, ATA +42' },
  { name: 'Normal Frame', type: 'armor', description: 'Basic body armor.\nDFP +10, EVP +12', equipped: true },
  { name: 'Barrier', type: 'shield', description: 'Basic shield.\nDFP +3, EVP +8', equipped: true },
  { name: 'HP Material', type: 'material', description: 'Permanently increases max HP by 2.', count: 1, usable: true },
  { name: 'Photon Drop', type: 'material', description: 'A rare crystal. Used for trading.', count: 3 },
  { name: 'Grinder', type: 'material', description: 'Used to strengthen weapons.', count: 5 },
];

const TECHNIQUES: TechItem[] = [
  { name: 'Foie', level: 3, pp: 8, description: 'Fires a ball of flame at the target.' },
  { name: 'Barta', level: 1, pp: 7, description: 'Launches a shard of ice forward.' },
  { name: 'Zonde', level: 2, pp: 6, description: 'Strikes the target with lightning.' },
  { name: 'Resta', level: 1, pp: 10, description: 'Restores HP to nearby allies.' },
  { name: 'Shifta', level: 1, pp: 15, description: 'Temporarily boosts attack power.' },
  { name: 'Deband', level: 1, pp: 15, description: 'Temporarily boosts defense.' },
];

const EQUIP_SLOTS = [
  { slot: 'Weapon', type: 'weapon' },
  { slot: 'Frame', type: 'armor' },
  { slot: 'Shield', type: 'shield' },
  { slot: 'Unit 1', type: 'unit' },
  { slot: 'Unit 2', type: 'unit' },
  { slot: 'Unit 3', type: 'unit' },
  { slot: 'Unit 4', type: 'unit' },
  { slot: 'Mag', type: 'mag' },
];

const MAGS: InvItem[] = [
  { name: 'Mag Lv12', type: 'mag', description: 'DEF 5 / POW 3 / DEX 2 / MIND 2', equipped: true },
  { name: 'Varuna Lv5', type: 'mag', description: 'DEF 3 / POW 1 / DEX 1 / MIND 0' },
];

const PSZ_ICON_BASE = import.meta.env.BASE_URL + 'assets/ui/psz-palette/';

interface PaletteAction {
  id: string;
  label: string;
  icon: string;
  category: 'combat' | 'recovery' | 'technique';
}

const PALETTE_ACTIONS: PaletteAction[] = [
  { id: 'attack', label: 'Attack', icon: 'attack.png', category: 'combat' },
  { id: 'strong_attack', label: 'Strong Atk', icon: 'strong_attack.png', category: 'combat' },
  { id: 'dodge', label: 'Dodge', icon: 'dodge.png', category: 'combat' },
  { id: 'monomate', label: 'Monomate', icon: 'monomate.png', category: 'recovery' },
  { id: 'dimate', label: 'Dimate', icon: 'dimate.png', category: 'recovery' },
  { id: 'trimate', label: 'Trimate', icon: 'trimate.png', category: 'recovery' },
  { id: 'monofluid', label: 'Monofluid', icon: 'monofluid.png', category: 'recovery' },
  { id: 'difluid', label: 'Difluid', icon: 'difluid.png', category: 'recovery' },
  { id: 'trifluid', label: 'Trifluid', icon: 'trifluid.png', category: 'recovery' },
  { id: 'sol_atomizer', label: 'Sol Atom.', icon: 'sol_atomizer.png', category: 'recovery' },
  { id: 'star_atomizer', label: 'Star Atom.', icon: 'star_atomizer.png', category: 'recovery' },
  { id: 'moon_atomizer', label: 'Moon Atom.', icon: 'moon_atomizer.png', category: 'recovery' },
  { id: 'telepipe', label: 'Telepipe', icon: 'telepipe.png', category: 'recovery' },
  { id: 'foie', label: 'Foie', icon: 'foie.png', category: 'technique' },
  { id: 'barta', label: 'Barta', icon: 'barta.png', category: 'technique' },
  { id: 'zonde', label: 'Zonde', icon: 'zonde.png', category: 'technique' },
  { id: 'grants', label: 'Grants', icon: 'grants.png', category: 'technique' },
  { id: 'megid', label: 'Megid', icon: 'megid.png', category: 'technique' },
  { id: 'resta', label: 'Resta', icon: 'resta.png', category: 'technique' },
  { id: 'anti', label: 'Anti', icon: 'anti.png', category: 'technique' },
  { id: 'shifta', label: 'Shifta', icon: 'shifta.png', category: 'technique' },
  { id: 'deband', label: 'Deband', icon: 'deband.png', category: 'technique' },
  { id: 'jellen', label: 'Jellen', icon: 'jellen.png', category: 'technique' },
  { id: 'zalure', label: 'Zalure', icon: 'zalure.png', category: 'technique' },
];

function PszIcon({ actionId, size = 20, selected = false, noBg = false }: { actionId: string; size?: number; selected?: boolean; noBg?: boolean }) {
  const action = PALETTE_ACTIONS.find((a) => a.id === actionId);
  if (!action) return <div style={{ width: size, height: size }} />;
  return (
    <div style={{
      width: size, height: size, borderRadius: 4, flexShrink: 0,
      background: noBg ? 'transparent' : selected ? 'rgba(40,80,40,0.9)' : 'rgba(5,5,15,0.9)',
      border: `1px solid ${selected ? 'rgba(80,180,80,0.5)' : 'rgba(60,60,80,0.4)'}`,
      position: 'relative',
    }}>
      <img src={PSZ_ICON_BASE + action.icon} alt={action.label}
        style={{
          position: 'absolute',
          width: Math.round(size * 1.4), height: Math.round(size * 1.4),
          imageRendering: 'pixelated',
        }} />
    </div>
  );
}

const QUEST_INFO = { name: 'The Paru Pact', objective: 'Investigate the energy signatures deep in the Paru ruins.', client: 'Elio', area: 'Makara Ruins' };
const SYSTEM_ITEMS = [
  { label: 'Save', desc: 'Save your progress.' },
  { label: 'Return to Title', desc: 'Return to the title screen.' },
  { label: 'Options', desc: 'Adjust game settings.' },
];

const TYPE_ORDER: Record<string, number> = { tool: 0, weapon: 1, armor: 2, shield: 3, unit: 4, material: 5 };
const SORTED_INV = [...INVENTORY].sort((a, b) => (TYPE_ORDER[a.type] ?? 9) - (TYPE_ORDER[b.type] ?? 9));
const FEED_ITEMS = SORTED_INV.filter(i => (i.type === 'tool' || i.type === 'material') && (i.count ?? 0) > 0);

// ── Shared UI ──────────────────────────────────────────────────────────────────
function InnerPanel({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return <div style={{ background: C.panelBg, border: `1.5px solid ${C.panelBorder}`, borderRadius: 4, boxShadow: `0 2px 6px ${C.panelShadow}`, ...style }}>{children}</div>;
}
function SectionLabel({ text }: { text: string }) {
  return <div style={{ background: C.labelBg, padding: '6px 14px', borderRadius: 4, border: `1px solid ${C.backdropBorder}` }}><span style={{ color: C.textLight, fontSize: 15, fontFamily: 'monospace', fontWeight: 600, letterSpacing: 1 }}>{text}</span></div>;
}
function CharacterStatus() {
  return (
    <InnerPanel style={{ padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{ width: 14, height: 14, borderRadius: 7, background: '#d03030', border: '1.5px solid #f06060', flexShrink: 0 }} />
        <span style={{ color: C.textDark, fontSize: 16, fontWeight: 700, fontFamily: 'monospace' }}>Flauros</span>
      </div>
      {[{ l: 'HP', p: 85, c1: '#1a8830', c2: C.hpGreen }, { l: 'PP', p: 100, c1: '#1858a8', c2: C.ppBlue }].map(b => (
        <div key={b.l} style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
          <span style={{ color: C.textMuted, fontSize: 10, fontFamily: 'monospace', width: 18 }}>{b.l}</span>
          <div style={{ flex: 1, height: 10, background: 'rgba(0,0,0,0.15)', borderRadius: 2, border: '1px solid rgba(0,0,0,0.1)' }}>
            <div style={{ width: `${b.p}%`, height: '100%', background: `linear-gradient(to right, ${b.c1}, ${b.c2})`, borderRadius: 2 }} />
          </div>
        </div>
      ))}
    </InnerPanel>
  );
}
function DescBox({ text, style }: { text: string; style?: React.CSSProperties }) {
  return <InnerPanel style={{ padding: '10px 14px', ...style }}><span style={{ color: C.textDark, fontSize: 13, fontFamily: 'monospace', whiteSpace: 'pre-line' }}>{text}</span></InnerPanel>;
}

// Left column shared across sub-views
function LeftCol({ label, children }: { label: string; children?: React.ReactNode }) {
  return (
    <div style={{ position: 'absolute', zIndex: 2, top: PANEL_PAD, left: PANEL_PAD, width: LEFT_PANEL_W - PANEL_PAD * 2, display: 'flex', flexDirection: 'column', gap: 8 }}>
      <CharacterStatus />
      <SectionLabel text={label} />
      {children}
    </div>
  );
}

// Bottom list + description layout
function BottomPanels({ list, desc, listWidth = 300, descWidth = 200 }: { list: React.ReactNode; desc: string; listWidth?: number; descWidth?: number }) {
  return (
    <>
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: listWidth, height: 300 }}>
        <InnerPanel style={{ padding: '4px 0', height: '100%', overflowY: 'auto' }}>{list}</InnerPanel>
      </div>
      <div style={{ position: 'absolute', zIndex: 2, left: listWidth + 10, bottom: 5, width: descWidth, height: 300 }}>
        <DescBox text={desc} style={{ height: '100%' }} />
      </div>
    </>
  );
}

function ItemRow({ item, selected, onClick, showCount }: { item: InvItem; selected: boolean; onClick: () => void; showCount?: boolean }) {
  return (
    <div onClick={onClick} style={{
      padding: '4px 8px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6,
      background: selected ? C.selectBg : 'transparent', color: selected ? C.selectText : C.textDark,
      fontSize: 13, fontFamily: 'monospace', fontWeight: selected ? 700 : 400,
    }}>
      <span style={{ width: 14, fontSize: 9, fontWeight: 700, color: selected ? '#fff' : '#e08820', opacity: item.equipped ? 1 : 0 }}>E</span>
      <TypeIcon type={item.type} selected={selected} />
      <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.name}</span>
      {showCount && item.count != null && <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.7)' : C.textMuted }}>x{item.count}</span>}
    </div>
  );
}

// ── Sub-views ──────────────────────────────────────────────────────────────────

function ItemsView({ idx, setIdx }: { idx: number; setIdx: (i: number) => void }) {
  const item = SORTED_INV[idx];
  const desc = item ? `${item.description}${item.usable ? '\n\n[Enter] Use' : ''}` : '';
  return (
    <>
      <LeftCol label="Items" />
      <BottomPanels
        desc={desc}
        list={SORTED_INV.map((it, i) => <ItemRow key={`${it.name}-${i}`} item={it} selected={i === idx} onClick={() => setIdx(i)} showCount />)}
      />
    </>
  );
}

function EquipView({ slotIdx, setSlotIdx, picking, itemIdx, setItemIdx, onPick, onEquip, onBack }: {
  slotIdx: number; setSlotIdx: (i: number) => void;
  picking: boolean; itemIdx: number; setItemIdx: (i: number) => void;
  onPick: () => void; onEquip: () => void; onBack: () => void;
}) {
  const slot = EQUIP_SLOTS[slotIdx];
  const equipped = INVENTORY.find(i => i.equipped && i.type === slot.type);
  const candidates = INVENTORY.filter(i => i.type === slot.type);

  if (picking) {
    const sel = candidates[itemIdx];
    return (
      <>
        <LeftCol label={`Equip: ${slot.slot}`} />
        <BottomPanels
          listWidth={320}
          descWidth={190}
          desc={sel?.description ?? 'Select equipment.'}
          list={<>
            <div style={{ padding: '4px 10px', fontSize: 11, fontFamily: 'monospace', color: C.textMuted }}>Choose {slot.slot}:</div>
            {candidates.map((it, i) => <ItemRow key={it.name} item={it} selected={i === itemIdx} onClick={() => { setItemIdx(i); }} />)}
            <div onClick={onBack} style={{ padding: '5px 14px', cursor: 'pointer', fontSize: 13, fontFamily: 'monospace', color: C.textMuted, marginTop: 4 }}>← Back</div>
          </>}
        />
      </>
    );
  }

  return (
    <>
      <LeftCol label="Equip" />
      <BottomPanels
        listWidth={320}
        descWidth={190}
        desc={equipped?.description ?? 'Nothing equipped.'}
        list={EQUIP_SLOTS.map((eq, i) => {
          const eqItem = INVENTORY.find(it => it.equipped && it.type === eq.type);
          const sel = i === slotIdx;
          return (
            <div key={eq.slot} onClick={() => { setSlotIdx(i); onPick(); }} style={{
              padding: '5px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
              background: sel ? C.selectBg : 'transparent', color: sel ? C.selectText : C.textDark,
              fontSize: 13, fontFamily: 'monospace', fontWeight: sel ? 700 : 400,
            }}>
              <TypeIcon type={eq.type} selected={sel} />
              <span style={{ width: 55, color: sel ? 'rgba(255,255,255,0.7)' : C.textMuted, fontSize: 11 }}>{eq.slot}</span>
              <span>{eqItem?.name ?? '--'}</span>
            </div>
          );
        })}
      />
    </>
  );
}

function TechsView({ idx, setIdx }: { idx: number; setIdx: (i: number) => void }) {
  const tech = TECHNIQUES[idx];
  return (
    <>
      <LeftCol label="Techs" />
      <BottomPanels
        desc={tech ? `${tech.description}\n\nLevel: ${tech.level}  PP: ${tech.pp}` : ''}
        list={TECHNIQUES.map((t, i) => {
          const sel = i === idx;
          return (
            <div key={t.name} onClick={() => setIdx(i)} style={{
              padding: '5px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
              background: sel ? C.selectBg : 'transparent', color: sel ? C.selectText : C.textDark,
              fontSize: 13, fontFamily: 'monospace', fontWeight: sel ? 700 : 400,
            }}>
              <TypeIcon type="tech" selected={sel} />
              <span style={{ flex: 1 }}>{t.name}</span>
              <span style={{ fontSize: 11, color: sel ? 'rgba(255,255,255,0.7)' : C.textMuted }}>Lv{t.level}</span>
              <span style={{ fontSize: 11, color: sel ? 'rgba(255,255,255,0.7)' : C.textMuted, width: 35, textAlign: 'right' }}>{t.pp}PP</span>
            </div>
          );
        })}
      />
    </>
  );
}

const PICKER_ROWS: { label?: string; ids: string[] }[] = [
  { label: 'Combat', ids: ['attack', 'strong_attack', 'dodge'] },
  { label: 'Recovery', ids: ['monomate', 'dimate', 'trimate'] },
  { ids: ['monofluid', 'difluid', 'trifluid'] },
  { ids: ['sol_atomizer', 'star_atomizer', 'moon_atomizer'] },
  { ids: ['telepipe'] },
  { label: 'Technique', ids: ['foie', 'barta', 'zonde'] },
  { ids: ['grants', 'megid'] },
  { ids: ['resta', 'anti'] },
  { ids: ['shifta', 'deband'] },
  { ids: ['jellen', 'zalure'] },
];

function PaletteView({ pages, pageIdx, setPageIdx, slotIdx, setSlotIdx, picking, setPicking, onAssign, subIdx }: {
  pages: string[][]; pageIdx: number; setPageIdx: (i: number) => void;
  slotIdx: number; setSlotIdx: (i: number) => void;
  picking: boolean; setPicking: (b: boolean) => void;
  onAssign: (action: string) => void;
  subIdx: number;
}) {
  const page = pages[pageIdx];

  return (
    <>
      <LeftCol label="Palette">
        <div style={{ display: 'flex', gap: 4 }}>
          {pages.map((_, i) => (
            <div key={i} onClick={() => setPageIdx(i)} style={{
              flex: 1, textAlign: 'center', padding: '4px 0', borderRadius: 3, cursor: 'pointer',
              background: i === pageIdx ? C.selectBg : C.panelBg, color: i === pageIdx ? C.selectText : C.textDark,
              fontSize: 12, fontFamily: 'monospace', fontWeight: 700, border: `1px solid ${C.panelBorder}`,
            }}>P{i + 1}</div>
          ))}
        </div>
        {/* HUD preview */}
        <InnerPanel style={{ padding: 8 }}>
          <div style={{ position: 'relative', width: 192, margin: '0 auto' }}>
            <img
              src={PSZ_ICON_BASE + (pageIdx === 0 ? 'palette_bg.png' : 'palette_bg_r.png')}
              alt="palette"
              style={{ width: 192, imageRendering: 'pixelated', display: 'block' }}
            />
            {[0, 1, 2].map((i) => {
              const centers = [
                { x: 39, y: 40 },
                { x: 87, y: 62 },
                { x: 135, y: 40 },
              ];
              const c = centers[i];
              const isSel = i === slotIdx;
              return (
                <div key={i} onClick={() => { setSlotIdx(i); setPicking(true); }} style={{
                  position: 'absolute', left: c.x - 17, top: c.y - 17,
                  width: 34, height: 34, cursor: 'pointer',
                  borderRadius: 4,
                  boxShadow: isSel ? '0 0 0 2px #4dcc4d' : 'none',
                }}>
                  <PszIcon actionId={page[i]} size={34} selected={isSel} noBg />
                </div>
              );
            })}
          </div>
        </InnerPanel>
      </LeftCol>

      {/* Action picker — only visible when a slot is selected for reassignment */}
      {picking && (
        <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 510, height: 300 }}>
          <InnerPanel style={{ padding: '8px 12px', height: '100%', overflowY: 'auto' }}>
            {PICKER_ROWS.map((row, ri) => (
              <div key={ri}>
                {row.label && (
                  <div style={{
                    fontSize: 12, color: C.textLight, padding: '6px 2px 4px',
                    fontFamily: 'monospace', fontWeight: 600,
                    borderBottom: `1px solid ${C.panelBorder}`,
                    marginBottom: 4, marginTop: ri > 0 ? 4 : 0,
                  }}>{row.label}</div>
                )}
                <div style={{ display: 'flex', gap: 4, marginBottom: 2 }}>
                  {row.ids.map((id) => {
                    const action = PALETTE_ACTIONS.find((a) => a.id === id);
                    if (!action) return null;
                    const isCurrent = id === page[slotIdx];
                    const isKbSelected = PALETTE_ACTIONS[subIdx]?.id === id;
                    return (
                      <div
                        key={id}
                        onClick={() => onAssign(id)}
                        style={{
                          display: 'flex', alignItems: 'center', gap: 8,
                          padding: '5px 8px', borderRadius: 4, cursor: 'pointer',
                          width: 160,
                          background: isKbSelected ? C.selectBg : isCurrent ? 'rgba(224,136,32,0.15)' : 'transparent',
                          color: isKbSelected ? C.selectText : isCurrent ? C.textLight : C.textDark,
                          fontWeight: isKbSelected || isCurrent ? 700 : 400,
                          fontSize: 13, fontFamily: 'monospace',
                          border: isKbSelected ? '1px solid rgba(224,136,32,0.5)' : isCurrent ? '1px solid rgba(224,136,32,0.3)' : '1px solid transparent',
                        }}
                      >
                        <PszIcon actionId={id} size={26} selected={isKbSelected || isCurrent} />
                        <span>{action.label}</span>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </InnerPanel>
        </div>
      )}
    </>
  );
}

function MagsView({ magIdx, setMagIdx, feedIdx, setFeedIdx, feeding }: {
  magIdx: number; setMagIdx: (i: number) => void;
  feedIdx: number; setFeedIdx: (i: number) => void;
  feeding: boolean;
}) {
  if (feeding) {
    const item = FEED_ITEMS[feedIdx];
    return (
      <>
        <LeftCol label="Feed Mag">
          <InnerPanel style={{ padding: '8px 12px' }}>
            <div style={{ fontFamily: 'monospace', fontSize: 14, fontWeight: 700, color: C.textDark }}>{MAGS[magIdx]?.name}</div>
            <div style={{ fontFamily: 'monospace', fontSize: 11, color: C.textMuted, marginTop: 2 }}>{MAGS[magIdx]?.description}</div>
          </InnerPanel>
        </LeftCol>
        <BottomPanels
          desc={item ? `${item.description}\n\nx${item.count}` : 'Select item to feed.'}
          list={FEED_ITEMS.map((it, i) => <ItemRow key={`${it.name}-${i}`} item={it} selected={i === feedIdx} onClick={() => setFeedIdx(i)} showCount />)}
        />
      </>
    );
  }
  return (
    <>
      <LeftCol label="Mags" />
      <BottomPanels
        desc={MAGS[magIdx]?.description ?? ''}
        list={MAGS.map((m, i) => <ItemRow key={m.name} item={m} selected={i === magIdx} onClick={() => setMagIdx(i)} />)}
      />
    </>
  );
}

function QuestView() {
  return (
    <>
      <LeftCol label="Quest" />
      <div style={{ position: 'absolute', zIndex: 2, left: 5, bottom: 5, width: 505, height: 300 }}>
        <InnerPanel style={{ padding: '16px 20px', height: '100%' }}>
          {[{ l: 'Quest', v: QUEST_INFO.name }, { l: 'Client', v: QUEST_INFO.client }, { l: 'Area', v: QUEST_INFO.area }].map(r => (
            <div key={r.l} style={{ display: 'flex', gap: 12, padding: '6px 0', fontFamily: 'monospace', fontSize: 15, borderBottom: '1px solid rgba(100,140,190,0.2)' }}>
              <span style={{ color: C.textMuted, width: 70 }}>{r.l}</span>
              <span style={{ color: C.textDark, fontWeight: 600 }}>{r.v}</span>
            </div>
          ))}
          <div style={{ marginTop: 12, fontFamily: 'monospace', fontSize: 13, color: C.textDark, lineHeight: 1.6 }}>{QUEST_INFO.objective}</div>
        </InnerPanel>
      </div>
    </>
  );
}

function SystemView({ idx, setIdx }: { idx: number; setIdx: (i: number) => void }) {
  return (
    <>
      <LeftCol label="System" />
      <BottomPanels
        desc={SYSTEM_ITEMS[idx]?.desc ?? ''}
        list={SYSTEM_ITEMS.map((item, i) => (
          <div key={item.label} onClick={() => setIdx(i)} style={{
            padding: '8px 16px', cursor: 'pointer', fontSize: 15, fontFamily: 'monospace',
            background: i === idx ? C.selectBg : 'transparent', color: i === idx ? C.selectText : C.textDark,
            fontWeight: i === idx ? 700 : 500,
          }}>{item.label}</div>
        ))}
      />
    </>
  );
}

function InfoPanel({ page, onPrev, onNext }: { page: number; onPrev: () => void; onNext: () => void }) {
  const pages = [
    [{ l: 'Lv', v: '14' }, { l: 'Type', v: 'HUmar' }, { l: 'Exp Pts', v: '12,480' }, { l: 'To Next Lv', v: '3,520' }, { l: 'Meseta', v: '8,250' }],
    [{ l: 'ATP', v: '186' }, { l: 'ATA', v: '94' }, { l: 'Weapon', v: 'Saber +3' }, { l: 'Grind', v: '+3' }, { l: 'Special', v: 'Heat' }],
    [{ l: 'DFP', v: '42' }, { l: 'EVP', v: '68' }, { l: 'Frame', v: 'Normal Frame' }, { l: 'Shield', v: 'Barrier' }, { l: 'Units', v: '0 / 4' }],
    [{ l: 'MST', v: '30' }, { l: 'TP', v: '45 / 45' }, { l: 'Foie', v: 'Lv 3' }, { l: 'Resta', v: 'Lv 1' }, { l: 'Shifta', v: '--' }],
  ];
  return (
    <InnerPanel style={{ padding: 0, height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 10, padding: '6px 0', borderBottom: '1px solid rgba(100,140,190,0.3)' }}>
        <span onClick={onPrev} style={{ color: C.arrowGreen, fontSize: 15, cursor: 'pointer', fontFamily: 'monospace', fontWeight: 700 }}>◀</span>
        <span style={{ color: C.textLight, fontSize: 13, fontFamily: 'monospace', background: C.pageBg, padding: '2px 12px', borderRadius: 3, border: '1px solid rgba(100,150,210,0.4)' }}>L {page + 1}/4 R</span>
        <span onClick={onNext} style={{ color: C.arrowGreen, fontSize: 15, cursor: 'pointer', fontFamily: 'monospace', fontWeight: 700 }}>▶</span>
      </div>
      <div style={{ padding: '8px 16px', flex: 1 }}>
        {pages[page].map(r => (
          <div key={r.l} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', fontFamily: 'monospace', fontSize: 16 }}>
            <span style={{ color: C.textMuted }}>{r.l}</span><span style={{ color: C.textDark, fontWeight: 600 }}>{r.v}</span>
          </div>
        ))}
      </div>
    </InnerPanel>
  );
}

// ── Main ────────────────────────────────────────────────────────────────────────
type Mode = 'main' | 'items' | 'equip' | 'techs' | 'palette' | 'mags' | 'quest' | 'system';

export default function StartMenu() {
  const [mode, setMode] = useState<Mode>('main');
  const [menuIdx, setMenuIdx] = useState(0);
  const [infoPage, setInfoPage] = useState(0);
  const [subIdx, setSubIdx] = useState(0);

  // Equip state
  const [equipSlotIdx, setEquipSlotIdx] = useState(0);
  const [equipPicking, setEquipPicking] = useState(false);
  const [equipItemIdx, setEquipItemIdx] = useState(0);

  // Palette state
  const [palettes, setPalettes] = useState(() => [['attack', 'strong_attack', 'monomate'], ['attack', 'foie', 'dimate']]);
  const [palPageIdx, setPalPageIdx] = useState(0);
  const [palSlotIdx, setPalSlotIdx] = useState(0);
  const [palPicking, setPalPicking] = useState(false);

  // Mags state
  const [magIdx, setMagIdx] = useState(0);
  const [magFeeding, setMagFeeding] = useState(false);
  const [magFeedIdx, setMagFeedIdx] = useState(0);

  const openSub = (label: string) => {
    const m = label.toLowerCase() as Mode;
    if (MENU_ITEMS.map(s => s.toLowerCase()).includes(m)) {
      setMode(m); setSubIdx(0); setEquipPicking(false); setPalPicking(false); setMagFeeding(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    const k = e.key;
    if (mode === 'main') {
      if (k === 'ArrowUp') setMenuIdx(p => (p - 1 + MENU_ITEMS.length) % MENU_ITEMS.length);
      else if (k === 'ArrowDown') setMenuIdx(p => (p + 1) % MENU_ITEMS.length);
      else if (k === 'ArrowLeft') setInfoPage(p => (p - 1 + 4) % 4);
      else if (k === 'ArrowRight') setInfoPage(p => (p + 1) % 4);
      else if (k === 'Enter') openSub(MENU_ITEMS[menuIdx]);
      else return;
    } else if (k === 'Escape' || k === 'Backspace') {
      if (mode === 'equip' && equipPicking) { setEquipPicking(false); }
      else if (mode === 'palette' && palPicking) { setPalPicking(false); }
      else if (mode === 'mags' && magFeeding) { setMagFeeding(false); }
      else { setMode('main'); }
    } else if (mode === 'equip') {
      if (equipPicking) {
        const cands = INVENTORY.filter(i => i.type === EQUIP_SLOTS[equipSlotIdx].type);
        if (k === 'ArrowUp') setEquipItemIdx(p => (p - 1 + cands.length) % cands.length);
        else if (k === 'ArrowDown') setEquipItemIdx(p => (p + 1) % cands.length);
        else return;
      } else {
        if (k === 'ArrowUp') setEquipSlotIdx(p => (p - 1 + EQUIP_SLOTS.length) % EQUIP_SLOTS.length);
        else if (k === 'ArrowDown') setEquipSlotIdx(p => (p + 1) % EQUIP_SLOTS.length);
        else if (k === 'Enter') { setEquipPicking(true); setEquipItemIdx(0); }
        else return;
      }
    } else if (mode === 'palette') {
      if (palPicking) {
        if (k === 'ArrowUp') setSubIdx(p => (p - 1 + PALETTE_ACTIONS.length) % PALETTE_ACTIONS.length);
        else if (k === 'ArrowDown') setSubIdx(p => (p + 1) % PALETTE_ACTIONS.length);
        else if (k === 'Enter') {
          setPalettes(prev => prev.map((pg, pi) => { if (pi !== palPageIdx) return pg; const np = [...pg]; np[palSlotIdx] = PALETTE_ACTIONS[subIdx].id; return np; }));
          setPalPicking(false);
        } else return;
      } else {
        if (k === 'ArrowUp') setPalSlotIdx(p => (p - 1 + 3) % 3);
        else if (k === 'ArrowDown') setPalSlotIdx(p => (p + 1) % 3);
        else if (k === 'ArrowLeft') setPalPageIdx(p => (p - 1 + palettes.length) % palettes.length);
        else if (k === 'ArrowRight') setPalPageIdx(p => (p + 1) % palettes.length);
        else if (k === 'Enter') { setPalPicking(true); setSubIdx(0); }
        else return;
      }
    } else if (mode === 'mags') {
      if (magFeeding) {
        if (k === 'ArrowUp') setMagFeedIdx(p => (p - 1 + FEED_ITEMS.length) % FEED_ITEMS.length);
        else if (k === 'ArrowDown') setMagFeedIdx(p => (p + 1) % FEED_ITEMS.length);
        else return;
      } else {
        if (k === 'ArrowUp') setMagIdx(p => (p - 1 + MAGS.length) % MAGS.length);
        else if (k === 'ArrowDown') setMagIdx(p => (p + 1) % MAGS.length);
        else if (k === 'Enter') { setMagFeeding(true); setMagFeedIdx(0); }
        else return;
      }
    } else {
      const lens: Record<string, number> = { items: SORTED_INV.length, techs: TECHNIQUES.length, system: SYSTEM_ITEMS.length };
      const len = lens[mode] ?? 0;
      if (k === 'ArrowUp' && len > 0) setSubIdx(p => (p - 1 + len) % len);
      else if (k === 'ArrowDown' && len > 0) setSubIdx(p => (p + 1) % len);
      else return;
    }
    e.preventDefault();
  };

  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%', background: '#0a0a1a' }}>
      <div tabIndex={0} onKeyDown={handleKeyDown} style={{
        width: VIEWPORT_W, height: VIEWPORT_H, position: 'relative', overflow: 'hidden', outline: 'none',
        background: 'linear-gradient(160deg, #1a2a3a 0%, #2a3a4a 30%, #1a2a3a 60%, #0a1a2a 100%)',
      }}>
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
              <DescBox text={MENU_DESC[MENU_ITEMS[menuIdx]] ?? ''} />
            </div>
            <div style={{ position: 'absolute', zIndex: 2, bottom: 5, right: 30, top: VIEWPORT_H - BOTTOM_PANEL_H + 5, width: 440 }}>
              <InfoPanel page={infoPage} onPrev={() => setInfoPage(p => (p - 1 + 4) % 4)} onNext={() => setInfoPage(p => (p + 1) % 4)} />
            </div>
          </>
        )}
        {mode === 'items' && <ItemsView idx={subIdx} setIdx={setSubIdx} />}
        {mode === 'equip' && <EquipView slotIdx={equipSlotIdx} setSlotIdx={setEquipSlotIdx} picking={equipPicking} itemIdx={equipItemIdx} setItemIdx={setEquipItemIdx} onPick={() => { setEquipPicking(true); setEquipItemIdx(0); }} onEquip={() => setEquipPicking(false)} onBack={() => setEquipPicking(false)} />}
        {mode === 'techs' && <TechsView idx={subIdx} setIdx={setSubIdx} />}
        {mode === 'palette' && <PaletteView pages={palettes} pageIdx={palPageIdx} setPageIdx={setPalPageIdx} slotIdx={palSlotIdx} setSlotIdx={setPalSlotIdx} picking={palPicking} setPicking={setPalPicking} subIdx={subIdx} onAssign={(a) => { setPalettes(prev => prev.map((pg, pi) => { if (pi !== palPageIdx) return pg; const np = [...pg]; np[palSlotIdx] = a; return np; })); setPalPicking(false); }} />}
        {mode === 'mags' && <MagsView magIdx={magIdx} setMagIdx={setMagIdx} feedIdx={magFeedIdx} setFeedIdx={setMagFeedIdx} feeding={magFeeding} />}
        {mode === 'quest' && <QuestView />}
        {mode === 'system' && <SystemView idx={subIdx} setIdx={setSubIdx} />}

        <div style={{ position: 'absolute', zIndex: 2, bottom: 8, left: LEFT_PANEL_W + 16, fontSize: 11, fontFamily: 'monospace', color: 'rgba(180,200,230,0.5)', display: 'flex', gap: 16 }}>
          {mode === 'main' ? <><span>↑↓ Navigate</span><span>←→ Info Pages</span><span>Enter: Select</span></> : <><span>↑↓ Navigate</span><span>Esc: Back</span>{mode === 'palette' && !palPicking && <span>←→ Pages</span>}{mode === 'mags' && !magFeeding && <span>Enter: Feed</span>}</>}
        </div>
      </div>
    </div>
  );
}
