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
    blurb: 'wlk_l/wlk_r walks have the head turned that way — approach is arc-only (clip matches the target\'s side); stt is the straight dash-charge: wolf, hyena, deer, tiger.',
    simNote: 'Implemented: arc-only approach + stt dash-charge (spec /states/enemies §quadruped). Godot runtime still walks straight — lands with the runtime PR.',
  },
  {
    id: 'quad_machine',
    label: 'Quad machine',
    blurb: 'Hover kiter: body faces the target while strafing wlk_f/b/l/r; holds standoff range; atk = projectile, atkb = grenade lob. Corner it to beat it: Izhirak-S6, Azherowa-B2.',
    simNote: 'Implemented: standoff kiting + projectile/lob deliveries (spec /states/enemies §quad-machine).',
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
    blurb: 'atk1 punch combo, atk2_st/lp/ed running shoulder slam (charge), atk3 belly-flop leap, stt chest-beat threat on aggro: Hilde gorillas.',
    simNote: 'Implemented: chest-beat threat hold, charge phases (st→lp moves→ed), belly-flop leap with landing AoE (spec /states/enemies §big-rig).',
  },
  {
    id: 'flyer_combo',
    label: 'Flyer combo',
    blurb: 'stt takeoff on aggro, hovers at shoulder height (hard to melee), fly = approach / tk = orbit; atk1 beak, atk2 gust (uncertain), atk3 wing swipe: Pelcatraz, Pelcatobur.',
    simNote: 'Implemented: takeoff rise, shoulder-height hover, fly/tk locomotion (spec /states/enemies §flyer). atk2 gust semantics are an open question.',
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
    id: 'roller',
    label: 'Roller',
    blurb: 'Walks at medium distance until it has a straight path, then rolls: trf1 roll-up → wat3 engine-rotated ball THROUGH the player (knockdown, overshoots past you) → trf2 fall-over where it takes ×2 damage: Rohjade, Rohcrysta.',
    simNote: 'Implemented: standoff walk, roll-through charge with overshoot + knockdown, trf2 vulnerability window (spec /states/enemies §roller; sequence is kion\'s read of the clips — confirm in-game).',
  },
  {
    id: 'ape_gunner',
    label: 'Ape gunner',
    blurb: 'Two pistol shots (atcksht + atcktuki, the latter uncertain) and a charged punch sequence (atckstt wind-up → atckwat hold → atckswg swing); stt = sit-to-stand aggro; wat scratches its stomach: Froutang, Frunaked.',
    simNote: 'Implemented: projectile shots + windup_clips charged punch (spec /states/enemies §ape-gunner). Kion flags the family as an EP2-replacement candidate; wtclp intimidation is an open question.',
  },
  {
    id: 'box_mimic',
    label: 'Box mimic',
    blurb: 'Look like boxes and wait for the player to approach before attacking (tk1/tk2, wlk1/wlk2): Bolix, Goldix.',
    simNote: 'Baseline sim; ambush behavior notes pending — split out per kion, module to follow.',
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
