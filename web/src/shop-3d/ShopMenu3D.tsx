// ShopMenu3D — browsable fixture for the 3D immersive shop menus.
//
// The shop keeps the player in the world: the real Godot city location is
// rendered, the shopkeeper stands at its in-game spot, and the intended flow is
// demonstrable — walk up (follow cam) → interact (camera snaps to a fixed shop
// angle, menu overlays) → close (camera returns to follow). The player can be
// ghosted/hidden when it obstructs the clerk. Everything renders at the game's
// native 1280×720, scaled to fit the screen.
//
// URL: /psz-godot/#/shop-3d/:shopId
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import ShopStage, { type CamMode } from './ShopStage';
import { SHOPS, shopById } from './shopData';
import { VARIATIONS } from './variations';
import { FONT } from './theme';

const BAR_BG = '#12122a';
const BAR_BORDER = '#2a2a4a';
const VIEW_W = 1280, VIEW_H = 720;

const OPACITY_MODES = [
  { key: 'solid', label: 'Solid', op: 1 },
  { key: 'ghost', label: 'Ghost', op: 0.28 },
  { key: 'hidden', label: 'Hidden', op: 0 },
] as const;

function chip(active: boolean, accentHex?: string) {
  return {
    padding: '5px 12px', fontSize: 12, borderRadius: 5, cursor: 'pointer',
    border: `1px solid ${active ? (accentHex ?? '#f0a020') : BAR_BORDER}`,
    background: active ? (accentHex ? `${accentHex}22` : 'rgba(240,160,30,0.18)') : '#1b1b34',
    color: active ? '#fff' : '#9aa4c0', whiteSpace: 'nowrap' as const, fontWeight: 600,
  };
}

// Scale the fixed 1280×720 frame to fit whatever space is available (letterbox),
// like the game viewport.
function useFitScale(outerRef: React.RefObject<HTMLDivElement | null>) {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const el = outerRef.current;
    if (!el) return;
    const update = () => {
      const w = el.clientWidth, h = el.clientHeight;
      if (!w || !h) return;
      setScale(Math.min(w / VIEW_W, h / VIEW_H));
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [outerRef]);
  return scale;
}

export default function ShopMenu3D() {
  const { shopId } = useParams();
  const navigate = useNavigate();
  const shop = shopById(shopId) ?? SHOPS[0];
  const accentHex = `#${shop.accent.toString(16).padStart(6, '0')}`;

  const [variIdx, setVariIdx] = useState(0);
  const [tab, setTab] = useState(0);
  const [sel, setSel] = useState(0);
  const [mode, setMode] = useState<CamMode>('talk');
  const [opacityKey, setOpacityKey] = useState<(typeof OPACITY_MODES)[number]['key']>('solid');

  useEffect(() => { setTab(0); setSel(0); }, [shop.id]);

  const variation = VARIATIONS[variIdx];
  const Overlay = variation.Overlay;
  const talking = mode === 'talk';
  const opacity = OPACITY_MODES.find((o) => o.key === opacityKey)!.op;

  const outerRef = useRef<HTMLDivElement>(null);
  const scale = useFitScale(outerRef);

  // Rebuild the stage only when the shop changes; style/mode/opacity ride refs.
  const stageKey = shop.id;
  const talkCam = useMemo(() => ({ ...variation.talkCam }), [variation]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#05070d', fontFamily: FONT }}>
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
            <button key={v.id} onClick={() => setVariIdx(i)} style={chip(i === variIdx)} title={v.blurb}>{v.label}</button>
          ))}
        </div>
        <span style={{ width: 1, height: 20, background: BAR_BORDER, margin: '0 2px' }} />
        {/* Approach / Close toggles the follow<->talk camera */}
        <button onClick={() => setMode(talking ? 'follow' : 'talk')} style={chip(talking, accentHex)}>
          {talking ? '✕ Close (→ follow)' : '▶ Approach (→ talk)'}
        </button>
        <span style={{ fontSize: 11, color: '#6b7590', textTransform: 'uppercase', letterSpacing: 1 }}>Player</span>
        <div style={{ display: 'flex', gap: 5 }}>
          {OPACITY_MODES.map((o) => (
            <button key={o.key} onClick={() => setOpacityKey(o.key)} style={chip(o.key === opacityKey)}>{o.label}</button>
          ))}
        </div>
      </div>

      {/* Letterboxed 1280×720 game frame */}
      <div ref={outerRef} style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
        <div style={{ width: VIEW_W, height: VIEW_H, transform: `scale(${scale})`, transformOrigin: 'center', position: 'relative', flex: 'none', boxShadow: '0 0 0 1px #1c2233', overflow: 'hidden' }}>
          <ShopStage key={stageKey} area={shop.area} npc={shop.npc} accent={shop.accent} talkCam={talkCam} mode={mode} playerOpacity={opacity} />

          {/* Menu overlay only while talking */}
          {talking && <Overlay shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} />}

          {/* Follow-mode interaction prompt */}
          {!talking && (
            <div
              onClick={() => setMode('talk')}
              style={{
                position: 'absolute', left: '50%', bottom: 70, transform: 'translateX(-50%)',
                display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer',
                background: 'rgba(10,14,26,0.72)', border: `2px solid ${accentHex}`, borderRadius: 10,
                padding: '10px 18px', color: '#fff', fontSize: 16, fontWeight: 700,
                boxShadow: '0 4px 16px rgba(0,0,0,0.5)',
              }}>
              <span style={{
                background: accentHex, color: '#05070d', borderRadius: 6, width: 26, height: 26,
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800,
              }}>A</span>
              Talk to {shop.title}
            </div>
          )}

          {/* accent hairline */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 2, background: accentHex, opacity: 0.7, pointerEvents: 'none' }} />
          <span style={{ position: 'absolute', top: 8, left: 12, fontSize: 11, color: 'rgba(230,237,243,0.5)', pointerEvents: 'none' }}>1280×720</span>
        </div>
      </div>
    </div>
  );
}
