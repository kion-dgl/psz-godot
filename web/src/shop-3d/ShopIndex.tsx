// Landing grid for the 3D shop-menu experiments — one card per shop, each a live
// thumbnail of its shopkeeper. Click through to browse that shop across all four
// layout variations.
import { Link } from 'react-router-dom';
import { SHOPS } from './shopData';
import { C, SCANLINES, FONT } from './theme';

export default function ShopIndex() {
  return (
    <div style={{
      height: '100%', overflowY: 'auto', padding: '28px 32px',
      background: 'linear-gradient(180deg, #0a0e1a 0%, #05070d 100%)', color: '#e6edf3', fontFamily: FONT,
    }}>
      <h1 style={{ margin: '0 0 4px', fontSize: 24, fontWeight: 800, fontStyle: 'italic' }}>3D Shop Menus</h1>
      <p style={{ margin: '0 0 22px', fontSize: 14, color: '#8b97b4', maxWidth: 720, lineHeight: 1.5 }}>
        Immersive shop menus that keep the player in the world: the camera frames the shopkeeper NPC and
        PSZ-styled UI draws on top, instead of cutting to a flat 2D sprite menu. Pick a shop, then flip
        through the four layout variations (Side Stage · Lower Third · Holo Counter · Dossier).
      </p>

      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))', gap: 16,
      }}>
        {SHOPS.map((s) => {
          const hex = `#${s.accent.toString(16).padStart(6, '0')}`;
          return (
            <Link key={s.id} to={`/shop-3d/${s.id}`} style={{ textDecoration: 'none' }}>
              <div style={{
                borderRadius: 10, overflow: 'hidden', border: `1px solid ${BAR(hex)}`,
                background: `radial-gradient(120% 90% at 50% 0%, ${hex}33 0%, rgba(10,14,26,0.6) 60%)`,
                boxShadow: `0 0 0 1px rgba(255,255,255,0.03), 0 8px 24px rgba(0,0,0,0.5)`,
                transition: 'transform 0.12s ease',
              }}>
                <ShopThumb accent={hex} title={s.title} />
                <div style={{ padding: '12px 14px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ width: 10, height: 10, borderRadius: 5, background: hex }} />
                    <span style={{ fontSize: 15, fontWeight: 700, color: '#fff' }}>{s.label}</span>
                  </div>
                  <div style={{ fontSize: 12, color: '#8b97b4', marginTop: 6, lineHeight: 1.4 }}>{s.blurb}</div>
                  <div style={{ fontSize: 11, color: hex, marginTop: 8, fontWeight: 600 }}>
                    {s.currency === 'photon' ? 'Photon Drops' : s.currency === 'none' ? 'Quests' : 'Meseta'}
                    {' · '}{s.tabs.filter((t) => t.label).length || 1} view{(s.tabs.filter((t) => t.label).length || 1) > 1 ? 's' : ''}
                  </div>
                </div>
              </div>
            </Link>
          );
        })}
      </div>

      <div style={{ marginTop: 26, fontSize: 12, color: '#5f6a86' }}>
        Built with three.js. UI palette mirrors the flat mocks in <code style={{ color: '#8b97b4' }}>storybook/MenuDesign</code> and{' '}
        <code style={{ color: '#8b97b4' }}>scripts/ui/psz_style.gd</code>.
      </div>
    </div>
  );
}

function BAR(hex: string) { return `${hex}55`; }

// A lightweight non-WebGL card header — a stylised silhouette plaque so the grid
// stays cheap (no seven live canvases). The real NPC renders on the detail page.
function ShopThumb({ accent, title }: { accent: string; title: string }) {
  return (
    <div style={{
      height: 118, position: 'relative',
      background: `linear-gradient(180deg, ${accent}22 0%, rgba(5,7,13,0.9) 100%)`,
      backgroundImage: `${SCANLINES}`,
      display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
    }}>
      <div style={{
        width: 46, height: 78, borderRadius: '23px 23px 6px 6px',
        background: `linear-gradient(180deg, ${accent} 0%, ${accent}55 100%)`,
        marginBottom: -1, filter: 'blur(0.4px)', opacity: 0.85,
      }} />
      <div style={{
        position: 'absolute', top: 10, left: 12,
        fontSize: 11, fontWeight: 800, fontStyle: 'italic', color: C.textWhite,
        background: C.bgDark, padding: '3px 10px', borderRadius: 3, opacity: 0.9,
      }}>{title}</div>
    </div>
  );
}
