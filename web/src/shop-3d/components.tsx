// Shared PSZ-styled overlay widgets for the 3D shop menus. These mirror the
// flat mocks in storybook/MenuDesign.tsx (Panel / PillRow / TabBar / …) but are
// tuned for drawing ON TOP of a live 3D scene: translucent "glass" bodies, so
// the shopkeeper stays visible behind the UI. The variation layouts compose
// these; the palette lives in ./theme.
import type { CSSProperties, ReactNode } from 'react';
import { C, SCANLINES, glassPanelBg } from './theme';

export function Panel({
  title, children, width, hint, style, glass = true, bodyStyle,
}: {
  title?: string;
  children: ReactNode;
  width?: number | string;
  hint?: string;
  style?: CSSProperties;
  glass?: boolean;
  bodyStyle?: CSSProperties;
}) {
  return (
    <div style={{
      width: width || '100%',
      display: 'flex', flexDirection: 'column',
      filter: 'drop-shadow(0 3px 12px rgba(0,0,0,0.45))',
      ...style,
    }}>
      {title && (
        <div style={{ position: 'relative', height: 36, marginBottom: -1 }}>
          <div style={{
            position: 'absolute', inset: 0, background: C.bgDark,
            clipPath: 'polygon(0 0, 85% 0, 80% 100%, 0 100%)',
          }} />
          <div style={{
            position: 'absolute', top: 0, right: 0, bottom: 0, width: '30%',
            background: `linear-gradient(135deg, transparent 30%, ${C.bgDarker} 30%, ${C.bgDarker} 35%, ${C.bgDark} 35%)`,
          }} />
          <div style={{
            position: 'relative', padding: '6px 16px',
            fontSize: 16, fontWeight: 800, color: C.textWhite,
            fontStyle: 'italic', letterSpacing: 0.5,
            textShadow: '1px 1px 0 rgba(0,0,0,0.5)', zIndex: 1,
          }}>{title}</div>
        </div>
      )}
      <div style={{
        flex: 1,
        background: glass ? glassPanelBg(0.8) : C.bgLight,
        backgroundImage: SCANLINES,
        backdropFilter: glass ? 'blur(2px)' : undefined,
        borderTop: `2px solid ${C.bgDark}`,
        borderBottom: hint ? 'none' : `2px solid ${C.separator}`,
        padding: 8,
        ...bodyStyle,
      }}>
        {children}
      </div>
      {hint && (
        <div style={{
          background: C.hintBg, backgroundImage: SCANLINES,
          border: `1px solid ${C.hintBorder}`, borderRadius: '0 0 20px 20px',
          padding: '8px 20px', fontSize: 14, color: C.text,
          marginTop: 8, textAlign: 'center',
        }}>{hint}</div>
      )}
    </div>
  );
}

export function PillRow({
  label, selected, rightText, sub, onClick, rarity,
}: {
  label: string;
  selected?: boolean;
  rightText?: string;
  sub?: string;
  onClick?: () => void;
  rarity?: 'rare' | 'common';
}) {
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        padding: '7px 14px', marginBottom: 3,
        background: selected ? C.selectedGradient : C.itemBg,
        borderRadius: 3,
        border: selected ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
        cursor: 'pointer', fontSize: 14, fontWeight: 600,
        color: rarity === 'rare' ? C.rare : C.text,
        transition: 'background 0.1s ease',
      }}
    >
      <span style={{ display: 'flex', flexDirection: 'column' }}>
        <span>{label}</span>
        {sub && <span style={{ fontSize: 10, color: C.textLight, fontWeight: 500 }}>{sub}</span>}
      </span>
      {rightText && <span style={{ fontSize: 12, color: selected ? C.textOnSelected : C.textLight, fontWeight: 700 }}>{rightText}</span>}
    </div>
  );
}

export function TabBar({ tabs, active, onSelect, style }: {
  tabs: string[]; active: number; onSelect: (i: number) => void; style?: CSSProperties;
}) {
  return (
    <div style={{ display: 'flex', gap: 3, marginBottom: 8, ...style }}>
      {tabs.map((tab, i) => (
        <button key={tab} onClick={() => onSelect(i)} style={{
          padding: '5px 14px', fontSize: 12, fontWeight: 700,
          background: active === i ? C.selectedGradient : C.itemBg, color: C.text,
          border: active === i ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
          borderRadius: 4, cursor: 'pointer',
        }}>{tab}</button>
      ))}
    </div>
  );
}

export function Divider() {
  return <div style={{ height: 2, background: C.separator, margin: '6px 0', opacity: 0.5 }} />;
}

export function StatRow({ k, v, accent }: { k: string; v: string; accent?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
      <span style={{ color: C.textLight }}>{k}</span>
      <span style={{ fontWeight: 700, color: accent ?? C.text }}>{v}</span>
    </div>
  );
}

// The small "Kion · Lv.42 · 12,450 MST" identity strip most shops show.
export function WalletHeader({ meseta, photons, style }: {
  meseta: number; photons?: number; style?: CSSProperties;
}) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      background: glassPanelBg(0.72), backgroundImage: SCANLINES,
      border: `2px solid ${C.separator}`, borderRadius: 6,
      padding: '6px 14px', fontSize: 13, color: C.text,
      filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.4))',
      ...style,
    }}>
      <span style={{ fontWeight: 800, fontStyle: 'italic' }}>Kion <span style={{ fontWeight: 600, fontStyle: 'normal', color: C.textLight, fontSize: 11 }}>Lv.42 HUmar</span></span>
      <span style={{ marginLeft: 'auto', display: 'flex', gap: 12 }}>
        <span><span style={{ color: C.textLight }}>MST </span><b style={{ color: C.meseta }}>{meseta.toLocaleString()}</b></span>
        {photons != null && <span><span style={{ color: C.textLight }}>PD </span><b style={{ color: C.photon }}>{photons}</b></span>}
      </span>
    </div>
  );
}

// A big diegetic "Confirm" action button (buy / grind / accept).
export function ActionButton({ label, onClick, style }: {
  label: string; onClick?: () => void; style?: CSSProperties;
}) {
  return (
    <div onClick={onClick} style={{
      padding: '9px 14px', fontSize: 14, fontWeight: 700,
      background: C.selectedGradient, border: '2px solid #d08010',
      borderRadius: 5, color: C.textOnSelected, cursor: 'pointer', textAlign: 'center',
      boxShadow: '0 2px 6px rgba(0,0,0,0.3)', ...style,
    }}>{label}</div>
  );
}
