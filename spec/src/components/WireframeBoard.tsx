import { useEffect, useRef, useState } from 'react';

const CARD_W = 160;
const CARD_H = 100;
const TITLE_H = 22;

type ThumbKind =
  | 'splash'
  | 'loader'
  | 'modal'
  | 'title'
  | 'list-preview'    // char select: list left, preview right
  | 'slats'           // horizontal slats
  | 'panel-preview'   // customize: panel left, preview right
  | 'city'            // 3D area placeholder
  | 'shop'            // panel + detail
  | 'menu'            // in-game start/pause menu
  | 'stage';          // field area placeholder

type Node = {
  id: string;
  x: number;
  y: number;
  title: string;
  href: string;
  thumb: ThumbKind;
  group?: string;
};

type Edge = { from: string; to: string; label?: string; dashed?: boolean };

type Group = { id: string; x: number; y: number; w: number; h: number; label: string };

type Header = { x: number; y: number; label: string };

// Field stages. Most share the A → E (transition) → B → Z (boss) structure;
// Eternal Tower is the odd one out — entrance, floors, transition, boss.
type StageDef = { id: string; label: string; areas: { key: string; label: string }[] };
const ABEZ = [
  { key: 'a', label: 'A' },
  { key: 'e', label: 'E' },
  { key: 'b', label: 'B' },
  { key: 'z', label: 'Z' },
];
const STAGES: StageDef[] = [
  { id: 'valley',    label: 'Valley',    areas: ABEZ },
  { id: 'wetlands',  label: 'Wetlands',  areas: ABEZ },
  { id: 'snowfield', label: 'Snowfield', areas: ABEZ },
  { id: 'ruins',     label: 'Ruins',     areas: ABEZ },
  { id: 'paru',      label: 'Paru',      areas: ABEZ },
  { id: 'arca',      label: 'Arca',      areas: ABEZ },
  { id: 'shrine',    label: 'Shrine',    areas: ABEZ },
  { id: 'tower',     label: 'Eternal Tower', areas: [
    { key: 'entrance',   label: 'Entrance' },
    { key: 'floors',     label: 'Floors' },
    { key: 'transition', label: 'Transition' },
    { key: 'boss',       label: 'Boss' },
  ] },
];
const COLUMN_HEADERS = ['Area A', 'Area E · transition', 'Area B', 'Area Z · boss'];
const STAGE_X0 = 1720;
const STAGE_Y0 = 280;
const STAGE_COL = 200;
const STAGE_ROW = 135;

const NODES: Node[] = [
  // Journey row (Controls Setup raised 50px so the Download→Title skip line is clear)
  { id: 'splash',    x: 40,   y: 40,  title: 'Splash',           href: '/journey/splash',           thumb: 'splash' },
  { id: 'download',  x: 240,  y: 40,  title: 'Download',         href: '/journey/download',         thumb: 'loader' },
  { id: 'controls',  x: 440,  y: -30, title: 'Controls Setup',   href: '/journey/controls',         thumb: 'modal' },
  { id: 'title',     x: 640,  y: 40,  title: 'Title Screen',     href: '/journey/title',            thumb: 'title' },
  { id: 'charsel',   x: 840,  y: 40,  title: 'Character Select', href: '/journey/character-select', thumb: 'list-preview' },
  { id: 'create',    x: 1040, y: 40,  title: 'Create Character', href: '/journey/create-character', thumb: 'slats' },
  { id: 'customize', x: 1240, y: 40,  title: 'Customize',        href: '/journey/character-customize', thumb: 'panel-preview' },

  // In-game start menu — "Return to Title" routes back to the title screen
  { id: 'start-menu', x: 640, y: 240, title: 'Start Menu', href: '/start-menu', thumb: 'menu' },

  // City area
  { id: 'office',     x: 1180, y: 260, title: "Principal's Office", href: '/journey/city/office',     thumb: 'city', group: 'city' },
  { id: 'counter',    x: 1180, y: 420, title: 'Guild Counter',       href: '/journey/city/counter',    thumb: 'city', group: 'city' },
  { id: 'teleport',   x: 1400, y: 420, title: 'Teleport',            href: '/journey/city/teleport',   thumb: 'city', group: 'city' },
  { id: 'market',     x: 960,  y: 420, title: 'Market',              href: '/journey/city/market',     thumb: 'city', group: 'city' },
  { id: 'underground',x: 960,  y: 580, title: 'Underground',         href: '/journey/city/underground',thumb: 'city', group: 'city' },

  // Shops (Market area) — left of the city cluster
  { id: 'weapon-shop',  x: 700, y: 400, title: 'Weapon Shop',  href: '/shop/weapon-shop', thumb: 'shop', group: 'market-shops' },
  { id: 'item-shop',    x: 700, y: 540, title: 'Item Shop',    href: '/shop/item-shop',   thumb: 'shop', group: 'market-shops' },
  { id: 'tekker',       x: 480, y: 470, title: 'Tekker',       href: '/shop/tekker',      thumb: 'shop', group: 'market-shops' },

  // Bottom row — service counters lined up under the sewer:
  // Photon Collector, Synthesis Shop, Item Storage, Quest Counter
  { id: 'photon',       x: 700,  y: 760, title: 'Photon Collector', href: '/shop/photon-shop',   thumb: 'shop', group: 'underground-shops' },
  { id: 'crafting',     x: 920,  y: 760, title: 'Synthesis Shop',   href: '/shop/crafting-shop', thumb: 'shop', group: 'underground-shops' },
  { id: 'storage',      x: 1180, y: 760, title: 'Item Storage',     href: '/shop/storage',       thumb: 'shop', group: 'counter-shops' },
  { id: 'quest-counter',x: 1400, y: 760, title: 'Quest Counter',    href: '/shop/quest-counter', thumb: 'shop', group: 'counter-shops' },

  // Field stages — grid right of Teleport: 4 columns per stage row
  ...STAGES.flatMap((stage, row) =>
    stage.areas.map((area, col) => ({
      id: `field-${stage.id}-${area.key}`,
      x: STAGE_X0 + col * STAGE_COL,
      y: STAGE_Y0 + row * STAGE_ROW,
      title: `${stage.label} · ${area.label}`,
      href: `/journey/field/${stage.id}/${area.key}`,
      thumb: 'stage' as ThumbKind,
      group: 'field-stages',
    }))
  ),
];

const EDGES: Edge[] = [
  // Journey flow
  { from: 'splash', to: 'download' },
  { from: 'download', to: 'controls', label: 'first run' },
  { from: 'controls', to: 'title' },
  { from: 'download', to: 'title', label: 'subsequent', dashed: true },
  { from: 'title', to: 'charsel' },
  { from: 'charsel', to: 'create', label: 'empty slot' },
  { from: 'create', to: 'customize' },
  { from: 'customize', to: 'office', label: 'intro' },
  { from: 'charsel', to: 'market', label: 'existing' },

  // City connections (bidirectional approximated as single arrows for clarity)
  { from: 'office', to: 'counter' },
  { from: 'counter', to: 'market' },
  { from: 'counter', to: 'teleport' },
  { from: 'market', to: 'underground' },

  // Shop entries
  { from: 'market', to: 'weapon-shop', dashed: true },
  { from: 'market', to: 'item-shop', dashed: true },
  { from: 'market', to: 'tekker', dashed: true },
  { from: 'counter', to: 'quest-counter', dashed: true },
  { from: 'counter', to: 'storage', dashed: true },
  { from: 'underground', to: 'crafting', dashed: true },
  { from: 'underground', to: 'photon', dashed: true },

  // In-game start menu returns to title
  { from: 'start-menu', to: 'title', label: 'Return to Title', dashed: true },

  // Teleport warps to the first area of each stage
  ...STAGES.map((stage) => ({
    from: 'teleport',
    to: `field-${stage.id}-${stage.areas[0].key}`,
    dashed: true,
  })),

  // Intra-stage progression: column 0 → 1 → 2 → 3
  ...STAGES.flatMap((stage) =>
    stage.areas.slice(0, -1).map((area, i) => ({
      from: `field-${stage.id}-${area.key}`,
      to: `field-${stage.id}-${stage.areas[i + 1].key}`,
    }))
  ),
];

const GROUPS: Group[] = [
  { id: 'city',              x: 920,  y: 240, w: 660, h: 440, label: 'City' },
  { id: 'market-shops',      x: 460,  y: 380, w: 400, h: 320, label: 'Market Shops' },
  { id: 'underground-shops', x: 680,  y: 740, w: 400, h: 120, label: 'Underground Shops' },
  { id: 'counter-shops',     x: 1160, y: 740, w: 400, h: 120, label: 'Counter Shops' },
  {
    id: 'field-stages',
    x: STAGE_X0 - 20,
    y: STAGE_Y0 - 60,
    w: STAGE_COL * 4 + CARD_W - STAGE_COL + 40,
    h: STAGE_ROW * STAGES.length + 60,
    label: 'Field Stages',
  },
];

// Column headers above the field-stages grid.
const STAGE_HEADERS: Header[] = COLUMN_HEADERS.map((label, col) => ({
  x: STAGE_X0 + col * STAGE_COL,
  y: STAGE_Y0 - 36,
  label,
}));

function Thumb({ kind }: { kind: ThumbKind }) {
  const w = CARD_W - 8, h = CARD_H - 8;
  switch (kind) {
    case 'splash':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#000" />
          <rect x={w * 0.3} y={h * 0.35} width={w * 0.4} height={h * 0.3} fill="#fbba18" rx="2" />
        </svg>
      );
    case 'loader':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#2563eb" />
          <rect x="0" y="0" width={w} height="12" fill="#fef9c3" opacity="0.6" />
          <circle cx={w / 2} cy={h / 2 - 6} r="10" fill="none" stroke="#fde047" strokeWidth="2" />
          <rect x="10" y={h - 22} width={w - 20} height="6" fill="rgba(0,0,0,0.3)" rx="3" />
          <rect x="10" y={h - 22} width={(w - 20) * 0.55} height="6" fill="#fde047" rx="3" />
        </svg>
      );
    case 'modal':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#091a29" />
          <rect x={w * 0.15} y={h * 0.2} width={w * 0.7} height={h * 0.6} fill="#1e2838" stroke="#f8c840" rx="3" />
          <rect x={w * 0.25} y={h * 0.35} width={w * 0.5} height="6" fill="#fff" opacity="0.8" />
          <rect x={w * 0.3} y={h * 0.5} width={w * 0.4} height="4" fill="#aab" />
        </svg>
      );
    case 'title':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <defs>
            <linearGradient id="titleBg" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#1a2240" />
              <stop offset="100%" stopColor="#050917" />
            </linearGradient>
          </defs>
          <rect x="0" y="0" width={w} height={h} fill="url(#titleBg)" />
          <circle cx={w * 0.7} cy={h * 0.35} r="6" fill="#bfd0ff" opacity="0.5" />
          <rect x={w * 0.2} y={h * 0.18} width={w * 0.6} height={h * 0.25} fill="#fbba18" rx="2" opacity="0.85" />
          <rect x={w * 0.3} y={h - 24} width={w * 0.4} height="6" fill="#fde047" />
          <rect x={w * 0.4} y={h - 12} width={w * 0.2} height="4" fill="#888" />
        </svg>
      );
    case 'list-preview':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#a8cce8" />
          <rect x="0" y="0" width={w} height="10" fill="#fbba18" />
          <rect x="8" y="18" width={w * 0.4} height={h - 26} fill="#fff" opacity="0.85" rx="2" />
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x="12" y={24 + i * 14} width={w * 0.35} height="8" fill={i === 0 ? '#f0a020' : '#e0e8f0'} rx="1" />
          ))}
          <rect x={w * 0.5} y="18" width={w * 0.45} height={h - 26} fill="rgba(180,200,220,0.5)" rx="2" />
        </svg>
      );
    case 'slats':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#a8cce8" />
          <rect x="0" y="0" width={w} height="6" fill="#f8c840" />
          <rect x="0" y="6" width={w} height="14" fill="#2a3448" />
          {Array.from({ length: 9 }).map((_, i) => (
            <rect key={i} x={i * (w / 9)} y={22} width={w / 9 - 1} height={h - 22}
              fill={i === 4 ? '#2a3448' : 'rgba(120,160,200,0.3)'}
              stroke={i === 4 ? '#f0a020' : 'none'} strokeWidth="1" />
          ))}
        </svg>
      );
    case 'panel-preview':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#a8cce8" />
          <rect x="0" y="0" width={w} height="8" fill="#f8c840" />
          <rect x="0" y="8" width={w} height="14" fill="#2a3448" />
          <rect x="6" y="28" width={w * 0.4} height={h - 36} fill="rgba(220,230,240,0.9)" rx="2" />
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x="10" y={36 + i * 12} width={w * 0.35} height="8" fill={i === 0 ? '#f0a020' : '#d0d8e0'} rx="1" />
          ))}
          <rect x={w * 0.5} y="28" width={w * 0.45} height={h - 36} fill="rgba(150,180,210,0.4)" rx="2" />
        </svg>
      );
    case 'city':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#1a1a2a" />
          <path d={`M 0 ${h * 0.7} L ${w} ${h * 0.7} L ${w} ${h} L 0 ${h} Z`} fill="#8899aa" />
          <rect x={w * 0.4} y={h * 0.5} width={w * 0.2} height={h * 0.2} fill="#445566" />
          <circle cx={w / 2} cy={h * 0.55} r="4" fill="#44cc44" />
          <ellipse cx={w / 2} cy={h * 0.7} rx="5" ry="2" fill="#44cc44" opacity="0.5" />
        </svg>
      );
    case 'shop':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#a8cce8" />
          <rect x="6" y="6" width={w * 0.55} height={h - 12} fill="rgba(255,255,255,0.85)" stroke="#2a3448" strokeWidth="1.5" rx="2" />
          <rect x="6" y="6" width={w * 0.4} height="10" fill="#2a3448" />
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x="10" y={22 + i * 10} width={w * 0.47} height="7" fill={i === 0 ? '#f0a020' : '#e0e8f0'} rx="1" />
          ))}
          <rect x={w * 0.65} y="6" width={w * 0.3} height={h - 12} fill="rgba(255,255,255,0.85)" stroke="#2a3448" strokeWidth="1.5" rx="2" />
          <rect x={w * 0.65} y="6" width={w * 0.22} height="10" fill="#2a3448" />
          <rect x={w * 0.68} y="22" width={w * 0.24} height="6" fill="#1a1a2a" opacity="0.4" />
          <rect x={w * 0.68} y="32" width={w * 0.24} height="4" fill="#1a1a2a" opacity="0.3" />
        </svg>
      );
    case 'menu':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <rect x="0" y="0" width={w} height={h} fill="#0d1117" />
          <rect x={w * 0.18} y={h * 0.12} width={w * 0.64} height={h * 0.76} fill="#161b22" stroke="#30363d" rx="3" />
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x={w * 0.24} y={h * 0.22 + i * (h * 0.16)} width={w * 0.52} height={h * 0.1}
              fill={i === 3 ? '#f0a020' : '#21262d'} rx="1" />
          ))}
        </svg>
      );
    case 'stage':
      return (
        <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: '100%' }}>
          <defs>
            <linearGradient id="stageSky" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#243b55" />
              <stop offset="100%" stopColor="#101820" />
            </linearGradient>
          </defs>
          <rect x="0" y="0" width={w} height={h} fill="url(#stageSky)" />
          <path d={`M 0 ${h * 0.62} L ${w * 0.4} ${h * 0.5} L ${w * 0.7} ${h * 0.66} L ${w} ${h * 0.55} L ${w} ${h} L 0 ${h} Z`} fill="#3a4a3a" />
          <path d={`M 0 ${h * 0.78} L ${w} ${h * 0.72} L ${w} ${h} L 0 ${h} Z`} fill="#2a3a2a" />
          <circle cx={w * 0.35} cy={h * 0.84} r="2.5" fill="#cc4444" />
          <circle cx={w * 0.6} cy={h * 0.8} r="2.5" fill="#cc4444" />
          <circle cx={w * 0.5} cy={h * 0.7} r="3" fill="#44cc44" />
        </svg>
      );
  }
}

function arrowPath(from: { x: number; y: number }, to: { x: number; y: number }): string {
  // Center-to-center, but with simple right-angle elbow when separated mostly vertically.
  const fx = from.x + CARD_W / 2;
  const fy = from.y + CARD_H / 2;
  const tx = to.x + CARD_W / 2;
  const ty = to.y + CARD_H / 2;
  const dx = tx - fx;
  const dy = ty - fy;
  // Stop short of the target so the arrowhead doesn't overlap the card
  const len = Math.sqrt(dx * dx + dy * dy);
  const inset = 50;
  const t = Math.max(0, (len - inset) / len);
  const endX = fx + dx * t;
  const endY = fy + dy * t;
  return `M ${fx} ${fy} L ${endX} ${endY}`;
}

export default function WireframeBoard() {
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [scale, setScale] = useState(0.55);
  const [dragging, setDragging] = useState(false);
  const startRef = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const boardW = 2540;
    const boardH = 1400;
    const fit = () => {
      const cw = el.clientWidth;
      const ch = el.clientHeight;
      if (cw <= 0 || ch <= 0) return false;
      const s = Math.min(cw / boardW, ch / boardH, 1);
      setScale(s);
      setPan({
        x: (cw - boardW * s) / 2,
        y: (ch - boardH * s) / 2 + 10,
      });
      return true;
    };
    // Retry on the next frame if the canvas hasn't been laid out yet
    // (client:only islands can mount before flexbox resolves heights).
    if (!fit()) {
      requestAnimationFrame(() => { fit(); });
    }
  }, []);

  const onMouseDown = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('a')) return;
    setDragging(true);
    startRef.current = { x: e.clientX, y: e.clientY, panX: pan.x, panY: pan.y };
  };

  const onMouseMove = (e: React.MouseEvent) => {
    if (!dragging || !startRef.current) return;
    setPan({
      x: startRef.current.panX + (e.clientX - startRef.current.x),
      y: startRef.current.panY + (e.clientY - startRef.current.y),
    });
  };

  const stop = () => {
    setDragging(false);
    startRef.current = null;
  };

  const onWheel = (e: React.WheelEvent) => {
    const delta = -e.deltaY * 0.001;
    setScale((s) => Math.max(0.3, Math.min(2, s + delta)));
  };

  return (
    <div
      ref={containerRef}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={stop}
      onMouseLeave={stop}
      onWheel={onWheel}
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        background: '#010409',
        backgroundImage: 'radial-gradient(circle, #1f2937 1px, transparent 1px)',
        backgroundSize: '24px 24px',
        cursor: dragging ? 'grabbing' : 'grab',
        overflow: 'hidden',
        userSelect: 'none',
      }}
    >
      <div style={{
        position: 'absolute',
        transform: `translate(${pan.x}px, ${pan.y}px) scale(${scale})`,
        transformOrigin: '0 0',
      }}>
        {/* Group containers (drawn under cards) */}
        {GROUPS.map(g => (
          <div key={g.id} style={{
            position: 'absolute',
            left: g.x,
            top: g.y,
            width: g.w,
            height: g.h,
            border: '1px dashed rgba(139,148,158,0.3)',
            borderRadius: 6,
            background: 'rgba(22,27,34,0.4)',
          }}>
            <div style={{
              position: 'absolute',
              top: -10,
              left: 12,
              padding: '0 6px',
              fontSize: 10,
              color: '#8b949e',
              background: '#010409',
              textTransform: 'uppercase',
              letterSpacing: '0.1em',
            }}>{g.label}</div>
          </div>
        ))}

        {/* Field-stage column headers */}
        {STAGE_HEADERS.map((hd, i) => (
          <div key={i} style={{
            position: 'absolute',
            left: hd.x,
            top: hd.y,
            width: CARD_W,
            textAlign: 'center',
            fontSize: 11,
            fontWeight: 700,
            color: '#8b949e',
            textTransform: 'uppercase',
            letterSpacing: '0.08em',
          }}>{hd.label}</div>
        ))}

        {/* Arrows */}
        <svg style={{ position: 'absolute', left: 0, top: 0, width: 2800, height: 1500, pointerEvents: 'none', overflow: 'visible' }}>
          <defs>
            <marker id="arrowhead" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
              <path d="M0,0 L0,6 L9,3 z" fill="#58a6ff" />
            </marker>
            <marker id="arrowhead-dim" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
              <path d="M0,0 L0,6 L9,3 z" fill="#8b949e" />
            </marker>
          </defs>
          {EDGES.map((e, i) => {
            const from = NODES.find(n => n.id === e.from);
            const to = NODES.find(n => n.id === e.to);
            if (!from || !to) return null;
            const d = arrowPath(from, to);
            const fx = from.x + CARD_W / 2;
            const fy = from.y + CARD_H / 2;
            const tx = to.x + CARD_W / 2;
            const ty = to.y + CARD_H / 2;
            const mx = (fx + tx) / 2;
            const my = (fy + ty) / 2;
            return (
              <g key={i}>
                <path
                  d={d}
                  fill="none"
                  stroke={e.dashed ? '#8b949e' : '#58a6ff'}
                  strokeWidth="1.5"
                  strokeDasharray={e.dashed ? '4 4' : undefined}
                  markerEnd={`url(#${e.dashed ? 'arrowhead-dim' : 'arrowhead'})`}
                  opacity={e.dashed ? 0.5 : 0.8}
                />
                {e.label && (
                  <text x={mx} y={my - 4} fill="#8b949e" fontSize="9" textAnchor="middle" style={{ paintOrder: 'stroke', stroke: '#010409', strokeWidth: 3 }}>
                    {e.label}
                  </text>
                )}
              </g>
            );
          })}
        </svg>

        {/* Cards */}
        {NODES.map(n => (
          <a
            key={n.id}
            href={n.href}
            style={{
              position: 'absolute',
              left: n.x,
              top: n.y,
              width: CARD_W,
              height: CARD_H + TITLE_H,
              textDecoration: 'none',
              display: 'block',
            }}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div style={{
              width: CARD_W,
              height: CARD_H,
              background: '#0d1117',
              border: '1px solid #30363d',
              borderRadius: 4,
              overflow: 'hidden',
              transition: 'border-color 0.15s, transform 0.15s',
            }}
              className="wire-thumb"
            >
              <Thumb kind={n.thumb} />
            </div>
            <div style={{
              fontSize: 11,
              color: '#c9d1d9',
              textAlign: 'center',
              marginTop: 4,
              fontFamily: 'system-ui, sans-serif',
            }}>
              {n.title}
            </div>
          </a>
        ))}
      </div>

      {/* Help overlay */}
      <div style={{
        position: 'absolute',
        bottom: 12,
        right: 12,
        padding: '6px 10px',
        background: 'rgba(13,17,23,0.85)',
        border: '1px solid #30363d',
        borderRadius: 4,
        color: '#8b949e',
        fontSize: 11,
        fontFamily: 'system-ui, sans-serif',
        pointerEvents: 'none',
      }}>
        Drag to pan · Scroll to zoom · Click to open
      </div>

      <style>{`
        .wire-thumb:hover { border-color: #58a6ff !important; }
      `}</style>
    </div>
  );
}
