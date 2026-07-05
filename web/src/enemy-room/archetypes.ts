/**
 * Behavior archetypes — mirror of the spec table (/mechanics/enemy-attacks
 * "Rig groups & behavior archetypes") and of MODEL_ARCHETYPES in
 * scripts/tools/gen_enemy_attacks.py, which stamps each enemy's `archetype`
 * field. One room per archetype at #/enemy-room/<id>.
 *
 * `simNote` states what the current baseline sim (fsm.ts, the melee loop)
 * captures for this archetype and what still needs its own module (#494).
 */

export interface ArchetypeDef {
  id: string;
  label: string;
  /** Vocabulary signature + what the archetype does, for the room header. */
  blurb: string;
  /** Sim fidelity note shown in the room. */
  simNote: string;
  /** Out of enemy-room scope entirely (bosses → their own arena tool, #493). */
  outOfScope?: boolean;
}

export const ARCHETYPES: ArchetypeDef[] = [
  {
    id: 'simple_melee',
    label: 'Simple melee',
    blurb: 'atk, ded, dmg, stt, wat, wlk (+run/tht/atkb variants) — the basic chase-and-bite loop: bat, circle, vulture, lizard, rabbit, lion.',
    simNote: 'Native: the baseline sim IS this archetype.',
  },
  {
    id: 'quadruped',
    label: 'Quadruped circler',
    blurb: 'wlk_l/wlk_r directional walks + stp — four-legged rigs that circle their target: wolf, hyena, deer, tiger.',
    simNote: 'Baseline sim; circling locomotion (wlk_l/wlk_r steering) needs its module (#494).',
  },
  {
    id: 'quad_machine',
    label: 'Quad machine',
    blurb: '4-directional wlk_b/f/l/r + atkb — strafing machine quads: Izhirak-S6, Azherowa-B2.',
    simNote: 'Baseline sim; 4-dir strafing needs its module (#494).',
  },
  {
    id: 'bruiser',
    label: 'Bruiser',
    blurb: 'atk / atk_hi / atk_mi height-variant swings: Booma family.',
    simNote: 'Baseline sim covers it — author the three swings as an attack table.',
  },
  {
    id: 'bigrig_combo',
    label: 'Big-rig combo',
    blurb: 'atk1 + segmented atk2_st/lp/ed + atk3 — chained heavy combos: Hilde gorillas.',
    simNote: 'Baseline sim plays single clips; segmented st/lp/ed attack chains need their module (#494).',
  },
  {
    id: 'flyer_combo',
    label: 'Flyer combo',
    blurb: 'atk1/2/3 + fly + tk (takeoff) — airborne attackers: Pelcatraz, Pelcatobur.',
    simNote: 'Baseline sim on the ground plane; flight/altitude needs its module (#494).',
  },
  {
    id: 'two_attack',
    label: 'Two-attack melee',
    blurb: 'atk1 / atk2 — straightforward two-swing melee: Hypao, Vespao.',
    simNote: 'Baseline sim covers it — author both swings as an attack table.',
  },
  {
    id: 'stance_riser',
    label: 'Stance riser',
    blurb: 'wat1 (low idle) / wat2 (raised ready) with stt rise and wt2w lower transitions; attacks launch from the raised pose: Garapython, Garahadan (#491).',
    simNote: 'Baseline sim attacks from locomotion; the stance sub-state model is specced as #491.',
  },
  {
    id: 'transformer',
    label: 'Transformer',
    blurb: 'No standard attack clip: armadillo trf1/trf2 (roll), shrimp tk1/tk2, orangutan atck* family — attacks via transform/mechanics.',
    simNote: 'Baseline sim uses the fallback-duration attack (no clip); transform mechanics need their module (#494).',
  },
  {
    id: 'trickster',
    label: 'Hopper / trickster',
    blurb: 'frog jmp + tur (leaps, turns), rappy ded1/ded2 + stt1/stt2 (plays dead, flees).',
    simNote: 'Baseline sim; leap and play-dead behaviors need their module (#494).',
  },
  {
    id: 'machine_soldier',
    label: 'Machine soldier',
    blurb: 'atk_* variant trios (ranged/melee modes) + segmented run_st/lp/ed or stp_* locomotion: leg/lower, swordman, board, tank, shooter families.',
    simNote: 'Baseline sim (attack-clip scan picks one variant); ranged attacks + segmented locomotion need their module (#494).',
  },
  {
    id: 'mother_caster',
    label: 'Mother caster',
    blurb: 'Segmented atk_gu_* gunfire, tec_* casts, warp_st/ed teleports: Mother Trinity, Blade/Shot/Force Mother.',
    simNote: 'Baseline sim; warps, casts, and segmented gunfire need their module (#494).',
  },
  {
    id: 'unique',
    label: 'Uniques',
    blurb: 'One-off kits: Rumole (grd01–03 digs), Sinow Beat (backstep/transform/wat2), Poison Lily (stationary, own script).',
    simNote: 'Baseline sim as a stand-in; each unique gets bespoke handling when authored.',
  },
  {
    id: 'boss',
    label: 'Bosses',
    blurb: 'Five unique arena-bound kits (dragon, octopus, mother, dark falz, robot).',
    simNote: 'Out of scope here — boss behavior is bound to its arena; needs the dedicated boss tool (#493).',
    outOfScope: true,
  },
];

export const ARCHETYPE_BY_ID = new Map(ARCHETYPES.map((a) => [a.id, a]));
