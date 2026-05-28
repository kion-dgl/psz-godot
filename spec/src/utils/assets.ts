export function assetUrl(path: string): string {
  const clean = path.startsWith('/') ? path.slice(1) : path;
  if (clean.startsWith('assets/')) {
    return `/cdn/${clean}`;
  }
  return `/${clean}`;
}
