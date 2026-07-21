// Variation A — "Side Stage": the classic JRPG merchant framing. The camera sits
// to the shopkeeper's left and pushes them into the right third of frame; all UI
// lives in a left column (wallet strip, list panel, detail card). Reads as
// "shop menu on the left, merchant standing to the right."
import { WalletHeader, ItemList, DetailCard, SpeechBubble, currentItems } from '../parts';
import type { Variation, VariationCtx } from './types';

function Overlay({ shop, tab, setTab, sel, setSel }: VariationCtx) {
  const item = currentItems(shop, tab)[sel];
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <div style={{ position: 'absolute', top: 20, left: 28, pointerEvents: 'auto' }}>
        <WalletHeader meseta={shop.meseta} photons={shop.currency === 'photon' || shop.id === 'synth' ? shop.photons : undefined} style={{ width: 360 }} />
      </div>

      <div style={{
        position: 'absolute', top: 78, left: 28, bottom: 24,
        display: 'flex', gap: 14, alignItems: 'flex-start', pointerEvents: 'auto',
      }}>
        <ItemList shop={shop} tab={tab} setTab={setTab} sel={sel} setSel={setSel}
          hint={shop.hint} maxListHeight={430} width={368} />
        <DetailCard shop={shop} item={item} width={300} />
      </div>

      <div style={{ position: 'absolute', top: 34, right: 30, maxWidth: 300, pointerEvents: 'auto' }}>
        <SpeechBubble text={shop.blurb} accent={shop.accent} pointer="none" />
      </div>
    </div>
  );
}

export const SideStage: Variation = {
  id: 'side',
  label: 'A · Side Stage',
  blurb: 'Merchant framed right, menu column on the left — the classic JRPG shop shot.',
  talkCam: { azimuthDeg: -18, distance: 4.2, height: 2.0, lookHeight: 1.25, lateralShift: 0.2, fov: 46 },
  Overlay,
};
