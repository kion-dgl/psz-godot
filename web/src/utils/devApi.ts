/** Astro dev middleware lives under the project base and requires a trailing slash. */
export function devApiUrl(path: string): string {
  const [pathname, query] = path.split('?');
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  return `${base}${pathname.replace(/\/$/, '')}/${query ? `?${query}` : ''}`;
}
