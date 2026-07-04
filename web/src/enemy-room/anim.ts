/**
 * Clip-token resolution — mirror of enemy_base.gd `_find_animation` +
 * `ANIM_ALIASES` + `_find_attack_clip_fallback`. The resolution order is
 * normative (spec /states/enemies "Attack recovery") and MUST stay
 * identical between this tool and the Godot runtime.
 */

export interface NamedClip {
  name: string;
}

/** enemy_base.gd ANIM_ALIASES — keep in sync. */
export const ANIM_ALIASES: Record<string, string[]> = {
  wat: ['stt'], // wait/idle → standing
  wlk: ['fly', 'wlk_l'], // walk → fly (airborne) / left-variant (Godot alternates wlk_l/wlk_r)
  run: ['fly', 'wlk_l'],
  atk: ['atk1', 'atckwat'], // attack → variant 1 / orangutan's misspelled clip (#477)
};

/** Strip the rig prefix ("s_001_", "m051_", "z003_"…) → the Godot resolver token. */
export function clipToken(clipName: string): string {
  return clipName.replace(/^[a-z]{1,2}_?\d{3}_/, '');
}

/**
 * Resolution order (normative, spec /states/enemies):
 * exact name → *_<token> suffix → aliases → (attack only) atk-segment scan.
 */
export function resolveClip<T extends NamedClip>(clips: T[], token: string): T | null {
  if (!token) return null;
  const direct =
    clips.find((c) => c.name === token) ?? clips.find((c) => c.name.endsWith('_' + token)) ?? null;
  if (direct) return direct;
  for (const alias of ANIM_ALIASES[token] ?? []) {
    const found = resolveClip(clips, alias);
    if (found) return found;
  }
  if (token === 'atk') return attackClipFallback(clips);
  return null;
}

/**
 * Last-resort attack scan: any clip with an exact "atk" underscore-segment
 * qualifies, EXCEPT segmented charge/loop/end pieces (…_st/_lp/_ed — one
 * alone shows a partial attack). Alphabetically first for determinism.
 */
export function attackClipFallback<T extends NamedClip>(clips: T[]): T | null {
  let best: T | null = null;
  for (const c of clips) {
    const parts = c.name.split('_');
    if (!parts.includes('atk')) continue;
    if (['st', 'lp', 'ed'].includes(parts[parts.length - 1])) continue;
    if (!best || c.name < best.name) best = c;
  }
  return best;
}
