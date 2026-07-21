import type { FC } from 'react';
import type { FramePreset } from '../ShopScene';
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
  preset: FramePreset;
  Overlay: FC<VariationCtx>;
}
