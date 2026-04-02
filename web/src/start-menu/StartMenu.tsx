import { useState } from 'react';

/**
 * PSO-style start menu mock — fixed 1280x720 viewport.
 * Layout: L-shaped backdrop panel (left + bottom) with menu elements on top.
 * Theme: PSZ blue/silver — light panels, orange selection.
 */

// ── Layout constants ───────────────────────────────────────────────────────────
const VIEWPORT_W = 1280;
const VIEWPORT_H = 720;
const LEFT_PANEL_W = 240;   // Left backdrop strip width
const BOTTOM_PANEL_H = 200; // Bottom backdrop strip height
const PANEL_PAD = 12;       // Inner padding for menu elements

// ── PSZ Color palette ──────────────────────────────────────────────────────────
const C = {
  // Backdrop panels (L-shaped base layer)
  backdropBg: 'rgba(40, 60, 100, 0.82)',
  backdropBorder: 'rgba(100, 150, 210, 0.6)',
  backdropHighlight: 'rgba(160, 200, 255, 0.12)',

  // Inner panels (menu elements layer)
  panelBg: 'rgba(200, 215, 235, 0.92)',
  panelBorder: 'rgba(120, 160, 210, 0.7)',
  panelShadow: 'rgba(30, 50, 80, 0.3)',

  // Text
  textDark: '#1a2540',
  textMuted: '#4a5a78',
  textLight: '#e8eef8',

  // Selection
  selectBg: '#e08820',
  selectText: '#fff',

  // HP/PP bars
  hpGreen: '#28b848',
  ppBlue: '#2878d8',

  // Accent
  arrowGreen: '#30b850',
  pageBg: 'rgba(50, 80, 130, 0.6)',
};

// ── Data ───────────────────────────────────────────────────────────────────────
interface MenuItem {
  label: string;
  description: string;
}

interface InfoPage {
  title: string;
  rows: { label: string; value: string }[];
}

const MENU_ITEMS: MenuItem[] = [
  { label: 'Items',   description: 'Use items.' },
  { label: 'Equip',   description: 'Equip weapons and armor.' },
  { label: 'Palette', description: 'Edit the action palette.' },
  { label: 'Mags',    description: 'Feed and manage your Mag.' },
  { label: 'Quest',   description: 'View current quest objectives.' },
  { label: 'System',  description: 'System settings and options.' },
];

const INFO_PAGES: InfoPage[] = [
  {
    title: 'Status',
    rows: [
      { label: 'Lv', value: '14' },
      { label: 'Type', value: 'HUmar' },
      { label: 'Exp Pts', value: '12,480' },
      { label: 'To Next Lv', value: '3,520' },
      { label: 'Meseta', value: '8,250' },
    ],
  },
  {
    title: 'Attack',
    rows: [
      { label: 'ATP', value: '186' },
      { label: 'ATA', value: '94' },
      { label: 'Weapon', value: 'Saber' },
      { label: 'Grind', value: '+3' },
      { label: 'Special', value: 'Heat' },
    ],
  },
  {
    title: 'Defense',
    rows: [
      { label: 'DFP', value: '42' },
      { label: 'EVP', value: '68' },
      { label: 'Frame', value: 'Normal Frame' },
      { label: 'Shield', value: '--' },
      { label: 'Units', value: '0 / 4' },
    ],
  },
  {
    title: 'Technique',
    rows: [
      { label: 'MST', value: '30' },
      { label: 'TP', value: '45 / 45' },
      { label: 'Foie', value: 'Lv 3' },
      { label: 'Resta', value: 'Lv 1' },
      { label: 'Shifta', value: '--' },
    ],
  },
];

// ── Inner panel (drawn on z-index: 2 over the backdrop) ───────────────────────
function InnerPanel({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div style={{
      background: C.panelBg,
      border: `1.5px solid ${C.panelBorder}`,
      borderRadius: 4,
      boxShadow: `0 2px 6px ${C.panelShadow}`,
      ...style,
    }}>
      {children}
    </div>
  );
}

// ── Character status (top-left) ────────────────────────────────────────────────
function CharacterStatus() {
  return (
    <InnerPanel style={{ padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{
          width: 14, height: 14, borderRadius: 7,
          background: '#d03030', border: '1.5px solid #f06060',
          flexShrink: 0,
        }} />
        <span style={{
          color: C.textDark, fontSize: 16, fontWeight: 700,
          fontFamily: 'monospace', letterSpacing: 0.5,
        }}>
          Flauros
        </span>
      </div>
      {/* HP */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
        <span style={{ color: C.textMuted, fontSize: 10, fontFamily: 'monospace', width: 18 }}>HP</span>
        <div style={{ flex: 1, height: 10, background: 'rgba(0,0,0,0.15)', borderRadius: 2, border: '1px solid rgba(0,0,0,0.1)' }}>
          <div style={{ width: '85%', height: '100%', background: `linear-gradient(to right, #1a8830, ${C.hpGreen})`, borderRadius: 2 }} />
        </div>
      </div>
      {/* PP */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ color: C.textMuted, fontSize: 10, fontFamily: 'monospace', width: 18 }}>PP</span>
        <div style={{ flex: 1, height: 10, background: 'rgba(0,0,0,0.15)', borderRadius: 2, border: '1px solid rgba(0,0,0,0.1)' }}>
          <div style={{ width: '100%', height: '100%', background: `linear-gradient(to right, #1858a8, ${C.ppBlue})`, borderRadius: 2 }} />
        </div>
      </div>
    </InnerPanel>
  );
}

// ── Menu list ──────────────────────────────────────────────────────────────────
function MenuList({ selectedIndex, onSelect }: { selectedIndex: number; onSelect: (i: number) => void }) {
  return (
    <InnerPanel style={{ padding: '4px 0' }}>
      {MENU_ITEMS.map((item, i) => {
        const sel = i === selectedIndex;
        return (
          <div
            key={item.label}
            onClick={() => onSelect(i)}
            style={{
              padding: '7px 16px',
              cursor: 'pointer',
              background: sel ? C.selectBg : 'transparent',
              color: sel ? C.selectText : C.textDark,
              fontSize: 17, fontFamily: 'monospace',
              fontWeight: sel ? 700 : 500,
              letterSpacing: 1,
            }}
          >
            {item.label}
          </div>
        );
      })}
    </InnerPanel>
  );
}

// ── Description box ────────────────────────────────────────────────────────────
function DescriptionBox({ text }: { text: string }) {
  return (
    <InnerPanel style={{ padding: '10px 14px', minHeight: 40 }}>
      <span style={{
        color: C.textDark, fontSize: 15, fontFamily: 'monospace', letterSpacing: 0.3,
      }}>
        {text}
      </span>
    </InnerPanel>
  );
}

// ── Info panel with L/R pages ──────────────────────────────────────────────────
function InfoPanel({ page, totalPages, onPrev, onNext }: {
  page: number; totalPages: number; onPrev: () => void; onNext: () => void;
}) {
  const info = INFO_PAGES[page];
  return (
    <InnerPanel style={{ padding: 0 }}>
      {/* Page selector */}
      <div style={{
        display: 'flex', justifyContent: 'center', alignItems: 'center',
        gap: 10, padding: '6px 0',
        borderBottom: `1px solid rgba(100, 140, 190, 0.3)`,
      }}>
        <span onClick={onPrev} style={{
          color: C.arrowGreen, fontSize: 15, cursor: 'pointer',
          userSelect: 'none', fontFamily: 'monospace', fontWeight: 700,
        }}>
          ◀
        </span>
        <span style={{
          color: C.textDark, fontSize: 13, fontFamily: 'monospace',
          background: C.pageBg, color: C.textLight,
          padding: '2px 12px', borderRadius: 3,
          border: `1px solid rgba(100,150,210,0.4)`,
        }}>
          L {page + 1}/{totalPages} R
        </span>
        <span onClick={onNext} style={{
          color: C.arrowGreen, fontSize: 15, cursor: 'pointer',
          userSelect: 'none', fontFamily: 'monospace', fontWeight: 700,
        }}>
          ▶
        </span>
      </div>
      {/* Rows */}
      <div style={{ padding: '8px 16px' }}>
        {info.rows.map((row) => (
          <div key={row.label} style={{
            display: 'flex', justifyContent: 'space-between',
            padding: '4px 0', fontFamily: 'monospace', fontSize: 16,
          }}>
            <span style={{ color: C.textMuted }}>{row.label}</span>
            <span style={{ color: C.textDark, fontWeight: 600 }}>{row.value}</span>
          </div>
        ))}
      </div>
    </InnerPanel>
  );
}

// ── Main component ─────────────────────────────────────────────────────────────
export default function StartMenu() {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [infoPage, setInfoPage] = useState(0);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    switch (e.key) {
      case 'ArrowUp':
        setSelectedIndex((p) => (p - 1 + MENU_ITEMS.length) % MENU_ITEMS.length);
        e.preventDefault(); break;
      case 'ArrowDown':
        setSelectedIndex((p) => (p + 1) % MENU_ITEMS.length);
        e.preventDefault(); break;
      case 'ArrowLeft':
        setInfoPage((p) => (p - 1 + INFO_PAGES.length) % INFO_PAGES.length);
        e.preventDefault(); break;
      case 'ArrowRight':
        setInfoPage((p) => (p + 1) % INFO_PAGES.length);
        e.preventDefault(); break;
    }
  };

  return (
    <div style={{
      display: 'flex', justifyContent: 'center', alignItems: 'center',
      height: '100%', background: '#0a0a1a',
    }}>
      <div
        tabIndex={0}
        onKeyDown={handleKeyDown}
        style={{
          width: VIEWPORT_W, height: VIEWPORT_H,
          position: 'relative', overflow: 'hidden', outline: 'none',
          // Simulated game background
          background: 'linear-gradient(160deg, #1a2a3a 0%, #2a3a4a 30%, #1a2a3a 60%, #0a1a2a 100%)',
        }}
      >
        {/* Fake ground plane */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0, height: 360,
          background: 'linear-gradient(to bottom, rgba(40,50,60,0.3), rgba(60,70,50,0.5))',
        }} />

        {/* ── Z-INDEX 1: L-shaped backdrop (3 pieces, border on outside only) ── */}
        {/* Left strip — border-right, stops above the bottom panel */}
        <div style={{
          position: 'absolute', zIndex: 1,
          top: 0, left: 0,
          width: LEFT_PANEL_W,
          height: VIEWPORT_H - BOTTOM_PANEL_H,
          background: C.backdropBg,
          borderRight: `1.5px solid ${C.backdropBorder}`,
        }} />
        {/* Bottom strip — border-top, starts after the left panel */}
        <div style={{
          position: 'absolute', zIndex: 1,
          bottom: 0, left: LEFT_PANEL_W,
          right: 0,
          height: BOTTOM_PANEL_H,
          background: C.backdropBg,
          borderTop: `1.5px solid ${C.backdropBorder}`,
        }} />
        {/* Corner fill — no border, covers the bottom-left gap */}
        <div style={{
          position: 'absolute', zIndex: 1,
          bottom: 0, left: 0,
          width: LEFT_PANEL_W,
          height: BOTTOM_PANEL_H,
          background: C.backdropBg,
        }} />

        {/* ── Z-INDEX 2: Menu elements on top of backdrop ──────── */}
        {/* Left column: status + menu + description */}
        <div style={{
          position: 'absolute', zIndex: 2,
          top: PANEL_PAD, left: PANEL_PAD,
          width: LEFT_PANEL_W - PANEL_PAD * 2,
          display: 'flex', flexDirection: 'column', gap: 10,
        }}>
          <CharacterStatus />
          <MenuList selectedIndex={selectedIndex} onSelect={setSelectedIndex} />
          <DescriptionBox text={MENU_ITEMS[selectedIndex].description} />
        </div>

        {/* Bottom: info panel — right side of bottom strip with margins */}
        <div style={{
          position: 'absolute', zIndex: 2,
          bottom: 5,
          right: 30,
          top: VIEWPORT_H - BOTTOM_PANEL_H + 5,
          width: 440,
        }}>
          <InfoPanel
            page={infoPage}
            totalPages={INFO_PAGES.length}
            onPrev={() => setInfoPage((p) => (p - 1 + INFO_PAGES.length) % INFO_PAGES.length)}
            onNext={() => setInfoPage((p) => (p + 1) % INFO_PAGES.length)}
          />
        </div>

        {/* Control hints */}
        <div style={{
          position: 'absolute', zIndex: 2,
          bottom: 8, left: LEFT_PANEL_W + 16,
          fontSize: 11, fontFamily: 'monospace',
          color: 'rgba(180,200,230,0.5)',
          display: 'flex', gap: 16,
        }}>
          <span>↑↓ Navigate</span>
          <span>←→ Info Pages</span>
        </div>
      </div>
    </div>
  );
}
