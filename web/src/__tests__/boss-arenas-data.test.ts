/**
 * Data validation for data/boss_arenas.json (#493, tool at #/boss-room).
 * Boss rooms load the boss inside its own arena, so every referenced asset
 * (boss GLB, arena visual + floor GLBs) must actually exist on disk.
 */
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const CONFIG_PATH = path.resolve(__dirname, '../../public/data/boss_arenas.json');
const ENEMIES_PATH = path.resolve(__dirname, '../../public/data/enemies.json');
// Through the web/public/assets symlinks — same tree the dev server serves.
const ASSETS = path.resolve(__dirname, '../../public/assets');

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
const roster: Array<{ id: string; model_id?: string; is_boss?: boolean }> = JSON.parse(
  fs.readFileSync(ENEMIES_PATH, 'utf-8'),
);
const rosterById = new Map(roster.map((e) => [e.id, e]));
const bosses: Array<[string, any]> = Object.entries(config.bosses);
const arenas: Array<[string, any]> = Object.entries(config.arenas);

describe('boss_arenas.json — structure', () => {
  it('has schema_version 1, arenas, and bosses', () => {
    expect(config.schema_version).toBe(1);
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

  it('boss model GLBs exist on disk', () => {
    for (const [id, b] of bosses) {
      const glb = path.join(ASSETS, 'enemies', b.model_id, `${b.model_id}.glb`);
      expect(fs.existsSync(glb), `${id}: missing ${glb}`).toBe(true);
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

describe('boss_arenas.json — arenas', () => {
  it('every arena has its visual + floor GLBs on disk', () => {
    for (const [stageId, a] of arenas) {
      const dir = path.join(ASSETS, 'stages', a.area, stageId, 'lndmd');
      for (const file of [`${stageId}_m.glb`, `${stageId}-floor.glb`]) {
        expect(fs.existsSync(path.join(dir, file)), `${stageId}: missing ${file}`).toBe(true);
      }
    }
  });

  it('skybox flag matches the skybox GLB on disk', () => {
    for (const [stageId, a] of arenas) {
      const sky = path.join(ASSETS, 'stages', a.area, stageId, 'lndmd', 'skybox', 'o0s_zsky.glb');
      expect(fs.existsSync(sky), `${stageId}: skybox=${!!a.skybox} but disk disagrees`).toBe(!!a.skybox);
    }
  });

  it('arena area folders follow the boss-stage naming (…_z)', () => {
    for (const [stageId, a] of arenas) {
      expect(a.area.endsWith('_z'), `${stageId}: area ${a.area}`).toBe(true);
      expect(typeof a.label === 'string' && a.label.length > 0, `${stageId} label`).toBe(true);
    }
  });
});
