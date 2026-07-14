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
    expect(bosses.length).toBe(8); // 4 PSZ uniques + heaven's mother composite + chaos_mobius + 2 PSO stand-ins (chaos_sorcerer, sinow_beat)
  });

  it('every roster boss has a room', () => {
    // mother_trinity is flagged is_boss but rides the regular `mother` rig,
    // spawns in no quest, and has no designed fight — the mother_caster
    // enemy room covers the rig until the fight exists.
    // mother_trinity: rides the `mother` rig, no designed fight yet.
    // sinow_gold: the rare form of the sinow_beat boss room (a form, not its
    // own room).
    const NOT_ROOMED = new Set(['mother_trinity', 'sinow_gold']);
    const rosterBosses = roster.filter((e) => e.is_boss).map((e) => e.id);
    const missing = rosterBosses.filter((id) => !config.bosses[id] && !NOT_ROOMED.has(id));
    expect(missing, `is_boss roster entries without a boss room: ${missing.join(', ')}`).toHaveLength(0);
  });
});

describe('boss_arenas.json — bosses', () => {
  it('every boss resolves to roster entries with matching model_ids', () => {
    for (const [id, b] of bosses) {
      if (b.forms) {
        // Composite boss (heaven's mother): the forms are REGULAR roster
        // enemies the fight cycles through (blade_mother also spawns in
        // investigate_tower), so no is_boss requirement — each form must
        // simply resolve with a matching rig.
        expect(b.forms.length, `${id} forms`).toBeGreaterThan(1);
        for (const f of b.forms) {
          const e = rosterById.get(f.roster_id);
          expect(e, `${id} form ${f.roster_id} missing from enemies.json`).toBeTruthy();
          if (f.part_of) {
            // Split-boss form (chaos & mobius): model_id is a PART rig under
            // part_of, not the roster model — the roster still resolves to
            // the parent enemy's rig.
            expect(e!.model_id, `${id} form ${f.roster_id} parent rig`).toBe(f.part_of);
          } else {
            expect(e!.model_id, `${id} form ${f.roster_id} model_id mismatch`).toBe(f.model_id);
          }
        }
        // Consistency of the boss's primary model_id with its forms:
        // - split boss (any part_of form): model_id is the parent enemy rig.
        // - composite boss (heaven's mother): model_id is forms[0]'s rig.
        const splitParent = b.forms.find((f: any) => f.part_of)?.part_of;
        if (splitParent) {
          expect(b.model_id, `${id}: split boss model_id is the parent rig`).toBe(splitParent);
        } else {
          expect(b.model_id, `${id}: composite model_id must be forms[0]`).toBe(b.forms[0].model_id);
        }
        continue;
      }
      const e = rosterById.get(id);
      expect(e, `${id} missing from enemies.json`).toBeTruthy();
      expect(e!.is_boss, `${id} is not flagged is_boss in enemies.json`).toBe(true);
      expect(e!.model_id, `${id} model_id mismatch`).toBe(b.model_id);
    }
  });

  it('boss model GLBs are in the published pack (asset_tree.txt)', () => {
    for (const [id, b] of bosses) {
      // pack_pending stand-ins (PSO substitutes) live on R2 but aren't in the
      // game pack yet — skip, like the part rigs.
      if (b.pack_pending) continue;
      // part_of forms are PART rigs — they ship with the parts on the next
      // pack publish (like the tentacle/face parts), not asserted here.
      const models: string[] = b.forms
        ? b.forms.filter((f: any) => !f.part_of).map((f: any) => f.model_id)
        : [b.model_id];
      for (const m of models) {
        const glb = `assets/enemies/${m}/${m}.glb`;
        expect(ASSET_TREE.has(glb), `${id}: ${glb} not in asset_tree.txt`).toBe(true);
      }
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
  'beam_sweep', 'aoe_burst', 'grab', 'fly_pass', 'spout', 'heal', // /states/bosses
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

  it('sim knobs (stats/fsm) are positive numbers when present', () => {
    for (const [id, b] of bosses) {
      for (const [group, obj] of [['stats', b.stats], ['fsm', b.fsm]] as const) {
        for (const [k, v] of Object.entries(obj ?? {})) {
          if (typeof v === 'number') {
            // 0 = feature disabled for these
            const zeroOk = ['flight_interval', 'fatigue_attacks', 'punish_duration', 'punish_break_damage'];
            const min = zeroOk.includes(k) ? 0 : Number.MIN_VALUE;
            expect(v >= min, `${id} ${group}.${k} = ${v}`).toBe(true);
          }
        }
      }
    }
  });

  it('parts are unique non-empty names; instances carry [x,y,z] + finite angles', () => {
    // Existence in the pack is NOT checked here: parts ship with the next
    // pack publish; until then the room loads them from the R2 mirror.
    for (const [id, b] of bosses) {
      const seen = new Set<string>();
      for (const p of b.parts ?? []) {
        const name = typeof p === 'string' ? p : p.part;
        expect(typeof name === 'string' && name.length > 0, `${id} part name`).toBe(true);
        if (typeof p !== 'string' && p.animated !== undefined) {
          expect(typeof p.animated, `${id}/${name} animated`).toBe('boolean');
        }
        expect(seen.has(name), `${id}: duplicate part '${name}'`).toBe(false);
        seen.add(name);
        for (const inst of (typeof p === 'string' ? [] : p.instances ?? [])) {
          expect(
            Array.isArray(inst.pos) && inst.pos.length === 3 && inst.pos.every((n: unknown) => Number.isFinite(n)),
            `${id}/${name} instance pos`,
          ).toBe(true);
          for (const f of ['yaw_deg', 'pitch_deg']) {
            if (inst[f] !== undefined) expect(Number.isFinite(inst[f]), `${id}/${name} ${f}`).toBe(true);
          }
          if (inst.curve !== undefined) {
            // Spline-poser curve (#508): >= 2 finite [x,y,z] control points.
            expect(Array.isArray(inst.curve) && inst.curve.length >= 2, `${id}/${name} curve length`).toBe(true);
            for (const pt of inst.curve) {
              expect(
                Array.isArray(pt) && pt.length === 3 && pt.every((n: unknown) => Number.isFinite(n)),
                `${id}/${name} curve point`,
              ).toBe(true);
            }
          }
        }
      }
    }
  });

  it('spawn_pos, when authored, is a finite [x,y,z]', () => {
    for (const [id, b] of bosses) {
      if (b.spawn_pos === undefined) continue;
      expect(
        Array.isArray(b.spawn_pos) && b.spawn_pos.length === 3 && b.spawn_pos.every((n: unknown) => Number.isFinite(n)),
        `${id} spawn_pos`,
      ).toBe(true);
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

  it('arena area folders follow the boss-stage naming (…_z, tower excepted)', () => {
    for (const [stageId, a] of arenas) {
      // The Eternal Tower summit (s087_na1) is the one boss arena outside
      // the *_z convention — it lives on tower floor 7.
      const ok = a.area.endsWith('_z') || a.area === 'tower_7';
      expect(ok, `${stageId}: area ${a.area}`).toBe(true);
      expect(typeof a.label === 'string' && a.label.length > 0, `${stageId} label`).toBe(true);
    }
  });
});
