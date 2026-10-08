/** All same-site navigation includes the GitHub project base exactly once. */
export function siteUrl(path: string): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, '');
  if (/^(?:[a-z]+:|\/\/|#)/i.test(path)) return path;
  if (path === base || path.startsWith(`${base}/`)) return path;
  return `${base}/${path.replace(/^\//, '')}`;
}
