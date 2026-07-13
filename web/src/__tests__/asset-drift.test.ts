// Asset drift detection (utils/assets.ts) — the s00e_sa2 counter incident
// guard. assetUrl() reads R2 when VITE_ASSETS_BASE is set while the game and
// city-walk-mock read the local /assets/ tree; checkAssetDrift flags when the
// two copies differ so the web tools can warn instead of silently disagreeing.
import { describe, it, expect } from 'vitest';
import { repoAssetPath, checkAssetDrift } from '../utils/assets';

const CDN = 'https://cdn.example';

// fetch stub: maps URL → content-length (null → 404).
function fetchWithSizes(sizes: Record<string, number | null>): typeof fetch {
  return (async (input: RequestInfo | URL) => {
    const url = String(input);
    const size = sizes[url];
    if (size == null) return new Response(null, { status: 404 });
    return new Response(null, { status: 200, headers: { 'content-length': String(size) } });
  }) as typeof fetch;
}

describe('repoAssetPath', () => {
  it('extracts from a CDN URL', () => {
    expect(repoAssetPath(`${CDN}/assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb`))
      .toBe('assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb');
  });
  it('extracts from a BASE_URL-prefixed local path', () => {
    expect(repoAssetPath('/psz-godot/assets/foo/bar.glb')).toBe('assets/foo/bar.glb');
  });
  it('accepts a bare repo-relative path and strips query strings', () => {
    expect(repoAssetPath('assets/foo.glb?cb=123')).toBe('assets/foo.glb');
  });
  it('rejects non-asset paths and lookalike prefixes', () => {
    expect(repoAssetPath('/psz-godot/data/quests/foo.json')).toBeNull();
    expect(repoAssetPath('/web-assets/foo.glb')).toBeNull();
  });
});

describe('checkAssetDrift', () => {
  const PATH = 'assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb';
  const localUrl = `/${PATH}`;      // BASE_URL is '/' under vitest
  const cdnUrl = `${CDN}/${PATH}`;

  it('reports drift when sizes differ (the incident: 101KB local vs 810KB R2)', async () => {
    const drift = await checkAssetDrift(cdnUrl, {
      cdnBase: CDN, dev: true,
      fetchFn: fetchWithSizes({ [localUrl]: 101448, [cdnUrl]: 810244 }),
    });
    expect(drift).toEqual({ path: PATH, localSize: 101448, cdnSize: 810244 });
  });

  it('is silent when the copies match', async () => {
    expect(await checkAssetDrift(cdnUrl, {
      cdnBase: CDN, dev: true,
      fetchFn: fetchWithSizes({ [localUrl]: 810244, [cdnUrl]: 810244 }),
    })).toBeNull();
  });

  it('is silent when either copy is missing (asset never synced)', async () => {
    expect(await checkAssetDrift(cdnUrl, {
      cdnBase: CDN, dev: true,
      fetchFn: fetchWithSizes({ [cdnUrl]: 810244 }),
    })).toBeNull();
    expect(await checkAssetDrift(cdnUrl, {
      cdnBase: CDN, dev: true,
      fetchFn: fetchWithSizes({ [localUrl]: 810244 }),
    })).toBeNull();
  });

  it('is silent outside dev or without a CDN configured', async () => {
    const fetchFn = fetchWithSizes({ [localUrl]: 1, [cdnUrl]: 2 });
    expect(await checkAssetDrift(cdnUrl, { cdnBase: CDN, dev: false, fetchFn })).toBeNull();
    expect(await checkAssetDrift(cdnUrl, { cdnBase: '', dev: true, fetchFn })).toBeNull();
  });

  it('is silent for local-only (never-on-R2) prefixes and non-asset paths', async () => {
    const fetchFn = fetchWithSizes({});
    expect(await checkAssetDrift('assets/kenney_nature-pack/tree.glb', { cdnBase: CDN, dev: true, fetchFn })).toBeNull();
    expect(await checkAssetDrift('blob:abc123', { cdnBase: CDN, dev: true, fetchFn })).toBeNull();
  });
});
