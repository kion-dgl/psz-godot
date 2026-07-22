// Variation B — "Vignette": same head-on / NPC-right / list-left layout, but a
// soft left vignette darkens the scene behind the panels for a visual-novel feel
// and stronger menu legibility.
import { ShopColumns, SpeechBubble } from '../parts';
import { HEADON } from './SideStage';
import type { Variation, VariationCtx } from './types';

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <ShopColumns shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} variant="vignette" />
      <div style={{ position: 'absolute', top: 34, right: 30, maxWidth: 300, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>
    </div>
  );
}

export const LowerThird: Variation = {
  id: 'vignette',
  label: 'B · Vignette',
  blurb: 'Same layout with a soft left vignette behind the panels — VN legibility.',
  talkCam: HEADON,
  Overlay,
};
