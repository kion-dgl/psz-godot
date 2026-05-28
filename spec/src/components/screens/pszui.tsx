import type { ReactNode, CSSProperties } from 'react';

export const C = {
  bgLight: '#a8cce8',
  bgMid: '#8ab8d8',
  bgDark: '#2a3448',
  bgDarker: '#1e2838',
  itemBg: 'rgba(255,255,255,0.85)',
  itemBgHover: 'rgba(255,255,255,0.95)',
  selectedGradient: 'linear-gradient(90deg, #f0a020 0%, #f8c840 100%)',
  text: '#1a1a2a',
  textLight: '#3a4a5a',
  textWhite: '#ffffff',
  textOnSelected: '#1a1a2a',
  hintBg: 'rgba(255,255,255,0.7)',
  hintBorder: '#8aa8c8',
  separator: '#7aa0c0',
  hp: '#44bb44',
  hpBg: '#d8e8d8',
  pp: '#4488ee',
  ppBg: '#d8d8f0',
  rare: '#cc2222',
  common: '#1a1a2a',
};

export const SCANLINES = `repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(120,160,200,0.08) 2px,rgba(120,160,200,0.08) 4px)`;

export function Panel({ title, children, width, hint, style }: {
  title?: string; children: ReactNode; width?: number | string; hint?: string; style?: CSSProperties;
}) {
  return (
    <div style={{ width: width || '100%', display: 'flex', flexDirection: 'column', filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.25))', ...style }}>
      {title && (
        <div style={{ position: 'relative', height: 36, marginBottom: -1 }}>
          <div style={{ position: 'absolute', inset: 0, background: C.bgDark, clipPath: 'polygon(0 0, 85% 0, 80% 100%, 0 100%)' }} />
          <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: '30%', background: `linear-gradient(135deg, transparent 30%, ${C.bgDarker} 30%, ${C.bgDarker} 35%, ${C.bgDark} 35%)` }} />
          <div style={{ position: 'relative', padding: '6px 16px', fontSize: 16, fontWeight: 800, color: C.textWhite, fontStyle: 'italic', letterSpacing: 0.5, textShadow: '1px 1px 0 rgba(0,0,0,0.5)', zIndex: 1 }}>{title}</div>
        </div>
      )}
      <div style={{ flex: 1, background: C.bgLight, backgroundImage: SCANLINES, borderTop: `2px solid ${C.bgDark}`, borderBottom: hint ? 'none' : `2px solid ${C.separator}`, padding: 8 }}>{children}</div>
      {hint && (
        <div style={{ background: C.hintBg, backgroundImage: SCANLINES, border: `1px solid ${C.hintBorder}`, borderRadius: '0 0 20px 20px', padding: '8px 20px', fontSize: 14, color: C.text, marginTop: 8, textAlign: 'center' }}>{hint}</div>
      )}
    </div>
  );
}

export function PillRow({ label, selected, rightText, onClick }: {
  label: string; selected?: boolean; rightText?: string; onClick?: () => void;
}) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '7px 14px', marginBottom: 3,
      background: selected ? C.selectedGradient : C.itemBg,
      borderRadius: 3, border: selected ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
      cursor: 'pointer', fontSize: 14, fontWeight: 600, color: C.text,
    }}>
      <span>{label}</span>
      {rightText && <span style={{ fontSize: 12, color: C.textLight }}>{rightText}</span>}
    </div>
  );
}

export function TabBar({ tabs, active, onSelect }: {
  tabs: string[]; active: number; onSelect: (i: number) => void;
}) {
  return (
    <div style={{ display: 'flex', gap: 3, marginBottom: 8 }}>
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

export function ShopFrame({ children }: { children: ReactNode }) {
  return (
    <div style={{
      width: 960, height: 540, background: C.bgLight, backgroundImage: SCANLINES,
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12,
      padding: 24, boxSizing: 'border-box',
    }}>
      {children}
    </div>
  );
}
