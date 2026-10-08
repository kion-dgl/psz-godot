import app from '../../web/src/App.tsx?raw';
import { ARCHETYPES } from '../../web/src/enemy-room/archetypes';
import { SHOPS } from '../../web/src/shop-3d/shopData';
import bosses from '../../data/boss_arenas.json';

/** Derive static entry pages from the actual router, including every parameter. */
export function toolRoutes(): string[] {
  const parameters: Record<string, string[]> = {
    '/enemy-room/:archetype': ARCHETYPES.filter(a => !a.outOfScope).map(a => `/enemy-room/${a.id}`),
    '/boss-room/:bossId': Object.keys(bosses.bosses).map(id => `/boss-room/${id}`),
    '/shop-3d/:shopId': SHOPS.map(s => `/shop-3d/${s.id}`),
  };
  return [...app.matchAll(/<Route path="([^"]+)"/g)].flatMap(([, route]) => {
    if (route.includes(':')) {
      if (!parameters[route]) throw new Error(`Missing static expansion for ${route}`);
      return parameters[route];
    }
    return [route];
  });
}
