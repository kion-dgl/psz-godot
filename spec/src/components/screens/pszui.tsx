import type { ReactNode, CSSProperties } from 'react';
import { assetUrl } from '../../utils/assets';

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

export function PillRow({ label, selected, rightText, tag, muted, onClick }: {
  label: string; selected?: boolean; rightText?: string;
  tag?: { text: string; color: string }; muted?: boolean; onClick?: () => void;
}) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6,
      padding: '7px 14px', marginBottom: 3,
      background: selected ? C.selectedGradient : C.itemBg,
      borderRadius: 3, border: selected ? '2px solid #d08010' : '1px solid rgba(150,180,210,0.4)',
      cursor: 'pointer', fontSize: 14, fontWeight: 600,
      color: muted ? 'rgba(26,26,42,0.45)' : C.text,
      opacity: muted ? 0.85 : 1,
    }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
        {tag && (
          <span style={{
            fontSize: 9, fontWeight: 700, letterSpacing: '0.05em',
            color: tag.color, border: `1px solid ${tag.color}`,
            borderRadius: 3, padding: '0 4px', flexShrink: 0,
          }}>{tag.text}</span>
        )}
      </span>
      {rightText && <span style={{ fontSize: 12, color: muted ? 'rgba(26,26,42,0.4)' : C.textLight, flexShrink: 0 }}>{rightText}</span>}
    </div>
  );
}

// Balance line shown at the bottom of a shop's left panel (Meseta, Photon Drops…)
export function Balance({ label, value, color = '#886600' }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, color: C.text, padding: '2px 4px' }}>
      <span>{label}</span><span style={{ fontWeight: 700, color }}>{value}</span>
    </div>
  );
}

// Single labelled stat row used in detail panels.
export function StatRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
      <span style={{ color: C.textLight }}>{label}</span>
      <span style={{ fontWeight: 700, color: color ?? C.text }}>{value}</span>
    </div>
  );
}

// Orange CTA button used in detail panels (Identify, Grind, Accept, Exchange…).
export function ActionButton({ label }: { label: string }) {
  return (
    <div style={{
      marginTop: 10, padding: 7, fontSize: 13, fontWeight: 600,
      background: C.selectedGradient, border: '2px solid #d08010',
      borderRadius: 4, color: C.text, cursor: 'pointer', textAlign: 'center',
    }}>{label}</div>
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

// Standard shop layout: list panel fills the left 75%, the right column
// stacks the highlighted-item info (top) over the shop-keeper portrait
// (bottom). Portrait images live at assets/ui/shop-previews/<portrait>.png
// (256x256, served via the /cdn R2 proxy).
export function ShopScreen({ title, hint, portrait, info, infoTitle = 'Detail', children }: {
  title: string;
  hint?: string;
  portrait: string;
  info: ReactNode;
  infoTitle?: string;
  children: ReactNode;
}) {
  // Right column (~40%): info panel fills the top, shop-keeper portrait sits
  // flush at the bottom (flex pushes it down). No border on the portrait.
  return (
    <div style={{
      width: 960, height: 540, background: C.bgLight, backgroundImage: SCANLINES,
      display: 'flex', gap: 10, padding: 16, boxSizing: 'border-box',
    }}>
      {/* Left — the shop list */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex' }}>
        <Panel title={title} hint={hint} style={{ width: '100%', height: '100%' }}>
          <div style={{ height: '100%', overflowY: 'auto' }}>{children}</div>
        </Panel>
      </div>

      {/* Right — info (fills) over portrait (bottom-aligned) */}
      <div style={{ flex: '0 0 38%', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
          <Panel title={infoTitle} style={{ width: '100%', height: '100%' }}>
            <div style={{ height: '100%', overflowY: 'auto' }}>{info}</div>
          </Panel>
        </div>
        <img
          src={assetUrl(`assets/ui/shop-previews/${portrait}.png`)}
          alt="shop keeper"
          style={{
            width: '100%', aspectRatio: '1 / 1', objectFit: 'cover',
            display: 'block', imageRendering: 'pixelated', flexShrink: 0,
          }}
        />
      </div>
    </div>
  );
}
