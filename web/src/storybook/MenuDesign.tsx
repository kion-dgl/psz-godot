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
  const items = ['Equipment', 'Inventory', 'Techniques', 'Action Palette', 'Status', 'Options', 'Quit Mission'];
  return (
    <Panel title="Menu" width={320} hint="Select from the Menu.">
      {items.map((item, i) => (
        <PillRow key={item} label={item} selected={sel === i} onClick={() => setSel(i)} />
      ))}
    </Panel>
  );
}


const PALETTE_ACTIONS = [
  { id: 'attack', label: 'Attack', category: 'combat' },
  { id: 'strong_attack', label: 'Strong Attack', category: 'combat' },
  { id: 'dodge', label: 'Dodge Roll', category: 'combat' },
  { id: 'monomate', label: 'Monomate', category: 'recovery' },
  { id: 'dimate', label: 'Dimate', category: 'recovery' },
  { id: 'trimate', label: 'Trimate', category: 'recovery' },
  { id: 'monofluid', label: 'Monofluid', category: 'recovery' },
  { id: 'difluid', label: 'Difluid', category: 'recovery' },
  { id: 'trifluid', label: 'Trifluid', category: 'recovery' },
] as const;

// Button labels for gamepad vs keyboard display
const SLOT_LABELS = {
  gamepad: ['X', 'A', 'B'],
  keyboard: ['J', 'K', 'L'],
} as const;
const SWAP_LABELS = { gamepad: 'RB', keyboard: 'Shift' } as const;

function ActionPaletteMenu() {
  const [pages, setPages] = useState(() => DEFAULT_PALETTE_PAGES.map(p => [...p]));
  const [activePage, setActivePage] = useState(0);
  const [selSlot, setSelSlot] = useState(0);
  const [picking, setPicking] = useState(false);
  const [inputMode, setInputMode] = useState<'gamepad' | 'keyboard'>('gamepad');

  const currentPage = pages[activePage];
  const slotKeys = SLOT_LABELS[inputMode];
  const swapKey = SWAP_LABELS[inputMode];

  const assignAction = (actionLabel: string) => {
    setPages(prev => prev.map((p, pi) => {
      if (pi !== activePage) return p;
      const newP = [...p];
      newP[selSlot] = actionLabel;
      return newP;
    }));
    setPicking(false);
  };

  // Action picker sub-view
  if (picking) {
    const combatActions = PALETTE_ACTIONS.filter(a => a.category === 'combat');
    const recoveryActions = PALETTE_ACTIONS.filter(a => a.category === 'recovery');
    return (
      <Panel title="Action Palette" width={380} hint={inputMode === 'gamepad'
        ? '\u2191\u2193 Select   A Confirm   B Back'
        : '\u2191\u2193 Select   Enter Confirm   Esc Back'}>
        <div style={{ fontSize: '12px', color: C.textLight, marginBottom: '6px', padding: '0 4px' }}>
          Assign to Page {activePage + 1} \u00b7 {slotKeys[selSlot]} slot
        </div>
        <div style={{ fontSize: '10px', fontWeight: 700, color: C.textLight, padding: '4px 6px 2px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Combat</div>
        {combatActions.map(a => (
          <PillRow
            key={a.id}
            label={a.label}
            selected={currentPage[selSlot] === a.label}
            onClick={() => assignAction(a.label)}
          />
        ))}
        <div style={{ fontSize: '10px', fontWeight: 700, color: C.textLight, padding: '8px 6px 2px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Recovery</div>
        {recoveryActions.map(a => (
          <PillRow
            key={a.id}
            label={a.label}
            selected={currentPage[selSlot] === a.label}
            onClick={() => assignAction(a.label)}
          />
        ))}
        <div style={{ marginTop: '8px' }}>
          <PillRow label="\u2190 Back" onClick={() => setPicking(false)} />
        </div>
      </Panel>
    );
  }

  return (
    <Panel title="Action Palette" width={380} hint={inputMode === 'gamepad'
      ? 'LB/RB Page   \u2191\u2193 Slot   A Edit   B Back'
      : 'Left/Right Page   \u2191\u2193 Slot   Enter Edit   Esc Back'}>
      {/* Input mode toggle */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px 4px' }}>
        <div style={{
          display: 'flex', gap: '2px', background: 'rgba(0,0,0,0.1)', borderRadius: '6px', padding: '2px',
        }}>
          {(['gamepad', 'keyboard'] as const).map(mode => (
            <button key={mode} onClick={() => setInputMode(mode)} style={{
              background: inputMode === mode ? C.bgDark : 'transparent',
              color: inputMode === mode ? C.textWhite : C.textLight,
              border: 'none', borderRadius: '4px', padding: '2px 8px',
              fontSize: '10px', fontWeight: 600, cursor: 'pointer',
            }}>{mode === 'gamepad' ? '\uD83C\uDFAE Gamepad' : '\u2328 Keyboard'}</button>
          ))}
        </div>
      </div>

      {/* Page tabs */}
      <TabBar
        tabs={pages.map((_, i) => `Page ${i + 1}`)}
        active={activePage}
        onSelect={(i) => { setActivePage(i); setSelSlot(0); }}
      />

      {/* Live palette preview — diamond layout matching HUD */}
      <div style={{
        display: 'flex', justifyContent: 'center', margin: '8px 0 12px',
      }}>
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0px',
        }}>
          {/* Swap indicator */}
          <div style={{
            background: C.itemBg, borderRadius: '8px',
            padding: '3px 10px', border: '1px solid rgba(150,180,210,0.4)',
            display: 'flex', alignItems: 'center', gap: '4px',
            marginBottom: '-2px', zIndex: 1,
          }}>
            <span style={{
              fontSize: '9px', fontWeight: 700, color: C.textWhite,
              background: 'rgba(40,60,80,0.7)', borderRadius: '6px',
              padding: '1px 6px', lineHeight: '16px',
            }}>{swapKey}</span>
            <span style={{ fontSize: '9px', fontWeight: 600, color: C.textLight }}>
              {activePage + 1}/{pages.length}
            </span>
          </div>
          {/* 3 slots — left and right raised, center lower (diamond) */}
          <div style={{ display: 'flex', gap: '6px', alignItems: 'flex-end' }}>
            {currentPage.map((label, i) => (
              <div key={i} style={{
                background: selSlot === i ? C.selectedGradient : C.itemBg,
                borderRadius: '8px',
                padding: '6px 12px',
                border: selSlot === i ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px',
                minWidth: '58px', cursor: 'pointer',
                marginBottom: i === 1 ? '0px' : '14px',
              }} onClick={() => setSelSlot(i)}>
                <span style={{
                  fontSize: '9px', fontWeight: 700, color: C.textWhite,
                  background: 'rgba(40,60,80,0.7)', borderRadius: '6px',
                  padding: '1px 6px', lineHeight: '16px',
                }}>{slotKeys[i]}</span>
                <span style={{ fontSize: '11px', fontWeight: 600, color: C.text, textAlign: 'center', lineHeight: '14px' }}>{label}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <Divider />

      {/* Slot list */}
      {currentPage.map((label, i) => (
        <PillRow
          key={i}
          label={`${slotKeys[i]}  Slot ${i + 1}`}
          rightText={label}
          selected={selSlot === i}
          onClick={() => { setSelSlot(i); setPicking(true); }}
        />
      ))}
    </Panel>
  );
}

function HudHpPp() {
  return (
    <div style={{
      background: C.bgLight, backgroundImage: SCANLINES,
      border: `2px solid ${C.separator}`,
      borderRadius: '4px 20px 12px 16px',
      padding: '8px 14px', width: '230px',
      filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.3))',
    }}>
      {/* Player name + level */}
      <div style={{
        fontSize: '13px', fontWeight: 800, color: C.text,
        marginBottom: '5px', fontStyle: 'italic',
        borderBottom: '1px solid rgba(120,160,200,0.3)',
        paddingBottom: '4px',
      }}>
        Kion
        <span style={{
          fontSize: '10px', fontWeight: 600, color: C.textLight,
          marginLeft: '8px', fontStyle: 'normal',
        }}>
          Lv. 42
        </span>
      </div>

      {/* HP bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '3px' }}>
        <span style={{ fontSize: '10px', fontWeight: 800, color: '#338833', width: '18px' }}>HP</span>
        <div style={{
          flex: 1, height: '14px', background: C.hpBg,
          borderRadius: '7px', overflow: 'hidden',
          border: '1px solid rgba(0,0,0,0.1)',
          position: 'relative',
        }}>
          <div style={{
            width: `${(342 / 480) * 100}%`, height: '100%',
            background: 'linear-gradient(180deg, #66dd66 0%, #338833 100%)',
            borderRadius: '7px',
          }} />
          <span style={{
            position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
            fontSize: '9px', fontWeight: 700, color: '#fff',
            textShadow: '0 1px 2px rgba(0,0,0,0.5)',
          }}>342</span>
          <span style={{
            position: 'absolute', top: '50%', right: '6px', transform: 'translateY(-50%)',
            fontSize: '9px', fontWeight: 700, color: C.text,
          }}>480</span>
        </div>
      </div>

      {/* PP bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
        <span style={{ fontSize: '10px', fontWeight: 800, color: '#3366bb', width: '18px' }}>PP</span>
        <div style={{
          flex: 1, height: '14px', background: C.ppBg,
          borderRadius: '7px', overflow: 'hidden',
          border: '1px solid rgba(0,0,0,0.1)',
          position: 'relative',
        }}>
          <div style={{
            width: `${(86 / 120) * 100}%`, height: '100%',
            background: 'linear-gradient(180deg, #6699ff 0%, #3355aa 100%)',
            borderRadius: '7px',
          }} />
          <span style={{
            position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
            fontSize: '9px', fontWeight: 700, color: '#fff',
            textShadow: '0 1px 2px rgba(0,0,0,0.5)',
          }}>86</span>
          <span style={{
            position: 'absolute', top: '50%', right: '6px', transform: 'translateY(-50%)',
            fontSize: '9px', fontWeight: 700, color: C.text,
          }}>120</span>
        </div>
      </div>
    </div>
  );
}

function HudMinimap() {
  return (
    <div style={{
      background: C.bgLight, backgroundImage: SCANLINES,
      border: `2px solid ${C.separator}`, borderRadius: '20px 4px 4px 12px',
      padding: '8px', width: '170px',
      filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.3))',
      display: 'flex', gap: '6px',
    }}>
      {/* Key indicators — inside panel, left of map */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
        <span style={{ fontSize: '8px', fontWeight: 700, color: C.textLight, textAlign: 'center' }}>Keys</span>
        {['A', 'B'].map((key, i) => (
          <div key={key} style={{
            width: '18px', height: '18px', fontSize: '10px', fontWeight: 800,
            background: i === 0 ? '#cc8844' : 'rgba(150,180,210,0.4)',
            color: i === 0 ? C.textWhite : C.textLight,
            borderRadius: '3px', border: '1px solid rgba(0,0,0,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            {key}
          </div>
        ))}
      </div>

      {/* Minimap grid */}
      <div style={{
        flex: 1, aspectRatio: '1', background: 'rgba(20,40,60,0.7)',
        borderRadius: '4px', border: '1px solid rgba(0,0,0,0.3)',
        position: 'relative',
      }}>
        {Array.from({ length: 25 }).map((_, i) => {
          const row = Math.floor(i / 5);
          const col = i % 5;
          const isVisited = [6, 7, 8, 11, 12, 13, 16, 17, 18].includes(i);
          const isCurrent = i === 12;
          const isGate = i === 8 || i === 16;
          return (
            <div key={i} style={{
              position: 'absolute',
              left: `${col * 20 + 2}%`, top: `${row * 20 + 2}%`,
              width: '16%', height: '16%',
              background: isCurrent ? '#44cc44' : isGate ? '#cc8844' : isVisited ? 'rgba(100,160,220,0.5)' : 'rgba(60,80,100,0.3)',
              borderRadius: '2px',
              border: isCurrent ? '2px solid #88ff88' : '1px solid rgba(100,140,180,0.3)',
            }} />
          );
        })}
      </div>
    </div>
  );
}

// Default palette pages shared by HUD and menu
const DEFAULT_PALETTE_PAGES = [
  ['Attack', 'Strong Attack', 'Monomate'],
  ['Attack', 'Dodge Roll', 'Dimate'],
];

// Abbreviate long action names for the compact HUD display
function shortLabel(label: string): string {
  const map: Record<string, string> = {
    'Attack': 'Atk', 'Strong Attack': 'S.Atk', 'Dodge Roll': 'Dodge',
    'Monomate': 'Mono', 'Dimate': 'Di', 'Trimate': 'Tri',
    'Monofluid': 'M.Flu', 'Difluid': 'D.Flu', 'Trifluid': 'T.Flu',
  };
  return map[label] ?? label;
}

function HudActionPalette() {
  const [pageIndex, setPageIndex] = useState(0);
  const pages = DEFAULT_PALETTE_PAGES;
  const currentPage = pages[pageIndex];
  const buttonKeys = ['X', 'A', 'B'];

  const swapPalette = () => setPageIndex(i => (i + 1) % pages.length);

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0px',
      filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.3))',
    }}>
      {/* RB — palette swap, clickable */}
      <div
        onClick={swapPalette}
        style={{
          background: C.itemBg, borderRadius: '8px',
          padding: '4px 12px', border: '1px solid rgba(150,180,210,0.4)',
          display: 'flex', alignItems: 'center', gap: '6px',
          marginBottom: '-2px', zIndex: 1, cursor: 'pointer',
        }}
      >
        <span style={{
          fontSize: '9px', fontWeight: 700, color: C.textWhite,
          background: 'rgba(40,60,80,0.7)', borderRadius: '6px',
          padding: '1px 6px', lineHeight: '16px',
        }}>RB</span>
        <span style={{ fontSize: '9px', fontWeight: 600, color: C.textLight }}>
          {pageIndex + 1}/{pages.length}
        </span>
      </div>
      {/* X A B — X and B raised, A lower (diamond-ish) */}
      <div style={{ display: 'flex', gap: '6px', alignItems: 'flex-end' }}>
        {currentPage.map((label, i) => (
          <div key={i} style={{
            background: C.itemBg, borderRadius: '8px',
            padding: '6px 12px', border: '1px solid rgba(150,180,210,0.4)',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px',
            minWidth: '52px',
            marginBottom: i === 1 ? '0px' : '14px',
          }}>
            <span style={{
              fontSize: '9px', fontWeight: 700, color: C.textWhite,
              background: 'rgba(40,60,80,0.7)', borderRadius: '6px',
              padding: '1px 6px', lineHeight: '16px',
            }}>{buttonKeys[i]}</span>
            <span style={{ fontSize: '11px', fontWeight: 600, color: C.text }}>{shortLabel(label)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function HudActivityLog() {
  const entries = [
    { text: 'Picked up Monomate x2', color: C.text },
    { text: 'Booma defeated!', color: C.rare },
    { text: 'Obtained 120 Meseta', color: '#886600' },
    { text: 'NPC: "The valley is dangerous. Be careful."', color: '#4466aa' },
    { text: 'Picked up Photon Drop x1', color: '#8844cc' },
    { text: 'Key A obtained!', color: '#cc8844' },
  ];
  return (
    <div style={{
      background: C.bgLight, backgroundImage: SCANLINES,
      border: `2px solid ${C.separator}`, borderRadius: '8px',
      padding: '4px', width: '320px',
      filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.3))',
    }}>
      <div style={{
        fontSize: '10px', fontWeight: 800, color: C.textWhite,
        background: C.bgDark, backgroundImage: SCANLINES,
        borderRadius: '4px 4px 0 0',
        padding: '3px 8px',
      }}>Log</div>
      <div style={{
        background: C.itemBg, borderRadius: '4px',
        padding: '8px 10px', border: '1px solid rgba(150,180,210,0.4)',
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
          {entries.map((entry, i) => (
            <div key={i} style={{
              fontSize: '12px', color: entry.color,
              opacity: 0.5 + (i / entries.length) * 0.5,
            }}>
              {entry.text}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function HudFull() {
  return (
    <div style={{
      width: '800px', height: '500px', position: 'relative',
      background: 'rgba(30,50,70,0.3)', borderRadius: '8px',
      border: '1px dashed rgba(100,140,180,0.3)',
    }}>
      {/* Top-left: HP/PP */}
      <div style={{ position: 'absolute', top: '12px', left: '12px' }}>
        <HudHpPp />
      </div>
      {/* Top-right: Minimap */}
      <div style={{ position: 'absolute', top: '12px', right: '12px' }}>
        <HudMinimap />
      </div>
      {/* Bottom-right: Action palette */}
      <div style={{ position: 'absolute', bottom: '12px', right: '12px' }}>
        <HudActionPalette />
      </div>
      {/* Bottom-left: Activity log */}
      <div style={{ position: 'absolute', bottom: '12px', left: '12px' }}>
        <HudActivityLog />
      </div>
      {/* Center label */}
      <div style={{
        position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
        fontSize: '14px', color: 'rgba(150,180,210,0.4)', fontStyle: 'italic',
      }}>
        gameplay area
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

function ItemShop() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const items = [
    { name: 'Monomate', price: 50, desc: 'Restores a small amount of HP.' },
    { name: 'Dimate', price: 300, desc: 'Restores a moderate amount of HP.' },
    { name: 'Trimate', price: 2000, desc: 'Fully restores HP.' },
    { name: 'Monofluid', price: 100, desc: 'Restores a small amount of PP.' },
    { name: 'Difluid', price: 600, desc: 'Restores a moderate amount of PP.' },
    { name: 'Telepipe', price: 350, desc: 'Warps back to the city from the field.' },
    { name: 'Moon Atomizer', price: 500, desc: 'Revives a fallen ally.' },
    { name: 'Star Atomizer', price: 5000, desc: 'Fully restores HP of all nearby allies.' },
    { name: 'Sol Atomizer', price: 200, desc: 'Cures status effects for all nearby allies.' },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Item Shop" width={380} hint={`Press ENTER to buy - ${items[sel].price} MST`}>
        <TabBar tabs={['Buy', 'Sell']} active={tab} onSelect={setTab} />
        {items.map((item, i) => (
          <PillRow
            key={item.name}
            label={item.name}
            rightText={`${item.price.toLocaleString()} MST`}
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

      <Panel title="Item Info" width={260}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '4px' }}>
            {items[sel].name}
          </div>
          <div style={{ fontSize: '12px', fontWeight: 600, color: '#886600', marginBottom: '8px' }}>
            {items[sel].price.toLocaleString()} MST
          </div>
          <Divider />
          <div style={{ fontSize: '13px', color: C.text, lineHeight: '1.5' }}>
            {items[sel].desc}
          </div>
        </div>
      </Panel>
    </div>
  );
}

function StorageCounter() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const stored = [
    { name: 'Brand', type: 'Saber', rarity: 'common' },
    { name: 'Varista', type: 'Handgun', rarity: 'common' },
    { name: 'Photon Drop', type: 'Material', rarity: 'common' },
    { name: 'Photon Drop', type: 'Material', rarity: 'common' },
    { name: 'Grinder', type: 'Material', rarity: 'common' },
    { name: 'Resist/Fire', type: 'Unit', rarity: 'common' },
    { name: 'DB\'s Saber', type: 'Saber', rarity: 'rare' },
    { name: 'Mag Cell', type: 'Material', rarity: 'rare' },
  ];
  const inventory = [
    { name: 'Monomate', qty: 8 },
    { name: 'Dimate', qty: 3 },
    { name: 'Telepipe', qty: 4 },
    { name: 'Saber', qty: 1 },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Storage" width={360} hint={tab === 0 ? 'Select item to withdraw.' : 'Select item to deposit.'}>
        <TabBar tabs={['Withdraw', 'Deposit']} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        <div style={{
          fontSize: '11px', color: C.textLight, padding: '0 4px', marginBottom: '6px',
        }}>
          {tab === 0
            ? <span>{stored.length}/200 stored</span>
            : <span>{inventory.length}/40 items</span>
          }
        </div>
        {(tab === 0 ? stored : inventory).map((item, i) => (
          <PillRow
            key={`${item.name}-${i}`}
            label={item.name}
            rightText={'type' in item ? item.type : `x${(item as any).qty}`}
            selected={sel === i}
            onClick={() => setSel(i)}
          />
        ))}
      </Panel>

      <Panel title="Detail" width={240}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          {tab === 0 ? (
            <>
              <div style={{ fontSize: '15px', fontWeight: 700, color: stored[sel]?.rarity === 'rare' ? C.rare : C.text, marginBottom: '4px' }}>
                {stored[sel]?.name}
              </div>
              <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
                {stored[sel]?.type}
              </div>
            </>
          ) : (
            <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '4px' }}>
              {inventory[sel]?.name}
            </div>
          )}
          <Divider />
          <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
            {[tab === 0 ? 'Withdraw' : 'Deposit', 'Cancel'].map((action) => (
              <div key={action} style={{
                flex: 1, padding: '7px', fontSize: '13px', fontWeight: 600,
                background: C.itemBg, border: '1px solid rgba(150,180,210,0.4)',
                borderRadius: '4px', color: C.text, cursor: 'pointer', textAlign: 'center',
              }}>
                {action}
              </div>
            ))}
          </div>
        </div>
      </Panel>
    </div>
  );
}

function TekkerMenu() {
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);

  const unidentified = [
    { name: '??? Saber', slots: '???' },
    { name: '??? Sword', slots: '???' },
    { name: '??? Handgun', slots: '???' },
  ];
  const grindable = [
    { name: 'Saber', grind: '+0', maxGrind: '+9', cost: 100 },
    { name: 'Brand', grind: '+3', maxGrind: '+12', cost: 300 },
    { name: 'Buster', grind: '+1', maxGrind: '+15', cost: 500 },
  ];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Tekker" width={380} hint={tab === 0 ? 'Identify a mysterious weapon.' : 'Grind your weapon for ATK bonus.'}>
        <TabBar tabs={['Identify', 'Grind']} active={tab} onSelect={(i) => { setTab(i); setSel(0); }} />
        {tab === 0 ? (
          <>
            {unidentified.length === 0 ? (
              <div style={{ padding: '16px', fontSize: '13px', color: C.textLight, textAlign: 'center' }}>
                No unidentified weapons.
              </div>
            ) : (
              unidentified.map((w, i) => (
                <PillRow
                  key={`${w.name}-${i}`}
                  label={w.name}
                  rightText={w.slots}
                  selected={sel === i}
                  onClick={() => setSel(i)}
                />
              ))
            )}
          </>
        ) : (
          <>
            {grindable.map((w, i) => (
              <PillRow
                key={w.name}
                label={w.name}
                rightText={`${w.grind} / ${w.maxGrind}`}
                selected={sel === i}
                onClick={() => setSel(i)}
              />
            ))}
            <Divider />
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontSize: '13px', color: C.text, padding: '2px 4px',
            }}>
              <span>Grind Cost:</span>
              <span style={{ fontWeight: 700, color: '#886600' }}>{grindable[sel]?.cost.toLocaleString()} MST</span>
            </div>
          </>
        )}
      </Panel>

      <Panel title="Detail" width={280}>
        <div style={{
          background: C.itemBg, borderRadius: '4px',
          padding: '10px 12px', border: '1px solid rgba(150,180,210,0.4)',
        }}>
          {tab === 0 ? (
            <>
              <div style={{ fontSize: '15px', fontWeight: 700, color: C.rare, marginBottom: '4px' }}>
                {unidentified[sel]?.name}
              </div>
              <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
                Unidentified weapon
              </div>
              <Divider />
              <div style={{ fontSize: '13px', color: C.text, lineHeight: '1.5' }}>
                This weapon must be identified before it can be equipped. The Tekker will reveal its true stats and element.
              </div>
              <div style={{
                marginTop: '10px', padding: '7px', fontSize: '13px', fontWeight: 600,
                background: C.selectedGradient, border: '2px solid #d08010',
                borderRadius: '4px', color: C.text, cursor: 'pointer', textAlign: 'center',
              }}>
                Identify (100 MST)
              </div>
            </>
          ) : (
            <>
              <div style={{ fontSize: '15px', fontWeight: 700, color: C.text, marginBottom: '4px' }}>
                {grindable[sel]?.name}
              </div>
              <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
                Current grind: {grindable[sel]?.grind}
              </div>
              <Divider />
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '13px' }}>
                {[
                  ['ATK Bonus', `+${parseInt(grindable[sel]?.grind.replace('+', '') || '0') * 2}`],
                  ['Max Grind', grindable[sel]?.maxGrind || ''],
                  ['Success Rate', '90%'],
                ].map(([k, v]) => (
                  <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ color: C.textLight }}>{k}</span>
                    <span style={{ fontWeight: 700, color: C.text }}>{v}</span>
                  </div>
                ))}
              </div>
              <div style={{
                marginTop: '10px', padding: '7px', fontSize: '13px', fontWeight: 600,
                background: C.selectedGradient, border: '2px solid #d08010',
                borderRadius: '4px', color: C.text, cursor: 'pointer', textAlign: 'center',
              }}>
                Grind ({grindable[sel]?.cost} MST)
              </div>
            </>
          )}
        </div>
      </Panel>
    </div>
  );
}

function QuestCounter() {
  const [mode, setMode] = useState(0);
  const [sel, setSel] = useState(0);
  const quests = [
    { name: 'Valley Patrol', area: 'Gurhacia Valley', diff: 'Normal', rank: 'C', reward: 500, desc: 'Patrol the valley and eliminate hostile creatures.' },
    { name: 'Swamp Sweep', area: 'Ozette Wetlands', diff: 'Normal', rank: 'C', reward: 600, desc: 'Clear out the creatures infesting the wetlands.' },
    { name: 'Forest Recon', area: 'Rioh Snowfield', diff: 'Hard', rank: 'B', reward: 1200, desc: 'Investigate unusual activity in the snowfield.' },
    { name: 'Desert Storm', area: 'Makara Desert', diff: 'Hard', rank: 'B', reward: 1500, desc: 'A sandstorm has stirred up the desert creatures.' },
    { name: 'Tower Ascent', area: 'Eternal Tower', diff: 'S. Hard', rank: 'A', reward: 5000, desc: 'Climb the tower and reach the summit.' },
  ];
  const difficulties = ['Normal', 'Hard', 'S. Hard'];

  return (
    <div style={{ display: 'flex', gap: '12px' }}>
      <Panel title="Quest Counter" width={420} hint="Select a quest to accept.">
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          marginBottom: '8px', padding: '0 4px',
        }}>
          <TabBar tabs={difficulties} active={mode} onSelect={(i) => { setMode(i); setSel(0); }} />
        </div>
        {quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard')).map((q, i) => (
          <PillRow
            key={q.name}
            label={q.name}
            rightText={`[${q.rank}]`}
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
            {quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.name}
          </div>
          <div style={{ fontSize: '11px', color: C.textLight, marginBottom: '8px' }}>
            {quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.area}
          </div>
          <Divider />
          <div style={{ fontSize: '13px', color: C.text, lineHeight: '1.5', marginBottom: '8px' }}>
            {quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.desc}
          </div>
          <Divider />
          <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '13px' }}>
            {[
              ['Difficulty', quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.diff || ''],
              ['Rank', quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.rank || ''],
              ['Reward', `${(quests.filter((q) => q.diff === difficulties[mode] || (mode === 2 && q.diff === 'S. Hard'))[sel]?.reward || 0).toLocaleString()} MST`],
            ].map(([k, v]) => (
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: C.textLight }}>{k}</span>
                <span style={{ fontWeight: 700, color: C.text }}>{v}</span>
              </div>
            ))}
          </div>
          <div style={{
            marginTop: '10px', padding: '7px', fontSize: '13px', fontWeight: 600,
            background: C.selectedGradient, border: '2px solid #d08010',
            borderRadius: '4px', color: C.text, cursor: 'pointer', textAlign: 'center',
          }}>
            Accept Quest
          </div>
        </div>
      </Panel>
    </div>
  );
}

// --- Main Page ---

const MENU_DEMOS = [
  { id: 'hud-full', label: 'HUD (Full)', component: HudFull },
  { id: 'hud-hp', label: 'HUD: HP/PP', component: HudHpPp },
  { id: 'hud-map', label: 'HUD: Minimap', component: HudMinimap },
  { id: 'hud-actions', label: 'HUD: Actions', component: HudActionPalette },
  { id: 'hud-log', label: 'HUD: Log', component: HudActivityLog },
  { id: 'pause', label: 'Pause Menu', component: PauseMenu },
  { id: 'action-palette', label: 'Action Palette', component: ActionPaletteMenu },
  { id: 'equipment', label: 'Equipment', component: EquipmentMenu },
  { id: 'inventory', label: 'Inventory', component: InventoryMenu },
  { id: 'weapon-shop', label: 'Weapon Shop', component: ShopMenu },
  { id: 'item-shop', label: 'Item Shop', component: ItemShop },
  { id: 'tekker', label: 'Tekker', component: TekkerMenu },
  { id: 'storage', label: 'Storage', component: StorageCounter },
  { id: 'quest', label: 'Quest Counter', component: QuestCounter },
  { id: 'status', label: 'Status', component: StatusScreen },
];

export default function MenuDesign() {
  const [activeMenu, setActiveMenu] = useState('hud-full');
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
