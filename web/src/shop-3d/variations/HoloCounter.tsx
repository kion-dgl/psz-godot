// Variation C — "Holo Panels": same head-on / NPC-right / list-left layout, but
// the panels read as glowing holographic projections (accent-lit borders).
import { ShopColumns, SpeechBubble } from '../parts';
import { HEADON } from './SideStage';
import type { Variation, VariationCtx } from './types';

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <ShopColumns shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} variant="holo" />
      <div style={{ position: 'absolute', top: 34, right: 30, maxWidth: 300, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>
    </div>
  );
}

export const HoloCounter: Variation = {
  id: 'holo',
  label: 'C · Holo Panels',
  blurb: 'Same layout with glowing holographic panels projected in front of the player.',
  talkCam: HEADON,
  Overlay,
};
