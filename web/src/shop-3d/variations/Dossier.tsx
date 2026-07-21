// Variation D — "Solid": same head-on / NPC-right / list-left layout, but with
// opaque (non-glass) panels and a hard accent outline — the densest, most
// readable "PC-terminal" treatment.
import { ShopColumns, SpeechBubble } from '../parts';
import { HEADON } from './SideStage';
import type { Variation, VariationCtx } from './types';

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <ShopColumns shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel} variant="solid" />
      <div style={{ position: 'absolute', top: 34, right: 30, maxWidth: 300, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>
    </div>
  );
}

export const Dossier: Variation = {
  id: 'solid',
  label: 'D · Solid',
  blurb: 'Same layout with opaque panels and a hard accent outline — max legibility.',
  talkCam: HEADON,
  Overlay,
};
