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
export function assetUrl(path: string): string {
  const base = import.meta.env.BASE_URL || '/';
  const cdn = (import.meta.env.VITE_ASSETS_BASE || '').replace(/\/$/, '');
  const clean = path.startsWith('/') ? path.slice(1) : path;
  if (cdn && clean.startsWith('assets/')) {
    return `${cdn}/${clean}`;
  }
  return `${base}${clean}`;
}
