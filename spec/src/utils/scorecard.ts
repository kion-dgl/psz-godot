/** GitHub owns the live issue list; the static scorecard only supplies its filter. */
export function scorecardIssuesUrl(label: string): string {
  return `https://github.com/kion-dgl/psz-godot/issues?q=${encodeURIComponent(`is:issue is:open label:"${label}"`)}`;
}
