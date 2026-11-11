# Full technique audit — November 11, 2026

Rendered FOmar/rod Coliseum diagnostic; level-1 techniques, two stationary durable Ghowls. All 18 catalogue entries were granted only to this isolated test character, including normally unavailable legacy/advanced spells. Nine base hold/release paths were also exercised. Passing audit assertions describe current gates and cleanup, not completion or fidelity approval.

| Technique | PP spent | Combined enemy HP loss | HP gained | Finding |
|---|---:|---:|---:|---|
| foie | 5 | 22 | 0 | implemented delivery; visual/feel review pending |
| gifoie | 20 | 92 | 0 | implemented delivery; visual/feel review pending |
| rafoie | 30 | 86 | 0 | implemented delivery; visual/feel review pending |
| barta | 6 | 40 | 0 | implemented delivery; visual/feel review pending |
| gibarta | 22 | 600 | 0 | implemented delivery; visual/feel review pending |
| rabarta | 35 | 116 | 0 | implemented delivery; visual/feel review pending |
| zonde | 4 | 20 | 0 | implemented delivery; visual/feel review pending |
| gizonde | 18 | 74 | 0 | implemented delivery; visual/feel review pending |
| razonde | 28 | 88 | 0 | implemented delivery; visual/feel review pending |
| grants | 50 | 78 | 0 | generic Foie fallback; spell-specific delivery absent |
| megid | 40 | 9 | 0 | generic Foie fallback; spell-specific delivery absent |
| resta | 10 | 0 | 20 | implemented delivery; visual/feel review pending |
| anti | 8 | 0 | 0 | implemented delivery; visual/feel review pending |
| reverser | 0 | 0 | 0 | blocked before cost: no 3D support recipient/resolver |
| shifta | 0 | 0 | 0 | blocked before cost: no 3D support recipient/resolver |
| deband | 0 | 0 | 0 | blocked before cost: no 3D support recipient/resolver |
| jellen | 0 | 0 | 0 | blocked before cost: no 3D support recipient/resolver |
| zalure | 0 | 0 | 0 | blocked before cost: no 3D support recipient/resolver |

Anti removed an applied poison status. Damage totals are one observed run, not balance targets: random rolls, multiple targets and repeated wave contacts differ by spell. Gibarta in particular needs a hit-budget/balance review. Resta was tested on self; party healing is not established. No downed companion revive test can pass while Reverser is blocked.

## Visual review

The first Foie/Barta/Resta changes remain prototypes. Lightning already has bolt visuals; Gifoie/Gibarta and Razonde still retain older presentation. Grants/Megid do not have distinct delivery. Support spells need functional delivery before a visual pass can claim to represent successful effects. Original-game comparison, all-level scaling, every status outcome, and owner feel acceptance remain open. Screenshots of every entry were captured under `/tmp/force-technique-captures`.

## Playtest

Run from this checkout:

```sh
python3 scripts/tools/run_ranger_aim.py --class fomar --weapon rod --scene res://scripts/tools/force_technique_probe.tscn
```

F3 cycles six technique banks; mouse buttons cast the three displayed spells, holding selects charged variants. F2 restarts the encounter, F4 refills HP/PP, F5 applies poison for Anti. T toggles enemy AI, Z toggles shoulder view, Q locks a target, Tab switches targets, Space dodges. Shift exposes Attack/Resta/Monofluid. Normal saves and disk availability are unchanged.

Automated repeat: add `--check --rendered`, set `PSZ_TECH_REPORT` to an output JSON path and `PSZ_BOSS_SCREENSHOTS` to a capture directory.
