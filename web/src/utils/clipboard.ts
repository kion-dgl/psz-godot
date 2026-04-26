/**
 * Cross-context clipboard write.
 *
 * navigator.clipboard.writeText is gated on a Secure Context (HTTPS or
 * localhost). The quest editor is served over plain HTTP from the droplet
 * so the modern API is undefined and any caller relying on it throws
 * "Cannot read properties of undefined (reading 'writeText')".
 *
 * This helper tries the modern API first, then falls back to a hidden
 * textarea + execCommand('copy'), which still works in every shipped
 * browser even though the API is officially deprecated.
 */
export function copyText(text: string): void {
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(text).catch(() => fallback(text));
    return;
  }
  fallback(text);
}

function fallback(text: string): void {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.left = '-9999px';
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  try { document.execCommand('copy'); } finally { document.body.removeChild(ta); }
}
