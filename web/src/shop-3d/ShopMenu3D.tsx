// ShopMenu3D — the browsable fixture for the 3D immersive shop menus.
//
// Concept: rather than cutting to a flat 2D sprite menu, the shop keeps the
// player in the world — the camera frames the shopkeeper NPC and PSZ-styled UI
// is drawn on top. This page lets you flip through every shop AND every layout
// "variation" (camera shot + overlay treatment) side by side, so the different
// approaches can be compared before one is chosen to build in Godot.
//
// URL: /psz-godot/#/shop-3d/:shopId   (defaults to the first shop)
import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import ShopScene from './ShopScene';
import { SHOPS, shopById } from './shopData';
import { VARIATIONS } from './variations';

const BAR_BG = '#12122a';
const BAR_BORDER = '#2a2a4a';

function chip(active: boolean, accentHex?: string) {
  return {
    padding: '5px 12px', fontSize: 12, borderRadius: 5, cursor: 'pointer',
    border: `1px solid ${active ? (accentHex ?? '#f0a020') : BAR_BORDER}`,
    background: active ? (accentHex ? `${accentHex}22` : 'rgba(240,160,30,0.18)') : '#1b1b34',
    color: active ? '#fff' : '#9aa4c0', whiteSpace: 'nowrap' as const, fontWeight: 600,
  };
}

export default function ShopMenu3D() {
  const { shopId } = useParams();
  const navigate = useNavigate();
  const shop = shopById(shopId) ?? SHOPS[0];
  const accentHex = `#${shop.accent.toString(16).padStart(6, '0')}`;

  const [variIdx, setVariIdx] = useState(0);
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);

  // Reset selection when the shop changes.
  useEffect(() => { setTab(0); setSel(0); }, [shop.id]);

  const variation = VARIATIONS[variIdx];
  const Overlay = variation.Overlay;

  // Remount the 3D stage on shop/variation change so the camera preset and model
  // reload cleanly.
  const sceneKey = `${shop.id}-${variation.id}`;
  const preset = useMemo(() => ({ ...variation.preset }), [variation]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#05070d' }}>
      {/* Dev toolbar (not part of the game UI) */}
      <div style={{
        display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10,
        padding: '8px 12px', background: BAR_BG, borderBottom: `1px solid ${BAR_BORDER}`,
      }}>
        <span style={{ fontSize: 11, color: '#6b7590', textTransform: 'uppercase', letterSpacing: 1 }}>Shop</span>
        <div style={{ display: 'flex', gap: 5, overflowX: 'auto', maxWidth: '100%' }}>
          {SHOPS.map((s) => (
            <button key={s.id} onClick={() => navigate(`/shop-3d/${s.id}`)} style={chip(s.id === shop.id, `#${s.accent.toString(16).padStart(6, '0')}`)}>
              {s.label}
            </button>
          ))}
        </div>
        <span style={{ width: 1, height: 20, background: BAR_BORDER, margin: '0 2px' }} />
        <span style={{ fontSize: 11, color: '#6b7590', textTransform: 'uppercase', letterSpacing: 1 }}>Style</span>
        <div style={{ display: 'flex', gap: 5 }}>
          {VARIATIONS.map((v, i) => (
            <button key={v.id} onClick={() => setVariIdx(i)} style={chip(i === variIdx)} title={v.blurb}>
              {v.label}
            </button>
          ))}
        </div>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: '#7c86a2', maxWidth: 360, textAlign: 'right' }}>{variation.blurb}</span>
      </div>

      {/* The stage: 3D shopkeeper behind, PSZ UI overlay in front */}
      <div style={{ position: 'relative', flex: 1, minHeight: 0, overflow: 'hidden' }}>
        <ShopScene
          key={sceneKey}
          modelUrl={shop.npc.model}
          texUrl={shop.npc.tex}
          idleClip={shop.npc.idle}
          accent={shop.accent}
          preset={preset}
        />
        <Overlay shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} />
        {/* accent hairline at the very bottom, ties overlay to the shop colour */}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, background: accentHex, opacity: 0.7, pointerEvents: 'none' }} />
      </div>
    </div>
  );
}
