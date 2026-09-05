/**
 * The layout-mask system that turns one flat authored table into a room's
 * real variations — transcribed from field_population.gd's _pick_layout so
 * the editor's preview and the game agree by construction.
 *
 * A room file is six groups. One of five masks picks which of groups 0–4 a
 * visit builds verbatim; group 5's bit is forced into every mask and its
 * count is rolled separately (0–3 at 40/20/20/20). A mask is eligible for a
 * room only if every group it names is non-empty.
 *
 * THERE ARE FIVE MASKS AND ONLY FOUR ARE REACHABLE, BY DESIGN — do not "fix"
 * this. The draw returns a category 0..3 (measured on all 44 values across
 * five captured fields), so mask 4 — the only one naming group 4 — is never
 * selected and group 4's objects never spawn in a free field. The editor
 * still lets you preview it: it is a composition the table contains.
 */

/** The room's group-size table (`entry.groups` in room_objects.json). */
export type GroupTable = number[];

/**
 * Bitset of the groups the table populates — the input to eligibility.
 * Group 5's bit is forced in: every mask names it because the roll may
 * legitimately take nothing.
 */
export function occupiedGroups(groups: GroupTable): number {
  let occupied = 0;
  for (let g = 0; g < Math.min(groups.length, 6); g++) {
    if (groups[g] > 0) occupied |= 1 << g;
  }
  return occupied | 0x20;
}

/**
 * Which layouts this room can take: mask m is eligible iff it names no empty
 * group (m === (m & occupied)) — exactly _pick_layout's test.
 */
export function layoutEligibility(groups: GroupTable, masks: number[]): boolean[] {
  const occupied = occupiedGroups(groups);
  return masks.map((m) => m === (m & occupied));
}

/**
 * Each layout's real share of visits for one depth band's weight row,
 * including _pick_layout's fallback: an ineligible drawn index falls to the
 * highest eligible index ≤ 3, and 0 when none is eligible. Rows sum to 100,
 * so shares are exact percentages — mask 4's share is always 0.
 */
export function layoutShares(masks: number[], eligible: boolean[], weights: number[]): number[] {
  let fallback = 0;
  for (let i = 0; i <= 3 && i < masks.length; i++) {
    if (eligible[i]) fallback = i;
  }
  const shares = masks.map(() => 0);
  for (let d = 0; d <= 3 && d < weights.length; d++) {
    shares[eligible[d] ? d : fallback] += weights[d];
  }
  return shares;
}

/** Groups 0–4 a mask builds. Group 5 rides every mask as the roll, so it is
 * not listed. */
export function maskGroups(mask: number): number[] {
  const out: number[] = [];
  for (let g = 0; g <= 4; g++) {
    if ((mask >> g) & 1) out.push(g);
  }
  return out;
}

/**
 * One layout's outcome from the flat table: groups 0–4 by mask bit, group 5
 * capped at the rolled count, ungrouped records in no mask (they only build
 * on the flat fallback path for rooms with no recoverable group table).
 *
 * Which N of group 5 is a Fisher-Yates shuffle per visit; table order here,
 * so the preview is one honest outcome rather than the odds. The game also
 * truncates at 20 per group / per room — today's data tops out at 14, so
 * those caps can never bind and are not re-implemented.
 */
export function filterByLayout<T extends { g?: number | null }>(
  objects: T[],
  mask: number,
  group5Count: number,
): T[] {
  let taken5 = 0;
  return objects.filter((o) => {
    if (o.g == null) return false;
    if (o.g <= 4) return ((mask >> o.g) & 1) === 1;
    return o.g === 5 && taken5++ < group5Count;
  });
}

/**
 * The same mask applied to the REFERENCE layer (room_reference.json: authored
 * keys, treasure boxes). Those records carry a scalar g, and a position the
 * file repeats under each group that builds it — so this filters groups 0–4
 * by bit and group 5 by a non-empty roll, then dedupes by position. Records
 * with no group stay: nothing says which layout builds them.
 *
 * Enemy spawn slots are NOT passed through this — they belong to the room's
 * wave, not to the object table, and every layout fights from the same slots.
 */
export function filterReferenceByLayout<T extends { g?: number | null; k: string; x: number; y: number; z: number }>(
  records: T[],
  mask: number,
  group5Count: number,
): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const r of records) {
    if (r.g != null) {
      if (r.g <= 4 ? ((mask >> r.g) & 1) !== 1 : r.g === 5 && group5Count <= 0) continue;
      const key = `${r.k}|${r.x.toFixed(2)}|${r.y.toFixed(2)}|${r.z.toFixed(2)}`;
      if (seen.has(key)) continue;
      seen.add(key);
    }
    out.push(r);
  }
  return out;
}

/**
 * The layout this room most often takes — the tab's default view, so it opens
 * on a real arrangement (intent) rather than the flattened table (scatter).
 * Falls back to layout 0, which is also _pick_layout's terminal fallback.
 */
export function pickDefaultLayout(masks: number[], eligible: boolean[], weights: number[]): number {
  const shares = layoutShares(masks, eligible, weights);
  let best = 0;
  shares.forEach((s, i) => {
    if (s > shares[best]) best = i;
  });
  return best;
}
