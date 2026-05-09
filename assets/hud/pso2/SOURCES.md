# PSO2 wiki icons

These 16×16 PNGs were sourced from the Arks Visiphone wiki
(<https://pso2.arks-visiphone.com/wiki/Template:Icons>) on 2026-05-09
for use as type-icons in the inventory / shop UI. NGS-prefixed variants
were intentionally skipped.

Each file's original wiki path is recorded here. Files are renamed to
match how the in-game UI refers to them (item kind / weapon registry
type), not the original wiki name.

## Currency

| File              | Wiki                 |
|-------------------|----------------------|
| icon_meseta.png   | UIMSTIcon.png        |

## Disk

The wiki has no PSO1-style technique-disk icon — the closest visual
match is the Music Disk template entry. Used as a generic disk icon
for technique disks in PSZ.

| File              | Wiki                 |
|-------------------|----------------------|
| icon_disk.png     | UIIconMusic.png      |

## Rarity stars

PSO2 typically maps rarity tiers in 3-step bands: 1-3 blue, 4-6 green,
7-9 red, 10-12 gold, 13-15 rainbow.

| File                      | Wiki                 |
|---------------------------|----------------------|
| icon_rarity_blue.png      | UIStarBlueIcon.png   |
| icon_rarity_green.png     | UIStarGreenIcon.png  |
| icon_rarity_red.png       | UIStarRedIcon.png    |
| icon_rarity_gold.png      | UIStarGoldIcon.png   |
| icon_rarity_rainbow.png   | UIStarRainbowIcon.png|

## Rank stars (small badges)

Compact alternative for rank/grade indicators where the full rarity
star feels too large.

| File                  | Wiki              |
|-----------------------|-------------------|
| icon_star_bronze.png  | UIBronzeStar.png  |
| icon_star_silver.png  | UISilverStar.png  |
| icon_star_gold.png    | UIGoldStar.png    |

## Item categories

Generic fallbacks for inventory rows that don't have a more specific
icon (weapons get their type-icon instead — see Weapons section below).

| File              | Wiki              |
|-------------------|-------------------|
| icon_material.png | UIMaterial.png    |
| icon_tool.png     | ToolSmall.png     |
| icon_mag.png      | MagDevice.png     |

## Weapons

Filename matches the weapon registry type key (`sword`, `partizan`,
`wired_lance`, etc.), so the start menu can do
`load("res://assets/hud/pso2/icon_%s.png" % weapon.weapon_type)`.

| File                       | Wiki                       |
|----------------------------|----------------------------|
| icon_sword.png             | SwordSmall.png             |
| icon_partizan.png          | PartizanSmall.png          |
| icon_wired_lance.png       | WiredLanceSmall.png        |
| icon_double_saber.png      | DoubleSaberSmall.png       |
| icon_knuckles.png          | KnucklesSmall.png          |
| icon_twin_daggers.png      | TwinDaggerSmall.png        |
| icon_gunslash.png          | GunslashSmall.png          |
| icon_katana.png            | KatanaSmall.png            |
| icon_dual_blades.png       | DualBladeSmall.png         |
| icon_assault_rifle.png     | AssaultRifleSmall.png      |
| icon_launcher.png          | LauncherSmall.png          |
| icon_twin_machineguns.png  | TwinMachinegunSmall.png    |
| icon_bullet_bow.png        | BulletBowSmall.png         |
| icon_rod.png               | RodSmall.png               |
| icon_wand.png              | WandSmall.png              |
