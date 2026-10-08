import { describe, expect, it } from 'vitest';
import { siteUrl } from '../../spec/src/utils/site';
import { devApiUrl } from '../../web/src/utils/devApi';

describe('site URLs', () => {
  it('keeps tool paths ordinary and avoids a repeated base', () => {
    const path = siteUrl('/tools/combat-room/');
    expect(siteUrl(path)).toBe(path);
    expect(path).not.toContain('#');
    expect(siteUrl('https://example.com/path')).toBe('https://example.com/path');
  });
  it('puts editor query strings after the endpoint slash', () => {
    expect(devApiUrl('/api/collider/export?path=assets%2Ftest.glb')).toMatch(/\/api\/collider\/export\/\?path=assets%2Ftest.glb$/);
  });
});
