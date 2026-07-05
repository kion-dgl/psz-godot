/**
 * segmentFamilies — st/lp/ed chain detection for boss clips (#493: segmented
 * clips are first-class for bosses). Pinned against the real boss GLB clip
 * inventories so the grouping can't silently drift from the rigs.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';
import { segmentFamilies } from '../boss-room/types';

const ASSETS = path.resolve(__dirname, '../../public/assets');
// The /assets/ tree is not in git (ships via R2/pack) — these pins need the
// real GLB bytes, so they only run where a local tree exists (dev boxes).
// CI's coverage of the referenced paths is boss-arenas-data.test.ts, which
// validates against the committed asset_tree.txt.
const HAS_ASSETS = fs.existsSync(path.join(ASSETS, 'enemies', 'boss_dragon', 'boss_dragon.glb'));

/** Clip names from a GLB's JSON chunk (glTF binary: 12-byte header, then chunks). */
function glbClipNames(modelId: string): string[] {
  const buf = fs.readFileSync(path.join(ASSETS, 'enemies', modelId, `${modelId}.glb`));
  const jsonLen = buf.readUInt32LE(12);
  const json = JSON.parse(buf.subarray(20, 20 + jsonLen).toString('utf-8'));
  return (json.animations ?? []).map((a: { name: string }) => a.name);
}

describe('segmentFamilies — synthetic', () => {
  it('groups st/lp/ed by shared prefix and requires ≥2 segments', () => {
    const fams = segmentFamilies(['x_atkst', 'x_atklp', 'x_atkend', 'x_lonelyst', 'x_wat']);
    expect(fams).toEqual([{ prefix: 'x_atk', st: 'x_atkst', lp: 'x_atklp', ed: 'x_atkend' }]);
  });

  it('does not turn ded/wat-style names into families', () => {
    expect(segmentFamilies(['z_004_ded', 'z_004_wat1', 'z_005_down'])).toEqual([]);
  });
});

describe.skipIf(!HAS_ASSETS)('segmentFamilies — real boss rigs (local assets only)', () => {
  it('boss_mother: cmb chains st→lp→end; laser/swing/hedb chain st→lp', () => {
    const fams = segmentFamilies(glbClipNames('boss_mother'));
    const byPrefix = new Map(fams.map((f) => [f.prefix, f]));
    expect(byPrefix.get('z_004_cmb')).toEqual({
      prefix: 'z_004_cmb',
      st: 'z_004_cmbst',
      lp: 'z_004_cmblp',
      ed: 'z_004_cmbend',
    });
    expect(byPrefix.get('z_004_laser')).toMatchObject({ st: 'z_004_laserst', lp: 'z_004_laserlp' });
    expect(byPrefix.get('z_004_swing')).toMatchObject({ st: 'z_004_swingst', lp: 'z_004_swinglp' });
    expect(byPrefix.get('z_004_hedb')).toMatchObject({ st: 'z_004_hedbst', lp: 'z_004_hedblp' });
  });

  it('boss_darkfalz: thr/rad/dif chain st→lp', () => {
    const fams = segmentFamilies(glbClipNames('boss_darkfalz'));
    const prefixes = fams.map((f) => f.prefix);
    expect(prefixes).toEqual(expect.arrayContaining(['z_005_thr', 'z_005_rad', 'z_005_dif']));
  });

  it('boss_dragon: brs (breath) chains st→lp', () => {
    const fams = segmentFamilies(glbClipNames('boss_dragon'));
    expect(fams.map((f) => f.prefix)).toContain('z_001_brs');
  });

  it('boss_robot: single orphan lp clip forms no family', () => {
    expect(segmentFamilies(glbClipNames('boss_robot'))).toEqual([]);
  });
});
