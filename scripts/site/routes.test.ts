import { describe, expect, it } from 'vitest';
import { toolRoutes } from './routes';
import bosses from '../../data/boss_arenas.json';

describe('static tool entry pages', () => {
  const routes = toolRoutes();
  it('includes top-level, nested and parameterized routes without duplicates', () => {
    expect(routes).toContain('/quest-editor/edit');
    expect(routes).toContain('/combat-room');
    expect(routes).toContain('/enemy-room/lunging_melee');
    expect(new Set(routes).size).toBe(routes.length);
    expect(routes.some(route => /[:#?]/.test(route))).toBe(false);
  });
  it('prerenders every authored boss', () => {
    for (const id of Object.keys(bosses.bosses)) expect(routes).toContain(`/boss-room/${id}`);
  });
});
