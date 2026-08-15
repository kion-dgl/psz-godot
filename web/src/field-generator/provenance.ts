/**
 * WHERE EACH VALUE IN A GENERATED FIELD COMES FROM.
 *
 * The field generator is a mix of things measured out of the original, things
 * inferred from those measurements, and things we invented because nobody has
 * decoded them yet. Nothing in the output distinguishes them, which is how
 * invented numbers end up being defended as if they were facts — this repo has
 * done it at least twice (the refuted "boxes = 2 x byte at +0x31" reading, and
 * the trap fuse divisor that play-testing showed was wrong).
 *
 * So every value the preview shows is tagged here, with the source that backs
 * it. `measured` means psz-re read it out of the ROM or the level files and
 * says so; `inferred` means it follows from something measured but was not
 * observed directly; `ours` means we made it up and it is not parity.
 *
 * Keep this honest even when it is unflattering — an `ours` entry is a to-do,
 * not an embarrassment, and mislabelling one as `measured` costs far more than
 * admitting it.
 */

export type Confidence = 'measured' | 'inferred' | 'ours';

export interface Provenance {
  /** What the preview calls it. */
  label: string;
  level: Confidence;
  /** Where it comes from, or what still has to happen for it to be measured. */
  source: string;
  /** Optional detail worth reading before trusting the value. */
  note?: string;
}

export const CONFIDENCE_STYLE: Record<Confidence, { color: string; mark: string; title: string }> = {
  measured: { color: '#6ec98a', mark: '●', title: 'measured from the original' },
  inferred: { color: '#e0c97a', mark: '◐', title: 'inferred from something measured' },
  ours: { color: '#ff8a5c', mark: '○', title: 'ours — invented, not parity' },
};

export const PROVENANCE: Provenance[] = [
  // ── Layout ────────────────────────────────────────────────────────────
  {
    label: 'room shape / doors',
    level: 'measured',
    source: 'psz-re sys.field-doorways (confirmed; 62 captures, 592 rooms, 1058 connections)',
    note: 'Shape comes from the cell degree and nothing else, so doors == connections by construction. There is never a spare door.',
  },
  {
    label: 'room tile choice',
    level: 'ours',
    source: 'GridGenerator._tile_with_exact_doors',
    note: 'Which of the area’s tiles fills a cell is our pick. Only the DEGREE is parity.',
  },
  {
    label: 'layout mask + group roll',
    level: 'measured',
    source: 'psz-re fmt.room-object-set; masks at 0x020EC288, group-5 weights at 0x020EC270',
    note: 'Five masks, group 5 rolled 0..3 at 40/20/20/20. Mask index 4 is unreachable by the depth-banded draw — that is faithful, not a bug.',
  },
  {
    label: 'cell rotation',
    level: 'inferred',
    source: 'psz-re: rooms are rotated and the rotation is derived, not stored',
    note: 'We derive it by fitting doors to the layout. The original derives it too, but the exact rule is not transcribed.',
  },

  // ── Gates ─────────────────────────────────────────────────────────────
  {
    label: 'door attribute values (0/1/2/4)',
    level: 'measured',
    source: 'psz-re level_topology_builder.door_attributes; cell +0x14+dir',
  },
  {
    label: 'key-gate budget',
    level: 'measured',
    source: 'psz-re level_topology_builder.key_gate_budget: (rooms - 2) * params[5] / 100, params[5] = 35',
  },
  {
    label: 'enemy-defeat chance',
    level: 'measured',
    source: 'psz-re params[8] = 75 (runtime), corroborated by the 268/106/0 capture split',
    note: 'The table default of 10 is NOT the value the game runs with. One roll per ROOM, so a room gates all its forward exits or none.',
  },
  {
    label: 'one-key vs two-key',
    level: 'inferred',
    source: 'psz-re FUN_020b27ec: params[6] = 30 for flag-0x20 rooms, params[7] = 10 otherwise',
    note: 'We always take the params[7] arm: this generator has no equivalent of the 0x20 paired-cell flag, so two-key gates are rarer here than in the original.',
  },
  {
    label: 'key scatter',
    level: 'measured',
    source: 'psz-re FUN_020b2920: BFS depth < 2 from the gated room, max 2 keys per room',
    note: 'Never behind its own gate. The key economy closes in 62 of 62 captures.',
  },

  // ── Objects ───────────────────────────────────────────────────────────
  {
    label: 'box / wall / trap positions',
    level: 'measured',
    source: 'psz-re set/<NN>/<v>/<room>/*.rel via data/re_reference/room_objects.json',
    note: 'Room-local (x, y, z) in the same frame as room_doorways.json, plus a 16-bit facing. Authored, never scattered at runtime.',
  },
  {
    label: 'trap damage (needler 25, burn 50)',
    level: 'measured',
    source: 'psz-re: the one constant each type carries across 248 and 458 records',
  },
  {
    label: 'field-trap damage + fuse timing',
    level: 'ours',
    source: 'psz-godot#607',
    note: 'The original carries no per-instance trap parameters, so the 15 damage is ours. The fuse FRAMES are measured but the 60fps divisor is not — play-testing says the resulting 0.75s is far too short to react to.',
  },
  {
    label: 'fence ↔ switch pairing',
    level: 'ours',
    source: 'psz-godot#610',
    note: 'The real pairing lives in the object parameter block, which psz-re does not publish. Every fence in a room is linked to every switch in it, and a fence with no switch is dropped rather than sealing the room.',
  },
  {
    label: 'enemy positions',
    level: 'ours',
    source: 'psz-godot#604 — FieldPopulation.ENEMY_RING_RADIUS = 5.0',
    note: 'A blind ring. psz-re HAS the authored positions (enemy_deploy_positions.json, 13,417 slots, 99.1% inside ±22) and we do not use them yet — this is why enemies stand on rocks and waves split across voids.',
  },
  {
    label: 'enemy wave composition',
    level: 'measured',
    source: 'psz-re enemy_room_assignment + enemy_wave_templates (set d)',
    note: 'WHICH enemies a room may roll is measured. How many WAVES a room runs is not decoded at all — every room here is wave 1 of 1.',
  },
];
