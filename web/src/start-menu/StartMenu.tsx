import { useState } from 'react';

/**
 * PSO-style start menu mock — fixed 1280x720 viewport.
 * Layout reference: PSO Episode I&II (GameCube)
 * Theme: PSZ blue/silver with octagon pattern
 *
 * Left side:  Character status (top), menu list (middle), description (bottom)
 * Right side: Info panel (bottom) with L/R page tabs
 * Background: Semi-transparent — game world visible behind
 */

// ── Theme colors ───────────────────────────────────────────────────────────────
const C = {
  // Panel backgrounds
  panelBg: 'rgba(20, 30, 60, 0.88)',
  panelBorder: 'rgba(100, 140, 200, 0.5)',
  panelHighlight: 'rgba(130, 170, 220, 0.15)',

  // Text
  textPrimary: '#e8eaf0',
  textSecondary: '#8899bb',
  textMuted: '#556688',

  // Selection
  selectBg: '#d08020',
  selectText: '#fff',

  // HP/PP bars
  hpGreen: '#30cc50',
  ppBlue: '#3088ee',

  // Decorative
  borderLight: 'rgba(140, 180, 230, 0.35)',
  borderAccent: 'rgba(100, 160, 240, 0.6)',
  patternColor: 'rgba(80, 120, 180, 0.06)',
};

// ── Data types ─────────────────────────────────────────────────────────────────
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

// ── Octagon pattern SVG ────────────────────────────────────────────────────────
function OctagonPattern() {
  // Subtle repeating octagon grid for panel backgrounds
  const size = 24;
  const r = 10;
  const cx = size / 2;
  const cy = size / 2;
  // Approximate octagon vertices
  const d = r * 0.383; // sin(22.5deg) * r
  const a = r * 0.924; // cos(22.5deg) * r
  const pts = [
    [cx + d, cy - a], [cx + a, cy - d],
    [cx + a, cy + d], [cx + d, cy + a],
    [cx - d, cy + a], [cx - a, cy + d],
    [cx - a, cy - d], [cx - d, cy - a],
  ].map(([x, y]) => `${x},${y}`).join(' ');

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><polygon points="${pts}" fill="none" stroke="rgba(100,150,220,0.08)" stroke-width="0.5"/></svg>`;
  const encoded = btoa(svg);
  return (
    <div style={{
      position: 'absolute',
      inset: 0,
      backgroundImage: `url("data:image/svg+xml;base64,${encoded}")`,
      backgroundRepeat: 'repeat',
      pointerEvents: 'none',
    }} />
  );
}

// ── Panel wrapper ──────────────────────────────────────────────────────────────
function Panel({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div style={{
      position: 'relative',
      background: C.panelBg,
      border: `1.5px solid ${C.panelBorder}`,
      borderRadius: 4,
      overflow: 'hidden',
      ...style,
    }}>
      <OctagonPattern />
      {/* Top highlight line */}
      <div style={{
        position: 'absolute',
        top: 0,
        left: 4,
        right: 4,
        height: 1,
        background: `linear-gradient(90deg, transparent, ${C.borderAccent}, transparent)`,
      }} />
      <div style={{ position: 'relative', zIndex: 1 }}>
        {children}
      </div>
    </div>
  );
}

// ── Character status bar (top-left) ────────────────────────────────────────────
function CharacterStatus() {
  const hp = 85;
  const pp = 100;

  return (
    <Panel style={{ padding: '8px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        {/* Section ID icon placeholder */}
        <div style={{
          width: 16, height: 16,
          borderRadius: 8,
          background: '#e04040',
          border: '1px solid #ff6666',
          flexShrink: 0,
        }} />
        <span style={{
          color: C.textPrimary,
          fontSize: 16,
          fontWeight: 600,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        }}>
          Flauros
        </span>
      </div>
      {/* HP bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
        <span style={{ color: C.textSecondary, fontSize: 10, fontFamily: 'monospace', width: 18 }}>HP</span>
        <div style={{ flex: 1, height: 8, background: 'rgba(0,0,0,0.4)', borderRadius: 2, overflow: 'hidden' }}>
          <div style={{ width: `${hp}%`, height: '100%', background: `linear-gradient(to right, #208830, ${C.hpGreen})`, borderRadius: 2 }} />
        </div>
      </div>
      {/* PP bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ color: C.textSecondary, fontSize: 10, fontFamily: 'monospace', width: 18 }}>PP</span>
        <div style={{ flex: 1, height: 8, background: 'rgba(0,0,0,0.4)', borderRadius: 2, overflow: 'hidden' }}>
          <div style={{ width: `${pp}%`, height: '100%', background: `linear-gradient(to right, #2060aa, ${C.ppBlue})`, borderRadius: 2 }} />
        </div>
      </div>
    </Panel>
  );
}

// ── Menu list (left side) ──────────────────────────────────────────────────────
function MenuList({ selectedIndex, onSelect }: { selectedIndex: number; onSelect: (i: number) => void }) {
  return (
    <Panel style={{ padding: '4px 0' }}>
      {MENU_ITEMS.map((item, i) => {
        const isSelected = i === selectedIndex;
        return (
          <div
            key={item.label}
            onClick={() => onSelect(i)}
            style={{
              padding: '8px 16px',
              cursor: 'pointer',
              background: isSelected ? C.selectBg : 'transparent',
              color: isSelected ? C.selectText : C.textPrimary,
              fontSize: 18,
              fontFamily: 'monospace',
              fontWeight: isSelected ? 700 : 400,
              letterSpacing: 1,
              transition: 'background 0.1s',
            }}
          >
            {item.label}
          </div>
        );
      })}
    </Panel>
  );
}

// ── Description box (bottom-left) ──────────────────────────────────────────────
function DescriptionBox({ text }: { text: string }) {
  return (
    <Panel style={{ padding: '10px 14px', minHeight: 44 }}>
      <span style={{
        color: C.textPrimary,
        fontSize: 16,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
      }}>
        {text}
      </span>
    </Panel>
  );
}

// ── Info panel with pages (bottom-right) ───────────────────────────────────────
function InfoPanel({ page, totalPages, onPrev, onNext }: {
  page: number;
  totalPages: number;
  onPrev: () => void;
  onNext: () => void;
}) {
  const info = INFO_PAGES[page];

  return (
    <Panel style={{ padding: 0 }}>
      {/* Page selector bar */}
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        gap: 8,
        padding: '6px 0',
        borderBottom: `1px solid ${C.borderLight}`,
      }}>
        <span
          onClick={onPrev}
          style={{ color: '#40cc60', fontSize: 16, cursor: 'pointer', userSelect: 'none', fontFamily: 'monospace' }}
        >
          ◀
        </span>
        <span style={{
          color: C.textPrimary,
          fontSize: 13,
          fontFamily: 'monospace',
          background: 'rgba(60, 90, 140, 0.4)',
          padding: '2px 10px',
          borderRadius: 3,
          border: `1px solid ${C.borderLight}`,
        }}>
          L {page + 1}/{totalPages} R
        </span>
        <span
          onClick={onNext}
          style={{ color: '#40cc60', fontSize: 16, cursor: 'pointer', userSelect: 'none', fontFamily: 'monospace' }}
        >
          ▶
        </span>
      </div>
      {/* Info rows */}
      <div style={{ padding: '8px 16px' }}>
        {info.rows.map((row) => (
          <div key={row.label} style={{
            display: 'flex',
            justifyContent: 'space-between',
            padding: '4px 0',
            fontFamily: 'monospace',
            fontSize: 16,
          }}>
            <span style={{ color: C.textSecondary }}>{row.label}</span>
            <span style={{ color: C.textPrimary, fontWeight: 600, textAlign: 'right' }}>{row.value}</span>
          </div>
        ))}
      </div>
    </Panel>
  );
}

// ── Main Start Menu component ──────────────────────────────────────────────────
export default function StartMenu() {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [infoPage, setInfoPage] = useState(0);

  // Keyboard navigation
  const handleKeyDown = (e: React.KeyboardEvent) => {
    switch (e.key) {
      case 'ArrowUp':
        setSelectedIndex((prev) => (prev - 1 + MENU_ITEMS.length) % MENU_ITEMS.length);
        e.preventDefault();
        break;
      case 'ArrowDown':
        setSelectedIndex((prev) => (prev + 1) % MENU_ITEMS.length);
        e.preventDefault();
        break;
      case 'ArrowLeft':
      case 'q':
        setInfoPage((prev) => (prev - 1 + INFO_PAGES.length) % INFO_PAGES.length);
        e.preventDefault();
        break;
      case 'ArrowRight':
      case 'e':
        setInfoPage((prev) => (prev + 1) % INFO_PAGES.length);
        e.preventDefault();
        break;
    }
  };

  return (
    <div style={{
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      height: '100%',
      background: '#0a0a1a',
    }}>
      <div
        tabIndex={0}
        onKeyDown={handleKeyDown}
        style={{
          width: 1280,
          height: 720,
          position: 'relative',
          overflow: 'hidden',
          outline: 'none',
          // Simulated game background — gradient placeholder
          background: 'linear-gradient(135deg, #1a2a3a 0%, #2a3a4a 30%, #1a2a3a 60%, #0a1a2a 100%)',
        }}
      >
        {/* Fake game world hint — ground plane */}
        <div style={{
          position: 'absolute',
          bottom: 0,
          left: 0,
          right: 0,
          height: 360,
          background: 'linear-gradient(to bottom, rgba(40, 50, 60, 0.3), rgba(60, 70, 50, 0.5))',
        }} />

        {/* ── LEFT COLUMN ─────────────────────────────────────── */}
        <div style={{
          position: 'absolute',
          top: 20,
          left: 20,
          width: 210,
          display: 'flex',
          flexDirection: 'column',
          gap: 10,
        }}>
          {/* Character status */}
          <CharacterStatus />

          {/* Menu list */}
          <MenuList selectedIndex={selectedIndex} onSelect={setSelectedIndex} />

          {/* Description */}
          <DescriptionBox text={MENU_ITEMS[selectedIndex].description} />
        </div>

        {/* ── BOTTOM-RIGHT INFO PANEL ─────────────────────────── */}
        <div style={{
          position: 'absolute',
          bottom: 20,
          right: 20,
          width: 440,
        }}>
          <InfoPanel
            page={infoPage}
            totalPages={INFO_PAGES.length}
            onPrev={() => setInfoPage((p) => (p - 1 + INFO_PAGES.length) % INFO_PAGES.length)}
            onNext={() => setInfoPage((p) => (p + 1) % INFO_PAGES.length)}
          />
        </div>

        {/* ── CONTROL HINTS ───────────────────────────────────── */}
        <div style={{
          position: 'absolute',
          bottom: 8,
          left: '50%',
          transform: 'translateX(-50%)',
          display: 'flex',
          gap: 20,
          fontSize: 11,
          fontFamily: 'monospace',
          color: 'rgba(180, 200, 230, 0.5)',
        }}>
          <span>Arrow Up/Down: Navigate</span>
          <span>Arrow Left/Right: Info Pages</span>
          <span>Enter: Select</span>
          <span>Esc: Close</span>
        </div>
      </div>
    </div>
  );
}
