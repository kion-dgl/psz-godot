# Class Design: PSO Races × PSU Archetypes

Each of the 14 classes gets a PSU-inspired archetype that defines its playstyle beyond just stat curves. Each class has an innate weapon that gives a small bonus (e.g. +15% damage or attack speed).

In original PSO, class choice was mostly cosmetic stat differences. PSZ wants classes to play very differently. Males lean tanky (ATK/DEF), females lean versatile (EVA/techs).

When implementing combat per class, design around the archetype. Weapon access, technique limits, trap slots, and combo finishers should reinforce the identity.

## Implementation Order: Humans First

Phase 1 (Humans — 6 classes):
- HUmar (Saber), HUmarl (Daggers)
- RAmar (Rifle), RAmarl (Handgun)
- FOmar (Rod), FOmarl (Wand)

Phase 2 (Newman — 4 classes):
- HUnewm (Double Saber), HUnewearl (Slicer)
- FOnewm (Rod), FOnewearl (Wand)

Phase 3 (Cast — 4 classes):
- HUcast (Sword), HUcaseal (Claw)
- RAcast (Launcher), RAcaseal (Mechgun)

## Full Class Map

| Class | Race | Gender | Innate Weapon | PSU Archetype | Identity |
|-------|------|--------|---------------|---------------|----------|
| HUmar | Human | M | Saber | Fightmaster | Solid all-rounder, saber/sword/spear, limited spells, heals |
| HUmarl | Human | F | Daggers | Wartecher | Up close + buffs/spells/heals, evasion tank |
| HUnewm | Newman | M | Double Saber | Acrofighter | Hard-hitting close spells + double saber combos |
| HUnewearl | Newman | F | Slicer | Acrotecher | Space control, slicer/spear/pistol + spell finishers |
| HUcast | Cast | M | Sword | Fortefighter | Risk/reward heavy hitter, traps, no healing |
| HUcaseal | Cast | F | Claw | Fighgunner | Hit and run, claw/daggers/mechgun, high evasion |
| RAmar | Human | M | Rifle | Gunmaster | Best ranged proficiency, all guns |
| RAmarl | Human | F | Handgun | Guntecher | Ranged + tech hybrid, mobile support |
| RAcast | Cast | M | Launcher | Protranser | AoE ranged + traps + sword access |
| RAcaseal | Cast | F | Mechgun | Fortegunner | Pure ranged DPS, traps |
| FOmar | Human | M | Rod | Fortetecher | Battle mage, Gi- close AoE, Barta boost |
| FOmarl | Human | F | Wand | Acrotecher | Priestess/nun, heals/buffs/Grants boost |
| FOnewm | Newman | M | Rod | Masterforce | All-rounder caster, Ra- and Gi-, dark boost |
| FOnewearl | Newman | F | Wand | Masterforce | "Megumin" glass cannon nuke, Foie boost, lowest HP |

## Hunter Playstyle Details

### HUmar (Fightmaster) — "The Swordsman"
Solid all-around character. Best with sabers, but good with swords and spears too. Has limited attack spells and can heal — no buffs though. Reliable in any situation, never the best at one thing but never bad at anything. Endgame fantasy: searching for the legendary katanas. The class you pick when you just want to hit things and not worry about complicated builds.

### HUmarl (Wartecher) — "The Spell Blade"
Gets up close and personal with daggers, then throws around hard-hitting spells and heals when needed. Buffs herself to stay competitive. Lower HP pool and defense than HUmar, but high evasion + Resta spam means she stays alive as long as she doesn't get surrounded. The moment she's cornered with no PP, she's in trouble. Plays like a rogue who weaves magic between dagger combos.

### HUnewm (Acrofighter) — "The Whirlwind"
Double saber combos backed by hard-hitting close-range spells. Access to higher-level techniques means he can use Barta to freeze or Foie to burn enemies to get a handle on chaotic situations. PP regen from Newman race keeps the spell pressure up. The flashy combo character who's always spinning through groups.

### HUnewearl (Acrotecher) — "The Tactician"
All about controlling space. Slicer, spear, and pistols keep enemies at a specific distance, then follows up with a wave of spells to finish off softened groups. Evasive and methodical — she dictates the terms of the fight. Not a brawler, not a pure caster — a mid-range controller who punishes enemies for getting too close OR too far.

### HUcast (Fortefighter) — "The Juggernaut"
Risk vs reward. Heavy sword attacks deal massive damage, but no Resta means every hit he takes matters. Has to know when to push and when to use traps to create breathing room. No magic at all — pure mechanical skill. The class that rewards players who learn enemy patterns because there's no healing safety net. Traps are his only utility.

### HUcaseal (Fighgunner) — "The Skirmisher"
Knows how to get into a fight and how to get out of one. Claws and daggers for close burst damage, mechguns to kite and finish from range. High evasion means she's hitting where it counts then moving before the backlash. HP regen + traps give her sustain tools that don't require standing still. The most mobile Hunter — always repositioning.

## Ranger Playstyle Details

### RAmar (Gunmaster) — "The Sharpshooter"
Focused on rifle — high accuracy, picking off targets from the back line. Can pull out a saber and fight when things get close. Limited spell access means he's mostly casting weak heals on himself to stay in the fight. Has a few helpful traps for utility. Straightforward and reliable — aim, shoot, repeat. The sniper who can handle himself in a pinch.

### RAmarl (Guntecher) — "Mami Tomoe"
Pistols, daggers, mechguns — she can buff herself and get up close and personal. Can heal too, making her great in most situations as long as she doesn't get careless. Mobile gunner who weaves between ranged and melee depending on what the fight demands. The most versatile Ranger — not the highest damage but always has an answer.

### RAcast (Protranser) — "The Engineer"
In the rear with the gear. Heavy launcher for crowd control from range, but can grab a sword and get personal when needed. His real trick: luring groups of enemies in and setting off chains of traps for massive damage. The tactical Ranger who controls the battlefield through positioning and preparation rather than raw firepower. Fights are won before they start.

### RAcaseal (Fortegunner) — "The Operator"
Guns for every situation. Mechguns are her favorite for pure DPS spray, but she'll grab a rifle for precision or launcher for AoE as needed. Can even pull out a saber before rolling to evade if things get close. Focus is mid-range space management — always at the optimal distance for whatever weapon she's holding. The most weapon-flexible Ranger.

## Force Playstyle Details

### FOmar (Fortetecher) — "The Battle Mage"
Mobile frontline Force. Runs up with the party and uses Gibarta to freeze groups in close range. Can melee with his rod when needed and take a hit thanks to decent DEF. Barta element boost means ice is his bread and butter. Weakness: slow/weak healing, weak buffs. Has to disengage from fights to recover — can't heal through damage like FOmarl can. Plays like a melee class that happens to use magic instead of swords.

### FOmarl (Acrotecher) — "The Priestess"
Ultimate support class. Best healing (Resta), best buffs (Shifta/Deband), and Reverser access makes her the most wanted party member. NOT a frontline fighter — she stays back and keeps everyone alive. Balanced offensive magic means she can scrape by solo but it's slow. Her ace is Grants (light element boost) which makes her a powerful endgame character once you invest the levels to get there. Early game is a grind, late game she's essential.

### FOnewm (Masterforce) — "The Edge Lord"
Dark magic specialist who sits in the back hurling Megid at anything in his path. Good all-around spells and can take a hit better than FOnewearl. Dark element boost + Megid access is his identity — high risk instant-death magic that trivializes some fights and does nothing in others. Limited buffs, okay healing. PP regen from Newman race keeps him casting. Plays like a dark wizard who gambles on Megid procs.

### FOnewearl (Masterforce) — "Megumin / Glass Cannon"
Sits in the back constantly spamming Rafoie to make everything on screen explode. Foie element boost + Ra- ranged focus = massive fire AoE from safety. Highest damage output of any Force but lowest HP pool — one mistake and she's dead. Huge PP pool + Newman PP regen sustains the spam. Weak healing, no buffs. Pure offense.

*Design consideration: Could add a spell charge mechanic (hold to power up) or cooldown after big casts that forces her to run and dodge. Creates a rhythm of nuke → dodge → nuke rather than pure spam.*

## Force Technique Access

| Technique | FOmar | FOmarl | FOnewm | FOnewearl |
|-----------|-------|--------|--------|-----------|
| Foie/Gifoie/Rafoie | Basic | Basic | Basic | **Boosted** |
| Barta/Gibarta/Rabarta | **Boosted** | Basic | Basic | Basic |
| Zonde/Gizonde/Razonde | Basic | Basic | Basic | Basic |
| Grants | Low cap | **Boosted** | Medium | Medium |
| Megid | No | No | **Boosted** | Basic |
| Resta | Slow/weak | **Best** | Okay | Weak |
| Reverser | No | **Yes** | No | Yes |
| Shifta/Deband | Weak | **Enhanced** | Limited | None/minimal |
| Gi- (close AoE) | **Primary** | No | Yes | No |
| Ra- (ranged) | No | **Yes** | Yes | **Primary** |

## Weapon Equip Table

**Universal:** Saber, Handgun (all 14 classes)

**Baselines:**
- Hunters: + Sword, Daggers
- Rangers: + Rifle, Mechgun, Launcher
- Forces: + Rod, Wand

**Gender split (Hunter melee):**
- Males: + Spear (no Claw)
- Females: + Claw (no Spear)

**Exceptions by class (beyond baseline):**

| Weapon | HUmar | HUmarl | HUnewm | HUnewearl | HUcast | HUcaseal | RAmar | RAmarl | RAcast | RAcaseal | FOmar | FOmarl | FOnewm | FOnewearl |
|--------|-------|--------|--------|-----------|--------|----------|-------|--------|--------|----------|-------|--------|--------|-----------|
| Saber | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Handgun | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Sword | Y | Y | Y | Y | Y | Y | - | - | Y | - | - | - | - | - |
| Spear | Y | - | Y | - | Y | - | Y | - | - | - | Y | - | - | - |
| Daggers | Y | Y | Y | Y | Y | Y | - | Y | - | - | - | - | - | - |
| Claw | - | Y | - | Y | - | Y | - | - | - | - | - | - | - | - |
| D. Saber | - | - | Y | - | - | - | - | - | - | Y | - | - | - | - |
| Slicer | - | - | - | Y | - | - | - | - | - | - | - | Y | - | - |
| Rifle | - | - | - | - | - | - | Y | Y | Y | Y | - | - | - | - |
| Mechgun | - | - | - | - | - | Y | Y | Y | Y | Y | - | - | - | - |
| Launcher | - | - | - | - | - | - | Y | Y | Y | Y | - | - | - | - |
| Rod | - | - | - | - | - | - | - | - | - | - | Y | Y | Y | Y |
| Wand | - | Y | - | - | - | - | - | - | - | - | Y | Y | Y | Y |

**Notable exceptions from baselines:**
- RAcast: +Sword (Protranser melee)
- RAmarl: +Daggers (Guntecher close combat)
- RAmar: +Spear (versatile sharpshooter)
- RAcaseal: +D. Saber (mirrors HUcaseal)
- HUcaseal: +Mechgun (Fighgunner ranged)
- HUmarl: +Wand (Wartecher casting)
- FOmar: +Spear (battle mage frontline)
- FOmarl: +Slicer (priestess ranged disc)

## Weapon Types (13 total)

**Melee (7):** Saber, Daggers, Sword, Double Saber, Claw, Slicer, Spear
**Ranged (4):** Handgun, Rifle, Mechgun, Launcher
**Tech (2):** Rod (offensive), Wand (support)

## PSU Archetype Definitions (reference)

- **Fightmaster**: Incredible melee proficiency, all melee weapons
- **Gunmaster**: Incredible ranged proficiency, all ranged weapons
- **Masterforce**: Incredible tech proficiency, all techniques
- **Fortefighter**: Pure melee power, trades weapon variety for damage + defense
- **Fortegunner**: Pure ranged power, trades weapon variety for damage + accuracy
- **Fortetecher**: Pure tech power, trades weapon variety for damage, fragile
- **Wartecher**: Tech/melee hybrid, emphasis on high Defense
- **Guntecher**: Ranged/tech hybrid, proficient with both guns and techniques
- **Acrofighter**: One-handed weapon specialist, swift attacks, dual wielding
- **Acrotecher**: Support-based, combat ability + technique aptitude
- **Protranser**: Trap master, versatile weapon access
- **Fighgunner**: Melee/ranged hybrid, proficient with melee and ranged weapons
