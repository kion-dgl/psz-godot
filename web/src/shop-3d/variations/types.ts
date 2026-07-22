import type { FC } from 'react';
import type { TalkCam } from '../ShopStage';
import type { ShopDef } from '../shopData';

export interface VariationCtx {
  shop: ShopDef;
  tab: number; setTab: (i: number) => void;
  sel: number; setSel: (i: number) => void;
}

export interface Variation {
  id: string;
  label: string;      // short name in the style switcher
  blurb: string;      // one-line description of the treatment
  talkCam: TalkCam;   // the fixed shop-interaction camera for this style
  Overlay: FC<VariationCtx>;
}
