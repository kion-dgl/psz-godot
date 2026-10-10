/** GitHub labels own issue membership; no issue list is stored in the site. */
export function scorecardIssuesUrl(label: string): string {
  return `https://github.com/kion-dgl/psz-godot/issues?q=${encodeURIComponent(`is:issue state:open label:"${label}"`)}`;
}

/** Ordinal grade scale for ordering and display, not completion percentages. */
const gradeScale = ['F', 'D-', 'D', 'D+', 'C-', 'C', 'C+', 'B-', 'B', 'B+', 'A-', 'A', 'A+'];
export function gradeRank(grade: string): number {
  return gradeScale.indexOf(grade);
}
export function gradeBarWidth(grade: string): number {
  return Math.max(0, (gradeRank(grade) + 1) / gradeScale.length * 100);
}
