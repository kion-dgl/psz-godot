const CDN = 'https://pub-8bb0622759a042aa9dbd9cb4bd1f21e6.r2.dev';

export function assetUrl(path: string): string {
  const clean = path.startsWith('/') ? path.slice(1) : path;
  if (clean.startsWith('assets/')) {
    return `${CDN}/${clean}`;
  }
  return `/${clean}`;
}
