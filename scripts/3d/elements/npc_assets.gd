extends RefCounted
class_name NpcAssets
## Shared NPC asset tables — model GLB/texture paths, animation class IDs, and
## the female-class list. Companion NPCs (companion_npc.gd) and field NPCs
## (field_npc.gd) index the same character set, so these three tables were
## byte-identical in both (#517). Per-file capsule/fallback colors stay local.

## npc_id → { glb, texture } model paths.
const MODELS: Dictionary = {
	"kai": {"glb": "res://assets/npcs/kai/pc_a01_000.glb", "texture": "res://assets/npcs/kai/pc_a01_000.png"},
	"sarisa": {"glb": "res://assets/npcs/sarisa/pc_a00_000.glb", "texture": "res://assets/npcs/sarisa/pc_a00_000.png"},
	"dorn": {"glb": "res://assets/npcs/dorn/dorn.glb", "texture": "res://assets/npcs/dorn/dorn.png"},
	"dr_carlo": {"glb": "res://assets/npcs/dr_carlo/dr_carlo.glb", "texture": "res://assets/npcs/dr_carlo/dr_carlo.png"},
	"elio": {"glb": "res://assets/npcs/elio/elio.glb", "texture": "res://assets/npcs/elio/elio.png"},
	"fern": {"glb": "res://assets/npcs/fern/fern.glb", "texture": "res://assets/npcs/fern/fern.png"},
	"vash": {"glb": "res://assets/npcs/vash/vash.glb", "texture": "res://assets/npcs/vash/vash.png"},
	"ren": {"glb": "res://assets/npcs/ren/ren.glb", "texture": "res://assets/npcs/ren/ren.png"},
	"mira": {"glb": "res://assets/npcs/mira/mira.glb", "texture": "res://assets/npcs/mira/mira.png"},
}

## npc_id → class ID, used to pick the animation prefix (and gender via FEMALE_CLASSES).
const CLASSES: Dictionary = {
	"kai": "humar", "sarisa": "hunewearl", "dorn": "hucast",
	"dr_carlo": "fomar", "elio": "racaseal", "fern": "humarl",
	"vash": "ramar", "ren": "humar", "mira": "fomarl",
}

## Classes that use the female animation prefix.
const FEMALE_CLASSES := ["humarl", "ramarl", "fomarl", "hunewearl", "fonewearl", "hucaseal", "racaseal"]
