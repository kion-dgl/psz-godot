// Variation B — "Lower Third": visual-novel framing. The shopkeeper is centred
// and shot slightly from below the waist up, with a greeting bubble floating by
// their head; the whole menu docks into a translucent lower-third bar so the top
// two-thirds of the screen stays the live character. Most immersive of the set.
import { FONT } from '../theme';
import { WalletHeader, ItemList, DetailCard, SpeechBubble, currentItems } from '../parts';
import type { Variation, VariationCtx } from './types';

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  const item = currentItems(shop, tab)[sel];
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', fontFamily: FONT }}>
      {/* Top-right wallet */}
      <div style={{ position: 'absolute', top: 18, right: 24, pointerEvents: 'auto' }}>
        <WalletHeader meseta={shop.meseta} photons={shop.currency === 'photon' || shop.id === 'synth' ? shop.photons : undefined} style={{ width: 320 }} />
      </div>

      {/* Greeting bubble up by the NPC's head */}
      <div style={{ position: 'absolute', top: 60, left: '50%', transform: 'translateX(-30%)', pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="bottom" />
      </div>

      {/* Docked lower-third menu bar */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: 340,
        background: `linear-gradient(180deg, rgba(10,14,26,0) 0%, rgba(10,14,26,0.55) 22%, rgba(10,14,26,0.78) 100%)`,
        pointerEvents: 'none',
      }} />
      <div style={{
        position: 'absolute', left: 24, right: 24, bottom: 16, height: 296,
        display: 'flex', gap: 16, alignItems: 'stretch', pointerEvents: 'auto',
      }}>
        <div style={{ flex: '0 0 46%', display: 'flex', flexDirection: 'column' }}>
          <ItemList shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel}
            hint={shop.hint} maxListHeight={172} />
        </div>
        <div style={{ flex: 1 }}>
          <DetailCard shop={shop} item={item} title="Detail" />
        </div>
      </div>
    </div>
  );
}

export const LowerThird: Variation = {
  id: 'lower',
  label: 'B · Lower Third',
  blurb: 'Visual-novel framing: centred merchant, greeting bubble, menu docked into the lower third.',
  talkCam: { azimuthDeg: 0, distance: 3.5, height: 1.85, lookHeight: 1.2, lateralShift: 0, fov: 42 },
  Overlay,
};
