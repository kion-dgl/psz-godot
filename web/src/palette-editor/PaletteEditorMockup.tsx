import { useState } from 'react';

const ICON_BASE = import.meta.env.BASE_URL + 'assets/ui/psz-palette/';

type Category = 'combat' | 'recovery' | 'technique';

interface Action {
  id: string;
  label: string;
  short: string;
  category: Category;
  icon: string;
  chargedIcon?: string;
}

const ALL_ACTIONS: Action[] = [
  { id: 'attack', label: 'Attack', short: 'Atk', category: 'combat', icon: 'attack.png', chargedIcon: 'charged_photon_art.png' },
  { id: 'strong_attack', label: 'Strong Attack', short: 'S.Atk', category: 'combat', icon: 'strong_attack.png', chargedIcon: 'charged_photon_art.png' },
  { id: 'dodge', label: 'Dodge', short: 'Dodge', category: 'combat', icon: 'dodge.png' },
  { id: 'monomate', label: 'Monomate', short: 'Mono', category: 'recovery', icon: 'monomate.png' },
  { id: 'dimate', label: 'Dimate', short: 'Di', category: 'recovery', icon: 'dimate.png' },
  { id: 'trimate', label: 'Trimate', short: 'Tri', category: 'recovery', icon: 'trimate.png' },
  { id: 'monofluid', label: 'Monofluid', short: 'M.Flu', category: 'recovery', icon: 'monofluid.png' },
  { id: 'difluid', label: 'Difluid', short: 'D.Flu', category: 'recovery', icon: 'difluid.png' },
  { id: 'trifluid', label: 'Trifluid', short: 'T.Flu', category: 'recovery', icon: 'trifluid.png' },
  { id: 'sol_atomizer', label: 'Sol Atomizer', short: 'Sol', category: 'recovery', icon: 'sol_atomizer.png' },
  { id: 'star_atomizer', label: 'Star Atomizer', short: 'Star', category: 'recovery', icon: 'star_atomizer.png' },
  { id: 'moon_atomizer', label: 'Moon Atomizer', short: 'Moon', category: 'recovery', icon: 'moon_atomizer.png' },
  { id: 'telepipe', label: 'Telepipe', short: 'Pipe', category: 'recovery', icon: 'telepipe.png' },
  { id: 'foie', label: 'Foie', short: 'Foie', category: 'technique', icon: 'foie.png', chargedIcon: 'charged_foie.png' },
  { id: 'barta', label: 'Barta', short: 'Barta', category: 'technique', icon: 'barta.png', chargedIcon: 'charged_barta.png' },
  { id: 'zonde', label: 'Zonde', short: 'Zonde', category: 'technique', icon: 'zonde.png', chargedIcon: 'charged_zonde.png' },
  { id: 'grants', label: 'Grants', short: 'Grants', category: 'technique', icon: 'grants.png', chargedIcon: 'charged_grants.png' },
  { id: 'megid', label: 'Megid', short: 'Megid', category: 'technique', icon: 'megid.png', chargedIcon: 'charged_megid.png' },
  { id: 'resta', label: 'Resta', short: 'Resta', category: 'technique', icon: 'resta.png', chargedIcon: 'charged_resta.png' },
  { id: 'anti', label: 'Anti', short: 'Anti', category: 'technique', icon: 'anti.png', chargedIcon: 'charged_anti.png' },
  { id: 'shifta', label: 'Shifta', short: 'Shifta', category: 'technique', icon: 'shifta.png', chargedIcon: 'charged_shifta.png' },
  { id: 'deband', label: 'Deband', short: 'Deband', category: 'technique', icon: 'deband.png', chargedIcon: 'charged_deband.png' },
  { id: 'jellen', label: 'Jellen', short: 'Jellen', category: 'technique', icon: 'jellen.png', chargedIcon: 'charged_jellen.png' },
  { id: 'zalure', label: 'Zalure', short: 'Zalure', category: 'technique', icon: 'zalure.png', chargedIcon: 'charged_zalure.png' },
];

const CATEGORIES: { key: Category; label: string }[] = [
  { key: 'combat', label: 'Combat' },
  { key: 'recovery', label: 'Recovery' },
  { key: 'technique', label: 'Technique' },
];

const DEFAULT_PAGES = [
  ['attack', 'strong_attack', 'monomate'],
  ['attack', 'foie', 'dimate'],
];

const colors = {
  bg: '#0d0d1a',
  panelBg: 'rgba(13, 13, 26, 0.95)',
  border: 'rgba(77, 128, 77, 0.5)',
  headerBg: 'rgba(26, 46, 89, 0.9)',
  slotBg: 'rgba(8, 8, 18, 0.9)',
  slotBorder: 'rgba(60, 90, 60, 0.6)',
  slotSelected: 'rgba(38, 77, 38, 0.8)',
  slotSelectedBorder: '#4dcc4d',
  iconBg: 'rgba(5, 5, 15, 0.95)',
  pickerHover: 'rgba(40, 60, 40, 0.5)',
  pickerSelected: 'rgba(50, 100, 50, 0.7)',
  assigned: '#4dcc4d',
  text: '#d9d9d9',
  textDim: '#808080',
  textLight: 'rgba(180, 190, 200, 0.7)',
  catHeader: 'rgba(100, 140, 200, 0.9)',
};

function ActionIcon({ actionId, size = 32 }: { actionId: string; size?: number }) {
  const action = ALL_ACTIONS.find((a) => a.id === actionId);
  if (!action) return <div style={{ width: size, height: size }} />;
  return (
    <div style={{
      width: size, height: size,
      background: colors.iconBg,
      borderRadius: 4,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <img
        src={ICON_BASE + action.icon}
        alt={action.label}
        style={{ width: size - 4, height: size - 4, imageRendering: 'pixelated' }}
      />
    </div>
  );
}

function PalettePreview({
  pages,
  activePage,
  selectedSlot,
  onSelectSlot,
  onChangePage,
}: {
  pages: string[][];
  activePage: number;
  selectedSlot: number;
  onSelectSlot: (slot: number) => void;
  onChangePage: (page: number) => void;
}) {
  const page = pages[activePage];
  return (
    <div style={{ position: 'relative', width: 280, margin: '0 auto' }}>
      <img
        src={ICON_BASE + (activePage === 0 ? 'palette_bg.png' : 'palette_bg_r.png')}
        alt="palette"
        style={{ width: 280, height: 146, imageRendering: 'pixelated' }}
      />
      {/* Icons overlaid on the 3 octagon slots */}
      {[0, 1, 2].map((i) => {
        const centers = [
          { x: 57, y: 59 },
          { x: 127, y: 89 },
          { x: 196, y: 59 },
        ];
        const c = centers[i];
        const isSelected = i === selectedSlot;
        return (
          <div
            key={i}
            onClick={() => onSelectSlot(i)}
            style={{
              position: 'absolute',
              left: c.x - 20,
              top: c.y - 20,
              width: 40, height: 40,
              cursor: 'pointer',
              borderRadius: 6,
              border: isSelected ? `2px solid ${colors.slotSelectedBorder}` : '2px solid transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >
            <ActionIcon actionId={page[i]} size={36} />
          </div>
        );
      })}
      {/* Page tabs */}
      <div style={{ display: 'flex', justifyContent: 'center', gap: 8, marginTop: 8 }}>
        {pages.map((_, i) => (
          <button
            key={i}
            onClick={() => onChangePage(i)}
            style={{
              background: i === activePage ? colors.slotSelected : colors.slotBg,
              color: i === activePage ? colors.text : colors.textDim,
              border: `1px solid ${i === activePage ? colors.slotSelectedBorder : colors.slotBorder}`,
              borderRadius: 4, padding: '4px 16px', cursor: 'pointer',
              fontSize: 12, fontFamily: 'monospace',
            }}
          >
            Page {i + 1}
          </button>
        ))}
      </div>
    </div>
  );
}

function ActionPicker({
  currentId,
  onPick,
}: {
  currentId: string;
  onPick: (actionId: string) => void;
}) {
  const [hoveredId, setHoveredId] = useState<string | null>(null);

  return (
    <div style={{
      background: colors.panelBg,
      border: `1px solid ${colors.border}`,
      borderRadius: 6,
      padding: 8,
      maxHeight: 320,
      overflowY: 'auto',
    }}>
      {CATEGORIES.map((cat) => {
        const actions = ALL_ACTIONS.filter((a) => a.category === cat.key);
        return (
          <div key={cat.key}>
            <div style={{
              fontSize: 11, color: colors.catHeader,
              padding: '6px 4px 2px', fontFamily: 'monospace',
              borderBottom: '1px solid rgba(100,140,200,0.2)',
              marginBottom: 4,
            }}>
              {cat.label}
            </div>
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(4, 1fr)',
              gap: 4,
              marginBottom: 8,
            }}>
              {actions.map((action) => {
                const isCurrent = action.id === currentId;
                const isHovered = action.id === hoveredId;
                return (
                  <div
                    key={action.id}
                    onClick={() => onPick(action.id)}
                    onMouseEnter={() => setHoveredId(action.id)}
                    onMouseLeave={() => setHoveredId(null)}
                    style={{
                      display: 'flex', flexDirection: 'column',
                      alignItems: 'center', gap: 2,
                      padding: 4, borderRadius: 4, cursor: 'pointer',
                      background: isCurrent ? colors.pickerSelected : isHovered ? colors.pickerHover : 'transparent',
                      border: isCurrent ? `1px solid ${colors.assigned}` : '1px solid transparent',
                      transition: 'background 0.1s',
                    }}
                  >
                    <ActionIcon actionId={action.id} size={36} />
                    <span style={{
                      fontSize: 9, color: isCurrent ? colors.assigned : colors.textLight,
                      fontFamily: 'monospace', textAlign: 'center',
                      lineHeight: 1.1,
                    }}>
                      {action.short}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function PaletteEditorMockup() {
  const [pages, setPages] = useState(DEFAULT_PAGES.map((p) => [...p]));
  const [activePage, setActivePage] = useState(0);
  const [selectedSlot, setSelectedSlot] = useState(0);

  const currentActionId = pages[activePage][selectedSlot];

  const handlePick = (actionId: string) => {
    const next = pages.map((p) => [...p]);
    next[activePage][selectedSlot] = actionId;
    setPages(next);
  };

  return (
    <div style={{
      minHeight: '100vh', background: colors.bg,
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: 24, fontFamily: 'monospace', color: colors.text,
    }}>
      <h2 style={{ color: '#88aaff', fontSize: 16, marginBottom: 4 }}>
        Palette Editor Mockup
      </h2>
      <p style={{ color: colors.textDim, fontSize: 11, marginBottom: 16 }}>
        Click a slot, then pick an action below
      </p>

      <PalettePreview
        pages={pages}
        activePage={activePage}
        selectedSlot={selectedSlot}
        onSelectSlot={setSelectedSlot}
        onChangePage={setActivePage}
      />

      <div style={{ marginTop: 16, width: 320 }}>
        <div style={{
          fontSize: 12, color: colors.textLight, marginBottom: 6,
          textAlign: 'center',
        }}>
          Page {activePage + 1}, Slot {selectedSlot + 1}
        </div>
        <ActionPicker
          currentId={currentActionId}
          onPick={handlePick}
        />
      </div>
    </div>
  );
}
