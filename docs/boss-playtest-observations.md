# Boss observations and acceptance checklist

Recorded 2026-10-12 from Kion's original-game observations and Godot Coliseum
playtests in PR #754. This is the behavior checklist for subsequent passes.
User observations are requirements to preserve, not claims of independently
verified ROM behavior. An unchecked item means acceptance still needs checking;
it does not mean no implementation exists.

Build a mechanically complete fight in psz-godot first. Tune distances, durations,
and damage for playability, label those values as authored, and then compare each
behavior against the original. An animation catalog or a passing controller test
alone cannot close a gameplay observation.

## Octo Diablo: original-game observations

### Arena and entrance

- [ ] O01: Arena is an octagon of planks around an empty central opening/water.
- [ ] O02: Short entrance shows one tentacle emerging on the left, then one on
  the right, then the body emerging in the middle.
- [ ] O03: Entrance camera stays behind the player and tracks left and right
  with the reveals. Keep control interruption brief; exact duration is unmeasured.

### First phase: above half health

- [ ] O04: Body stays in the center with four tentacles extending in different
  directions. Some remain extended while others are poised to strike a passing
  player; limbs must present distinct threats concurrently.
- [ ] O05: Tentacle joints are attackable. Front and back of the head can also
  be attacked, but ordinary melee barely reaches the central body.
- [ ] O06: Body occasionally shoots ink while controlling the central area.
- [ ] O07: Tentacles can lift and slam down at the player, with readable windup.
- [ ] O08: Body can spin in the center, carrying all four tentacles around and
  damaging the player on contact during the attack.
- [ ] O09: Suction begins with tentacles lowered and pulls the player inward.
  Reaching the capture region damages the player.
- [ ] O10: If suction fails to capture the player, an airburst propels the boss
  backward into the planks. It becomes stunned briefly, creating a direct body
  melee opportunity. Test this outcome separately from successful capture.

### Half-health transition

- [ ] O11: At half health, boss submerges; a brief cutscene shows it surfacing
  beside the planks. Transition should resolve ongoing attacks safely.
- [ ] O12: Four central tentacles give way to two flanking tentacles, one left
  and one right of the body. Hidden limbs must stop delivering/receiving hits.

### Second phase: after the half-health transition

- [ ] O13: Body sits close to a plank edge and is substantially easier to hit
  directly with melee than in the central phase.
- [ ] O14: Ink attacks continue and can inflict poison. First-phase poison
  behavior was not specified and needs separate confirmation.
- [ ] O15: Boss can reposition to another side of the octagon.
- [ ] O16: Both tentacles can perform a crossing attack in front of the body.
- [ ] O17: Suction pulls the player toward the body; running away can avoid
  capture. Successful capture damages the player.
- [ ] O18: Failed suction leaves the body idling/cooling down for a short
  punish window. It does not use the first-phase recoil into the planks.

### Defeat

- [ ] O19: Brief defeat cutscene shows the boss falling into the water.
- [ ] O20: After defeat, rain and dark storm conditions clear; the sky remains
  cloudy. Combat ends and normal control/rewards resume safely.

## Reyburn: original observations and requested adaptations

These preserve earlier feedback as well as Octo's checklist. Original observations
and Godot design requests are distinguished explicitly.

- [ ] R01 (original): Player enters arena; dragon flies overhead, loops, lands
  in front, and roars before control returns. Keep this to a few seconds.
- [ ] R02 (requested): Camera stays close behind the player and follows the
  dragon through the sky. Dragon should face the player when combat begins.
- [ ] R03 (requested): Initial separation and recovery time prevent immediate
  bite/knockdown/bite deaths when the cutscene ends.
- [ ] R04 (requested): Repeated eligible conditions must not cause unbounded
  same-attack spam. Provide cooldowns or an alternate behavior.
- [ ] R05 (requested): After player defeat, stop attacking and loaf/idle.
  Eating the defeated character was a joke and is explicitly out of scope.
- [ ] R06 (requested): Every landing is supported by the arena floor collision
  mesh, including the boss footprint; no landing outside the arena.
- [ ] R07 (original): A flight generally includes 2–3 aerial fireball attacks,
  changing position between attacks before looking for a landing zone.
- [ ] R08 (requested): Ground turning has momentum: move, turn, move, turn.
  Avoid standing still and rotating like a turret or turning instantly.
- [ ] R09 (playtest): Feet sometimes float while walking. Check visible foot
  contact as well as body height on the floor mesh.
- [ ] R10 (observed/requested): Walking seeks an attack vantage rather than
  circling indefinitely; a forward dash can create room to turn and fire.
- [ ] R11 (playtest): Player could walk into the dragon. Body collision must
  block appropriately without making attacks or escape routes impossible.
- [ ] R12 (playtest): Each walking step caused damage and chained the player
  without recovery. Ordinary movement must not create this damage lock.

Reyburn has local implementations addressing these reports; the latest player
assessment was “mechanically it works,” with room for improvement. That is not
a claim that all visual acceptance checks or original-game comparisons passed.
See [implementation notes](reyburn-octo-implementation.md) for authored tuning.

## Mechanical implementation order for Octo

1. Arena, body placement, four independent tentacles, joint targets, and melee
   reach (O01, O04–O05). Verify the player can navigate and damage the boss.
2. Complete first-phase combat: ink, slam, spin, suction capture, and failed
   suction recoil/stun (O06–O10). Verify both suction outcomes by playing them.
3. Half-health transition and complete two-tentacle edge phase, including
   relocation, crossing attack, poison, and distinct suction recovery (O11–O18).
4. Entrance, transition camera, defeat, and weather (O02–O03, O19–O20).

All phases need safe player-death interruption, bounded recovery, coherent
collision, and restart cleanup. These are port acceptance requirements rather
than newly asserted original-game facts. Do not mark the fight complete after
only the first implementation slice.

## Original-game verification pass

For each ID above, retain an original clip or trace with start/end frames,
scenario (difficulty, player position/equipment, boss phase), observed outcome,
and source location. Record Godot's result separately. Use verdicts **matches**,
**intentional adaptation**, **discrepancy**, or **unresolved**. Preserve conflicting
evidence alongside the observation; do not silently rewrite the checklist.

| IDs | Specific question for original-game research |
| --- | --- |
| O01, O04–O05, O13 | What are arena/body/limb transforms, joint hit volumes, and reachable melee distances in both phases? |
| O02–O03, O11, O19 | What triggers each camera sequence, when does control return, and how long does it last? |
| O04, O07–O08, O16 | Which spatial predicates select limbs, how do they run concurrently, and what are their damaging windows and origins? |
| O09–O10, O17–O18 | What are pull region/strength, capture boundary, escape conditions, and successful/failed outcome branches in each phase? |
| O10, O18 | How long are punish windows, where does the body stop, and what ends vulnerability? |
| O06, O14 | Which ink variants inflict poison, with what trajectory, duration, and phase eligibility? |
| O11–O12 | How do half-HP clamping, active limb completion, disappearance, and reappearance coordinate? |
| O15 | How is the next octagon side selected and how does the body travel there? |
| O19–O20 | Which defeat/arena events end combat and change rain, lighting, and cloud state? |
| R01–R12 | Which authored Reyburn fixes differ from original movement, attack sequencing, collision, or recovery? |

### Research inventory inspected on 2026-10-12

Remote: `ssh kion@192.168.10.37`, repository
`/home/kion/projects/psz-re`, inspected commit
`fa5c6fb36e475eb8433be2d0445521150dcfb405`.

- `docs/boss-behavior-live.md` is the corrected research entry point;
  `docs/boss-porting.md` explicitly warns that its historical findings need
  those corrections. Do not reuse the older projectile weights as attack weights.
- `data/boss_behavior_contract.json`, `data/boss_octo_diablo.json`, and
  `data/traces/boss_live/octo_{full,half_crossing,natural_crossing}*` exist.
  Inventory inspection does not verify every checklist item against those traces.
- Live-analysis notes report a natural half-HP clamp/transition and independent
  body/four-short/two-long channels. They explicitly leave restraint, escape
  input, water boundaries, limb attack origins, and statuses for parity tests.
- Suction research starting addresses listed there: `0219DC6C`, `0219F048`,
  `0219F5A0`, `0219F8D0`, `0219FB3C`. Use these to ask a narrow question with a
  reproducible scenario; do not substitute function names for observed behavior.
- Running Codex process 6736 had cwd `/home/kion/projects`; process 1622721 had
  cwd `/home/kion/projects/psp2i-recomp`. The latter is the wrong project. The
  former's specific conversation still needs confirmation before messaging.
  Process IDs are inspection-time hints, not persistent session identifiers.

No remote research task was dispatched and no original-game behavior was newly
verified while recording this checklist.

## Octo follow-up playtest: 2026-10-12

Kion reported a massive improvement after the encounter update, with these
remaining issues. These checks supplement, rather than replace, O01–O20:

- [ ] P01: Opening body faces the player; do not reveal its back to the camera.
- [ ] P02: Suction has visible inward-moving wind around the mouth while pulling.
- [ ] P03: All four tentacles remain visible and rotate with the central spin.
- [ ] P04: Half-health emergence and subsequent relocation put the body beside
  the planks, not intersecting them.
- [ ] P05: Edge-phase tentacles visibly flank the body's left and right sides.
- [ ] P06: Defeat weather clears gradually, without an abrupt sky/rain switch.

Local fixes use player-relative opening yaw, extended spin limbs, collision-sampled
outer plank boundaries with a 4.5-unit body offset, lateral long-limb roots,
procedural inward wind streaks, a four-second rain fade, and a six-second sky
crossfade. These are authored presentation/placement choices requiring another
visual playtest; they are not newly recovered original-game constants.

## Paru: first Mac playtest, 2026-10-12

Kion tested PR #756 after main merge `3af72591`: no opening or victory
cutscene, reticle remained at arena center instead of either robot, and the
fight took too long even after raising the player to level 100.

The follow-up adds authored camera framing during both robots' entry/death
animations. The entrance preserves the original robot paths, with a camera fixed
behind the player tracking the animated skeletons; only victory root travel is bounded. It
locks control during those shots, and delays rewards until defeat
presentation ends. Target selection positions the reticle on the moving receiver.
Paru uses the retail difficulty HP pool without remake level multiplication:
normal is now 5,400 instead of 11,448 at the default Paru enemy level 15.
Player level and equipment still affect outgoing damage; this is not a claim
that fight duration has been validated by a second human playtest.

- [ ] Confirm opening and victory framing and control handoff on Mac.
- [ ] Confirm targeting while each robot moves and rises.
- [ ] Assess fight duration with the intended equipment and difficulty.

Bosses scorecard (`score:bosses`): no grade change; follow-up playtest pending.

## Paru: original-game comparison follow-up, 2026-10-12

Kion observes a spinning drill on the floating robot, an entrance from underground,
hovering attacks and periodic burrowing/emergence toward the player. The other
robot favors dashes, sometimes strafes and shoots. The linked spinning sequence
already looks good and must be preserved. Possible Zonde casting is tentative.

Implementation follow-up uses a procedural spinning drill on the existing
combined-archive mesh, an authored hover/burrow mix within the recovered attack
spans, a locked emergence point with a warning ring, and underground damage and
targeting exclusion. The dash robot now approaches, periodically strafes and
adds occasional post-dash laser shots. Original entrance paths remain unchanged.
Zonde remains unconfirmed; do not equate arena electrical effects with casting.
Exact split geometry, retail selection predicates, persistent slow holes, and
spatial fidelity remain open. Hands-on acceptance of this pass is pending.

Design note: Kion considers this the weakest original boss and is considering
replacing it with a Sinow encounter later. This is not a decision to replace the
current implementation; finish and assess the robot encounter first.

### Asset identity correction

Kion identifies o0c_bsef01 as the digging effect, z_003u as the drill robot,
and z_003n as its partner. The original viewer GLBs match recorded source hashes.
The original z_003u has animated put02 tracks; the prior Humilias z_103u adapter
removed that joint and caused the missing drill. Runtime now uses the original
Paru rigs and native drill tracks, replacing the procedural drill. Digging uses
o0c_bsef01 with authored expansion/lifetime. Publish the added assets to the
pack and mirror before exporting/landing this follow-up.
