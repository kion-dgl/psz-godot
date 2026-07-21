// Variation C — "Holo Counter": you're standing at the shop counter. The camera
// sits low and looks slightly UP at the clerk across a physical counter slab
// (drawn in the 3D scene), and the menu is projected as free-floating
// "holographic" panels with an accent glow — as if the counter is emitting them.
// Diegetic UI: the panels feel like part of the world, not a flat overlay.
import type { ReactNode } from 'react';
import { FONT } from '../theme';
import { WalletHeader, ItemList, DetailCard, SpeechBubble, currentItems } from '../parts';
import type { Variation, VariationCtx } from './types';

function Holo({ accent, children, style }: { accent: number; children: ReactNode; style?: React.CSSProperties }) {
  const hex = `#${accent.toString(16).padStart(6, '0')}`;
  return (
    <div style={{
      borderRadius: 8,
      boxShadow: `0 0 0 1px ${hex}, 0 0 22px -2px ${hex}, 0 10px 30px rgba(0,0,0,0.5)`,
      ...style,
    }}>
      {children}
    </div>
  );
}

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  const item = currentItems(shop, tab)[sel];
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', fontFamily: FONT }}>
      {/* Holo wallet chip, top-left */}
      <div style={{ position: 'absolute', top: 20, left: 26, pointerEvents: 'auto' }}>
        <Holo accent={shop.accent}>
          <WalletHeader meseta={shop.meseta} photons={shop.currency === 'photon' || shop.id === 'synth' ? shop.photons : undefined} style={{ width: 320 }} />
        </Holo>
      </div>

      {/* Clerk greeting, upper-centre */}
      <div style={{ position: 'absolute', top: 26, right: 40, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>

      {/* Floating detail panel — left, projected off the counter */}
      <div style={{ position: 'absolute', left: 40, bottom: 34, width: 292, pointerEvents: 'auto' }}>
        <Holo accent={shop.accent}>
          <DetailCard shop={shop} item={item} />
        </Holo>
      </div>

      {/* Floating list panel — right of centre */}
      <div style={{ position: 'absolute', right: 44, bottom: 34, width: 380, pointerEvents: 'auto' }}>
        <Holo accent={shop.accent}>
          <ItemList shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel}
            hint={shop.hint} maxListHeight={280} />
        </Holo>
      </div>
    </div>
  );
}

export const HoloCounter: Variation = {
  id: 'holo',
  label: 'C · Holo Counter',
  blurb: 'At the counter, looking up at the clerk; the menu floats as glowing holographic panels.',
  preset: { azimuthDeg: 10, elevationDeg: -3, distanceMul: 2.5, targetYFrac: 0.62, lateralShift: 0.06, counter: true, fov: 38 },
  Overlay,
};
