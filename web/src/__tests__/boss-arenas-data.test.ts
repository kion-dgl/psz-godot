/**
 * Data validation for data/boss_arenas.json (#493, tool at #/boss-room).
 * Boss rooms load the boss inside its own arena, so every referenced asset
 * (boss GLB, arena visual + floor GLBs) must be in the published pack.
 * Existence is checked against the committed asset_tree.txt — the /assets/
 * tree itself is not in git (it ships via R2/pack), so CI has no files on
 * disk; asset_tree.txt is the same source of truth check-asset-refs uses.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const CONFIG_PATH = path.resolve(__dirname, '../../public/data/boss_arenas.json');
const ENEMIES_PATH = path.resolve(__dirname, '../../public/data/enemies.json');
const ASSET_TREE = new Set(
  fs
    .readFileSync(path.resolve(__dirname, '../../../asset_tree.txt'), 'utf-8')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean),
);

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
const roster: Array<{ id: string; model_id?: string; is_boss?: boolean }> = JSON.parse(
  fs.readFileSync(ENEMIES_PATH, 'utf-8'),
);
const rosterById = new Map(roster.map((e) => [e.id, e]));
const bosses: Array<[string, any]> = Object.entries(config.bosses);
const arenas: Array<[string, any]> = Object.entries(config.arenas);

describe('boss_arenas.json — structure', () => {
  it('has schema_version 2, arenas, and bosses', () => {
    expect(config.schema_version).toBe(2);
    expect(arenas.length).toBeGreaterThan(0);
    expect(bosses.length).toBe(5);
  });

  it('every roster boss has a room', () => {
    // mother_trinity is flagged is_boss but rides the regular `mother` rig,
    // spawns in no quest, and has no designed fight — the mother_caster
    // enemy room covers the rig until the fight exists.
    const NOT_ROOMED = new Set(['mother_trinity']);
    const rosterBosses = roster.filter((e) => e.is_boss).map((e) => e.id);
    const missing = rosterBosses.filter((id) => !config.bosses[id] && !NOT_ROOMED.has(id));
    expect(missing, `is_boss roster entries without a boss room: ${missing.join(', ')}`).toHaveLength(0);
  });
});

describe('boss_arenas.json — bosses', () => {
  it('every boss resolves to an is_boss roster entry with a matching model_id', () => {
    for (const [id, b] of bosses) {
      const e = rosterById.get(id);
      expect(e, `${id} missing from enemies.json`).toBeTruthy();
      expect(e!.is_boss, `${id} is not flagged is_boss in enemies.json`).toBe(true);
      expect(e!.model_id, `${id} model_id mismatch`).toBe(b.model_id);
    }
  });

  it('boss model GLBs are in the published pack (asset_tree.txt)', () => {
    for (const [id, b] of bosses) {
      const glb = `assets/enemies/${b.model_id}/${b.model_id}.glb`;
      expect(ASSET_TREE.has(glb), `${id}: ${glb} not in asset_tree.txt`).toBe(true);
    }
  });

  it('every boss default arena is defined and not marked unassigned', () => {
    for (const [id, b] of bosses) {
      const arena = config.arenas[b.arena];
      expect(arena, `${id}: arena ${b.arena} not defined`).toBeTruthy();
      expect(arena.unassigned, `${id}: default arena ${b.arena} is marked unassigned`).toBeFalsy();
    }
  });

  it('boss fields are sane (model_scale > 0, clip_notes are strings)', () => {
    for (const [id, b] of bosses) {
      expect(b.model_scale, `${id} model_scale`).toBeGreaterThan(0);
      expect(typeof b.quest_source, `${id} quest_source`).toBe('string');
      for (const [token, note] of Object.entries(b.clip_notes ?? {})) {
        expect(typeof note === 'string' && note.length > 0, `${id} clip_notes.${token}`).toBe(true);
      }
    }
  });
});

// v2 behavior draft (spec /states/bosses): enemy kinds + boss-only kinds.
// An unknown kind fails the data test — same forcing function as the enemy
// archetype rule: new vocabulary demands a spec decision, not a typo.
const KNOWN_KINDS = new Set([
  'melee_arc', 'projectile', 'lob', 'charge', 'leap', // /mechanics/enemy-attacks
  'beam_sweep', 'aoe_burst', 'grab', 'fly_pass', 'spout', // /states/bosses
]);

describe('boss_arenas.json — behavior draft (v2)', () => {
  it('a boss with no attacks carries a note saying why (blocked drafts are loud)', () => {
    for (const [id, b] of bosses) {
      if ((b.attacks ?? []).length === 0) {
        expect(typeof b.note === 'string' && b.note.length > 0, `${id}: empty draft without a note`).toBe(true);
      }
    }
  });

  it('phases have unique ids and labels; hp_frac in (0, 1) when set', () => {
    for (const [id, b] of bosses) {
      const ids = new Set<string>();
      for (const p of b.phases ?? []) {
        expect(typeof p.id === 'string' && p.id.length > 0, `${id} phase id`).toBe(true);
        expect(ids.has(p.id), `${id}: duplicate phase '${p.id}'`).toBe(false);
        ids.add(p.id);
        expect(typeof p.label === 'string' && p.label.length > 0, `${id} phase '${p.id}' label`).toBe(true);
        if (p.hp_frac !== undefined) {
          expect(p.hp_frac > 0 && p.hp_frac < 1, `${id} phase '${p.id}' hp_frac ${p.hp_frac}`).toBe(true);
        }
      }
    }
  });

  it('attacks are well-formed: unique id, clip token, known kind, sane numbers', () => {
    for (const [id, b] of bosses) {
      const ids = new Set<string>();
      for (const a of b.attacks ?? []) {
        expect(typeof a.id === 'string' && a.id.length > 0, `${id} attack id`).toBe(true);
        expect(ids.has(a.id), `${id}: duplicate attack '${a.id}'`).toBe(false);
        ids.add(a.id);
        expect(typeof a.clip === 'string' && a.clip.length > 0, `${id}/${a.id} clip`).toBe(true);
        if (a.chain !== undefined) {
          expect(Array.isArray(a.chain) && a.chain.length > 0, `${id}/${a.id} chain`).toBe(true);
          for (const t of a.chain) expect(typeof t === 'string' && t.length > 0, `${id}/${a.id} chain token`).toBe(true);
        }
        if (a.kind !== undefined) expect(KNOWN_KINDS.has(a.kind), `${id}/${a.id} unknown kind '${a.kind}'`).toBe(true);
        const min = a.min_range ?? 0;
        const max = a.max_range ?? Infinity;
        expect(min <= max, `${id}/${a.id} range band ${min}–${max}`).toBe(true);
        for (const f of ['windup_frac', 'damage_end_frac'] as const) {
          if (a[f] !== undefined) expect(a[f] >= 0 && a[f] <= 1, `${id}/${a.id} ${f}`).toBe(true);
        }
        for (const f of ['weight', 'damage_mult', 'hit_reach', 'hit_half_angle_deg'] as const) {
          if (a[f] !== undefined) expect(a[f] > 0, `${id}/${a.id} ${f}`).toBe(true);
        }
      }
    }
  });

  it('attack phase gates and anchor refs resolve', () => {
    for (const [id, b] of bosses) {
      const phaseIds = new Set((b.phases ?? []).map((p: any) => p.id));
      const anchorNames = new Set((b.anchors ?? []).map((a: any) => a.name));
      for (const a of b.attacks ?? []) {
        for (const p of a.phases ?? []) {
          expect(phaseIds.has(p), `${id}/${a.id}: unknown phase '${p}'`).toBe(true);
        }
        if (a.anchor !== undefined) {
          expect(anchorNames.has(a.anchor), `${id}/${a.id}: unknown anchor '${a.anchor}'`).toBe(true);
        }
      }
    }
  });

  it('anchors have unique names and [x,y,z] positions', () => {
    for (const [id, b] of bosses) {
      const names = new Set<string>();
      for (const a of b.anchors ?? []) {
        expect(typeof a.name === 'string' && a.name.length > 0, `${id} anchor name`).toBe(true);
        expect(names.has(a.name), `${id}: duplicate anchor '${a.name}'`).toBe(false);
        names.add(a.name);
        expect(
          Array.isArray(a.pos) && a.pos.length === 3 && a.pos.every((n: unknown) => typeof n === 'number' && Number.isFinite(n)),
          `${id} anchor '${a.name}' pos`,
        ).toBe(true);
      }
    }
  });
});

describe('boss_arenas.json — arenas', () => {
  it('every arena has its visual + floor GLBs in the published pack', () => {
    for (const [stageId, a] of arenas) {
      const dir = `assets/stages/${a.area}/${stageId}/lndmd`;
      for (const file of [`${stageId}_m.glb`, `${stageId}-floor.glb`]) {
        expect(ASSET_TREE.has(`${dir}/${file}`), `${stageId}: ${file} not in asset_tree.txt`).toBe(true);
      }
    }
  });

  it('skybox flag matches the skybox GLB in the published pack', () => {
    for (const [stageId, a] of arenas) {
      const sky = `assets/stages/${a.area}/${stageId}/lndmd/skybox/o0s_zsky.glb`;
      expect(ASSET_TREE.has(sky), `${stageId}: skybox=${!!a.skybox} but asset_tree.txt disagrees`).toBe(!!a.skybox);
    }
  });

  it('arena area folders follow the boss-stage naming (…_z)', () => {
    for (const [stageId, a] of arenas) {
      expect(a.area.endsWith('_z'), `${stageId}: area ${a.area}`).toBe(true);
      expect(typeof a.label === 'string' && a.label.length > 0, `${stageId} label`).toBe(true);
    }
  });
});
