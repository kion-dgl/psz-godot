#!/usr/bin/env python3
"""
Convert psz-sketch JSON data to Godot .tres resource files.

Usage:
    python convert_psz_data.py --source /path/to/psz-sketch/src/content --output /path/to/psz-godot/data
"""

import json
import os
import argparse
from pathlib import Path


# Weapon type mapping from string to enum index
WEAPON_TYPE_MAP = {
    "Saber": 0,
    "Sword": 1,
    "Daggers": 2,
    "Claw": 3,
    "Double Saber": 4,
    "Spear": 5,
    "Slicer": 6,
    "Gun Blade": 7,
    "Shield": 8,
    "Handgun": 9,
    "Mech Gun": 10,
    "Rifle": 11,
    "Bazooka": 12,
    "Laser Cannon": 13,
    "Rod": 14,
    "Wand": 15,
}

# Armor type mapping
ARMOR_TYPE_MAP = {
    "Armor": 0,
    "Frame": 1,
    "Robe": 2,
    "Rare": 3,
}

# Element mapping for enemies
ELEMENT_MAP = {
    "Native": 0,
    "Beast": 1,
    "Machine": 2,
    "Dark": 3,
}


def sanitize_id(name: str) -> str:
    """Convert name to valid ID (lowercase, underscores)."""
    return name.lower().replace(" ", "_").replace("-", "_").replace("'", "")


def escape_string(s: str) -> str:
    """Escape string for Godot .tres format."""
    if s is None:
        return ""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def convert_weapon(json_path: Path, output_dir: Path):
    """Convert a weapon JSON to .tres format."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    weapon_id = sanitize_id(json_path.stem)
    weapon_type = WEAPON_TYPE_MAP.get(data.get("weaponType", "Saber"), 0)

    # Build photon arts array
    photon_arts = data.get("photonArts", [])
    pa_str = "[]"
    if photon_arts:
        pa_items = []
        for pa in photon_arts:
            pa_items.append(
                f'{{"name": "{escape_string(pa.get("name", ""))}", '
                f'"attack_mod": {pa.get("attackMod", 0)}, '
                f'"accuracy_mod": {pa.get("accuracyMod", 0)}, '
                f'"pp_used": {pa.get("ppUsed", 0)}, '
                f'"element": "{escape_string(pa.get("element", "-"))}"}}'
            )
        pa_str = "[" + ", ".join(pa_items) + "]"

    # Build usable_by array
    usable_by = data.get("usableBy", [])
    usable_str = "PackedStringArray(" + ", ".join(f'"{u}"' for u in usable_by) + ")"

    tres_content = f'''[gd_resource type="Resource" script_class="WeaponData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/weapon_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{weapon_id}"
name = "{escape_string(data.get("name", ""))}"
japanese_name = "{escape_string(data.get("japaneseName", ""))}"
rarity = {data.get("rarity", 1)}
weapon_type = {weapon_type}
max_grind = {data.get("maxGrind", 0)}
level = {data.get("level", 1)}
resale_value = {data.get("resaleValue", 0)}
attack_base = {data.get("attackBase", 0) or 0}
attack_max = {data.get("attackMax", 0) or 0}
accuracy_base = {data.get("accuracyBase", 0)}
accuracy_max = {data.get("accuracyMax", 0)}
element = "{escape_string(data.get("element", ""))}"
element_level = {data.get("elementLevel", 0) or 0}
photon_arts = {pa_str}
usable_by = {usable_str}
pso_world_id = {data.get("psoWorldId", 0)}
model_id = "{escape_string(data.get("modelId", ""))}"
variant_id = "{escape_string(data.get("variantId", "") or "")}"
'''

    output_path = output_dir / "weapons" / f"{weapon_id}.tres"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(tres_content)

    return weapon_id


def convert_armor(json_path: Path, output_dir: Path):
    """Convert an armor JSON to .tres format."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    armor_id = sanitize_id(json_path.stem)
    armor_type = ARMOR_TYPE_MAP.get(data.get("type", "Armor"), 0)

    # Get resistances
    resistances = data.get("resistances", {})

    # Build usable_by array
    usable_by = data.get("usableBy", [])
    usable_str = "PackedStringArray(" + ", ".join(f'"{u}"' for u in usable_by) + ")"

    tres_content = f'''[gd_resource type="Resource" script_class="ArmorData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/armor_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{armor_id}"
name = "{escape_string(data.get("name", ""))}"
japanese_name = "{escape_string(data.get("japaneseName", ""))}"
type = {armor_type}
rarity = {data.get("rarity", 1)}
max_grind = {data.get("maxGrind", 0)}
level = {data.get("level", 1) or 1}
resale_value = {data.get("resaleValue", 0) or 0}
defense_base = {data.get("defenseBase", 0)}
defense_max = {data.get("defenseMax", 0)}
evasion_base = {data.get("evasionBase", 0)}
evasion_max = {data.get("evasionMax", 0)}
max_slots = {data.get("maxSlots", 0)}
resist_fire = {resistances.get("fire", 0)}
resist_ice = {resistances.get("ice", 0)}
resist_lightning = {resistances.get("lightning", 0)}
resist_light = {resistances.get("light", 0)}
resist_dark = {resistances.get("dark", 0)}
usable_by = {usable_str}
set_bonus = "{escape_string(data.get("setBonus", ""))}"
pso_world_id = {data.get("psoWorldId", 0)}
'''

    output_path = output_dir / "armors" / f"{armor_id}.tres"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(tres_content)

    return armor_id


def convert_enemy(json_path: Path, output_dir: Path):
    """Convert an enemy JSON to .tres format."""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    enemy_id = sanitize_id(json_path.stem)
    element = ELEMENT_MAP.get(data.get("element", "Native"), 0)

    # Build locations array
    locations = data.get("locations", [])
    locations_str = "PackedStringArray(" + ", ".join(f'"{loc}"' for loc in locations) + ")"

    # Default combat stats (to be tuned later)
    is_rare = data.get("isRare", False)
    is_boss = data.get("isBoss", False)

    # Scale base stats for rare/boss
    hp_base = 100
    attack_base = 10
    defense_base = 5
    exp_reward = 10
    meseta_min = 5
    meseta_max = 15

    if is_rare:
        hp_base = 200
        attack_base = 15
        defense_base = 8
        exp_reward = 50
        meseta_min = 20
        meseta_max = 50

    if is_boss:
        hp_base = 1000
        attack_base = 25
        defense_base = 15
        exp_reward = 200
        meseta_min = 100
        meseta_max = 300

    behavior = 5 if is_boss else 0  # BOSS or MELEE

    tres_content = f'''[gd_resource type="Resource" script_class="EnemyData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/enemy_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{enemy_id}"
name = "{escape_string(data.get("name", ""))}"
japanese_name = "{escape_string(data.get("japaneseName", ""))}"
element = {element}
locations = {locations_str}
is_rare = {str(is_rare).lower()}
is_boss = {str(is_boss).lower()}
model_id = "{escape_string(data.get("modelId", ""))}"
hp_base = {hp_base}
attack_base = {attack_base}
defense_base = {defense_base}
move_speed = 3.0
attack_range = 2.0
detection_range = 15.0
exp_reward = {exp_reward}
meseta_min = {meseta_min}
meseta_max = {meseta_max}
behavior = {behavior}
attack_cooldown = 1.5
collision_radius = 0.5
collision_height = 1.5
'''

    output_path = output_dir / "enemies" / f"{enemy_id}.tres"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(tres_content)

    return enemy_id


def main():
    parser = argparse.ArgumentParser(description="Convert psz-sketch JSON to Godot .tres")
    parser.add_argument("--source", required=True, help="Path to psz-sketch/src/content")
    parser.add_argument("--output", required=True, help="Path to psz-godot/data")
    parser.add_argument("--type", choices=["all", "weapons", "armors", "enemies"], default="all")
    args = parser.parse_args()

    source = Path(args.source)
    output = Path(args.output)

    if args.type in ["all", "weapons"]:
        weapons_dir = source / "weapons"
        if weapons_dir.exists():
            count = 0
            for json_file in weapons_dir.glob("*.json"):
                try:
                    convert_weapon(json_file, output)
                    count += 1
                except Exception as e:
                    print(f"Error converting {json_file}: {e}")
            print(f"Converted {count} weapons")

    if args.type in ["all", "armors"]:
        armors_dir = source / "armors"
        if armors_dir.exists():
            count = 0
            for json_file in armors_dir.glob("*.json"):
                try:
                    convert_armor(json_file, output)
                    count += 1
                except Exception as e:
                    print(f"Error converting {json_file}: {e}")
            print(f"Converted {count} armors")

    if args.type in ["all", "enemies"]:
        enemies_dir = source / "enemies"
        if enemies_dir.exists():
            count = 0
            for json_file in enemies_dir.glob("*.json"):
                try:
                    convert_enemy(json_file, output)
                    count += 1
                except Exception as e:
                    print(f"Error converting {json_file}: {e}")
            print(f"Converted {count} enemies")


if __name__ == "__main__":
    main()
