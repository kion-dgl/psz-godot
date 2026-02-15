/**
 * Asset URL helper — prepends Vite base URL to asset paths.
 * Ensures paths work in both dev (symlinked public/) and
 * production (GitHub Pages at /psz-godot/).
 */
export function assetUrl(path: string): string {
  const base = import.meta.env.BASE_URL || '/';
  const clean = path.startsWith('/') ? path.slice(1) : path;
  return `${base}${clean}`;
}
