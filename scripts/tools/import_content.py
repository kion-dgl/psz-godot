#!/usr/bin/env python3
"""Import all JSON content from psz-sketch into Godot .tres resource files.

Usage: python3 scripts/tools/import_content.py /path/to/psz-sketch
"""

import json
import os
import sys
import re


def slugify(name: str) -> str:
    """Convert a name to a filesystem-safe slug."""
    s = name.lower().strip()
    s = re.sub(r'[^a-z0-9]+', '_', s)
    s = s.strip('_')
    return s


def read_json(path: str) -> dict:
    with open(path, 'r') as f:
        return json.load(f)


def write_tres(path: str, content: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)


def dict_to_gdscript(d: dict, indent: int = 0) -> str:
    """Convert a Python dict to GDScript Dictionary literal."""
    if not d:
        return "{}"
    parts = []
    prefix = "  " * indent
    for k, v in d.items():
        key_str = '"%s"' % k
        val_str = value_to_gdscript(v, indent + 1)
        parts.append('%s%s: %s' % (prefix + "  ", key_str, val_str))
    return "{\n%s\n%s}" % (",\n".join(parts), prefix)


def array_to_gdscript(arr: list, indent: int = 0) -> str:
    """Convert a Python list to GDScript Array literal."""
    if not arr:
        return "[]"
    if all(isinstance(x, (int, float)) for x in arr):
        return "[%s]" % ", ".join(str(x) for x in arr)
    parts = []
    prefix = "  " * indent
    for v in arr:
        parts.append(prefix + "  " + value_to_gdscript(v, indent + 1))
    return "[\n%s\n%s]" % (",\n".join(parts), prefix)


def value_to_gdscript(v, indent: int = 0) -> str:
    if v is None:
        return "0"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % v.replace('"', '\\"').replace('\n', '\\n')
    if isinstance(v, dict):
        return dict_to_gdscript(v, indent)
    if isinstance(v, list):
        return array_to_gdscript(v, indent)
    return str(v)


def packed_string_array(arr: list) -> str:
    if not arr:
        return 'PackedStringArray()'
    items = ', '.join('"%s"' % s.replace('"', '\\"') for s in arr)
    return 'PackedStringArray(%s)' % items


# ---- Class Data ----
def import_classes(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'classes')
    if not os.path.isdir(src):
        print(f"  Skipping classes: {src} not found")
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tech_limits = data.get('techniqueLimits') or {}
        trap_limits = data.get('trapLimits') or {}
        # Convert None values in tech_limits to 0
        clean_tech = {k: (v if v is not None else 0) for k, v in tech_limits.items()}

        tres = f'''[gd_resource type="Resource" script_class="ClassData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/class_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
race = "{data['race']}"
gender = "{data['gender']}"
type = "{data['type']}"
bonuses = {packed_string_array(data.get('bonuses', []))}
material_limit = {data.get('materialLimit', 100)}
stats = {dict_to_gdscript(data['stats'])}
technique_limits = {dict_to_gdscript(clean_tech)}
trap_limits = {dict_to_gdscript(trap_limits)}
'''
        write_tres(os.path.join(data_dir, 'classes', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Consumable Data ----
def import_consumables(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'consumables')
    if not os.path.isdir(src):
        print(f"  Skipping consumables: {src} not found")
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="ConsumableData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/consumable_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
details = "{data.get('details', '').replace('"', '\\"')}"
rarity = {data.get('rarity', 1)}
max_stack = {data.get('maxStack', 10)}
pso_world_id = {data.get('psoWorldId', 0)}
'''
        write_tres(os.path.join(data_dir, 'consumables', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Unit Data ----
def import_units(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'units')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="UnitData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/unit_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
rarity = {data.get('rarity', 1)}
category = "{data.get('category', '')}"
effect = "{data.get('effect', '')}"
effect_value = {data.get('effectValue', 0)}
pso_world_id = {data.get('psoWorldId', 0)}
'''
        write_tres(os.path.join(data_dir, 'units', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Photon Art Data ----
def safe_float(val, default=0.0) -> float:
    """Safely convert a value to float, stripping units like 'm' or '°'."""
    if val is None:
        return default
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip().rstrip('m°')
    try:
        return float(s)
    except ValueError:
        return default


def import_photon_arts(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'photon-arts')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="PhotonArtData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/photon_art_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
weapon_type = "{data.get('weaponType', '')}"
class_type = "{data.get('classType', '')}"
attack_mod = {safe_float(data.get('attackMod'))}
accuracy_mod = {safe_float(data.get('accuracyMod'))}
pp_cost = {data.get('ppCost', 0)}
targets = {data.get('targets', 1)}
hit_range = {safe_float(data.get('range'))}
area = {safe_float(data.get('area'))}
hits = {data.get('hits', 1)}
notes = "{(data.get('notes', '') or '').replace('"', '\\"')}"
'''
        write_tres(os.path.join(data_dir, 'photon_arts', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Mag Data ----
def import_mags(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'mags')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="MagData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/mag_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
stage = "{data.get('stage', '')}"
evolution_level = {data.get('evolutionLevel', 0)}
evolution_requirement = {dict_to_gdscript(data.get('evolutionRequirement', {}))}
photon_blast = "{data.get('photonBlast', '')}"
pso_world_id = {data.get('psoWorldId', 0)}
'''
        write_tres(os.path.join(data_dir, 'mags', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Mission Data ----
def import_missions(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'missions')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="MissionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/mission_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
area = "{data.get('area', '')}"
is_main = {value_to_gdscript(data.get('main', False))}
is_secret = {value_to_gdscript(data.get('isSecret', False))}
requires = {packed_string_array(data.get('requires', []))}
rewards = {dict_to_gdscript(data.get('rewards', {}))}
'''
        write_tres(os.path.join(data_dir, 'missions', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Quest Area Data ----
def import_quest_areas(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'quest-areas')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data.get('areaId', fname.replace('.json', '')))
        tres = f'''[gd_resource type="Resource" script_class="QuestAreaData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/quest_area_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
area_id = "{data.get('areaId', '')}"
area_name = "{data.get('areaName', '')}"
description = "{data.get('description', '').replace('"', '\\"')}"
unlock_condition = "{data.get('unlockCondition', '')}"
recommended_level = {data.get('recommendedLevel', 1)}
environment = "{data.get('environment', '')}"
quest_count = {data.get('questCount', 0)}
'''
        write_tres(os.path.join(data_dir, 'quest_areas', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Quest Definition Data ----
def import_quest_definitions(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'quest-definitions')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data.get('questId', fname.replace('.json', '')))
        tres = f'''[gd_resource type="Resource" script_class="QuestDefinitionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/quest_definition_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
quest_id = "{data.get('questId', '')}"
quest_name = "{data.get('questName', '')}"
quest_type = "{data.get('questType', '')}"
area = "{data.get('area', '')}"
description = "{data.get('description', '').replace('"', '\\"')}"
difficulties = {array_to_gdscript(data.get('difficulties', []))}
requirements = {dict_to_gdscript(data.get('requirements', {}))}
objectives = {array_to_gdscript(data.get('objectives', []))}
is_repeatable = {value_to_gdscript(data.get('isRepeatable', False))}
is_secret = {value_to_gdscript(data.get('isSecret', False))}
'''
        write_tres(os.path.join(data_dir, 'quest_definitions', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Material Data ----
def import_materials(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'materials')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="MaterialData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/material_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
details = "{data.get('details', '').replace('"', '\\"')}"
rarity = {data.get('rarity', 6)}
pso_world_id = {data.get('psoWorldId', 0)}
'''
        write_tres(os.path.join(data_dir, 'materials', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Set Bonus Data ----
def import_set_bonuses(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'set-bonuses')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data.get('armor', fname.replace('.json', '')))
        tres = f'''[gd_resource type="Resource" script_class="SetBonusData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/set_bonus_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
armor = "{data.get('armor', '')}"
weapons = {packed_string_array(data.get('weapons', []))}
bonuses = {dict_to_gdscript(data.get('bonuses', {}))}
'''
        write_tres(os.path.join(data_dir, 'set_bonuses', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Drop Table Data ----
def import_drop_tables(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'drops')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = fname.replace('.json', '')
        tres = f'''[gd_resource type="Resource" script_class="DropTableData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/drop_table_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
difficulty = "{slug}"
area_drops = {dict_to_gdscript(data)}
'''
        write_tres(os.path.join(data_dir, 'drop_tables', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Shop Data ----
def import_shops(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'shops')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data.get('name', fname.replace('.json', '')))
        tres = f'''[gd_resource type="Resource" script_class="ShopData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/shop_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data.get('name', '')}"
description = "{data.get('description', '').replace('"', '\\"')}"
items = {array_to_gdscript(data.get('items', []))}
'''
        write_tres(os.path.join(data_dir, 'shops', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Mag Personality Data ----
def import_mag_personalities(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'mag-personalities')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="MagPersonalityData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/mag_personality_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
category = "{data.get('category', '')}"
tier = "{data.get('tier', '')}"
unlock_level = {data.get('unlockLevel', 0)}
favorite_food = "{data.get('favoriteFood', '')}"
switch_from = "{data.get('switchFrom', '')}"
triggers = {dict_to_gdscript(data.get('triggers', {}))}
'''
        write_tres(os.path.join(data_dir, 'mag_personalities', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Modifier Data ----
def import_modifiers(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'modifiers')
    if not os.path.isdir(src):
        return 0
    count = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        slug = slugify(data['name'])
        tres = f'''[gd_resource type="Resource" script_class="ModifierData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/modifier_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "{slug}"
name = "{data['name']}"
japanese_name = "{data.get('japaneseName', '')}"
details = "{data.get('details', '').replace('"', '\\"')}"
rarity = {data.get('rarity', 3)}
pso_world_id = {data.get('psoWorldId', 0)}
'''
        write_tres(os.path.join(data_dir, 'modifiers', f'{slug}.tres'), tres)
        count += 1
    return count


# ---- Experience Table ----
def import_experience(content_dir: str, data_dir: str):
    src = os.path.join(content_dir, 'experience')
    if not os.path.isdir(src):
        return 0
    for fname in os.listdir(src):
        if not fname.endswith('.json'):
            continue
        data = read_json(os.path.join(src, fname))
        levels = data.get('levels', data if isinstance(data, list) else [])
        tres = f'''[gd_resource type="Resource" script_class="ExperienceTable" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/experience_table.gd" id="1"]

[resource]
script = ExtResource("1")
levels = {array_to_gdscript(levels)}
'''
        write_tres(os.path.join(data_dir, 'experience_table.tres'), tres)
        return 1
    return 0


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/tools/import_content.py /path/to/psz-sketch")
        sys.exit(1)

    sketch_dir = sys.argv[1]
    content_dir = os.path.join(sketch_dir, 'src', 'content')
    data_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'data')

    if not os.path.isdir(content_dir):
        print(f"Error: content directory not found: {content_dir}")
        sys.exit(1)

    print(f"Importing from: {content_dir}")
    print(f"Outputting to:  {data_dir}")
    print()

    importers = [
        ("Classes", import_classes),
        ("Consumables", import_consumables),
        ("Units", import_units),
        ("Photon Arts", import_photon_arts),
        ("Mags", import_mags),
        ("Missions", import_missions),
        ("Quest Areas", import_quest_areas),
        ("Quest Definitions", import_quest_definitions),
        ("Materials", import_materials),
        ("Set Bonuses", import_set_bonuses),
        ("Drop Tables", import_drop_tables),
        ("Shops", import_shops),
        ("Mag Personalities", import_mag_personalities),
        ("Modifiers", import_modifiers),
        ("Experience Table", import_experience),
    ]

    total = 0
    for name, func in importers:
        count = func(content_dir, data_dir)
        print(f"  {name}: {count} files")
        total += count

    print(f"\nTotal: {total} .tres files generated")


if __name__ == '__main__':
    main()
