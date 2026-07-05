/**
 * Clip-token resolution parity — these pins mirror test_enemy_attack_recovery
 * in scripts/tools/test_runner.gd exactly. The resolution order is normative
 * (spec /states/enemies "Attack recovery") and MUST match the Godot runtime.
 */
import { describe, it, expect } from 'vitest';
import { resolveClip, clipToken } from '../enemy-room/anim';

const clips = (...names: string[]) => names.map((name) => ({ name }));

describe('enemy-room clip resolution — Godot parity', () => {
  it('resolves plain _atk suffix first', () => {
    expect(resolveClip(clips('s071_atk', 's071_atk_hi', 's071_atk_mi'), 'atk')?.name).toBe('s071_atk');
  });

  it('resolves atk1 rigs via the alias table', () => {
    expect(resolveClip(clips('b_014_atk1', 'b_014_wlk'), 'atk')?.name).toBe('b_014_atk1');
  });

  it("resolves orangutan's misspelled atckwat via the alias table", () => {
    expect(resolveClip(clips('b_044_atckwat', 'b_044_wat'), 'atk')?.name).toBe('b_044_atckwat');
  });

  it('swordman rig: atk scan picks atk_pu, not th_st/th_ed segments', () => {
    expect(
      resolveClip(clips('b062_atk_pu', 'b062_atk_sw', 'b062_atk_th_st', 'b062_atk_th_ed', 'b062_wat'), 'atk')?.name,
    ).toBe('b062_atk_pu');
  });

  it('board rig: atk scan picks whole atk_sh over sp_* segments', () => {
    expect(
      resolveClip(clips('m051_atk_sp_ed', 'm051_atk_sp_lp', 'm051_atk_sp_st', 'm051_atk_sh'), 'atk')?.name,
    ).toBe('m051_atk_sh');
  });

  it('mother rig: atk scan picks atk_sa_a (alphabetical among whole clips)', () => {
    expect(
      resolveClip(
        clips('b072_atk_gu_a_st', 'b072_atk_gu_a_lp', 'b072_atk_gu_a_ed', 'b072_atk_sa_a', 'b072_atk_sb_a'),
        'atk',
      )?.name,
    ).toBe('b072_atk_sa_a');
  });

  it('segment-only rig resolves nothing (fallback-duration path)', () => {
    expect(resolveClip(clips('z003_atk_dl_lp', 'z003_wat'), 'atk')).toBeNull();
  });

  it('the scan applies to the atk token only', () => {
    // A wat-token lookup must not scan into unrelated wat-segment clips.
    expect(resolveClip(clips('b062_atk_pu'), 'wat')).toBeNull();
  });

  it('dmg resolves the dam-named damage clips via the alias table', () => {
    // Five rigs name their damage clip dam: booma, swordman, tank, orangutan, shrimp.
    expect(resolveClip(clips('s_040_dam', 's_040_atk'), 'dmg')?.name).toBe('s_040_dam');
    expect(resolveClip(clips('b_044_dam', 'b_044_wat'), 'dmg')?.name).toBe('b_044_dam');
    // Rigs with a real dmg clip are unaffected (direct suffix wins).
    expect(resolveClip(clips('m_012_dmg', 'm_012_dam_x'), 'dmg')?.name).toBe('m_012_dmg');
  });

  it('clipToken strips rig prefixes', () => {
    expect(clipToken('s_001_atk')).toBe('atk');
    expect(clipToken('m051_atk_sh')).toBe('atk_sh');
    expect(clipToken('z003_atk_dl_lp')).toBe('atk_dl_lp');
  });
});
