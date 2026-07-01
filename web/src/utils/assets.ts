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
