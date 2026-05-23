import type { ClassInfo } from '../character-creator/data/classData';

export type VariantId =
  | 'pso-list'
  | 'matrix'
  | 'carousel'
  | 'slats'
  | 'slats-light'
  | 'slats-sky'
  | 'slats-steel'
  | 'slats-psz'
  | 'cards'
  | 'type-first';

export const TYPE_COLORS: Record<string, string> = {
  Hunter: '#ff6b6b',
  Ranger: '#51cf66',
  Force: '#6b8afd',
};

export const STAT_MAX = 180;

export type StatBarProps = {
  label: string;
  value: number;
  color: string;
  textColor?: string;
  trackColor?: string;
  width?: number;
};

export function statBarSegments(value: number, max = STAT_MAX, slots = 10): number {
  return Math.max(0, Math.min(slots, Math.round((value / max) * slots)));
}

export type VariantProps = {
  classes: ClassInfo[];
  selectedId: string;
  onSelect: (id: string) => void;
};
