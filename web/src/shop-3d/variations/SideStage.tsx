// Variation A — "Side Stage": camera directly in front of the shopkeeper (who
// stays put), NPC parked on the right, and the menu on the left as a tall LIST
// panel (~90% height) with the INFO panel to its right (~40% height). The
// baseline glass-panel treatment.
import { ShopColumns, SpeechBubble } from '../parts';
import type { Variation, VariationCtx } from './types';

export const HEADON: Variation['talkCam'] = { azimuthDeg: 0, distance: 4.3, height: 2.05, lookHeight: 1.3, lateralShift: 0.24, fov: 42 };

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <ShopColumns shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} variant="glass" />
      <div style={{ position: 'absolute', top: 34, right: 30, maxWidth: 300, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>
    </div>
  );
}

export const SideStage: Variation = {
  id: 'side',
  label: 'A · Side Stage',
  blurb: 'Head-on shopkeeper on the right; tall list + info panel on the left. Glass panels.',
  talkCam: HEADON,
  Overlay,
};
