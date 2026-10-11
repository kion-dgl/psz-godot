extends RefCounted
## Source-backed numeric fixtures and transaction/lifecycle boundaries.
const Math := preload("res://scripts/utils/combat_math.gd")
const Growth := preload("res://scripts/utils/enemy_progression.gd")
const Grind := preload("res://scripts/utils/weapon_grinding.gd")

static func run(t: Node) -> void:
	_numeric_fixtures(t)
	var saved_chars: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	CharacterManager._characters.resize(20)
	var ch = CharacterManager.create_character(18, "humar", "SystemsFixture")
	if ch.is_empty():
		CharacterManager.delete_character(18)
		ch = CharacterManager.create_character(18, "humar", "SystemsFixture")
	CharacterManager.set_active_slot(18)
	var base = EnemyRegistry.get_enemy("ghowl")
	var early = Growth.scaled(base, 1)
	var later = Growth.scaled(base, 20)
	t.assert_true(later.hp_base > early.hp_base and later.exp_reward > early.exp_reward, "enemy growth affects HP and EXP")
	t.assert_eq(base.hp_base, 100, "spawn scaling preserves registry")
	t.assert_eq(early.hp_base, 95, "recovered lizard normal HP")
	_grinding_and_growth(t, ch)
	_blast_and_levels(t, ch)
	CharacterManager.delete_character(18)
	CharacterManager._characters = saved_chars
	CharacterManager._active_slot = -1
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)

static func _numeric_fixtures(t: Node) -> void:
	t.assert_eq(Math.damage(100, 25), 15, "ATP minus DFP then divide by five")
	t.assert_eq(Math.damage(24, 25), 0, "defense can reduce damage to zero")
	t.assert_eq(Math.damage(100, 25, true), 22, "critical adds truncated half")
	t.assert_eq(Math.damage(100, 25, false, 100), 0, "full resistance is immunity")
	for kind in ["technique", "blast"]:
		for i in 20:
			t.assert_true(CombatManager.apply_damage_to_enemy(100, 0, 9999, 0, kind).hit, "nonphysical attacks bypass accuracy: " + kind)
	for row in [[4096, 85], [4710, 98], [5324, 110]]:
		t.assert_eq(Math.hit_percent(213, 0, row[0]), row[1], "recovered live accuracy sample")
	t.assert_eq(Math.attribute_attack(56, 40, {"native_pct": 50}, 0), 116, "family attribute applies only to weapon ATP")
	t.assert_eq(Math.attribute_attack(56, 40, {"native_pct": 50}, 2), 96, "unmatched family stays neutral")

static func _grinding_and_growth(t: Node, ch: Dictionary) -> void:
	Inventory.add_item("monogrinder", 2)
	GameState.meseta = 1000
	ch.meseta = 0 # runtime wallet wins over stale character snapshot
	var quote := Grind.quote("saber")
	t.assert_true(quote.success, "owned starter weapon has a quote")
	var result := Grind.apply("saber")
	t.assert_true(result.success, "grinding uses carried wallet")
	t.assert_eq(Inventory.get_item_count("monogrinder"), 1, "one grinder consumed")
	t.assert_eq(GameState.meseta, 1000 - int(quote.cost), "quoted fee consumed once")
	t.assert_eq(WeaponRegistry.get_weapon("saber").get_attack_at_grind(1), 39, "original weapon grind adds two ATP")
	var max_grind: int = WeaponRegistry.get_weapon("saber").max_grind
	ch.weapon_grinds.saber = max_grind
	t.assert_true(not Grind.apply("saber").success, "cap rejects transaction")
	t.assert_eq(Inventory.get_item_count("monogrinder"), 1, "cap retains material")
	t.assert_true(not Grind.apply("saber#999").success, "unowned instance rejected")
	Inventory.add_item("rod", 1)
	t.assert_true(not Grind.apply("rod").success, "unsupported zero-ATP weapon cannot consume a grinder")
	t.assert_eq(Inventory.get_item_count("monogrinder"), 1, "unsupported weapon retains material")
	ch.material_bonuses = {"hp": 4, "pp": 2}
	CharacterManager.add_experience(100)
	var stats := CharacterManager.get_stats_at_level("humar", ch.level)
	t.assert_eq(ch.max_hp, stats.hp + 4, "level-up retains HP material bonus")
	t.assert_eq(ch.max_pp, stats.pp + 2, "level-up retains PP material bonus")
	ch.equipment.weapon = "helion_roar"
	t.assert_eq(CombatManager.get_weapon_special(ch).element, "status:burn", "native Heat special reaches burn delivery")
	ch.weapon_stats.helion_roar = {"element": "ice", "element_level": 2}
	t.assert_eq(CombatManager.get_weapon_special(ch).element, "ice", "crafted override takes precedence over native special")
	ch.equipment.weapon = "saber"
	var exp_before: int = ch.experience
	CharacterManager.add_experience(-100)
	t.assert_eq(ch.experience, exp_before, "negative EXP rejected")

static func _blast_and_levels(t: Node, ch: Dictionary) -> void:
	var mag: Dictionary = ch.mag_states.mag
	PhotonBlast.reset()
	PhotonBlast.gain_damage(100, 100, false)
	t.assert_eq(PhotonBlast.gauge, 0, "unevolved mag does not charge")
	mag.stats.power = 50
	for form in ["yul", "yth", "aio", "ingh"]:
		mag.form_id = form
		t.assert_true(not PhotonBlast.equipped_blast().is_empty(), "each evolved archetype resolves a blast")
	PhotonBlast.gain_damage(0, 100, false)
	t.assert_eq(PhotonBlast.gauge, 0, "misses cannot charge")
	t.assert_eq(PhotonBlast.charge_amount(1, 100, false), 27, "original six-bucket low award")
	t.assert_eq(PhotonBlast.charge_amount(20, 100, false), 114, "original six-bucket boundary uses strict less-than")
	t.assert_eq(PhotonBlast.charge_amount(1000, 100, false), PhotonBlast.charge_amount(100, 100, false), "overkill capped")
	for i in 200:
		PhotonBlast.gain_damage(100, 100, false)
	t.assert_eq(PhotonBlast.gauge, 10000, "PB gauge saturates at original limit")
	PhotonBlast.reset()
	for class_data in ClassRegistry.get_all_classes():
		var class_id: String = class_data.id
		var low := CharacterManager.get_stats_at_level(class_id, 1)
		var high := CharacterManager.get_stats_at_level(class_id, 20)
		t.assert_true(high.hp > low.hp and high.attack > low.attack, "class growth reaches combat stats: " + class_id)
	t.assert_eq(Growth.level_for({"area_id": "rioh", "difficulty": "hard"}), 35, "fixed area plus difficulty level")
	t.assert_eq(Growth.level_for({"area_id": "rioh", "enemy_level": 12, "difficulty": "normal"}), 12, "authored quest level overrides area")
