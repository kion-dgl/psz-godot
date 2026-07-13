/**
 * Asset URL helper.
 *
 * Large binary assets (GLB, PNG under /assets/*) live on the Cloudflare R2
 * CDN when VITE_ASSETS_BASE is set at build time. This lets the repo stay
 * small (no tracked /assets/ tree) while the web app still renders every
 * model and texture. Other relative paths fall back to BASE_URL so routed
 * static files (index.html, data/, etc.) keep working on GitHub Pages.
 *
 * Dev fallback: when VITE_ASSETS_BASE is unset, /assets/* still resolves
 * against BASE_URL, which goes through web/public/ symlinks to the repo's
 * /assets/ tree. That keeps `npm run dev` working for anyone with a local
 * /assets/ populated via scripts/tools/fetch_assets_dev.sh.
 */
// Prefixes whose content lives on the CDN when VITE_ASSETS_BASE is set.
// Keep in sync with scripts/publish/sync_tree.ts SYNC_ROOTS and
// scripts/tools/fetch_assets_dev.sh's prefix → local-dir mapping.
const CDN_PREFIXES = ['assets/'];

// Vendored CC0 packs that live in the repo, not on R2. Bypass the CDN even
// when VITE_ASSETS_BASE is set so they resolve through web/public symlinks.
const LOCAL_ONLY_PREFIXES = [
  'assets/kenney_input-prompts/',
  'assets/kenney_nature-pack/',
  'assets/fonts/', // JetBrains Mono (OFL) — vendored in-repo, ships in the binary, never on R2 (#450)
];

export function assetUrl(path: string): string {
  const base = import.meta.env.BASE_URL || '/';
  const cdn = (import.meta.env.VITE_ASSETS_BASE || '').replace(/\/$/, '');
  const clean = path.startsWith('/') ? path.slice(1) : path;
  if (LOCAL_ONLY_PREFIXES.some((p) => clean.startsWith(p))) {
    return `${base}${clean}`;
  }
  if (cdn && CDN_PREFIXES.some((p) => clean.startsWith(p))) {
    return `${cdn}/${clean}`;
  }
  return `${base}${clean}`;
}

/** Always resolve against the local dev server (web/public symlinks → repo /assets/). */
export function localAssetUrl(path: string): string {
  const base = import.meta.env.BASE_URL || '/';
  const clean = path.startsWith('/') ? path.slice(1) : path;
  return `${base}${clean}`;
}

/**
 * Extract the repo-relative `assets/...` path from any URL or path, or null if
 * there isn't one (blob:, file-input loads, non-asset routes).
 */
export function repoAssetPath(urlOrPath: string): string | null {
  const idx = urlOrPath.indexOf('assets/');
  if (idx < 0) return null;
  // Guard against e.g. ".../web-assets/foo": require a separator (or string
  // start) before "assets/".
  if (idx > 0 && !'/'.includes(urlOrPath[idx - 1])) return null;
  return urlOrPath.slice(idx).split(/[?#]/)[0];
}

export interface AssetDrift {
  path: string;      // repo-relative assets/... path
  localSize: number; // bytes served by the dev server (what the game renders)
  cdnSize: number;   // bytes on R2 (what assetUrl()-based tools show)
}

/**
 * Detect drift between the local copy of an asset and its R2 (CDN) copy.
 *
 * The web tools split their reads: assetUrl() resolves to R2 when
 * VITE_ASSETS_BASE is set, while hardcoded/local paths (and Godot itself) read
 * the repo's /assets/ tree. When the two copies differ, a floor traced in one
 * tool silently mismatches the model rendered in another — the s00e_sa2
 * counter incident. This check makes that drift loud.
 *
 * Dev-only and advisory: resolves null when the check doesn't apply (no CDN
 * configured, prod build, non-asset path), when either copy is missing, or
 * when sizes match. Size comparison is deliberate — cheap (HEAD), and any
 * real re-export changes byte count in practice.
 */
export async function checkAssetDrift(
  urlOrPath: string,
  opts?: { cdnBase?: string; dev?: boolean; fetchFn?: typeof fetch },
): Promise<AssetDrift | null> {
  const dev = opts?.dev ?? import.meta.env.DEV;
  const cdn = (opts?.cdnBase ?? import.meta.env.VITE_ASSETS_BASE ?? '').replace(/\/$/, '');
  if (!dev || !cdn) return null;
  const path = repoAssetPath(urlOrPath);
  if (!path || LOCAL_ONLY_PREFIXES.some((p) => path.startsWith(p))) return null;
  const doFetch = opts?.fetchFn ?? fetch;
  const size = async (url: string): Promise<number | null> => {
    try {
      const res = await doFetch(url, { method: 'HEAD' });
      if (!res.ok) return null;
      const len = res.headers.get('content-length');
      return len != null ? parseInt(len, 10) : null;
    } catch {
      return null;
    }
  };
  const [localSize, cdnSize] = await Promise.all([
    size(localAssetUrl(path)),
    size(`${cdn}/${path}`),
  ]);
  // Either copy missing/unreadable → can't judge; stay quiet rather than cry
  // wolf on every asset that was never synced to R2.
  if (localSize == null || cdnSize == null) return null;
  if (localSize === cdnSize) return null;
  return { path, localSize, cdnSize };
}
