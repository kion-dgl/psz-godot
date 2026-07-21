import { SideStage } from './SideStage';
import { LowerThird } from './LowerThird';
import { HoloCounter } from './HoloCounter';
import { Dossier } from './Dossier';
import type { Variation } from './types';

export const VARIATIONS: Variation[] = [SideStage, LowerThird, HoloCounter, Dossier];
export type { Variation, VariationCtx } from './types';
